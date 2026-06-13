# Reference Index

Deep-dive references for the Python Concurrency skill. Start at
[../SKILL.md](../SKILL.md) for the model-selection decision table, then come here
for implementation detail. Baseline: **CPython 3.14** (free-threading via the
separate **`python3.14t`** build).

## Files

| File | Use it for |
|---|---|
| `asyncio-patterns.md` | `TaskGroup` structured concurrency, `asyncio.timeout`, cancellation and shielding, streams, `Queue`-based producer/consumer, bridging sync↔async (`to_thread`, `run_coroutine_threadsafe`), and testing async code |
| `free-threading.md` | Installing and verifying the free-threaded build (`python3.14t`) with `uv`, `sys._is_gil_enabled()`, thread-safety patterns without the GIL, extension/ecosystem compatibility (`Py_mod_gil`), and when to stay on the GIL build |
| `subinterpreters.md` | The `concurrent.interpreters` API (PEP 734), `InterpreterPoolExecutor`, picklable data passing, isolation compared with `multiprocessing`, and multi-phase-init extension constraints |

## Problem Router

- "I have many I/O calls to run concurrently" → `asyncio-patterns.md` (TaskGroup)
- "I need a timeout / to cancel cleanly" → `asyncio-patterns.md` (timeouts, cancellation)
- "I must call a blocking library from async code" → `asyncio-patterns.md` (bridging)
- "I want real multi-core for CPU-bound Python" → `free-threading.md` or `subinterpreters.md`
- "Does my extension/library work without the GIL?" → `free-threading.md` (compatibility)
- "I want process-like isolation but cheaper" → `subinterpreters.md`
- "Sending data to a worker raises a pickling error" → `subinterpreters.md` (sharing)

## Related Skills

- [../../modern-python/SKILL.md](../../modern-python/SKILL.md) — 3.14 language features
- [../../python-tooling/SKILL.md](../../python-tooling/SKILL.md) — `uv`, interpreters, project layout
- [../../python-testing/SKILL.md](../../python-testing/SKILL.md) — pytest and async test config
