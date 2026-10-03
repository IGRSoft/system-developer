# Python 3.14 Feature Tour

Python 3.14 was released in October 2025. Version gates and routing live in [../SKILL.md](../SKILL.md); free-threading and subinterpreters in [free-threading.md](../../python-concurrency/references/free-threading.md) and [subinterpreters.md](../../python-concurrency/references/subinterpreters.md); lint rules in [python-anti-patterns.md](python-anti-patterns.md). Point releases adjust error wording and library details, so check the official "What's New in Python 3.14" when exact behavior matters.

## Release Snapshot

Builds: `python3.14` is the standard build. `python3.14t` is the free-threaded build (PEP 779: officially supported, still a separate binary); without it, use `concurrent.interpreters` or `multiprocessing`.

| Feature | PEP | Module / syntax | Pre-3.14 fallback |
|---------|-----|-----------------|-------------------|
| Template strings | 750 | `t"..."` → `Template` | explicit escaping functions |
| Deferred annotations | 649/749 | lazy `__annotations__`, `annotationlib` | `from __future__ import annotations` |
| Subinterpreters | 734 | `concurrent.interpreters` | `multiprocessing` |
| Zstandard | 784 | `compression.zstd` | `backports.zstd` / `zstandard` |
| Unparenthesized except | 758 | `except A, B:` | `except (A, B):` |
| finally control-flow warning | 765 | `SyntaxWarning` | manual review |
| Remote debugging | 768 | `sys.remote_exec`, `pdb -p` | py-spy (sampling only) |
| Asyncio introspection | — | `python -m asyncio ps/pstree` | manual task dumps |

## Template Strings (PEP 750)

### A t-string is not a str

```python
greeting = t"Hello {name}"
type(greeting)        # <class 'string.templatelib.Template'>
print(greeting)       # prints the Template repr, not "Hello World"
greeting + ""         # TypeError: Template + str is disallowed
```

A `Template` keeps the static strings and the interpolated values separate, so a processor decides how to combine them (escape, quote, parameterize) before anything becomes a string.

| Use | For |
|-----|-----|
| f-string | display: logs, messages |
| t-string | output that crosses a syntax boundary: SQL, HTML, shell, regex, structured logging |
| `str.format` / `string.Template` | user-supplied format strings |

The template literal lives in your source: t-strings make your templates injection-resistant, not user-supplied format strings.

### Template anatomy

```python
amount = 42
tpl = t"total: {amount:>8} units"

tpl.strings          # ('total: ', ' units')   always len(interpolations) + 1
tpl.interpolations   # (Interpolation(42, 'amount', None, '>8'),)
tpl.values           # (42,)
```

| `Interpolation` attribute | Meaning |
|---------------------------|---------|
| `value` | evaluated result (eager, at creation) |
| `expression` | source text, e.g. `"amount"` |
| `conversion` | `"r"`, `"s"`, `"a"`, or `None` |
| `format_spec` | text after `:`, default `""` |

Values are evaluated eagerly, in order, like f-strings; only rendering is deferred. Iterating a `Template` yields `str` and `Interpolation` items in document order, skipping empty static strings (they stay in `.strings`).

### Reference renderer (f-string equivalence)

Every processor is a function `Template -> T`. This one reproduces f-string output:

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
def sql(template: Template) -> tuple[str, list[object]]:
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
cursor.execute(q, p)                       # the value travels as a parameter
```

Interpolated values never enter the query text; the f-string version is a CWE-89 finding.

### Worked example: HTML escaping

```python
import html

def safe_html(template: Template) -> str:
    return "".join(
        html.escape(str(item.value)) if isinstance(item, Interpolation) else item
        for item in template
    )

safe_html(t"<p>{comment}</p>")   # '<p>&lt;script&gt;...</p>' for a <script> payload
```

### Worked example: shell command construction

```python
import shlex

def sh(template: Template) -> str:
    return "".join(
        shlex.quote(str(item.value)) if isinstance(item, Interpolation) else item
        for item in template
    )

sh(t"wc -l {filename}")      # "wc -l 'evil; rm -rf /'"
```

Prefer `subprocess.run([...])` with an argument list; use this only when a shell string is unavoidable. See [secure-coding](../../../_shared/secure-coding/SKILL.md).

### Composition and typing

```python
a + b              # OK: Template + Template
a + "plain"        # TypeError: stops unprocessed text slipping past escaping
rt"raw \n {x}"     # OK: raw + template
# bt"..." / ft"..."  SyntaxError
```

Interpolations accept full expressions, as in f-strings. Accepting `Template` rather than `str` in an API is the enforcement: the type checker rejects a pre-formatted string. Iterating a `str` silently yields characters, so add an `isinstance(t, Template)` check where untyped callers exist.

Skip t-strings for plain display, for hot paths where the extra allocations measurably matter, and for code that must run on 3.13 or earlier (no backport).

## Deferred Annotations and annotationlib (PEP 649/749)

### What changed

Annotations are no longer evaluated at definition time. The compiler stores them in an `__annotate__` function, evaluated on first access to `__annotations__` or through `annotationlib`.

```python
class Node:
    value: int
    next: Node | None      # no quotes, no future import

