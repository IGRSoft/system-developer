# Advanced Typing

Use this when:

- You are writing generic classes or functions and need PEP 695 details: bounds, constraints, defaults, variance, scoping.
- You are designing structural interfaces with `Protocol` and need the `runtime_checkable` rules and traps.
- You are typing dict-shaped payloads with `TypedDict` and need `Required`/`NotRequired`/`ReadOnly` semantics.
- You are writing decorators and need `ParamSpec`/`Concatenate` to preserve signatures.
- You need `@overload` ordering and overlap rules.
- You are shipping or consuming a C extension and need `.pyi` stubs and `py.typed`.

Skip this file if:

- You need baseline syntax, checker selection, or the ratchet strategy. Use [../SKILL.md](../SKILL.md).
- You need 3.14 language features beyond annotations. Use the modern-python skill.
- You are typing test code. Use the python-testing skill.

Jump to:

- PEP 695 Generics in Depth
- Variance: Inferred, Not Declared
- Type Parameter Scoping Rules
- Protocols
- runtime_checkable Caveats
- TypedDict: Required, NotRequired, ReadOnly
- Typed **kwargs with Unpack
- ParamSpec and Concatenate Decorators
- Overloads
- .pyi Stubs for C Extensions

## PEP 695 Generics in Depth

Python 3.12 (PEP 695) made type parameters part of the declaration syntax.
Pre-3.12 fallback for every construct here: module-level `TypeVar(...)` plus
`Generic[...]`/`Protocol[...]` bases.

### Functions

```python
def first[T](items: list[T]) -> T:
    return items[0]

def pairs[K, V](m: dict[K, V]) -> list[tuple[K, V]]:
    return list(m.items())
```

### Bounds and constraints

A *bound* (`T: float`) accepts any subtype of the bound. A *constraint set*
(`S: (str, bytes)`) accepts exactly those types — no subtypes, no mixing:

```python
def clamp[T: float](x: T, lo: T, hi: T) -> T:     # bound: int, float, bool OK
    return min(max(x, lo), hi)

def concat[S: (str, bytes)](a: S, b: S) -> S:     # constraints: all-str or all-bytes
    return a + b
```

Use constraints when behavior differs per branch type and mixing is a bug
(`concat("a", b"b")` must fail). Use bounds everywhere else.

Bounds may be generic or protocol types:

```python
from collections.abc import Hashable

def dedupe[T: Hashable](items: list[T]) -> list[T]:
    return list(dict.fromkeys(items))
```

### Classes

```python
class Stack[T]:
    def __init__(self) -> None:
        self._items: list[T] = []

    def push(self, item: T) -> None:
        self._items.append(item)

    def pop(self) -> T:
        return self._items.pop()

class KeyedCache[K: Hashable, V]:
    def __init__(self) -> None:
        self._data: dict[K, V] = {}
```

Methods may add their own parameters; they nest inside the class scope:

```python
class Box[T]:
    def __init__(self, value: T) -> None:
        self.value = value

    def map[U](self, f: Callable[[T], U]) -> "Box[U]":   # quote pre-3.14 only
        return Box(f(self.value))
```

### Type aliases

The `type` statement creates `TypeAliasType` objects — lazily evaluated, so
forward references work on every supported version without quotes:

```python
type JSON = dict[str, JSON] | list[JSON] | str | int | float | bool | None
type Handler[T] = Callable[[T], None]
type Matrix[T: float] = list[list[T]]
```

Lazy evaluation means errors inside an alias surface at *use*, not definition.
A misspelled name in a `type` alias passes import and fails when a checker or
`alias.__value__` resolves it.

### Type parameter defaults (Python 3.13+, PEP 696)

```python
class Registry[T = object]:
    def __init__(self) -> None:
        self._items: list[T] = []

r = Registry()            # Registry[object]
s: Registry[str] = Registry()
```

Rules: defaulted parameters must come after non-defaulted ones; a default may
reference earlier parameters (`class Pair[A, B = A]`). Pre-3.13 fallback:
`TypeVar("T", default=object)` from `typing_extensions`.

