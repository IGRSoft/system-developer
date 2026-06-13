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

**Modern annotations, generics, and strict checking for Python 3.12–3.14**

## When to Use

Use this skill when:
- Annotating new code or adding types to an untyped module
- Writing generic functions, classes, or type aliases
- Selecting and configuring a type checker (pyright or mypy)
- Reviewing code for legacy typing idioms (`TypeVar` boilerplate, `Optional`, quoted forward refs)
- Designing interfaces — deciding between `Protocol` and ABC

## Baseline Syntax (Python 3.12+)

PEP 695 is the house style. Never write `TypeVar("T")` boilerplate in new code.

```python
def first[T](items: list[T]) -> T:          # generic function
    return items[0]

class Stack[T]:                              # generic class
    def __init__(self) -> None:
        self._items: list[T] = []
    def push(self, item: T) -> None:
        self._items.append(item)

type Pair[T] = tuple[T, T]                   # generic type alias
type JSON = dict[str, "JSON"] | list["JSON"] | str | int | float | bool | None
```

Bounds and constraints go inline: `def largest[T: float](xs: list[T]) -> T` (bound),
`def concat[S: (str, bytes)](a: S, b: S) -> S` (constraints). Type-parameter
defaults `class Box[T = int]` need Python 3.13+ (PEP 696).

Always with it:
- Builtin generics: `list[int]`, `dict[str, User]`, `tuple[int, ...]` — never `typing.List`
- `X | None` — never `Optional[X]`; `int | str` — never `Union[int, str]`
- `collections.abc` for interfaces: `Sequence`, `Mapping`, `Callable`, `Iterator`

| Need | 3.12+ (use this) | Pre-3.12 fallback |
|------|------------------|-------------------|
| Generic function/class | `def f[T](...)` / `class C[T]` | Module-level `T = TypeVar("T")` + `Generic[T]` |
| Type alias | `type Alias = ...` | `Alias: TypeAlias = ...` (PEP 613) |
| Variance | Inferred automatically | Manual `covariant=True` on `TypeVar` |

## 3.14: Deferred Annotations — Stop Quoting

Python 3.14 evaluates annotations lazily (PEP 649/749). Consequences:

```python
class Node:
    def next(self) -> Node: ...          # 3.14: no quotes needed, even mid-class

# DON'T add on 3.14 — it forces the older string semantics:
# from __future__ import annotations
```

Pre-3.14 fallback: keep `from __future__ import annotations` (or quote forward
refs). Runtime annotation consumers (dataclass tooling, validators) should use
`annotationlib` / `typing.get_type_hints()`, never raw `__annotations__` string
handling. See [version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md).

## Checker Selection: pyright vs mypy

Pick **one** as the CI gate. Running both is acceptable for libraries; agreeing
with both costs real effort.

| Criterion | pyright | mypy |
|-----------|---------|------|
| Speed on large repos | Fast (incremental, watch mode) | Slower; `dmypy` daemon helps |
| Inference strength | Stronger (narrowing, unannotated returns) | Conservative; wants annotations |
| Plugin ecosystem | None (by design) | Plugins (e.g. ORM/framework plugins) |
| Editor story | Powers Pylance/VS Code | LSP via separate servers |
| Per-file strictness | `# pyright: strict` comment | Per-module overrides in config |
| Default choice | New projects, app code | Codebases needing mypy plugins |

This plugin's default: **pyright strict** for new projects; keep mypy where a
required plugin (ORM models, framework descriptors) does narrowing pyright cannot.

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
2. Freeze the count: fail CI if errors *increase* (mypy: per-module `strict = true`
   overrides; pyright: move files into a strict include list or add `# pyright: strict`).
3. Strictify module-by-module, leaf packages first; new files start strict.
4. Delete the ratchet when the override list is empty. Never add blanket
   `# type: ignore` — always the narrow form `# type: ignore[error-code]` with a reason.

## Protocols over ABCs

Default to `Protocol` for interfaces: callers' types satisfy them structurally,
no inheritance coupling, trivially fake-able in tests. Use ABCs only when you
need shared *implementation* or registration.

```python
from typing import Protocol

class SupportsClose(Protocol):
    def close(self) -> None: ...

def shutdown(resources: list[SupportsClose]) -> None:
    for r in resources:
        r.close()                    # any object with close() qualifies
```

