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

**Navigation and version snapshot for Python 3.12-3.14 development**

## Version Snapshot

| Version | Headline (one line) |
|---------|---------------------|
| 3.12 | PEP 695 `type` statement and `class Foo[T]` generics; formalized f-string grammar (PEP 701); better error messages |
| 3.13 | Experimental free-threaded build (`python3.13t`) and experimental JIT; new REPL |
| 3.14 | Free-threading **supported** (PEP 779, still a separate build); subinterpreters in stdlib (PEP 734); t-strings (PEP 750); deferred annotations by default (PEP 649/749); `compression.zstd` (PEP 784) |
| 3.15 | Beta (GA Oct 2026, PEP 790) — verify against release notes; free-threading-by-default is **Phase III (future, not 3.15)** |

Compiler/runtime minutiae shift between point releases — for anything you pin in
CI, verify against your interpreter (`python3 -VV`) and link the canonical
[version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md).

**Toolchain in one line:** `uv` (env + lockfile) - `ruff` (lint + format) -
`pyright` or `mypy` (one as CI gate) - `pytest` (tests). Pin tool versions in
`pyproject.toml`/`uv.lock`, never in prose.

## Skill Selection Guide

| I need to... | Use this skill |
|--------------|----------------|
| Use a 3.14 feature (t-strings, deferred annotations, zstd, `except*`) | [modern-python/SKILL.md](modern-python/SKILL.md) |
| Catch anti-patterns / map a fix to a ruff rule | [modern-python/references/python-anti-patterns.md](modern-python/references/python-anti-patterns.md) |
| Add type annotations, generics, protocols, strict checking | [python-typing/SKILL.md](python-typing/SKILL.md) |
| Pick asyncio vs threads vs subinterpreters vs multiprocessing | [python-concurrency/SKILL.md](python-concurrency/SKILL.md) |
| Set up uv, ruff, packaging, project structure | [python-tooling/SKILL.md](python-tooling/SKILL.md) |
| Write or structure pytest tests | [python-testing/SKILL.md](python-testing/SKILL.md) |

## Decision Tree

```
Python task?
├── Which version has feature X? → version-feature-matrix (canonical)
├── Writing/reviewing modern code → modern-python/SKILL.md
│   ├── 3.14 feature tour → modern-python/references/python-3.14-features.md
│   └── Anti-pattern + ruff fix → modern-python/references/python-anti-patterns.md
├── Type annotations / generics / strict checking → python-typing/SKILL.md
├── Concurrency model choice → python-concurrency/SKILL.md
│   ├── asyncio (many concurrent I/O) → references/asyncio-patterns.md
│   ├── free-threading (CPU-bound, 3.14t) → references/free-threading.md
│   └── subinterpreters (isolation) → references/subinterpreters.md
├── uv / ruff / packaging → python-tooling/SKILL.md
├── pytest, fixtures, coverage → python-testing/SKILL.md
└── Migrating to 3.14 → /system-developer:fix-modernize
```

## File Overview

| File | Purpose |
|------|---------|
| [_index.md](_index.md) | Full navigation for the python/ subtree |
| [modern-python/SKILL.md](modern-python/SKILL.md) | 3.14 feature gates, t-strings, deferred annotations, exception groups |
| [python-typing/SKILL.md](python-typing/SKILL.md) | PEP 695 generics, protocols, pyright/mypy strict |
| [python-concurrency/SKILL.md](python-concurrency/SKILL.md) | Concurrency-model decision table for the free-threading era |
| [python-tooling/SKILL.md](python-tooling/SKILL.md) | uv workflows, ruff, packaging, project layout |
| [python-testing/SKILL.md](python-testing/SKILL.md) | pytest patterns, fixtures, coverage |

## Related Skills

- [modern-c](${CLAUDE_SKILL_DIR}/c/SKILL.md) / [cpp-skills](${CLAUDE_SKILL_DIR}/cpp/SKILL.md) — for C-extension and FFI boundaries
- [ffi-interop](${CLAUDE_SKILL_DIR}/tooling/ffi-interop/SKILL.md) — binding C/C++ to Python (pybind11, nanobind, C API)
- [secure-coding](${CLAUDE_SKILL_DIR}/_shared/secure-coding/SKILL.md) — input validation, `shell=True`/pickle/yaml hazards
- [version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md) — canonical Python version minimums