### TypeVarTuple and variadic generics

```python
def head[*Ts](row: tuple[int, *Ts]) -> tuple[*Ts]:
    return row[1:]

class Array[DType, *Shape]: ...
```

Use for fixed-arity heterogeneous tuples (shaped arrays, argument packs).
Most application code never needs this — prefer plain `tuple[X, ...]`.

## Variance: Inferred, Not Declared

PEP 695 removed `covariant=True`/`contravariant=True` declarations. The checker
*infers* variance from how the parameter is used:

- `T` only in return/read positions → covariant (`Producer[Dog]` usable as `Producer[Animal]`)
- `T` only in argument/write positions → contravariant
- `T` in both → invariant

```python
class Producer[T]:
    def get(self) -> T: ...            # T inferred covariant

class Consumer[T]:
    def put(self, item: T) -> None: ...  # T inferred contravariant

class Cell[T]:
    def get(self) -> T: ...
    def set(self, v: T) -> None: ...   # both -> invariant
```

Consequences:

- You cannot force variance. If inference says invariant, the *class design*
  makes it so — split read and write interfaces if you need covariance.
- Mutable containers are invariant by construction: `list[Dog]` is not a
  `list[Animal]` (someone could `append` a `Cat`). Accept `Sequence[Animal]`
  (covariant, read-only) in signatures instead of `list[Animal]`.
- Private attributes (single leading underscore) typed `T` do not block
  covariance inference; public mutable attributes do.

Signature guidance that falls out of variance:

| Position | Prefer | Over | Why |
|----------|--------|------|-----|
| Parameter | `Sequence[T]`, `Mapping[K, V]`, `Iterable[T]` | `list[T]`, `dict[K, V]` | Covariant + accepts more callers |
| Return | Concrete `list[T]` / `dict[K, V]` | Abstract types | Callers get full API |
| Callback param | `Callable[[Animal], R]` | `Callable[[Dog], R]` | Contravariant in arguments |

## Type Parameter Scoping Rules

- Parameters belong to the function/class/alias that declares them; an inner
  generic function may not reuse an enclosing parameter name (checker error).
- The PEP 695 scope is a real (lazy) scope: bounds and defaults are evaluated
  lazily, so they may forward-reference names defined later in the module.
- Old-style `TypeVar` and PEP 695 parameters do not mix in one declaration.
  Migrate a declaration wholesale or leave it.
- `Self` is not a type parameter — it is always available in class bodies
  (3.11+) and is the right return type for fluent APIs and alternative
  constructors (`def parse(cls, s: str) -> Self`).

## Protocols

A `Protocol` describes *structure*: anything with matching members satisfies it,
no inheritance required. This is the static formalization of duck typing.

```python
from typing import Protocol

class Reader(Protocol):
    def read(self, n: int = -1, /) -> bytes: ...

class Closeable(Protocol):
    def close(self) -> None: ...

def drain(src: Reader) -> bytes:
    return src.read()
```

`io.BytesIO`, sockets wrapped in `makefile()`, and your test fake all satisfy
`Reader` without importing it. That is the point: the *consumer* defines the
interface it needs; producers stay decoupled.

### Protocol vs ABC decision

| Factor | Protocol | ABC |
|--------|----------|-----|
| Third-party types can satisfy it | Yes, automatically | Only via `register()` |
| Shared method implementations | Possible but unusual | Primary use case |
| `isinstance` reliability | Presence-only (see caveats) | Exact (nominal) |
| Test fakes | Any matching object | Must subclass |
| Coupling | None | Import + inheritance |

Default to `Protocol`. Reach for ABC when subclasses genuinely share code or
you need nominal identity (plugin registration, exhaustive registries).

### Generic protocols

```python
class Loader[T](Protocol):
    def load(self, raw: bytes) -> T: ...

class JsonLoader:
    def load(self, raw: bytes) -> dict[str, object]:
        return json.loads(raw)

def ingest[T](loader: Loader[T], blob: bytes) -> T:
    return loader.load(blob)
```

### Callback protocols

