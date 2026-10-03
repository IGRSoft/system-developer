---
name: modern-python
description: >-
  Modern Python language features for 3.12-3.14 with explicit version gates:
  t-strings (PEP 750), deferred annotations (PEP 649/749), exception groups
  and except*, except without parentheses (PEP 758), compression.zstd, PEP 695
  generics, and the PEP 765 finally warning. Use when adopting a 3.14 feature,
  checking which version a feature needs, finding a pre-3.14 fallback, or
  reviewing code for legacy idioms superseded by newer syntax.
---

# Modern Python (3.12-3.14)

Full 3.14 tour with worked examples: [references/python-3.14-features.md](references/python-3.14-features.md). Anti-pattern catalog with ruff rule IDs: [references/python-anti-patterns.md](references/python-anti-patterns.md).

## Per-Feature Version Gate

Use the feature only if the interpreter floor meets its minimum; otherwise use the fallback. Canonical minimums: [version-feature-matrix](../../_shared/version-feature-matrix.md).

### 3.11-3.12

| Feature | PEP | Min | Fallback |
|---------|-----|-----|----------|
| `type` aliases, `class Foo[T]`, `def f[T]()` | 695 | 3.12 | `TypeVar` + `Generic[T]`; `TypeAlias` |
| Exception groups + `except*` | 654 | 3.11 | one `try`/`except` per type |
| `Exception.add_note()` | 678 | 3.11 | put context in the message |

### 3.14

| Feature | PEP | Fallback |
|---------|-----|----------|
| `except A, B:` (no parentheses) | 758 | `except (A, B):`, valid everywhere |
| t-strings → `string.templatelib.Template` | 750 | no backport; explicit escaping helpers |
| Deferred annotations + `annotationlib` | 649/749 | `from __future__ import annotations` |
| `compression.zstd` | 784 | `backports.zstd` (same API) or `zstandard` |
| `return`/`break`/`continue` in `finally` warns | 765 | review by hand |
| `concurrent.interpreters` | 734 | `multiprocessing` |
| Free-threaded build `python3.14t` supported | 779 | `multiprocessing`, GIL-releasing C code |

Subinterpreters and free-threading: [python-concurrency](../python-concurrency/SKILL.md).

## t-strings: produce a Template, not a str (3.14+)

A t-string evaluates interpolations eagerly but defers rendering: it yields a `Template` that a processor turns into the final output.

```python
from string.templatelib import Template, Interpolation

def sql(t: Template) -> tuple[str, list[object]]:   # values become parameters, never SQL text
    text, params = "", []
    for part in t:
        match part:
            case str():            text += part
            case Interpolation():  text += "?"; params.append(part.value)
    return text, params

query, params = sql(t"SELECT * FROM users WHERE id = {user_id}")
# ("SELECT * FROM users WHERE id = ?", [user_id])
```

f-strings stay correct for display (logs, messages). Use a t-string when output crosses a syntax boundary (SQL, HTML, shell, regex), and type the API as `Template` so callers can't pass a pre-formatted `str`.

## Deferred Annotations (3.14)

3.14 evaluates annotations lazily by default. In code whose floor is 3.14, don't add `from __future__ import annotations`: it restores the old string semantics, so `annotationlib` sees strings instead of values.

```python
class Node:
    def next(self) -> Node: ...        # 3.14: no quotes, no future import

import annotationlib                    # introspect via annotationlib, not by parsing strings
hints = annotationlib.get_annotations(Node.next)
```

Below 3.14, keep the future import (or quote forward refs) and read hints with `typing.get_type_hints()`.

## Exception Groups, except*, add_note

```python
def fan_out(tasks) -> None:
    errors = []
    for t in tasks:
        try:
            run(t)
        except Exception as e:
            e.add_note(f"while running {t.name}")    # attach context, keep the original message
            errors.append(e)
    if errors:
        raise ExceptionGroup("fan_out failed", errors)

try:
    fan_out(tasks)
except* ConnectionError as eg:      # handles that leaf type across the whole group
    log.warning("network failures: %d", len(eg.exceptions))
except* ValueError as eg:
    log.error("bad inputs: %d", len(eg.exceptions))
```

`asyncio.TaskGroup` raises an `ExceptionGroup` when children fail, so `except*` is its matching handler.

## finally and except syntax (3.14)

- PEP 765: `return`/`break`/`continue` in `finally` now raises a `SyntaxWarning` because it discards the in-flight exception and return value. Keep `finally` to cleanup and treat the warning as an error in new code.
- PEP 758: `except A, B:` is 3.14-only and needs parentheses when there is an `as` clause. Code with a lower floor keeps `except (A, B):`.

## Context Managers and match

- Acquire external resources with `with` (or `contextlib.ExitStack` for a dynamic set), not `__del__`.
- Prefer `match` over chained `isinstance` for closed sets (enums, `Literal`, tagged shapes); end exhaustive matches with `case _: assert_never(x)` so a new variant is a static error ([python-typing](../python-typing/SKILL.md)).

## Anti-Pattern Routing

[references/python-anti-patterns.md](references/python-anti-patterns.md) maps each anti-pattern to a ruff rule and fix: mutable default args (`B006`), bare `except` (`E722`/`BLE001`), legacy typing (`UP`), blocking calls in async (`ASYNC`), unclosed resources (`SIM115`), `print` debugging (`T201`).

## Diagnostics: syntax and import errors

| Symptom | Cause | Fix |
|---------|-------|-----|
| `SyntaxError` on `except A, B:` | 3.13 or earlier | `except (A, B):` |
| `SyntaxError` on `except*` | 3.10 or earlier | 3.11+, or `except ExceptionGroup` and inspect `.exceptions` |
| `SyntaxWarning: 'return' in a 'finally' block` | PEP 765 | move the control flow out of `finally` |
| `No module named 'compression'` | zstd is 3.14+ | upgrade, or `backports.zstd` |

## Diagnostics: runtime

| Symptom | Cause | Fix |
|---------|-------|-----|
| `t"..."` gives a `Template` where a `str` was expected | t-strings aren't strings | apply a renderer; use an f-string for display |
| `annotationlib` tool sees strings, not values | future import still present on 3.14 | remove it |
| `NameError` on a forward-ref annotation (pre-3.14) | eager evaluation | add the future import or quote the ref |
| Caught exception loses its context | re-raised without chaining | `raise NewError(...) from e`; `add_note` instead of reformatting |

## Related Skills

- [python-typing](../python-typing/SKILL.md): PEP 695 generics, protocols, deferred-annotation typing
- [python-concurrency](../python-concurrency/SKILL.md): TaskGroup exception groups, free-threading, subinterpreters
- [python-tooling](../python-tooling/SKILL.md): `ruff --select UP` modernization, `target-version`
- [python-testing](../python-testing/SKILL.md): testing error paths and exception groups
