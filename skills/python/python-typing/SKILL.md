---
name: python-typing
description: >-
  Static typing for Python 3.12-3.14: PEP 695 generics, protocols over ABCs,
  TypedDict/Literal/overload/ParamSpec patterns, and strict pyright/mypy
  configuration. Use when adding type annotations, writing generic functions
  or classes, choosing between pyright and mypy, ratcheting a codebase to
  strict mode, fixing checker errors, or typing decorators and C-extension
  stubs.
---

# Python Typing (PEP 695 Era)

## Baseline Syntax (Python 3.12+)

PEP 695 is the house style; new code doesn't use `TypeVar("T")` boilerplate.

```python
def first[T](items: list[T]) -> T:          # generic function
    return items[0]

class Stack[T]:                              # generic class
    def __init__(self) -> None:
        self._items: list[T] = []
    def push(self, item: T) -> None:
        self._items.append(item)

type Pair[T] = tuple[T, T]                   # generic type alias
type JSON = dict[str, JSON] | list[JSON] | str | int | float | bool | None
```

Bounds and constraints go inline: `def largest[T: float](xs: list[T]) -> T` (bound),
`def concat[S: (str, bytes)](a: S, b: S) -> S` (constraints). Type-parameter
defaults `class Box[T = int]` need Python 3.13+ (PEP 696).

Use builtin generics (`list[int]`, `tuple[int, ...]`, not `typing.List`),
`X | None` and `int | str` (not `Optional`/`Union`), and `collections.abc` for
interfaces (`Sequence`, `Mapping`, `Callable`, `Iterator`).

### Pre-3.12 fallback

| Need | 3.12+ | Pre-3.12 |
|------|-------|----------|
| Generic function/class | `def f[T](...)` / `class C[T]` | Module-level `T = TypeVar("T")` + `Generic[T]` |
| Type alias | `type Alias = ...` | `Alias: TypeAlias = ...` (PEP 613) |
| Variance | Inferred | `covariant=True` on `TypeVar` |

## 3.14: Deferred Annotations, Stop Quoting

Python 3.14 evaluates annotations lazily (PEP 649/749), so forward references
need no quotes, even inside the class being defined:

```python
class Node:
    def next(self) -> Node: ...
```

Don't add `from __future__ import annotations` on 3.14; it forces the older
string semantics. Before 3.14, keep it (or quote forward refs). Runtime
annotation consumers should use `annotationlib` / `typing.get_type_hints()`
rather than parsing raw `__annotations__` strings. Version minimums:
[version-feature-matrix](../../_shared/version-feature-matrix.md).

## Checker Selection: pyright vs mypy

Pick one as the CI gate. Running both is fine for libraries, but satisfying
both costs real effort.

| Criterion | pyright | mypy |
|-----------|---------|------|
| Speed on large repos | Fast (incremental, watch mode) | Slower; `dmypy` daemon helps |
| Inference | Stronger (narrowing, unannotated returns) | Conservative; wants annotations |
| Plugins | None (by design) | ORM/framework plugins |
| Editor | Powers Pylance/VS Code | LSP via separate servers |
| Per-file strictness | `# pyright: strict` comment | Per-module overrides in config |

Default: pyright strict for new projects; keep mypy where a required plugin
(ORM models, framework descriptors) does narrowing pyright cannot.

### Faster checkers: ty and pyrefly

The Rust-based `ty` (Astral, `uvx ty check`) and `pyrefly` (Meta,
`uvx pyrefly check`) are much faster but newer. Run them alongside the gate
(editor loop, pre-commit, large-repo triage), compare findings, and promote one
to the gate only once it agrees with pyright/mypy on your real code.

### Strict config

```toml
[tool.pyright]                       # pyproject.toml
pythonVersion = "3.14"
typeCheckingMode = "strict"

[tool.mypy]                          # if mypy is the gate instead
python_version = "3.14"
strict = true
warn_unreachable = true
enable_error_code = ["ignore-without-code", "redundant-expr"]
```

### Ratchet Strategy (existing codebases)

1. Start at `typeCheckingMode = "basic"` / non-strict mypy; fix real errors.
2. Freeze the count: fail CI if errors increase (mypy: per-module `strict = true`
   overrides; pyright: a strict include list or `# pyright: strict`).
3. Strictify module by module, leaf packages first; new files start strict.
4. Delete the ratchet when the override list is empty.

Suppress with the narrow form `# type: ignore[error-code]` plus a reason, not a
blanket `# type: ignore`.

