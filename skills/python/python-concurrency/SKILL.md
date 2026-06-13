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

**Pick the model first. Then write the code. Most concurrency bugs are model-selection bugs.**

> Version baseline: **CPython 3.14** (`python3.14`). Free-threading uses the
> separate **`python3.14t`** build. Where a feature is newer than 3.14, the row
> says so. Verify volatile toolchain minutiae against your interpreter
> (`python3.14 -VV`, `sysconfig.get_config_var(...)`).

## When to Use

Use this skill when:

- You must choose between asyncio, threads, multiprocessing, free-threading, or subinterpreters.
- You are writing `async`/`await` code and want the modern (TaskGroup-era) patterns.
- You are targeting or evaluating the free-threaded build (`python3.14t`).
- You need true multi-core parallelism for CPU-bound Python.
- You are diagnosing "attached to a different loop", deadlocks, or races.

## The Decision Table

| Workload | Use | Why / Marker |
|---|---|---|
| Many concurrent I/O operations (network, sockets, DB with async drivers) | **asyncio** + `TaskGroup` | Single thread, cooperative; thousands of in-flight ops cheaply |
| I/O via blocking libraries (sync DB driver, `requests`, file I/O) | **threads** (`ThreadPoolExecutor`, `asyncio.to_thread`) | GIL releases on blocking syscalls; threads overlap the waits |
| CPU-bound, on the **free-threaded build** (`python3.14t`) | **threads** | PEP 703/779: no GIL → real multi-core within one process |
| CPU-bound, on the **default GIL build** | **multiprocessing** or **`InterpreterPoolExecutor`** | GIL serializes pure-Python CPU work; need separate interpreters/processes |
| Strong isolation, opt-in sharing (CSP / actor style) | **subinterpreters** (`concurrent.interpreters`) | PEP 734: process-like isolation, thread-like efficiency, share via pickle |
| Simple script, few connections | **stay synchronous** | Async adds complexity with no payoff at low concurrency |

**Two rules that override the table:**

1. **Stay fully sync or fully async within one call path.** Mixing hides blocking calls.
2. **GIL removal does not remove races.** On `python3.14t`, shared mutable state still
   needs `threading.Lock`/`Queue`/atomics-by-convention. The free-threaded build makes
   data races *more likely to manifest*, not impossible.

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

- **`TaskGroup` over `gather`.** `TaskGroup` propagates the first error, cancels
  siblings, and waits for cleanup. `gather` leaks tasks on failure unless you are
  careful. Use `gather(..., return_exceptions=True)` only when you genuinely want
  "collect all results and errors" fan-out.
- **`asyncio.timeout()` over `asyncio.wait_for()`.** The context manager composes,
  nests, and reads cleanly. `wait_for` is the legacy single-coroutine form.
- **Never create an unreferenced task.** `asyncio.create_task(coro())` whose result
  is discarded can be garbage-collected mid-flight. Keep a reference, or use a
  `TaskGroup`, or hold it in a set with a `done_callback` to discard.
- **One loop per thread.** Awaitables are bound to the loop that created them.
  Bridge across threads with `asyncio.to_thread` (into a worker) or
  `loop.run_coroutine_threadsafe` (from a worker back to the loop).

```python
import asyncio

async def main() -> None:
    async with asyncio.timeout(10):
        async with asyncio.TaskGroup() as tg:
            t1 = tg.create_task(fetch("a"))
            t2 = tg.create_task(fetch("b"))
    # both succeeded here; first failure would have cancelled the other
    print(t1.result(), t2.result())

asyncio.run(main())
```

### Free-threading (PEP 779, officially supported in 3.14)

- It is a **separate build** (`python3.14t`), not a runtime flag on the normal build.
- Check at runtime with `sys._is_gil_enabled()` (False ⇒ GIL disabled).
- C/Cython/pybind11 extensions must **declare** free-threading support
  (`Py_mod_gil = Py_MOD_GIL_NOT_USED`); otherwise importing them re-enables the GIL.
- Single-threaded overhead on the free-threaded build is roughly **5–10%** in 3.14
  (platform/compiler dependent — verify against your toolchain).

### Subinterpreters (PEP 734)

- `concurrent.interpreters.create()` for low-level control;
  `concurrent.futures.InterpreterPoolExecutor` for a familiar pool API.
- **No shared objects.** Data crosses by **pickle** (plus a few directly-shared
  immutables and `memoryview`/cross-interpreter `Queue`). Plan your interface
  around picklable messages, like `multiprocessing` but in-process.

## Diagnostic Table

| Symptom / Error | Cause | Fix | Reference |
|---|---|---|---|
| `RuntimeError: ... got Future ... attached to a different loop` | Awaitable created on loop A, awaited on loop B (often a cached client or a second `asyncio.run`) | Create resources inside the running loop; use one `asyncio.run` entry; bridge with `run_coroutine_threadsafe` | `references/asyncio-patterns.md` |
| `RuntimeError: no running event loop` | Calling `create_task`/`get_running_loop` from sync code | Enter via `asyncio.run(...)`; from a thread use `run_coroutine_threadsafe` | `references/asyncio-patterns.md` |
| Coroutine "was never awaited" warning | Called an `async def` without `await`/`create_task` | `await` it, or schedule it in a `TaskGroup` | `references/asyncio-patterns.md` |
| Task silently vanishes / partial results | Unreferenced `create_task` got GC'd | Keep a strong reference or use `TaskGroup` | `references/asyncio-patterns.md` |
| Whole program freezes under load | Blocking call (`time.sleep`, sync DB, CPU loop) on the event loop | Offload with `asyncio.to_thread`/executor | `references/asyncio-patterns.md` |
| Deadlock acquiring a lock | Re-entrant acquire, or lock-ordering inversion across threads/coroutines | Consistent lock order; never `await`/block while holding a lock you also need elsewhere | `references/free-threading.md` |
| Import re-enables the GIL on `python3.14t` | Extension does not declare `Py_mod_gil`/`Py_MOD_GIL_NOT_USED` | Update/replace the module; check `PYTHONWARNINGS`/import warning | `references/free-threading.md` |
| `pickle`/`NotShareableError` passing data to a subinterpreter | Object is not picklable / not shareable | Send picklable messages; use a cross-interpreter `Queue`/`memoryview` | `references/subinterpreters.md` |
| Crashes/data corruption only on free-threaded build | Real data race exposed by GIL removal | Add `Lock`/`Queue`; do not rely on the GIL for atomicity | `references/free-threading.md` |

## References

| File | Read it for |
|---|---|
| [references/asyncio-patterns.md](references/asyncio-patterns.md) | TaskGroup, timeouts, cancellation/shielding, streams, queues, thread bridging, testing |
| [references/free-threading.md](references/free-threading.md) | Installing/verifying `python3.14t`, thread-safety patterns, ecosystem/extension checks |
| [references/subinterpreters.md](references/subinterpreters.md) | `concurrent.interpreters`, `InterpreterPoolExecutor`, data passing, isolation vs processes |
| [references/_index.md](references/_index.md) | Navigation across the three references |

## Related Skills

- [modern-python](../modern-python/SKILL.md) — 3.14 language features (t-strings, deferred annotations)
- [python-tooling](../python-tooling/SKILL.md) — installing interpreters with `uv`, project layout
- [python-testing](../python-testing/SKILL.md) — pytest, async test configuration
- [ffi-interop](../../tooling/ffi-interop/SKILL.md) — C-extension `Py_mod_gil` and GIL-release boundaries
