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

**Version-gated feature adoption with explicit fallbacks**

## When to Use

Use this skill when:
- Adopting a new language feature and you need its minimum version + fallback
- Deciding between an f-string and a t-string for output that crosses a syntax boundary (SQL/HTML/shell)
- Migrating annotation handling for Python 3.14 (deferred annotations)
- Reviewing code for legacy idioms that newer syntax replaces
- Designing exception handling with groups (`except*`) or notes (`add_note`)

For the full 3.14 walkthrough with worked examples, read
[references/python-3.14-features.md](references/python-3.14-features.md). For the
anti-pattern catalog with ruff rule IDs, read
[references/python-anti-patterns.md](references/python-anti-patterns.md).

## Per-Feature Version Gate

Pick the lowest version that has the feature; if your interpreter is pinned
lower, use the fallback column. Canonical minimums live in
[version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md).

| Feature | PEP | Min version | Pre-version fallback |
|---------|-----|-------------|----------------------|
| `type` aliases / `class Foo[T]` / `def f[T]()` generics | 695 | 3.12+ | `TypeVar` + `Generic[T]`; `TypeAlias` |
| Exception groups + `except*` | 654 | 3.11+ | sequential `try`/`except` per type |
| `Exception.add_note()` | 678 | 3.11+ | embed context in the message |
| `except A, B:` (no parentheses) | 758 | **3.14+ only** | `except (A, B):` (works everywhere — prefer it for portable code) |
| t-strings → `string.templatelib.Template` | 750 | **3.14+ only** | no backport; explicit escaping/parameterizing helpers |
| Deferred annotations by default + `annotationlib` | 649/749 | **3.14+** (default) | `from __future__ import annotations` |
| `compression.zstd` | 784 | **3.14+ only** | `zstandard` PyPI package |
| `return`/`break`/`continue` in `finally` → `SyntaxWarning` | 765 | 3.14+ (warning) | always avoided; review manually pre-3.14 |
| `concurrent.interpreters` (subinterpreters) | 734 | **3.14+** (stdlib) | `multiprocessing` — see [python-concurrency](../python-concurrency/SKILL.md) |
| Free-threading **supported** (`python3.14t`) | 779 | **3.14+** (separate build) | `multiprocessing` / C-extension GIL release |

## t-strings: produce a Template, not a str (3.14+)

A t-string evaluates interpolations eagerly but defers *rendering*, yielding a
`Template` that a processor turns into the final string safely.

```python
from string.templatelib import Template, Interpolation

def sql(t: Template) -> tuple[str, list[object]]:   # safe DSL: never string-concatenate user data
    text, params = "", []
    for part in t:
        match part:
            case str():            text += part
            case Interpolation():  text += "?"; params.append(part.value)
    return text, params

user_id = 42
query, params = sql(t"SELECT * FROM users WHERE id = {user_id}")
# ("SELECT * FROM users WHERE id = ?", [42])
```

**Rule:** f-strings remain correct for *display* (logs, messages). Reach for a
t-string only when output crosses a syntax boundary (SQL, HTML, shell, regex).
Full processors and typing in [references/python-3.14-features.md](references/python-3.14-features.md) - Template Strings.

## Deferred Annotations: stop the future import (3.14)

Python 3.14 evaluates annotations lazily by default (PEP 649/749). In new 3.14
code, **do not** add `from __future__ import annotations` — it forces the older
string-based semantics and breaks `annotationlib` introspection.

```python
class Node:
    def next(self) -> Node: ...        # 3.14: no quotes, no future import needed

import annotationlib                    # introspect at runtime — never parse __annotations__ strings
hints = annotationlib.get_annotations(Node.next, format=annotationlib.Format.VALUE)
```

Pre-3.14 fallback: keep `from __future__ import annotations` (or quote forward
refs) and read hints via `typing.get_type_hints()`. Migration gotchas in
[references/python-3.14-features.md](references/python-3.14-features.md) - Deferred Annotations.

## Exception Groups, except*, add_note

```python
def fan_out(tasks) -> None:
    errors = []
    for t in tasks:
        try:
            run(t)
        except Exception as e:
            e.add_note(f"while running {t.name}")    # 3.11+: attach context, don't reformat
            errors.append(e)
    if errors:
        raise ExceptionGroup("fan_out failed", errors)   # 3.11+

try:
    fan_out(tasks)
except* ConnectionError as eg:      # handle one leaf type across the whole group
    log.warning("network failures: %d", len(eg.exceptions))
except* ValueError as eg:
    log.error("bad inputs: %d", len(eg.exceptions))
```

