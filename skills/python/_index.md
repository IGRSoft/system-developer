# Python Skills Index

Quick navigation for the `skills/python/` subtree. Start at [SKILL.md](SKILL.md)
for the version snapshot and skill selection.

## Skills

| Skill | Use it for |
|-------|------------|
| [modern-python/SKILL.md](modern-python/SKILL.md) | 3.14 feature gates: t-strings (PEP 750), deferred annotations (PEP 649/749), `except*`/exception groups, `except A, B` without parens (PEP 758), `compression.zstd` (PEP 784), PEP 695, PEP 765 finally warning |
| [python-typing/SKILL.md](python-typing/SKILL.md) | PEP 695 generics, protocols over ABCs, TypedDict/Literal/overload, strict pyright/mypy configuration |
| [python-concurrency/SKILL.md](python-concurrency/SKILL.md) | asyncio vs threads vs subinterpreters vs multiprocessing decision table; free-threading; TaskGroup |
| [python-tooling/SKILL.md](python-tooling/SKILL.md) | uv environment + lockfile workflows, ruff lint/format, packaging, project structure |
| [python-testing/SKILL.md](python-testing/SKILL.md) | pytest patterns, fixtures, parametrization, coverage |

## References

### modern-python

| File | Use it for |
|------|------------|
| [python-3.14-features.md](modern-python/references/python-3.14-features.md) | Full 3.14 tour: t-string processing, `annotationlib`, zstd, PEP 758/765, improved error messages, remote debugging (PEP 768), asyncio introspection CLI |
| [python-anti-patterns.md](modern-python/references/python-anti-patterns.md) | Anti-pattern catalog with detection ruff rule IDs and fixes |

### python-typing

| File | Use it for |
|------|------------|
| [typing-advanced.md](python-typing/references/typing-advanced.md) | PEP 695 variance/scoping/defaults, `runtime_checkable` caveats, ParamSpec/Concatenate, overload rules, `.pyi` stubs |

### python-concurrency

| File | Use it for |
|------|------------|
| [asyncio-patterns.md](python-concurrency/references/asyncio-patterns.md) | TaskGroup-era asyncio (no `get_event_loop`), cancellation, timeouts |
| [free-threading.md](python-concurrency/references/free-threading.md) | `python3.14t`, `sys._is_gil_enabled()`, `Py_mod_gil` for extensions |
| [subinterpreters.md](python-concurrency/references/subinterpreters.md) | `concurrent.interpreters`, `InterpreterPoolExecutor` (PEP 734) |

### python-tooling

| File | Use it for |
|------|------------|
| [uv-workflows.md](python-tooling/references/uv-workflows.md) | uv sync/run/lock/tool workflows |
| [packaging-and-project-structure.md](python-tooling/references/packaging-and-project-structure.md) | src layout, build backends, distributing packages |

### python-testing

| File | Use it for |
|------|------------|
| [pytest-advanced.md](python-testing/references/pytest-advanced.md) | Advanced fixtures, parametrization, plugins, coverage gating |

## Cross-Tree

| Topic | Location |
|-------|----------|
| Python version minimums (canonical) | [version-feature-matrix.md](../_shared/version-feature-matrix.md) |
| Input validation, injection, pickle/yaml/`shell=True` | [secure-coding](../_shared/secure-coding/SKILL.md) |
| Profiling (py-spy, cProfile, tracemalloc) | [diagnostics](../tooling/diagnostics/SKILL.md) |
| C/C++/Python boundaries (pybind11, nanobind, C API) | [ffi-interop](../tooling/ffi-interop/SKILL.md) |
