# Python Anti-Patterns (with ruff rule IDs)

Use this when:

- You are reviewing Python code and want each finding tied to an enforceable
  ruff rule and a concrete fix.
- You are configuring ruff and want to know which rule categories catch which
  classes of mistake.
- You are modernizing legacy code (`ruff check --select UP --fix`) and want the
  before/after for the common rewrites.

Skip this file if:

- You need the positive feature tour (t-strings, deferred annotations). Use
  [python-3.14-features.md](python-3.14-features.md).
- Your question is which version a feature needs. Use [../SKILL.md](../SKILL.md)
  and [version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md).
- The problem is concurrency-model selection. Use
  [../../python-concurrency/SKILL.md](../../python-concurrency/SKILL.md).

Jump to:

- How to read this file
- Minimal ruff configuration
- Mutable & default-argument traps
- Exception-handling anti-patterns
- Resource & context-manager anti-patterns
- Async anti-patterns
- Typing anti-patterns
- Legacy-syntax anti-patterns (UP)
- Security anti-patterns (S)
- Comprehension, loop & dict anti-patterns
- Testing & debugging anti-patterns
- Summary table (anti-pattern → rule → fix)

Rule IDs name the ruff check that detects each item. Ruff's rule set evolves
between releases — for any rule below, confirm with `ruff rule <ID>` and verify
against your ruff version before pinning it in CI.

## How to read this file

Each entry: the bad pattern, the ruff rule that flags it, and the fix. A rule in
**bold** is part of ruff's default rule set; the rest you opt into via
`[tool.ruff.lint] select = [...]`. Many of these are auto-fixable
(`ruff check --fix`); a `[*]` next to a rule in `ruff rule <ID>` output marks it
fixable.

## Minimal ruff configuration

Turn the categories in this file on:

```toml
# pyproject.toml
[tool.ruff]
target-version = "py314"          # gates UP rules to your real floor; lower if you ship older
src = ["src"]

[tool.ruff.lint]
select = [
    "E", "F", "W",                # pycodestyle + Pyflakes (the defaults)
    "B",                          # flake8-bugbear (mutable defaults, etc.)
    "UP",                         # pyupgrade (legacy-syntax modernization)
    "SIM",                        # flake8-simplify
    "C4",                         # flake8-comprehensions
    "ASYNC",                      # flake8-async (blocking calls in async)
    "S",                          # flake8-bandit (security)
    "BLE",                        # blind-except
    "RUF",                        # ruff-native rules
    "T20",                        # flake8-print (stray print)
    "PTH",                        # flake8-use-pathlib
]

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S101"]             # assert is fine in tests
```

`target-version` matters: `UP` rewrites are gated to the version you declare, so
ruff will not rewrite to syntax your deployment interpreter lacks.

## Mutable & default-argument traps

### Mutable default argument — `B006`

```python
# BAD: the list is created once and shared across every call
def append(item, into=[]):        # B006 mutable-argument-default
    into.append(item)
    return into

# GOOD: sentinel, build inside
def append(item, into: list | None = None) -> list:
    if into is None:
        into = []
    into.append(item)
    return into
```

### Function call in default argument — `B008`

```python
def handler(when=datetime.now()):     # B008: evaluated once at import time
    ...
def handler(when: datetime | None = None) -> None:
    when = when or datetime.now()     # evaluated per call
```

Exception: callable factories ruff knows are safe (e.g. `Query(...)` in some
frameworks) can be allow-listed via
`[tool.ruff.lint.flake8-bugbear] extend-immutable-calls`.

### Loop variable captured by closure — `B023`

```python
# BAD: every lambda sees the final i
callbacks = [lambda: i for i in range(3)]   # B023; all return 2

# GOOD: bind via default argument
callbacks = [lambda i=i: i for i in range(3)]
```

## Exception-handling anti-patterns

### Bare except — **`E722`** / blind `except Exception` — `BLE001`

```python
# BAD
try:
    work()
except:                 # E722 bare-except
    pass
try:
    work()
except Exception:       # BLE001 blind-except (when re-raise/handling is absent)
    pass

# GOOD: name the type, log, and re-raise or convert
try:
    work()
except ConnectionError as e:
    log.warning("connection failed", exc_info=e)
    raise
```

### Swallowing with `pass` — `S110` / `SIM105`

`try/except/pass` hides bugs (`S110` for security-relevant swallowing). When you
genuinely want to ignore one exception type, `contextlib.suppress` says so
explicitly (`SIM105` suggests it):

```python
import contextlib
with contextlib.suppress(FileNotFoundError):
    path.unlink()
```

### Losing the cause — `B904`

```python
# BAD: inside an except block, raising without chaining drops the traceback
except ValueError:
    raise BadRequest("bad input")          # B904 raise-without-from-inside-except

# GOOD
except ValueError as e:
    raise BadRequest("bad input") from e
```

### `raise NotImplemented` — `F901`

```python
def area(self): raise NotImplemented       # F901: NotImplemented is a value, not an exception
def area(self): raise NotImplementedError  # correct
```

## Resource & context-manager anti-patterns

### Unclosed file / resource — `SIM115`