Use when `Callable[...]` cannot express keyword arguments, defaults, or
overloaded call shapes:

```python
class OnProgress(Protocol):
    def __call__(self, done: int, total: int, *, message: str = "") -> None: ...

def copy_tree(src: Path, dst: Path, on_progress: OnProgress | None = None) -> None: ...
```

### Properties and attributes in protocols

```python
class HasId(Protocol):
    @property
    def id(self) -> str: ...        # satisfied by property OR plain attribute

class Named(Protocol):
    name: str                       # mutable attribute requirement
```

A read-only `@property` requirement is satisfied by a plain attribute; a plain
attribute requirement is *not* satisfied by a read-only property (writes must
be possible).

## runtime_checkable Caveats

`@runtime_checkable` permits `isinstance(obj, Proto)`. Know exactly what that
buys you:

```python
from typing import Protocol, runtime_checkable

@runtime_checkable
class Closeable(Protocol):
    def close(self) -> None: ...

isinstance(open("/etc/hosts"), Closeable)   # True
```

The caveats, in order of how often they bite:

1. **Presence-only.** `isinstance` checks that members *exist* — it never checks
   signatures or return types. An object with `def close(self, force, retries)`
   passes `isinstance(..., Closeable)` and explodes later. Static checking
   remains the authority; runtime checks are a smoke test.
2. **`issubclass` is restricted.** Only *method-only* protocols support
   `issubclass()`. If the protocol has any non-method member (attribute,
   property), `issubclass()` raises
   `TypeError: Protocols with non-method members don't support issubclass()`.
3. **Attribute timing.** Instance attributes set in `__init__` are visible to
   `isinstance` on instances, but a class object itself may not show them —
   another reason `issubclass` is unreliable for data protocols.
4. **Cost.** Each `isinstance` does per-member `hasattr` work (results are
   cached per class on modern CPython — verify against your toolchain). Keep it
   out of hot loops.
5. **No `Callable` member nuance.** Members that are `None` at check time fail
   the check even if the static type allows `None`.

Rule: use `runtime_checkable` for *defensive boundary assertions* (plugin
loading, deserialization), never as a substitute for static checking.

## TypedDict: Required, NotRequired, ReadOnly

`TypedDict` types dict-shaped data crossing boundaries: JSON payloads, config
mappings, `**kwargs` packs. Prefer `dataclass`/attrs for internal models — use
`TypedDict` when the data *is and stays* a dict.

```python
from typing import TypedDict, Required, NotRequired, ReadOnly

class JobSpec(TypedDict):
    cmd: list[str]                       # required (total=True default)
    timeout_s: NotRequired[int]          # may be absent (3.11+)

class LegacyEvent(TypedDict, total=False):
    payload: dict[str, object]           # everything optional...
    kind: Required[str]                  # ...except this (3.11+)

class AuditRecord(TypedDict):
    id: ReadOnly[str]                    # 3.13+ (PEP 705): checkers reject writes
    note: str
```

Version markers: `Required`/`NotRequired` are 3.11+; `ReadOnly` is 3.13+.
Pre-3.13 fallback for both: import from `typing_extensions` (works on all
supported versions and is the conventional source for new typing features).

Semantics worth memorizing:

- `total=False` makes every key optional; `Required[...]`/`NotRequired[...]`
  override per-key in either direction. Prefer per-key markers over `total=False`
  in new code — intent is local and explicit.
- Inheritance composes: a subclass may add keys and (3.13+) widen `ReadOnly`
  to writable, but may not change a key's value type.
- A `TypedDict` is structural at *assignment* but checkers track missing keys:
  `JobSpec(cmd=["ls"])` is fine; reading `spec["timeout_s"]` when it may be
  absent is an error — use `spec.get("timeout_s", 30)`.
- `.get()` with no default returns `V | None` for `NotRequired` keys.
- Runtime, it is a plain `dict` — no validation happens. Validate boundaries
  with a real validator; `TypedDict` only types what you *assert* the shape is.