## Protocols over ABCs

Default to `Protocol` for interfaces: callers' types satisfy them structurally,
with no inheritance coupling, and test fakes are trivial. Use ABCs only when you
need shared implementation or registration.

```python
from typing import Protocol

class SupportsClose(Protocol):
    def close(self) -> None: ...

def shutdown(resources: list[SupportsClose]) -> None:
    for r in resources:
        r.close()                    # any object with close() qualifies
```

`@runtime_checkable` enables `isinstance()` but checks only member presence,
not signatures; see [references/typing-advanced.md](references/typing-advanced.md).

## Workhorse Patterns

```python
from typing import Literal, TypedDict, NotRequired, overload

class JobSpec(TypedDict):            # typed dict payloads at boundaries
    cmd: list[str]
    timeout_s: NotRequired[int]      # may be absent (3.11+; total=False pre-3.11)

type Mode = Literal["r", "rb", "w", "wb"]   # closed string sets

@overload
def read(path: str, mode: Literal["r"]) -> str: ...
@overload
def read(path: str, mode: Literal["rb"]) -> bytes: ...
def read(path: str, mode: str) -> str | bytes:
    with open(path, mode) as f:
        return f.read()
```

### Signature-preserving decorators

Use PEP 695 `**P` syntax:

```python
from collections.abc import Callable
import functools

def logged[**P, R](func: Callable[P, R]) -> Callable[P, R]:
    @functools.wraps(func)
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        print(f"call {func.__name__}")
        return func(*args, **kwargs)
    return wrapper
```

Variance, `Required`/`ReadOnly`, `Concatenate` and overload rules are in
[references/typing-advanced.md](references/typing-advanced.md).

## Exhaustiveness: Self, Never, assert_never

```python
from typing import Self, assert_never

class Builder:
    def with_flag(self) -> Self:     # 3.11+; pre-3.11: bound TypeVar
        return self

def handle(mode: Mode) -> int:
    match mode:
        case "r" | "rb": return 0
        case "w" | "wb": return 1
        case _:
            assert_never(mode)       # checker error if a Mode member is unhandled
```

`assert_never` turns a forgotten case into a static error when the enum or
`Literal` grows. `Never` is also the return type of functions that always raise.

## Diagnostics

### Checker errors

| Error | Cause | Fix |
|-------|-------|-----|
| mypy: `Missing type arguments for generic type "list" [type-arg]` | Bare `list`/`dict` in strict mode | `list[int]`; `list[Any]` only deliberately |
| mypy `[union-attr]` / pyright `reportOptionalMemberAccess` on `X \| None` | Optional not narrowed | `if x is None: raise/return` before use, not `assert` in prod paths |
| mypy: `Function is missing a return type annotation [no-untyped-def]` | Strict requires full signatures | Annotate; `-> None` for procedures |
| mypy: `missing library stubs or py.typed marker [import-untyped]` | Untyped dependency | `types-*` stubs or a local `.pyi` |
| pyright: `TypeVar ... appears only once` (`reportInvalidTypeVarUse`) | Generic with no relationship to express | Use the concrete type or `object` |
| mypy `[overload-overlap]` / pyright `reportOverlappingOverload` | Overloads accept the same args, return different types | Most-specific first; disjoint params via `Literal` |

### Runtime and tooling errors

| Error | Cause | Fix |
|-------|-------|-----|
| `NameError` on an annotation (pre-3.14) | Forward ref evaluated eagerly | Add `from __future__ import annotations`; on 3.14 remove it |
| `TypeError: Protocols with non-method members don't support issubclass()` | `issubclass()` on a data protocol | Use `isinstance` or a method-only protocol |
| `isinstance(x, SomeProtocol)` is True, then the call fails | `runtime_checkable` ignores signatures | Treat it as a presence check; static checking is authoritative |
| mypy: `PEP 695 generics are not yet supported` | mypy older than 1.12 | Upgrade mypy; fallback `TypeVar`/`TypeAlias` |

## Related Skills

| Skill | Use for |
|-------|---------|
| [modern-python](../modern-python/SKILL.md) | 3.14 language features, deferred-annotation details, anti-patterns |
| [python-testing](../python-testing/SKILL.md) | Typing test code, typed fixtures and fakes |
| [python-tooling](../python-tooling/SKILL.md) | Wiring pyright/mypy into uv projects and CI |
| [ffi-interop](../../tooling/ffi-interop/SKILL.md) | C-extension boundaries that `.pyi` stubs describe |