```python
# BAD: leaks the handle on exception
f = open(path)                # SIM115 open-file-with-context-handler
data = f.read()

# GOOD
with open(path, encoding="utf-8") as f:
    data = f.read()
```

For a dynamic set of resources use `contextlib.ExitStack`. (Always pass
`encoding=` to `open` for text — `PLW1514`/`W` family flags the missing encoding
on some configs; verify against your ruff version.)

### String path manipulation instead of pathlib — `PTH` family

```python
# BAD
full = os.path.join(base, name)           # PTH118
if os.path.exists(full):                   # PTH110
    ...
# GOOD
full = Path(base) / name
if full.exists():
    ...
```

## Async anti-patterns

### Blocking call inside async — `ASYNC230` / `ASYNC251`

```python
# BAD: blocks the entire event loop
async def fetch():
    time.sleep(1)                  # ASYNC251 blocking-sleep-in-async-function
    data = open("f").read()        # ASYNC230 blocking-open-call-in-async-function
    return requests.get(url)       # use an async client

# GOOD
async def fetch():
    await asyncio.sleep(1)
    async with aiofiles.open("f") as fp:
        data = await fp.read()
    async with httpx.AsyncClient() as client:
        return await client.get(url)
```

Run unavoidable blocking work off the loop: `await asyncio.to_thread(fn, ...)`.

### Fire-and-forget task — `RUF006`

```python
# BAD: task may be garbage-collected before it runs; exceptions vanish
asyncio.create_task(background())          # RUF006 asyncio-dangling-task

# GOOD: keep a reference, or use a TaskGroup (3.11+)
async with asyncio.TaskGroup() as tg:
    tg.create_task(background())
```

See [asyncio-patterns](../../python-concurrency/references/asyncio-patterns.md).

## Typing anti-patterns

### Missing type parameters / bare collection — `UP006` / type-checker `type-arg`

```python
def users() -> list:               # type checker: Missing type parameters
    ...
def users() -> list[User]:         # parameterize
    ...
```

### `Optional[X]` / `Union[A, B]` instead of `|` — `UP045` / `UP007`

```python
def f(x: Optional[int]) -> Union[str, bytes]: ...   # UP045 / UP007
def f(x: int | None) -> str | bytes: ...
```

### Deprecated `typing.List` / `typing.Dict` — `UP035` / `UP006`

```python
from typing import List, Dict      # UP035 deprecated-import
def g() -> List[Dict[str, int]]: ...
# GOOD: builtin generics, no import
def g() -> list[dict[str, int]]: ...
```

Deep typing guidance (PEP 695, protocols, overloads) lives in
[python-typing](../../python-typing/SKILL.md).

## Legacy-syntax anti-patterns (UP)

`ruff check --select UP --fix` performs these mechanically. Set
`target-version` first so it only rewrites to syntax you can run.

| Legacy | Modern | Rule |
|--------|--------|------|
| `"%s" % x` / `.format()` for simple cases | f-string | `UP031` / `UP032` |
| `super(MyClass, self)` | `super()` | `UP008` |
| `class C(object):` | `class C:` | `UP004` |
| `open(path, "rU")` | `open(path)` | `UP015` |
| `from typing import List` | builtin `list` | `UP035` / `UP006` |
| `Optional[int]` / `Union[a, b]` | `int \| None` / `a \| b` | `UP045` / `UP007` |
| `TypeVar("T")` + `Generic[T]` | `class C[T]` (3.12+) | `UP046` / `UP047` (verify on your ruff version) |
| `yield`-loop just forwarding | `yield from` | `UP028` |

Do **not** let ruff add `from __future__ import annotations` on a 3.14 target —
on 3.14 deferred annotations are the default and the future import re-enables the
old string semantics. See [python-3.14-features.md](python-3.14-features.md) -
Deferred Annotations.

## Security anti-patterns (S)

The `S` (flake8-bandit) rules catch the high-severity classics. Triage findings
through [secure-coding](${CLAUDE_SKILL_DIR}/_shared/secure-coding/SKILL.md).

### Shell injection via `subprocess(..., shell=True)` — `S602` / `S604` / `S605`

```python
# BAD: user input reaches the shell
subprocess.run(f"ls {user_dir}", shell=True)        # S602 subprocess-popen-with-shell-equals-true

# GOOD: argument vector, no shell
subprocess.run(["ls", "--", user_dir], check=True)  # list args, "--" stops option parsing
```

### `os.system` / partial-path exec — `S605` / `S607`

Prefer `subprocess.run([...])` with an absolute or `shutil.which`-resolved
executable over `os.system` and bare command names.

### Unsafe deserialization — `S301` (pickle) / `S506` (yaml)

```python
pickle.loads(network_bytes)              # S301: pickle executes arbitrary code on load
data = yaml.load(text)                    # S506: full loader can construct arbitrary objects
# GOOD
data = yaml.safe_load(text)               # safe_load only builds primitives
# pickle: use json/msgpack for untrusted data; pickle only your own trusted artifacts
```

### `eval` / `exec` on input — `S307` / `S102`

Never feed untrusted strings to `eval`/`exec`. Parse with `ast.literal_eval` for
literals, or a real parser for anything structured.

