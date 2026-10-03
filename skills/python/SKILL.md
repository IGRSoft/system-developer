---
name: python-skills
description: >-
  Python language skills navigation for Python 3.12-3.14: modern features
  (t-strings, deferred annotations, PEP 695), static typing, concurrency
  (asyncio, free-threading, subinterpreters), uv/ruff tooling, and pytest
  testing. Use when writing or reviewing Python, choosing a 3.14 feature,
  picking a concurrency model, configuring uv/ruff/pyright, or writing tests.
---

# Python Skills

Routes Python 3.12-3.14 work to the right leaf skill or reference.

## Version Snapshot

- 3.12: PEP 695 `type` statement and `class Foo[T]` generics; f-string grammar formalized (PEP 701).
- 3.13: experimental free-threaded build (`python3.13t`) and JIT; new REPL.
- 3.14: free-threading supported (PEP 779, still a separate build); subinterpreters in stdlib (PEP 734); t-strings (PEP 750); deferred annotations by default (PEP 649/749); `compression.zstd` (PEP 784).
- 3.15: scheduled GA 2026-10-01 (PEP 790); check its release notes before relying on it. Free-threading by default is a later phase, not 3.15.

Check feature minimums against the interpreter (`python3 -VV`) and the [version-feature-matrix](../_shared/version-feature-matrix.md).

Toolchain: `uv` (env + lockfile), `ruff` (lint + format), `pyright` or `mypy` (one as the CI gate), `pytest`. Pin tool versions in `pyproject.toml`/`uv.lock`, not in prose.

## Skill Selection

| I need to... | Go to |
|--------------|-------|
| Use a 3.14 feature (t-strings, deferred annotations, zstd, `except*`) | [modern-python](modern-python/SKILL.md); full tour in [python-3.14-features.md](modern-python/references/python-3.14-features.md) |
| Catch anti-patterns / map a fix to a ruff rule | [python-anti-patterns.md](modern-python/references/python-anti-patterns.md) |
| Add type annotations, generics, protocols, strict checking | [python-typing](python-typing/SKILL.md) |
| Pick asyncio vs threads vs subinterpreters vs multiprocessing | [python-concurrency](python-concurrency/SKILL.md) |
| Set up uv, ruff, packaging, project structure | [python-tooling](python-tooling/SKILL.md) |
| Write or structure pytest tests, fixtures, coverage | [python-testing](python-testing/SKILL.md) |
| Migrate a codebase to 3.14 | `/system-developer:fix-modernize` |
| Every file in this subtree | [_index.md](_index.md) |

## Related Skills

| I need to... | Go to |
|--------------|-------|
| C-extension and FFI boundaries | [c-skills](../c/SKILL.md), [cpp-skills](../cpp/SKILL.md) |
| Bind C/C++ to Python (pybind11, nanobind, C API) | [ffi-interop](../tooling/ffi-interop/SKILL.md) |
| Input validation, `shell=True`/pickle/yaml hazards | [secure-coding](../_shared/secure-coding/SKILL.md) |
| Profiling (py-spy, cProfile, tracemalloc) | [diagnostics](../tooling/diagnostics/SKILL.md) |
