# Python Anti-Patterns (with ruff rule IDs)

Each entry gives the bad pattern, the ruff rule that flags it, and the fix. Ruff's default set is only `E4`, `E7`, `E9`, and `F`; enable the rest with `[tool.ruff.lint] select`. `ruff rule <ID>` shows a rule's details and whether it is auto-fixable, and is the check to run before pinning a rule in CI, since the rule set changes between releases. Version gates: [../SKILL.md](../SKILL.md); positive 3.14 features: [python-3.14-features.md](python-3.14-features.md).

## Minimal ruff configuration

```toml
# pyproject.toml
[tool.ruff]
target-version = "py314"          # UP rewrites only to syntax this version has; lower it to your floor
src = ["src"]

[tool.ruff.lint]
select = [
    "E", "F", "W",                # pycodestyle + Pyflakes
    "B",                          # bugbear (mutable defaults, etc.)
    "UP",                         # pyupgrade
    "SIM", "C4", "PERF",          # simplify, comprehensions, perflint
    "ASYNC",                      # blocking calls in async
    "S",                          # bandit (security)
    "BLE",                        # blind except
    "RUF",                        # ruff-native
    "T10", "T20",                 # debugger, print
    "PTH",                        # pathlib
]

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S101"]             # assert is fine in tests
```

## Mutable & default-argument traps

### Mutable default argument — `B006`

```python
def append(item, into=[]):        # B006: one list shared by every call
    into.append(item)
    return into

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

Allow-list safe framework factories with `[tool.ruff.lint.flake8-bugbear] extend-immutable-calls`.

### Loop variable captured by closure — `B023`

```python
callbacks = [lambda: i for i in range(3)]      # B023: all return 2
callbacks = [lambda i=i: i for i in range(3)]  # bind via default argument
```

## Exception-handling anti-patterns

### Bare except — `E722` / blind `except Exception` — `BLE001`

```python
try:
    work()
except:                 # E722
    pass
try:
    work()
except Exception:       # BLE001 when nothing re-raises or handles it
    pass

try:                    # fix: name the type, log, re-raise or convert
    work()
except ConnectionError as e:
    log.warning("connection failed", exc_info=e)
    raise
```

### Swallowing with `pass` — `S110` / `SIM105`

`try/except/pass` hides bugs (`S110`). To ignore one exception type on purpose, use `contextlib.suppress` (`SIM105` suggests it):

```python
with contextlib.suppress(FileNotFoundError):
    path.unlink()
```

### Losing the cause — `B904`

```python
except ValueError:
    raise BadRequest("bad input")          # B904: drops the original traceback
except ValueError as e:
    raise BadRequest("bad input") from e
```

### `raise NotImplemented` — `F901`

`NotImplemented` is a value, not an exception: raise `NotImplementedError`.

## Resource & context-manager anti-patterns

### Unclosed file / resource — `SIM115`

```python
f = open(path)                # SIM115: leaks the handle on exception
data = f.read()

with open(path, encoding="utf-8") as f:
    data = f.read()
```

Use `contextlib.ExitStack` for a dynamic set of resources. `PLW1514` flags text-mode `open` without `encoding=`.

### String path manipulation — `PTH` family

```python
full = os.path.join(base, name)           # PTH118
if os.path.exists(full): ...               # PTH110
full = Path(base) / name
if full.exists(): ...
```

## Async anti-patterns

### Blocking call inside async — `ASYNC210` / `ASYNC230` / `ASYNC251`

```python
async def fetch():
    time.sleep(1)                  # ASYNC251: blocks the event loop
    data = open("f").read()        # ASYNC230
    return requests.get(url)       # ASYNC210

async def fetch():
    await asyncio.sleep(1)
    async with aiofiles.open("f") as fp:
        data = await fp.read()
    async with httpx.AsyncClient() as client:
        return await client.get(url)
```

Run unavoidable blocking work with `await asyncio.to_thread(fn, ...)`.

### Fire-and-forget task — `RUF006`

```python
asyncio.create_task(background())          # RUF006: may be GC'd; exceptions vanish

async with asyncio.TaskGroup() as tg:      # keep a reference, or use a TaskGroup
    tg.create_task(background())
