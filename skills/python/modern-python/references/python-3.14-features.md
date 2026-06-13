# Python 3.14 Feature Tour

Use this when:

- You are writing code that targets Python 3.14 and want to use its new features correctly.
- You need to process t-strings (PEP 750) or migrate annotation handling to `annotationlib`.
- You are deciding whether a 3.14 feature is safe for your deployment target.
- You are debugging a live 3.14 process (remote debugging, asyncio introspection).

Skip this file if:

- You only need the headline version gates and routing. Use [../SKILL.md](../SKILL.md).
- Your question is free-threading or subinterpreters. Use [../../python-concurrency/references/free-threading.md](../../python-concurrency/references/free-threading.md) and [../../python-concurrency/references/subinterpreters.md](../../python-concurrency/references/subinterpreters.md).
- You want anti-patterns and lint rules. Use [python-anti-patterns.md](python-anti-patterns.md).

Jump to:

- Release Snapshot
- Template Strings (PEP 750)
- Deferred Annotations and annotationlib (PEP 649/749)
- Free-Threading and Subinterpreters (pointers)
- compression.zstd (PEP 784)
- Multiple Exception Types Without Parentheses (PEP 758)
- Control Flow in finally Blocks (PEP 765)
- Improved Error Messages
- Remote Debugging (PEP 768)
- Asyncio Introspection CLI
- Performance: Tail-Call Interpreter
- Smaller Improvements
- Migration Checklist (3.12/3.13 to 3.14)

Python 3.14 was released in October 2025. Point releases refine error-message
wording and library details — for anything marked *(verify)*, confirm against
your interpreter (`python3 -VV`, `python3 -c "import sys; print(sys.version_info)"`)
and the official "What's New in Python 3.14" document.

## Release Snapshot

| Build | Binary | What it is | Fallback if unavailable |
|-------|--------|------------|-------------------------|
| Default (GIL) | `python3.14` | Standard build; all features below | — (baseline) |
| Free-threaded | `python3.14t` | PEP 779: officially supported, separate build; GIL removed | Default build + `concurrent.interpreters` or `multiprocessing` |

Headline features, all default-build:

| Feature | PEP | Module / syntax | Pre-3.14 fallback |
|---------|-----|-----------------|-------------------|
| Template strings | 750 | `t"..."` → `string.templatelib.Template` | None — explicit escaping functions |
| Deferred annotations | 649/749 | Lazy `__annotations__`, `annotationlib` | `from __future__ import annotations` |
| Subinterpreters in stdlib | 734 | `concurrent.interpreters`, `InterpreterPoolExecutor` | `multiprocessing` |
| Zstandard compression | 784 | `compression.zstd` | `zstandard` PyPI package |
| Unparenthesized except | 758 | `except A, B:` | `except (A, B):` (works everywhere) |
| finally control-flow warning | 765 | `SyntaxWarning` | Manual review (it was always a bug magnet) |
| Remote debugging | 768 | `sys.remote_exec`, `pdb -p` | py-spy (sampling only) |
| Asyncio introspection | — | `python -m asyncio ps/pstree` | aiomonitor, manual task dumps |

## Template Strings (PEP 750)

### The core fact: a t-string is NOT a str

```python
from string.templatelib import Template

name = "World"
greeting = t"Hello {name}"

type(greeting)        # <class 'string.templatelib.Template'>
print(greeting)       # NOT "Hello World" - prints the Template repr
"Hello " + name       # str
t"Hello {name}" + ""  # TypeError: Template + str is disallowed
```

f-strings eagerly produce `str`. t-strings produce a `Template` object that
captures the static strings and the interpolated values *separately*, so a
processing function can decide how to combine them — escaping, quoting,
parameterizing — before anything becomes a string.

**Division of labor:**

| Use | For |
|-----|-----|
| f-string | Display: logs you format eagerly, messages, repr-ish output |
| t-string | Anything that crosses a syntax boundary: SQL, HTML, shell, regex, structured logging |
| `str.format` / `string.Template` ($-style) | Untrusted *format strings* (user supplies the template, you supply values) |