def link(a: Node, b: Node) -> Node: ...
```

Forward references work unquoted, and definition-time cost drops to near zero.

### The future import in 3.14 code

`from __future__ import annotations` forces PEP 563 semantics: every annotation becomes a string and the lazy machinery (including `Format.FORWARDREF`) is bypassed.

| Codebase | Guidance |
|----------|----------|
| 3.14 floor, new code | don't add the future import |
| supports 3.13 or earlier | keep it until the floor is 3.14 |
| 3.14, files that already have it | removing it is safe unless code string-compares `__annotations__` values |

Ruff's `FA` rules only fire for targets below 3.10, so they are inert at `py314`; check `lint.isort.required-imports`, which commonly injects the future import (`I002`).

### annotationlib: the three formats

```python
import annotationlib
from annotationlib import Format

class Config:
    timeout: float
    parent: Config | None

annotationlib.get_annotations(Config)                         # VALUE: evaluated objects
annotationlib.get_annotations(Config, format=Format.FORWARDREF)  # unresolvable names → ForwardRef
annotationlib.get_annotations(Config, format=Format.STRING)   # {'timeout': 'float', ...}
```

| Format | Behavior | Use for |
|--------|----------|---------|
| `VALUE` | evaluate; `NameError` on unresolvable names | runtime type use (validation, dispatch) |
| `FORWARDREF` | evaluate what it can, wrap the rest in `ForwardRef` | frameworks tolerating partly loaded modules |
| `STRING` | source-like strings, no evaluation | doc generators, stub tools |

Resolve a `ForwardRef` later with `ref.evaluate()` (accepts `globals=`, `locals=`, `owner=`).

### Migration gotchas

- `obj.__annotations__` still works but evaluates on access, so a `NameError` can now surface at access time. Framework code should use `get_annotations(..., format=Format.FORWARDREF)`.
- Assigning `__annotations__` replaces the lazy dict; `__annotate__` is no longer consulted.
- `typing.get_type_hints()` still works with the lazy machinery; non-typing consumers should use `annotationlib.get_annotations`.
- Runtime annotation consumers (pydantic, dataclass-based frameworks, ORMs) behave differently around partly initialized modules than under PEP 563; pin and test them on 3.14.

## compression.zstd (PEP 784)

3.14 adds a `compression` namespace: `compression.zstd` is new; `compression.gzip`, `.bz2`, `.lzma`, `.zlib` re-export the existing modules.

```python
from compression import zstd

blob = zstd.compress(b"payload", level=3)
raw = zstd.decompress(blob)
with zstd.open("archive.bin.zst", "wb") as f:
    f.write(raw)
```

`ZstdCompressor`/`ZstdDecompressor` handle streaming, `ZstdFile` file objects, `train_dict`/`ZstdDict` small-payload dictionaries. Integrations: `tarfile` `r:zst`/`w:zst` modes, `zipfile.ZIP_ZSTANDARD`, and the `shutil` `zstdtar` archive format.

### Availability

The module needs CPython built against libzstd, which embedded or hand-built interpreters may lack, so guard the import when shipping to mixed fleets:

```python
try:
    from compression import zstd
except ImportError:
    from backports import zstd     # same API on 3.9-3.13
```

zstd usually decompresses much faster than lzma and compresses better than zlib at similar speed; benchmark on your payloads.

## Multiple Exception Types Without Parentheses (PEP 758)

```python
try:
    fetch()
except TimeoutError, ConnectionError:          # 3.14+; also works with except*
    retry()

except TimeoutError, ConnectionError as e:     # SyntaxError
except (TimeoutError, ConnectionError) as e:   # 'as' requires parentheses
```

It is pure syntax sugar and a `SyntaxError` on 3.13 and earlier; code with a lower floor keeps the parenthesized form.

## Control Flow in finally Blocks (PEP 765)

`return`, `break`, or `continue` leaving a `finally` block now emits a `SyntaxWarning`, because it silently swallows the in-flight exception:

```python
def load() -> dict:
    try:
        return parse(read())
    finally:
        return {}            # SyntaxWarning: parse errors vanish

def load() -> dict:          # fix: decide in except, clean up in finally
    try:
        return parse(read())
    except ParseError:
        return {}
    finally:
        close_handles()
