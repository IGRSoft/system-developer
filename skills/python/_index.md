# Python Skills Index

Quick navigation for the `skills/python/` subtree. Start at [SKILL.md](SKILL.md)
for the guided entry with version snapshot and decision tree.

## Skills

| Skill | Use it for |
|-------|------------|
| [modern-python/SKILL.md](modern-python/SKILL.md) | 3.14 feature gates: t-strings (PEP 750), deferred annotations (PEP 649/749), `except*`/exception groups, `except A, B` without parens (PEP 758), `compression.zstd` (PEP 784), PEP 695, PEP 765 finally warning |
| [python-typing/SKILL.md](python-typing/SKILL.md) | PEP 695 generics, protocols over ABCs, TypedDict/Literal/overload, strict pyright/mypy configuration |
| [python-concurrency/SKILL.md](python-concurrency/SKILL.md) | asyncio vs threads vs subinterpreters vs multiprocessing decision table; free-threading; TaskGroup |
| [python-tooling/SKILL.md](python-tooling/SKILL.md) | uv environment + lockfile workflows, ruff lint/format, packaging, project structure |
| [python-testing/SKILL.md](python-testing/SKILL.md) | pytest patterns, fixtures, parametrization, coverage |

## References

| File | Use it for |
|------|------------|
| [modern-python/references/python-3.14-features.md](modern-python/references/python-3.14-features.md) | Full 3.14 tour: t-string processing, `annotationlib`, zstd, PEP 758/765, improved error messages, remote debugging (PEP 768), asyncio introspection CLI |
| [modern-python/references/python-anti-patterns.md](modern-python/references/python-anti-patterns.md) | Anti-pattern catalog with detection ruff rule IDs and fixes |
| [python-typing/references/typing-advanced.md](python-typing/references/typing-advanced.md) | PEP 695 variance/scoping/defaults, `runtime_checkable` caveats, ParamSpec/Concatenate, overload rules, `.pyi` stubs |
| [python-concurrency/references/asyncio-patterns.md](python-concurrency/references/asyncio-patterns.md) | TaskGroup-era asyncio (no `get_event_loop`), cancellation, timeouts |
| [python-concurrency/references/free-threading.md](python-concurrency/references/free-threading.md) | `python3.14t`, `sys._is_gil_enabled()`, `Py_mod_gil` for extensions |
| [python-concurrency/references/subinterpreters.md](python-concurrency/references/subinterpreters.md) | `concurrent.interpreters`, `InterpreterPoolExecutor` (PEP 734) |
| [python-tooling/references/uv-workflows.md](python-tooling/references/uv-workflows.md) | uv sync/run/lock/tool workflows |
| [python-tooling/references/packaging-and-project-structure.md](python-tooling/references/packaging-and-project-structure.md) | src layout, build backends, distributing packages |
| [python-testing/references/pytest-advanced.md](python-testing/references/pytest-advanced.md) | Advanced fixtures, parametrization, plugins, coverage gating |

## Cross-Tree

| Topic | Location |
|-------|----------|
| Python version minimums (canonical) | `${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md` |
| Input validation, injection, pickle/yaml/`shell=True` | `${CLAUDE_SKILL_DIR}/_shared/secure-coding/SKILL.md` |
| Profiling (py-spy, cProfile, tracemalloc) | `${CLAUDE_SKILL_DIR}/tooling/diagnostics/SKILL.md` |
| C/C++/Python boundaries (pybind11, nanobind, C API) | `${CLAUDE_SKILL_DIR}/tooling/ffi-interop/SKILL.md` |
| Workflow stage participation | `CORPFLOW.md` |