A t-string is still code — the template literal lives in your source. It does
not make user-supplied format strings safe; it makes *your* templates
injection-resistant by construction.

### Template anatomy

```python
from string.templatelib import Template, Interpolation

amount = 42
tpl = t"total: {amount:>8} units"

tpl.strings          # ('total: ', ' units')   - always len(interpolations) + 1
tpl.interpolations   # (Interpolation(42, 'amount', None, '>8'),)
tpl.values           # (42,)                   - shortcut for interpolation values
```

Each `Interpolation` carries:

| Attribute | Type | Meaning |
|-----------|------|---------|
| `value` | `object` | The evaluated expression result (eager, at t-string creation) |
| `expression` | `str` | Source text of the expression (`"amount"`) |
| `conversion` | `Literal["a", "r", "s"] \| None` | `!r` / `!s` / `!a` if present |
| `format_spec` | `str` | Everything after `:` (`">8"`), default `""` |

Values are evaluated **eagerly**, in order, exactly like f-strings. Only the
*rendering* is deferred.

### Iterating a Template

Iteration yields the parts in document order: `str` items for non-empty static
segments, `Interpolation` items for substitutions. Empty static strings are
skipped during iteration (but kept in `.strings`).

```python
for item in t"x={x} y={y}":
    print(type(item).__name__)
# str, Interpolation, str, Interpolation
```

### Reference renderer (f-string equivalence)

Every t-string processor is a function `Template -> T`. The identity renderer
that reproduces f-string output:

```python
from string.templatelib import Template, Interpolation

def render(template: Template) -> str:
    parts: list[str] = []
    for item in template:
        match item:
            case str():
                parts.append(item)
            case Interpolation(value=value, conversion=conv, format_spec=spec):
                if conv == "r":
                    value = repr(value)
                elif conv == "s":
                    value = str(value)
                elif conv == "a":
                    value = ascii(value)
                parts.append(format(value, spec))
    return "".join(parts)

assert render(t"pi ~ {3.14159:.2f}") == f"pi ~ {3.14159:.2f}"
```

### Worked example: parameterized SQL

```python
from string.templatelib import Template, Interpolation

def sql(template: Template) -> tuple[str, list[object]]:
    """Render a t-string into a placeholder query plus parameter list."""
    query: list[str] = []
    params: list[object] = []
    for item in template:
        if isinstance(item, Interpolation):
            query.append("?")
            params.append(item.value)
        else:
            query.append(item)
    return "".join(query), params

user_id = form["id"]                       # attacker-controlled
q, p = sql(t"SELECT * FROM users WHERE id = {user_id}")
cursor.execute(q, p)                       # value travels as a parameter, never as SQL
```

The injection is impossible by construction: interpolated values never enter
the query text. Compare the f-string version, which is a CWE-89 finding.

### Worked example: HTML escaping

```python
import html
from string.templatelib import Template, Interpolation

def safe_html(template: Template) -> str:
    out: list[str] = []
    for item in template:
        if isinstance(item, Interpolation):
            out.append(html.escape(str(item.value)))
        else:
            out.append(item)
    return "".join(out)

comment = '<script>alert("xss")</script>'
safe_html(t"<p>{comment}</p>")
# '<p>&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;</p>'
```

### Worked example: shell command construction

```python
import shlex
from string.templatelib import Template, Interpolation

def sh(template: Template) -> str:
    return "".join(
        shlex.quote(str(item.value)) if isinstance(item, Interpolation) else item
        for item in template
    )

filename = "evil; rm -rf /"
sh(t"wc -l {filename}")      # "wc -l 'evil; rm -rf /'"
```

Prefer `subprocess.run([...], shell=False)` with an argument list whenever you
can; use this pattern only when a shell string is unavoidable. See
[secure-coding](../../../_shared/secure-coding/SKILL.md).

### Composition rules

