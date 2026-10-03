---
name: python-concurrency
description: >-
  Choose and implement the right Python 3.14 concurrency model — asyncio,
  threads, free-threading, subinterpreters, or multiprocessing. Use when
  building concurrent or parallel Python, deciding between async and threads,
  targeting the free-threaded (3.14t) build, sharing work across interpreters,
  or diagnosing event-loop and data-race errors.
---

# Python Concurrency

Pick the model first, then write the code; most concurrency bugs are model-selection bugs.

Baseline: CPython 3.14 (`python3.14`). Free-threading is the separate `python3.14t` build.

## The Decision Table

| Workload | Use | Why |
|---|---|---|
| Many concurrent I/O operations (network, sockets, async DB drivers) | asyncio + `TaskGroup` | Single thread, cooperative; thousands of in-flight ops cheaply |
| I/O via blocking libraries (sync DB driver, `requests`, file I/O) | threads (`ThreadPoolExecutor`, `asyncio.to_thread`) | GIL releases on blocking syscalls; threads overlap the waits |
| CPU-bound, free-threaded build (`python3.14t`) | threads | PEP 703/779: no GIL, real multi-core in one process |
| CPU-bound, default GIL build | multiprocessing or `InterpreterPoolExecutor` | GIL serializes pure-Python CPU work |
| Strong isolation, opt-in sharing (CSP / actor style) | subinterpreters (`concurrent.interpreters`) | PEP 734: process-like isolation in one process, share via pickle |
| Simple script, few connections | stay synchronous | Async adds complexity with no payoff at low concurrency |

### Rules that override the table

1. Stay fully sync or fully async within one call path; mixing hides blocking calls.
2. GIL removal does not remove races. On `python3.14t`, shared mutable state still needs `threading.Lock`/`queue.Queue`; the free-threaded build makes races more likely to show, not impossible.

## Quick Routing

```
Is the work I/O-bound?
├── yes → are the libraries async-native?
│        ├── yes → asyncio + TaskGroup            → references/asyncio-patterns.md
│        └── no  → threads / asyncio.to_thread     → references/asyncio-patterns.md (bridging)
└── no (CPU-bound) → which build am I on?
         ├── python3.14t (free-threaded) → threads → references/free-threading.md
         └── default GIL build → InterpreterPoolExecutor or multiprocessing
                                                     → references/subinterpreters.md
Need hard isolation between components? → subinterpreters → references/subinterpreters.md
```

## Core Rules

### asyncio (3.14)

- `TaskGroup` over `gather`: it cancels siblings on the first error and waits for cleanup; `gather` leaves the others running. Use `gather(..., return_exceptions=True)` only for "collect every result and error" fan-out.
- `asyncio.timeout()` over `asyncio.wait_for()`: the context manager composes and nests.
- Keep a reference to every task: the loop holds tasks weakly, so a discarded `create_task(...)` can be collected mid-flight. Use a `TaskGroup`, or a set plus `add_done_callback(set.discard)`.
- One loop per thread. Bridge with `asyncio.to_thread` (into a worker) or `asyncio.run_coroutine_threadsafe(coro, loop)` (from a worker back to the loop).

```python
import asyncio

async def main() -> None:
    async with asyncio.timeout(10):
        async with asyncio.TaskGroup() as tg:
            t1 = tg.create_task(fetch("a"))
            t2 = tg.create_task(fetch("b"))
    print(t1.result(), t2.result())

asyncio.run(main())
```

### Free-threading (PEP 779, supported in 3.14)

- A separate build (`python3.14t`), not a runtime flag on the normal build.
- Check at runtime with `sys._is_gil_enabled()` (False means the GIL is off).
- C/Cython/pybind11 extensions must declare support (`Py_mod_gil = Py_MOD_GIL_NOT_USED`); importing one that doesn't re-enables the GIL.
- Single-threaded overhead is about 5–10% in 3.14.

### Subinterpreters (PEP 734)

- `concurrent.interpreters.create()` for low-level control; `concurrent.futures.InterpreterPoolExecutor` for a pool API.
- No shared objects. Data crosses by pickle, plus a few shareable immutables, `memoryview`, and the cross-interpreter `Queue`. Design the interface around picklable messages, as with `multiprocessing`.

## Diagnostic Table

### asyncio errors

| Symptom / Error | Cause | Fix |
|---|---|---|
| `RuntimeError: ... attached to a different loop` | Awaitable created on loop A, awaited on loop B (cached client, second `asyncio.run`) | Create resources inside the running loop; one `asyncio.run` entry; bridge with `run_coroutine_threadsafe` |
| `RuntimeError: no running event loop` | `create_task`/`get_running_loop` called from sync code | Enter via `asyncio.run(...)`; from a thread use `run_coroutine_threadsafe` |
| Coroutine "was never awaited" | `async def` called without `await`/`create_task` | `await` it, or schedule it in a `TaskGroup` |
| Task silently vanishes | Unreferenced `create_task` got GC'd | Keep a strong reference or use `TaskGroup` |
| Whole program freezes under load | Blocking call (`time.sleep`, sync DB, CPU loop) on the loop | Offload with `asyncio.to_thread`/executor |

Details: [references/asyncio-patterns.md](references/asyncio-patterns.md).

### Threads and interpreters

| Symptom / Error | Cause | Fix |
|---|---|---|
| Deadlock acquiring a lock | Re-entrant acquire, or lock-ordering inversion | Consistent lock order; don't `await`/block while holding a lock needed elsewhere |
| Import re-enables the GIL on `python3.14t` | Extension lacks `Py_mod_gil = Py_MOD_GIL_NOT_USED` | Update/replace the module; the import emits a warning naming it |
| Crashes/corruption only on free-threaded build | Data race exposed by GIL removal | Add `Lock`/`Queue`; don't rely on the GIL for atomicity |
| `NotShareableError`/pickling error sending to a subinterpreter | Object not picklable or shareable | Send picklable messages; use a cross-interpreter `Queue`/`memoryview` |

Details: [references/free-threading.md](references/free-threading.md), [references/subinterpreters.md](references/subinterpreters.md).

## References

| File | Read it for |
|---|---|
| [references/asyncio-patterns.md](references/asyncio-patterns.md) | TaskGroup, timeouts, cancellation/shielding, streams, queues, thread bridging, testing |
| [references/free-threading.md](references/free-threading.md) | Installing/verifying `python3.14t`, thread-safety patterns, ecosystem/extension checks |
| [references/subinterpreters.md](references/subinterpreters.md) | `concurrent.interpreters`, `InterpreterPoolExecutor`, data passing, isolation vs processes |
| [references/_index.md](references/_index.md) | Navigation across the three references |

## Related Skills

| Skill | For |
|---|---|
| [modern-python](../modern-python/SKILL.md) | 3.14 language features |
| [python-tooling](../python-tooling/SKILL.md) | Installing interpreters with `uv`, project layout |
| [python-testing](../python-testing/SKILL.md) | pytest, async test configuration |
| [ffi-interop](../../tooling/ffi-interop/SKILL.md) | C-extension `Py_mod_gil` and GIL-release boundaries |