```

See [asyncio-patterns](../../python-concurrency/references/asyncio-patterns.md).

## Typing anti-patterns

| Anti-pattern | Caught by | Fix |
|--------------|-----------|-----|
| Bare `list` / `dict` return type | type checker (mypy `type-arg` under `disallow_any_generics`), not ruff | `list[User]` |
| `Optional[int]`, `Union[str, bytes]` | `UP045`, `UP007` | `int \| None`, `str \| bytes` |
| `from typing import List, Dict` | `UP035`, `UP006` | builtin `list`, `dict` |

Deep typing guidance (PEP 695, protocols, overloads): [python-typing](../../python-typing/SKILL.md).

## Legacy-syntax anti-patterns (UP)

`ruff check --select UP --fix` applies these; set `target-version` first.

| Legacy | Modern | Rule |
|--------|--------|------|
| `"%s" % x` / simple `.format()` | f-string | `UP031` / `UP032` |
| `super(MyClass, self)` | `super()` | `UP008` |
| `class C(object):` | `class C:` | `UP004` |
| `open(path, "rU")` | `open(path)` | `UP015` |
| `Optional[int]` / `typing.List` | `int \| None` / `list` | `UP045`, `UP007` / `UP035`, `UP006` |
| `TypeVar` + `Generic[T]` | `class C[T]` (3.12+) | `UP046` / `UP047` |
| loop that only re-yields | `yield from` | `UP028` |

On a 3.14 target, keep `from __future__ import annotations` out of `lint.isort.required-imports`; it restores the old string semantics ([python-3.14-features.md](python-3.14-features.md), Deferred Annotations).

## Security anti-patterns (S)

Triage `S` findings through [secure-coding](../../../_shared/secure-coding/SKILL.md).

```python
subprocess.run(f"ls {user_dir}", shell=True)        # S602: input reaches the shell
subprocess.run(["ls", "--", user_dir], check=True)  # argument list; "--" ends options
```

| Pattern | Rule | Fix |
|---------|------|-----|
| `os.system`, bare command name | `S605` / `S607` | `subprocess.run([...])` with an absolute or `shutil.which` path |
| `pickle.loads` on untrusted data | `S301` | json/msgpack; pickle only trusted artifacts |
| `yaml.load` | `S506` | `yaml.safe_load` |
| `eval` / `exec` on input | `S307` / `S102` | `ast.literal_eval` or a real parser |
| Hardcoded secret | `S105` / `S106` | environment variable or secrets manager |
| Hardcoded `/tmp/...` | `S108` | `tempfile.NamedTemporaryFile` / `mkstemp` |
| `assert` for runtime checks | `S101` | explicit exception; `-O` strips asserts |

## Comprehension, loop & dict anti-patterns

```python
list([x for x in xs])             # C411 -> [x for x in xs]
dict([(k, v) for k, v in items])  # C404 -> {k: v for k, v in items}
any([x > 0 for x in xs])          # C419 -> any(x > 0 for x in xs)  (short-circuits)

out = []
for x in xs:                       # PERF401 -> [x * 2 for x in xs if x > 0]
    if x > 0:
        out.append(x * 2)

if k in d.keys():                  # SIM118 -> if k in d
for i in range(len(seq)):          # use enumerate(seq) when you need the index
    use(seq[i])
```

Mutating a collection while iterating it is not reliably lint-caught: iterate over a copy (`for x in list(items):`) or build a new collection.

## Testing & debugging anti-patterns

- Stray `print` (`T201`): use logging, e.g. `logger.debug("checkpoint", extra={"value": value})`.
- Committed `breakpoint()` / `pdb.set_trace()` (`T100`): remove.
- Happy-path-only tests and over-mocking aren't lint-detectable: test failure modes (invalid input, conflicts, timeouts) and mock only external boundaries. See [python-testing](../../python-testing/SKILL.md).

## Summary: correctness and async

| Anti-pattern | Rule(s) | Fix |
|--------------|---------|-----|
| Mutable default argument | `B006` | `None` sentinel |
| Call in default argument | `B008` | `None` default, evaluate per call |
| Closure over loop variable | `B023` | bind via default arg |
| Bare / blind except | `E722`, `BLE001` | name the type; re-raise or convert |
| `try/except/pass` | `S110`, `SIM105` | `contextlib.suppress(SpecificError)` |
| Raise without chaining | `B904` | `raise X(...) from e` |
| `raise NotImplemented` | `F901` | `raise NotImplementedError` |
| Unclosed resource | `SIM115` | `with` / `ExitStack` |
| Blocking call in async | `ASYNC210`, `ASYNC230`, `ASYNC251` | async libs; `asyncio.to_thread` |
| Dangling task | `RUF006` | keep a ref or `TaskGroup` |

## Summary: style, typing, security

| Anti-pattern | Rule(s) | Fix |
|--------------|---------|-----|
| String path math | `PTH` | `pathlib.Path` |
| `Optional`/`Union`, `typing.List` | `UP045`, `UP007`, `UP035`, `UP006` | `X \| None`, builtin generics |
| `%`/`.format()`, `super(C, self)` | `UP031`, `UP032`, `UP008` | f-strings, `super()` |
| `shell=True` with input | `S602`, `S604`, `S605` | list args + `--` |
| Unsafe deserialization | `S301`, `S506` | json/msgpack, `yaml.safe_load` |
| `eval`/`exec`, secrets, temp paths, `assert` | `S307`, `S102`, `S105`, `S106`, `S108`, `S101` | see Security table |
| Redundant `list()`/`dict()`, append-loop | `C411`, `C404`, `C419`, `PERF401` | comprehension / generator |
| `k in d.keys()` | `SIM118` | `k in d` |
| `print`, `breakpoint()` | `T201`, `T100` | logging; remove |

## Related Skills

- [python-typing](../../python-typing/SKILL.md): typing anti-patterns and strict-checker config
- [python-concurrency](../../python-concurrency/SKILL.md): async anti-patterns and TaskGroup
- [python-tooling](../../python-tooling/SKILL.md): wiring ruff into uv projects and CI