```python
a = t"one {x}"
b = t"two {y}"

a + b              # OK: Template + Template
a + "plain"        # TypeError - prevents smuggling unprocessed text past escaping
t"" .strings       # ('',) - empty template is valid
rt"raw \n {x}"     # OK: raw + template combine
# bt"..." / ft"..."  -> SyntaxError: bytes/f cannot combine with t
```

Interpolations are full expressions — nested f-strings, conditionals, and
calls are all legal inside `{...}`, same as f-strings (PEP 701 grammar).

### Typing t-string processors

```python
from string.templatelib import Template

def render_markdown(template: Template) -> str: ...

render_markdown(t"# {title}")    # OK
render_markdown(f"# {title}")    # type error AND runtime TypeError if checked:
                                 # str is not Template
```

Accepting `Template` (not `str`) in your API is the enforcement mechanism: a
caller physically cannot pass a pre-formatted (possibly injected) string.

### When NOT to use t-strings

- Pure display formatting — f-strings are simpler and eager.
- Hot paths that render millions of strings — Template construction allocates
  objects an f-string does not; measure before committing *(verify on your
  workload)*.
- Code that must run on ≤3.13 — there is no backport of the syntax.

## Deferred Annotations and annotationlib (PEP 649/749)

### What changed

In 3.14, annotations are no longer evaluated at definition time. The compiler
stores them in a hidden `__annotate__` function; evaluation happens lazily on
first access to `__annotations__` (or through `annotationlib`).

```python
class Node:
    value: int
    next: Node | None      # legal: no quotes, no future import needed

def link(a: Node, b: Node) -> Node: ...
```

Forward references work without string quoting and without
`from __future__ import annotations`. Definition-time cost of complex
annotations drops to near zero; you pay only if something inspects them.

### Stop adding `from __future__ import annotations` in new 3.14 code

The future import forces the older PEP 563 semantics: every annotation becomes
a plain string, and the new lazy machinery (including `Format.FORWARDREF`) is
bypassed. It still works for compatibility, but:

| Codebase | Guidance |
|----------|----------|
| 3.14-only, new code | Do not add the future import; rely on PEP 649 |
| Supports 3.13 and earlier | Keep the future import until the floor is 3.14 |
| 3.14, existing files with the import | Removing it is safe unless code string-compares `__annotations__` values |

If your ruff config enables `FA100` (missing future-annotations import),
disable it for 3.14+ projects — the rule's advice is inverted there. See
[python-anti-patterns.md](python-anti-patterns.md).

### annotationlib: the three formats

```python
import annotationlib
from annotationlib import Format

class Config:
    timeout: float
    parent: Config | None

annotationlib.get_annotations(Config)
# {'timeout': <class 'float'>, 'parent': Config | None}   (Format.VALUE: evaluates)

annotationlib.get_annotations(Config, format=Format.FORWARDREF)
# unresolvable names come back as ForwardRef objects instead of raising

annotationlib.get_annotations(Config, format=Format.STRING)
# {'timeout': 'float', 'parent': 'Config | None'}   (source-like strings)
```

| Format | Behavior | Use for |
|--------|----------|---------|
| `Format.VALUE` | Evaluate; raise `NameError` on unresolvable names | Runtime type use (validation, dispatch) |
| `Format.FORWARDREF` | Evaluate what it can; wrap the rest in `ForwardRef` | Frameworks that must tolerate partially defined modules |
| `Format.STRING` | Return source-like strings without evaluating | Documentation generators, stub tools |

A `ForwardRef` can be resolved later:

```python
ref = annotationlib.get_annotations(Config, format=Format.FORWARDREF)["parent"]
# ... after the module finishes loading:
resolved = ref.evaluate()        # accepts globals=/locals=/owner= overrides
```

### Migration gotchas

- **Direct `obj.__annotations__` access still works** — it triggers lazy
  evaluation and may now raise `NameError` at *access* time instead of
  definition time. Wrap framework-level access in
  `get_annotations(..., format=Format.FORWARDREF)`.