- The functional form `Movie = TypedDict("Movie", {"name": str})` exists for
  keys that are not identifiers (e.g. `"content-type"`); avoid otherwise.

## Typed **kwargs with Unpack

PEP 692 (3.12; earlier via `typing_extensions`) types `**kwargs` as a whole:

```python
from typing import TypedDict, Unpack, NotRequired

class RetryOpts(TypedDict):
    attempts: int
    backoff_s: NotRequired[float]

def fetch(url: str, **opts: Unpack[RetryOpts]) -> bytes: ...

fetch("https://example.invalid", attempts=3)             # OK
fetch("https://example.invalid", attemps=3)               # checker error: typo caught
```

Use this instead of `**kwargs: Any` whenever the keyword set is closed.

## ParamSpec and Concatenate Decorators

`ParamSpec` captures an entire parameter list so wrappers keep the wrapped
function's exact signature. PEP 695 spelling is `**P` in the bracket list.

### Signature-preserving decorator (the workhorse)

```python
from collections.abc import Callable
import functools, time

def timed[**P, R](func: Callable[P, R]) -> Callable[P, R]:
    @functools.wraps(func)
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        t0 = time.perf_counter()
        try:
            return func(*args, **kwargs)
        finally:
            print(f"{func.__name__}: {time.perf_counter() - t0:.3f}s")
    return wrapper
```

`P.args`/`P.kwargs` must be used together and only as `*args: P.args,
**kwargs: P.kwargs`. Without `ParamSpec`, decorated functions degrade to
`Callable[..., R]` and every call site loses checking — this single pattern
pays for the syntax.

### Decorator factories (decorators with arguments)

```python
def retry[**P, R](attempts: int) -> Callable[[Callable[P, R]], Callable[P, R]]:
    def decorate(func: Callable[P, R]) -> Callable[P, R]:
        @functools.wraps(func)
        def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
            for i in range(attempts):
                try:
                    return func(*args, **kwargs)
                except OSError:
                    if i == attempts - 1:
                        raise
            raise AssertionError("unreachable")
        return wrapper
    return decorate
```

### Concatenate: adding or consuming leading arguments

```python
from typing import Concatenate

class Conn: ...

def with_conn[**P, R](
    func: Callable[Concatenate[Conn, P], R],
) -> Callable[P, R]:
    @functools.wraps(func)
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        conn = Conn()                      # acquire
        return func(conn, *args, **kwargs)  # inject as first arg
    return wrapper

@with_conn
def save(conn: Conn, key: str, value: bytes) -> None: ...

save("k", b"v")                            # checker knows conn is injected
```

`Concatenate[X, P]` = "first a positional `X`, then whatever `P` captured".
Injected parameters must be positional. The mirror direction (wrapper *adds* a
leading parameter to the public signature) is
`Callable[P, R] -> Callable[Concatenate[Conn, P], R]`.

### Async variants

Wrap coroutines by parameterizing on the coroutine's return:

```python
from collections.abc import Awaitable

def traced[**P, R](
    func: Callable[P, Awaitable[R]],
) -> Callable[P, Awaitable[R]]:
    @functools.wraps(func)
    async def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        print(f"-> {func.__name__}")
        return await func(*args, **kwargs)
    return wrapper
```

A decorator that must handle both sync and async callables needs `@overload`
on the decorator itself — see the next section.

## Overloads

`@overload` declares multiple call shapes for one implementation. The checker
matches calls against the overload list top-down; the implementation body is
checked only for *internal* consistency.

```python
from typing import Literal, overload

@overload
def parse(raw: bytes) -> dict[str, object]: ...
@overload
def parse(raw: bytes, *, as_text: Literal[True]) -> str: ...
def parse(raw: bytes, *, as_text: bool = False) -> dict[str, object] | str:
    return raw.decode() if as_text else json.loads(raw)
```

Rules that prevent the common failures:

1. **Implementation is mandatory** outside stub files, must come last, and must
   accept every overload's arguments (usually with broader types).
2. **Order most-specific first.** Checkers take the first match; a general
   overload above a specific one shadows it silently.