```

In loops, move `break`/`continue` into the `except` branch. The warning is emitted at compile time, so cached `.pyc` files hide it; gate CI with `python -W error::SyntaxWarning -m compileall -f -q src`.

## Improved Error Messages

Representative 3.14 additions (wording varies by point release):

| Situation | Message adds |
|-----------|--------------|
| Misspelled keyword (`whille`) | `Did you mean 'while'?` |
| Unpacking mismatch | `too many values to unpack (expected 2, got 3)` |
| `elif` after `else` | targeted `SyntaxError` naming the misordered blocks |
| Incompatible string prefixes (`bt"..."`) | says the prefixes are incompatible |
| `with` on an async context manager (or the reverse) | suggests `async with` / `with` |

Keep full error text in triage and logs, since it often contains the fix. Tracebacks honor `NO_COLOR`, `FORCE_COLOR`, and `PYTHON_COLORS`; set `PYTHON_COLORS=0` where log pipelines choke on ANSI.

## Remote Debugging (PEP 768)

Attach debug code to a running process without a restart. The target runs it at its next safe eval-loop checkpoint.

```sh
python3.14 -m pdb -p 12345                  # stdlib debugger on a live process
python3.14 -c 'import sys; sys.remote_exec(12345, "/tmp/probe.py")'
```

Probes typically dump stacks (`faulthandler.dump_traceback()`), inspect globals, or enable tracing.

| Control (audit for production images) | Effect |
|---------------------------------------|--------|
| `PYTHON_DISABLE_REMOTE_DEBUG=1` | disables it for the process |
| `-X disable-remote-debug` | same, per invocation |
| `--without-remote-debug` (configure) | removes support at build time |

Attaching needs the same privileges as any debugger (same user or ptrace capability on Linux, root or entitlements on macOS). For a sampling view without injecting code, `py-spy dump` is lighter; see [profiling-tools](../../../tooling/diagnostics/references/profiling-tools.md).

## Asyncio Introspection CLI

Inspects the tasks of a live asyncio process, built on the remote-debugging machinery:

```sh
python3.14 -m asyncio ps 12345       # flat table: tasks and coroutine stacks
python3.14 -m asyncio pstree 12345   # await tree: who awaits whom
```

Use it to find what a service is stuck on: `pstree` locates the stuck leaf, `ps` gives its stack, then fix the await (missing timeout, lock ordering, forgotten `task_done`). Name tasks at spawn (`create_task(..., name=...)`) so dumps are readable. Patterns: [asyncio-patterns.md](../../python-concurrency/references/asyncio-patterns.md).

## Performance: Tail-Call Interpreter

An optional interpreter core that tail-calls between opcode handlers. It is a build-time option (needs Clang 19+), not the default everywhere, and needs no code changes. Gains are typically single-digit percent; measure your workload (`hyperfine 'python3.13 bench.py' 'python3.14 bench.py'`).

- 3.14 is generally at least as fast as 3.13 for pure-Python code.
- The free-threaded build trades single-thread speed for parallelism; measure before standardizing on `python3.14t`.
- The JIT stays experimental and off by default; `sys._jit.is_enabled()` reports it.

## Smaller Improvements

| Area | Change | Why it matters |
|------|--------|----------------|
| `map()` | `strict=True` | length-mismatch check, like `zip(strict=True)` |
| `pathlib` | `Path.copy()`, `move()`, `copy_into()`, `move_into()` | file operations without `shutil` |
| `uuid` | `uuid6()`, `uuid7()`, `uuid8()` (RFC 9562) | `uuid7` gives time-ordered DB keys |
| `argparse` | color output, suggestions on typos | better CLIs for free |
| PyREPL | syntax highlighting, import completion | default `python3` prompt |

The default build keeps the GIL, the JIT stays experimental, and the future import is not removed.

## Migration Checklist (3.12/3.13 to 3.14)

Each step ships independently.

1. Toolchain: `requires-python = ">=3.14"` (or keep a lower floor and gate features), `uv python install 3.14`, CI matrix, ruff `target-version = "py314"`.
2. Annotations: at a 3.14 floor, drop the future import, unquote forward refs, introspect via `annotationlib`.
3. Lint: remove the future import from `isort.required-imports`; run `ruff check --select UP --fix`.
4. finally blocks: add the `compileall` SyntaxWarning gate; fix each hit.
5. Compression: replace `zstandard` with `compression.zstd` where the floor allows.
6. Templates: introduce t-strings at SQL/HTML/shell seams and type those parameters as `Template`.
7. Concurrency: re-check CPU-bound code against the decision table in [python-concurrency](../../python-concurrency/SKILL.md) before switching builds.
8. Verify: run the suite on 3.14, then with `PYTHONWARNINGS=error::DeprecationWarning` to surface upcoming removals.