- **Mutating `__annotations__`** replaces the lazy dict with your literal one;
  subsequent `__annotate__` calls are skipped. Legal, but document it.
- **`typing.get_type_hints()`** continues to work and now cooperates with the
  lazy machinery; prefer `annotationlib.get_annotations` for non-typing
  consumers.
- **Runtime annotation consumers** (pydantic, dataclasses-based frameworks,
  ORMs): current releases target 3.14 semantics, but pin and test — behavior
  around partially initialized modules differs from PEP 563 *(verify your
  framework's 3.14 support status)*.

## Free-Threading and Subinterpreters (pointers)

Both are concurrency-model decisions, covered in depth elsewhere — this file
only records the 3.14 status:

- **PEP 779**: the free-threaded build (`python3.14t`) is *officially
  supported* (no longer "experimental"), still a separate binary. Check at
  runtime with `sys._is_gil_enabled()`. Details, extension-compatibility
  rules, and when it actually helps: [free-threading.md](../../python-concurrency/references/free-threading.md)
  (path relative to the `python/` subtree: `python-concurrency/references/`).
- **PEP 734**: `concurrent.interpreters` exposes subinterpreters in the
  stdlib; `concurrent.futures.InterpreterPoolExecutor` gives a pool API.
  Isolated-by-default, per-interpreter GIL. Decision table asyncio vs threads
  vs subinterpreters vs multiprocessing: [../../python-concurrency/SKILL.md](../../python-concurrency/SKILL.md).

## compression.zstd (PEP 784)

3.14 adds first-class Zstandard support and a new `compression` namespace
(`compression.zstd` is new; `compression.gzip`, `compression.bz2`,
`compression.lzma`, `compression.zlib` re-export the legacy modules).

```python
from compression import zstd

blob = zstd.compress(b"payload", level=3)
raw = zstd.decompress(blob)

with zstd.open("archive.bin.zst", "wb") as f:
    f.write(raw)
```

Streaming and dictionary APIs mirror the other compression modules:
`ZstdCompressor` / `ZstdDecompressor` for incremental work, `ZstdFile` for
file objects, `train_dict` / `ZstdDict` for small-payload dictionaries.

Integration points:

| Module | Zstandard support |
|--------|-------------------|
| `tarfile` | `r:zst` / `w:zst` modes |
| `zipfile` | Zstandard compression method constant |
| `shutil` | zstd-compressed tar archive format *(verify exact format name on your build)* |

**Availability check**: `compression.zstd` requires CPython built against
libzstd. Most distro and installer builds include it, but embedded or
hand-built interpreters may not — guard imports:

```python
try:
    from compression import zstd
except ImportError:
    zstd = None      # fall back to the 'zstandard' PyPI package or lzma
```

Pre-3.14 fallback: the `zstandard` package on PyPI (different API surface).

Choosing a codec: zstd generally gives much faster decompression than lzma at
comparable-to-slightly-worse ratios, and better ratios than zlib at similar
speed — but benchmark on your payloads rather than trusting general claims.

## Multiple Exception Types Without Parentheses (PEP 758)

```python
# 3.14+
try:
    fetch()
except TimeoutError, ConnectionError:
    retry()

# Works for except* too
except* TimeoutError, ConnectionError:
    ...
```

The parentheses are only optional when there is **no `as` clause**:

```python
except TimeoutError, ConnectionError as e:     # SyntaxError
except (TimeoutError, ConnectionError) as e:   # required form with 'as'
```

This is purely syntactic sugar. The parenthesized form works on every Python
version — keep it in code with a floor below 3.14, and note that this syntax
was an *error* on 3.0–3.13 (and meant something dangerous in Python 2), so
linters on mixed-version codebases should flag it.

## Control Flow in finally Blocks (PEP 765)

`return`, `break`, and `continue` statements that exit a `finally` block now
emit a `SyntaxWarning` (3.14). They silently swallow in-flight exceptions:

```python
def load() -> dict:
    try:
        return parse(read())
    finally:
        return {}        # SyntaxWarning: 'return' in 'finally' blocks the
                         # active exception - parse errors vanish forever
```

Fix patterns:

```python
# Cleanup only - no control flow in finally
def load() -> dict:
    try:
        return parse(read())
    except ParseError:
        return {}            # explicit, exception-aware fallback
    finally:
        close_handles()      # cleanup is fine

# Loop variant: move break/continue out
for item in items:
    try:
        process(item)
    except ProcessError:
        continue             # decide in except, not finally
    finally:
        item.release()
```

Treat the warning as an error in CI (`-W error::SyntaxWarning` or via
`PYTHONWARNINGS`); the construct is virtually always a latent bug. Future
releases may escalate it *(verify the deprecation schedule)*.

## Improved Error Messages

3.14 continues the error-message program. Representative improvements —
exact wording varies by point release, so treat these as illustrative
*(verify against your interpreter)*:

| Situation | 3.14-era message adds |
|-----------|----------------------|
| Misspelled keyword argument | `Did you mean 'flush'?` suggestion on `TypeError` |
| Unpacking mismatch | Received count alongside expected: `too many values to unpack (expected 2, got 5)` |
| `elif` after `else` | Targeted `SyntaxError` naming the misordered blocks |
| Invalid string prefix (e.g. `bf"..."`) | Explicit "prefixes are incompatible" instead of generic `invalid syntax` |
| Forgetting `self.` on attribute access | `NameError` suggesting the instance attribute |
| Missing `else` in conditional expression | Points at the incomplete `x if cond` form |

Practical impact: paste the *full* error text into triage. Modern CPython
errors often contain the fix; truncating them in logs throws that away. The
color/highlight behavior of tracebacks honors `NO_COLOR`, `FORCE_COLOR`, and
`PYTHON_COLORS` environment variables — set `PYTHON_COLORS=0` in CI log
pipelines that choke on ANSI sequences.

## Remote Debugging (PEP 768)

3.14 adds a zero-overhead-when-idle interface for attaching debug code to a
**running** CPython process — no restart, no ptrace-based bytecode injection
hacks.

```sh
# Attach the stdlib debugger to a live process
python3.14 -m pdb -p 12345
```

Programmatic form — inject a script that the target executes at its next safe
eval-loop checkpoint:

```python
import sys
sys.remote_exec(12345, "/tmp/probe.py")   # pid, path to script
```

The script runs inside the target interpreter; typical probes dump stacks
(`faulthandler.dump_traceback()`), inspect globals, or enable tracing.

Security and opt-out controls (audit these for production images):

| Control | Effect |
|---------|--------|
| `PYTHON_DISABLE_REMOTE_DEBUG=1` | Disables the interface for that process |
| `-X disable-remote-debug` | Same, per invocation |
| `--without-remote-debug-protocol` build flag *(verify exact configure flag name)* | Removes support at compile time |

OS-level protections still apply: attaching requires the same privileges as
debugging the process by other means (same user / appropriate capabilities on
Linux; debugging entitlements on macOS — on hardened production hosts expect
this to be denied by default).

When you only need a sampling view without injecting code, `py-spy dump`
remains the lighter-touch option; see
[profiling-tools](../../../tooling/diagnostics/references/profiling-tools.md).

## Asyncio Introspection CLI

3.14 ships a CLI for inspecting the task state of a **live** asyncio process
(built on the same remote-debugging machinery):

```sh
python3.14 -m asyncio ps 12345       # flat table: task name, coroutine stack
python3.14 -m asyncio pstree 12345   # await tree: who is awaiting whom
```

Use it for the classic production questions — "what is this service stuck
on?", "which task never completes?", "is something awaiting a lock forever?" —
without adding instrumentation to the app.

```text
$ python -m asyncio pstree 12345
└── Task-1 (main)
    └── serve()
        ├── Task-7 (handler-42)  await read()
        └── Task-9 (flusher)     await Lock.acquire()   <- suspect
```

Triage workflow: `pstree` to find the stuck leaf → `ps` for its full coroutine
stack → fix the await (missing timeout, lock ordering, forgotten `task_done`).
Pair with `asyncio.Task.set_name()` at spawn sites — unnamed tasks make these
dumps much harder to read. Patterns:
[asyncio-patterns.md](../../python-concurrency/references/asyncio-patterns.md)
(under `python-concurrency/references/`).

## Performance: Tail-Call Interpreter

3.14 adds an alternative interpreter core that uses tail calls between opcode
handlers instead of one giant switch. It is a **build-time** option (requires
a recent Clang with the relevant tail-call guarantees; not the default in all
distributions) — your code does not change.

Reported speedups average in the single-digit percent range on standard
benchmark suites; some widely circulated early numbers were inflated by an
unrelated compiler regression in the baseline. Treat any specific figure as
unverified until you run your own workload (`hyperfine 'python3.13 bench.py'
'python3.14 bench.py'`). The safe claims:

- 3.14 is generally at least as fast as 3.13 for pure-Python code.
- The free-threaded build trades some single-thread speed for parallelism —
  measure before standardizing on `python3.14t`.
- The experimental JIT remains opt-in and off by default *(verify status on
  your build: `python3 -c "import sys; print(sys._jit.is_enabled())"` on
  builds that expose it)*.

## Smaller Improvements

Hand-picked items worth knowing; all *(verify exact API shape against the
3.14 What's New)*:

| Area | Change | Why you care |
|------|--------|--------------|
| `map()` | `strict=True` keyword | Same length-mismatch protection `zip(strict=True)` got in 3.10 |
| `pathlib` | `Path.copy()`, `Path.move()`, `copy_into()`, `move_into()` | File operations without `shutil` imports |
| `uuid` | `uuid6()`, `uuid7()`, `uuid8()` (RFC 9562) | `uuid7` = time-ordered IDs, the modern DB-key default |
| `argparse` | Color output, better suggestions on error | Nicer CLIs for free |
| PyREPL | Syntax highlighting, smarter completion (e.g. import names) | The default `python3` prompt, not a third-party shell |
| `dbm` | `dbm.sqlite3` as default backend (3.13) carried forward | Portable small key-value storage |
| Warnings | `SyntaxWarning` for `finally` control flow (PEP 765) | See section above |

Deliberately *not* in 3.14: no removal of the GIL from the default build, no
stable JIT, no `from __future__ import annotations` removal. Plan migrations,
not rewrites.

## Migration Checklist (3.12/3.13 to 3.14)

Run in order; each step is independently shippable:

1. **Toolchain**: update `requires-python = ">=3.14"` (or keep a lower floor
   and gate features), `uv python install 3.14`, bump CI matrix. Set ruff
   `target-version = "py314"`.
2. **Annotations**: if the floor is now 3.14, remove
   `from __future__ import annotations` file by file; replace quoted forward
   references with bare names; switch introspection code to
   `annotationlib.get_annotations`.
3. **Lint config**: disable `FA100`-style rules; run
   `ruff check --select UP --fix` to modernize syntax to the new floor.
4. **finally blocks**: enable `-W error::SyntaxWarning` in the test runner;
   fix every PEP 765 hit (each one is a swallowed-exception bug).
5. **Compression**: replace `zstandard` PyPI usage with `compression.zstd`
   where the floor allows; keep the import guard if you ship to mixed fleets.
6. **Templates**: introduce t-strings at injection-prone seams (SQL, HTML,
   shell) — change function signatures to accept `Template`, not `str`, so
   the type checker enforces the boundary.
7. **Concurrency review**: re-evaluate CPU-bound code against the
   free-threading/subinterpreter decision table in
   [../../python-concurrency/SKILL.md](../../python-concurrency/SKILL.md) —
   do not switch builds casually.
8. **Verify**: full test suite on 3.14, then once more with
   `PYTHONWARNINGS=error::DeprecationWarning` to surface removals scheduled
   for 3.15/3.16.