3. **Overlap is an error** when two overloads accept the same arguments but
   return incompatible types (mypy `[overload-overlap]`). Make parameter sets
   disjoint — `Literal` flags and keyword-only markers are the standard tools.
4. **Two minimum.** A single `@overload` is a checker error; if you have one
   shape, you do not need overloads.
5. **Runtime is untouched.** Calling an `@overload`-decorated stub directly
   raises `NotImplementedError` via typing machinery; only the implementation
   runs. Overloads exist purely for checkers and IDEs.
6. Prefer a union return or separate functions (`read_text`/`read_bytes`) when
   overloads would only encode a bool flag — overloads are for APIs you cannot
   split.

Overload-on-`None` pattern for defaulted lookups:

```python
@overload
def get(key: str) -> str | None: ...
@overload
def get(key: str, default: str) -> str: ...
def get(key: str, default: str | None = None) -> str | None:
    return _store.get(key, default)
```

## .pyi Stubs for C Extensions

Compiled modules expose no annotations, so checkers see `Any` everywhere. Ship
a stub file next to the compiled module to restore typing.

### Layout

```text
mypkg/
├── __init__.py
├── py.typed              # marker: this package exports types (PEP 561)
├── _native.cpython-314-darwin.so
└── _native.pyi           # stub describing _native's API
```

Rules:

- `py.typed` (empty file) must be included in the wheel, or consumers' checkers
  ignore every annotation and stub in the package. With scikit-build-core or
  setuptools, confirm it lands via `package-data` — then check the built wheel
  (`unzip -l dist/*.whl | grep -E 'py.typed|pyi'`).
- The stub shadows the binary for checkers only; runtime never reads `.pyi`.
- For a stub-only distribution of someone else's package, publish
  `<pkg>-stubs` (PEP 561 stub package), e.g. `mypkg-stubs/_native.pyi`.

### Writing the stub

```python
# _native.pyi — no implementation bodies, ever
from collections.abc import Buffer
from typing import final

__version__: str

def crc32(data: Buffer, seed: int = 0) -> int: ...

@final
class Ring:
    capacity: int
    def __init__(self, capacity: int) -> None: ...
    def push(self, item: bytes) -> None: ...
    def pop(self) -> bytes | None: ...
    def __len__(self) -> int: ...
```

Stub conventions:

- Bodies are always `...`; no docstrings needed (keep them in the C module).
- Mark classes that C code does not allow subclassing as `@final`.
- Default values: use the real value when it is a simple literal, `= ...`
  otherwise.
- Accept `Buffer` (3.12+, PEP 688) for buffer-protocol parameters instead of
  `bytes | bytearray | memoryview` unions. Pre-3.12 fallback:
  `typing_extensions.Buffer`.
- Overloads work in stubs without an implementation — list them and stop.

### Generating and validating stubs

```sh
stubgen -m mypkg._native -o stubs/        # mypy's generator: a starting draft
python -m mypy.stubtest mypkg             # verify stubs match runtime objects
```

`stubgen` output for C extensions is skeletal (mostly `Any`) — treat it as a
checklist, then hand-annotate. `stubtest` imports the real module and diffs it
against the stub: missing members, wrong arg names, bad defaults all fail.
Run `stubtest` in CI on every platform you build wheels for; pybind11/nanobind
signatures can differ per build options. nanobind and pybind11 can also emit
stubs from their own metadata (`nanobind.stubgen`, `pybind11-stubgen`) — those
start closer to correct because the binding layer knows the signatures.

Diagnostic quick hits:

| Symptom | Cause | Fix |
|---------|-------|-----|
| Checker treats `mypkg._native.f` as `Any` | No stub found | Add `_native.pyi` + `py.typed` to the wheel |
| Stubs work locally, not for consumers | `py.typed`/`.pyi` missing from wheel | Fix package-data; inspect built wheel |
| `stubtest` error: runtime argument name differs | Hand-written stub drifted | Regenerate with binding-aware stubgen, re-edit |
| mypy `[import-untyped]` on your own package | `py.typed` absent | Add the marker file |