### Hardcoded secrets — `S105` / `S106`

```python
API_KEY = "sk-live-1234"                  # S105 hardcoded-password-string
# GOOD: read from the environment / a secrets manager
API_KEY = os.environ["API_KEY"]
```

### Insecure temp / `assert` for runtime checks — `S108` / `S101`

Use `tempfile.NamedTemporaryFile`/`mkstemp`, not hardcoded `/tmp/...` (`S108`).
`assert` is stripped under `python -O` — never use it for production validation
(`S101`); raise an explicit exception instead. `S101` is expected (and ignored)
in test files.

## Comprehension, loop & dict anti-patterns

### Needless `list()`/`dict()` around a comprehension — `C4xx`

```python
list([x for x in xs])             # C411 -> [x for x in xs]
dict([(k, v) for k, v in items])  # C404 -> {k: v for k, v in items}
sum([x for x in xs])              # C419 -> sum(x for x in xs)  (generator, no temp list)
```

### `for`-append loop that should be a comprehension — `PERF401`

```python
out = []
for x in xs:                       # PERF401
    if x > 0:
        out.append(x * 2)
out = [x * 2 for x in xs if x > 0]
```

### `.keys()` membership / index-based iteration — `SIM118` / `enumerate`

```python
if k in d.keys():                  # SIM118 -> if k in d
for i in range(len(seq)):          # use enumerate when you need the index
    use(seq[i])
for i, item in enumerate(seq):
    use(item)
```

### Mutating a collection while iterating it

Not always lint-caught — iterate over a copy (`for x in list(items):`) or build
a new collection. Deleting from a `dict`/`list` mid-iteration corrupts the loop.

## Testing & debugging anti-patterns

### Stray `print` for debugging — `T201`

```python
print("got here", value)           # T201 print
# GOOD: structured logging
logger.debug("checkpoint", extra={"value": value})
```

### `breakpoint()` / `pdb` left in code — `T100`

`ruff` flags committed `breakpoint()` and `pdb.set_trace()` calls (`T100`).

### Only-happy-path tests / over-mocking

Lint cannot catch coverage of error paths. Test the failure modes too — invalid
input, conflicts, timeouts — and mock only at external boundaries. Patterns in
[python-testing](../../python-testing/SKILL.md).

## Summary table (anti-pattern → rule → fix)

| Anti-pattern | ruff rule(s) | Fix |
|--------------|-------------|-----|
| Mutable default argument | `B006` | `None` sentinel, build inside |
| Call in default argument | `B008` | `None` default, evaluate per call |
| Closure over loop variable | `B023` | bind via default arg |
| Bare / blind except | `E722`, `BLE001` | name the type; log; re-raise or convert |
| `try/except/pass` swallow | `S110`, `SIM105` | `contextlib.suppress(SpecificError)` |
| Raise without chaining | `B904` | `raise X(...) from e` |
| `raise NotImplemented` | `F901` | `raise NotImplementedError` |
| Unclosed file/resource | `SIM115` | `with` block / `ExitStack` |
| String path math | `PTH` family | `pathlib.Path` |
| Blocking call in async | `ASYNC230`, `ASYNC251` | async libs; `asyncio.to_thread` |
| Dangling asyncio task | `RUF006` | keep a ref or use `TaskGroup` |
| Bare collection type | `UP006`, type-arg | parameterize: `list[T]` |
| `Optional`/`Union` | `UP045`, `UP007` | `X \| None`, `A \| B` |
| `typing.List`/`Dict` import | `UP035`, `UP006` | builtin generics |
| `%`/`.format()` strings | `UP031`, `UP032` | f-strings |
| Old `super(C, self)` | `UP008` | `super()` |
| `shell=True` with input | `S602`, `S604`, `S605` | list args + `--`, no shell |
| `pickle.loads` untrusted | `S301` | json/msgpack for untrusted data |
| `yaml.load` | `S506` | `yaml.safe_load` |
| `eval`/`exec` on input | `S307`, `S102` | `ast.literal_eval` / real parser |
| Hardcoded secret | `S105`, `S106` | env var / secrets manager |
| Hardcoded temp path | `S108` | `tempfile` |
| `assert` for prod checks | `S101` | raise explicit exception |
| Redundant `list()`/`dict()` | `C411`, `C404`, `C419` | drop the wrapper / use generator |
| Append-loop | `PERF401` | comprehension |
| `k in d.keys()` | `SIM118` | `k in d` |
| Stray `print` | `T201` | logging |
| Left-in `breakpoint()` | `T100` | remove |

## Related Skills

- [modern-python](../SKILL.md) — feature gates and the positive patterns these anti-patterns violate
- [python-typing](../../python-typing/SKILL.md) — typing anti-patterns in depth and strict-checker config
- [python-concurrency](../../python-concurrency/SKILL.md) — async anti-patterns and TaskGroup usage
- [python-tooling](../../python-tooling/SKILL.md) — wiring ruff into uv projects and CI
- [secure-coding](${CLAUDE_SKILL_DIR}/_shared/secure-coding/SKILL.md) — triage for the `S` (bandit) findings