`asyncio.TaskGroup` (3.11+) raises an `ExceptionGroup` when child tasks fail —
`except*` is the matching handler. See [python-concurrency](../python-concurrency/SKILL.md).

## PEP 765: control flow in finally is now a warning (3.14)

```python
def bad():
    try:
        return 1
    finally:
        return 2        # 3.14 SyntaxWarning: swallows the try/except outcome (and exceptions)

def good():
    result = compute()
    try:
        return result
    finally:
        cleanup()       # side effects only — never return/break/continue here
```

A `return`/`break`/`continue` in `finally` silently discards exceptions and the
intended return value. Treat the warning as an error in new code.

## except without parentheses (PEP 758, 3.14+)

```python
try:
    parse()
except ValueError, KeyError:    # 3.14+ only — syntax error on 3.13 and earlier
    handle()
```

For code that must run on multiple versions, keep the parenthesized form
`except (ValueError, KeyError):` — it is valid everywhere and the only portable
choice.

## Context Managers and match

- Acquire every external resource with a `with` block (or `contextlib.ExitStack`
  for a dynamic set); never rely on `__del__` for cleanup.
- Prefer `match` for closed sets (enums, `Literal`, tagged shapes) over chained
  `isinstance`; end exhaustive matches with `case _: assert_never(x)` so a new
  variant becomes a static error (see [python-typing](../python-typing/SKILL.md)).

## Anti-Pattern Routing

Code review and modernization map each anti-pattern to a ruff rule and fix in
[references/python-anti-patterns.md](references/python-anti-patterns.md): mutable
default args (`B006`), bare `except` (`E722`/`BLE001`), legacy typing (`UP`
rules), blocking calls in async (`ASYNC` rules), unclosed resources (`SIM115`),
and `print` debugging (`T201`).

## Diagnostics

| Symptom | Cause | Fix | Reference |
|---------|-------|-----|-----------|
| `t"..."` returns a `Template`, code expected a `str` | t-string is not a string by design | Write/apply a renderer; use an f-string for plain display | [python-3.14-features.md](references/python-3.14-features.md) - Template Strings |
| `SyntaxError` on `except A, B:` | Running on 3.13 or earlier (PEP 758 is 3.14+) | Use `except (A, B):` (portable) | this file - except without parentheses |
| `annotationlib`-based tool sees strings, not values | `from __future__ import annotations` still present on 3.14 | Remove the future import in 3.14 code | [python-3.14-features.md](references/python-3.14-features.md) - Deferred Annotations |
| `NameError` on a forward-ref annotation at runtime (pre-3.14) | Eager evaluation before 3.14 | Add `from __future__ import annotations` or quote the ref | [version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md) |
| `SyntaxWarning: 'return' in a 'finally' block` | PEP 765 control-flow-in-finally | Move `return`/`break`/`continue` out of `finally` | this file - PEP 765 |
| `ModuleNotFoundError: No module named 'compression'` | zstd module is 3.14+ | Upgrade to 3.14, or `pip install zstandard` and use that API | [python-3.14-features.md](references/python-3.14-features.md) - compression.zstd |
| `except*` raises `SyntaxError` | Running on 3.10 or earlier | Upgrade to 3.11+, or catch the group with a single `except ExceptionGroup` and inspect `.exceptions` | this file - Exception Groups |
| Caught exception loses original context | re-raised without chaining, or rewrapped | Use `raise NewError(...) from e`; prefer `add_note` over reformatting | this file - Exception Groups |

## Deep-Dive References

- [references/python-3.14-features.md](references/python-3.14-features.md) — full 3.14 tour: t-string processing, `annotationlib`, zstd, PEP 758/765, improved error messages, remote debugging (PEP 768), asyncio introspection CLI, tail-call interpreter
- [references/python-anti-patterns.md](references/python-anti-patterns.md) — anti-pattern catalog mapped to ruff rule IDs and fixes

## Related Skills

- [python-typing](../python-typing/SKILL.md) — PEP 695 generics, protocols, deferred-annotations typing details
- [python-concurrency](../python-concurrency/SKILL.md) — exception groups from TaskGroup; free-threading and subinterpreters
- [python-tooling](../python-tooling/SKILL.md) — ruff `--select UP` modernization, target-version config
- [python-testing](../python-testing/SKILL.md) — testing error paths and exception groups
- [version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md) — canonical Python version minimums