`@runtime_checkable` enables `isinstance()` but checks only member *presence*,
never signatures — see [references/typing-advanced.md](references/typing-advanced.md).

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

Decorators that preserve signatures use PEP 695 `**P` syntax:

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

Full treatments (variance, `Required`/`ReadOnly`, `Concatenate`, overload
ordering rules): [references/typing-advanced.md](references/typing-advanced.md).

## Exhaustiveness: Self, Never, assert_never

```python
from typing import Self, assert_never

class Builder:
    def with_flag(self) -> Self:     # 3.11+; pre-3.11: bound TypeVar dance
        return self

def handle(mode: Mode) -> int:
    match mode:
        case "r" | "rb": return 0
        case "w" | "wb": return 1
        case _:
            assert_never(mode)       # checker error if a Mode member is unhandled
```

`assert_never` turns "forgot a case" into a *static* error when the enum/Literal
grows; `Never` is also the return annotation for functions that always raise.

## Diagnostics

| Error | Cause | Fix | Reference |
|-------|-------|-----|-----------|
| mypy: `Missing type parameters for generic type "list" [type-arg]` | Bare `list`/`dict` in strict mode | Parameterize: `list[int]`; `list[Any]` only deliberately | [typing-advanced.md](references/typing-advanced.md) |
| mypy: `Item "None" of "User \| None" has no attribute ... [union-attr]` | Optional not narrowed | `if user is None: raise/return` before use | this file, Quick Start |
| pyright: `"name" is not a known attribute of "None"` (`reportOptionalMemberAccess`) | Same as above | Narrow with `is None` guard, not `assert` in prod paths | this file |
| mypy: `Function is missing a return type annotation [no-untyped-def]` | Strict requires full signatures | Annotate; `-> None` for procedures | this file |
| `NameError` on annotation at runtime (pre-3.14) | Forward ref evaluated eagerly | Add `from __future__ import annotations`; on 3.14 remove it instead | [version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md) |
| mypy: `module is installed, but missing library stubs or py.typed marker [import-untyped]` | Untyped dependency | Install `types-*` stub package or write local `.pyi` | [typing-advanced.md](references/typing-advanced.md) § stubs |
| pyright: `TypeVar ... appears only once` (`reportInvalidTypeVarUse`) | Generic with no relationship to express | Use the concrete type or `object`; generics need 2+ occurrences | [typing-advanced.md](references/typing-advanced.md) |
| mypy: `Overloaded function signatures 1 and 2 overlap [overload-overlap]` | Overloads match same args, differ in return | Reorder most-specific-first; make params disjoint via `Literal` | [typing-advanced.md](references/typing-advanced.md) § overloads |
| `TypeError: Protocols with non-method members don't support issubclass()` | `issubclass()` on a data protocol | Only method-only protocols support `issubclass`; use `isinstance` or redesign | [typing-advanced.md](references/typing-advanced.md) § protocols |
| Checker accepts wrong `isinstance(x, SomeProtocol)` result | `runtime_checkable` ignores signatures | Treat as presence check only; keep static checking authoritative | [typing-advanced.md](references/typing-advanced.md) § protocols |
| mypy: `error: PEP 695 type aliases are not yet supported` (older mypy) | Tool predates PEP 695 support | Upgrade mypy — verify against your toolchain; fallback `TypeAlias` | this file, Baseline |

## Deep-Dive References

- [references/typing-advanced.md](references/typing-advanced.md) — PEP 695 in depth (variance, scoping, defaults), protocols and `runtime_checkable` caveats, TypedDict `Required`/`NotRequired`/`ReadOnly`, ParamSpec/Concatenate decorators, overload rules, `.pyi` stubs for C extensions

## Related Skills

- [modern-python](../modern-python/SKILL.md) — 3.14 language features, deferred-annotations details, anti-patterns
- [python-testing](../python-testing/SKILL.md) — typing test code, typed fixtures and fakes
- [python-tooling](../python-tooling/SKILL.md) — wiring pyright/mypy into uv projects and CI
- [ffi-interop](${CLAUDE_SKILL_DIR}/tooling/ffi-interop/SKILL.md) — C-extension boundaries that `.pyi` stubs describe
- [version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md) — canonical Python version minimums
