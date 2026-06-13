# Subinterpreters (concurrent.interpreters)

Use this when:

- You want **multi-core parallelism** without switching to the free-threaded build.
- You want **process-like isolation** between components but cheaper than processes.
- You are designing a CSP / actor-style system (message passing, no shared state).
- You are choosing between `multiprocessing`, threads, and subinterpreters.

Skip if:

- Your work is I/O-bound → use asyncio or threads (`asyncio-patterns.md`).
- You can adopt the free-threaded build and want shared-memory threads → `free-threading.md`.
- You only need to pick a model → start at [../SKILL.md](../SKILL.md).

Jump to:

- What Subinterpreters Are (PEP 734)
- Two APIs: the Module and the Executor
- InterpreterPoolExecutor (start here)
- The Low-Level concurrent.interpreters API
- Passing Data: Pickle, Shareables, Queues
- Isolation vs. multiprocessing vs. Threads
- Extension Constraints (multi-phase init)
- Limitations in 3.14
- Diagnostics

> Baseline: **CPython 3.14**. `concurrent.interpreters` (PEP 734) and
> `concurrent.futures.InterpreterPoolExecutor` are **new in 3.14**. The underlying
> isolation (interpreters not sharing the GIL) has existed since 3.12 (PEP 684).
> APIs are young — verify edge cases against your interpreter.

---

## What Subinterpreters Are (PEP 734)

An "interpreter" is a complete execution context of the Python runtime — its own
import state, its own builtins, its own module objects. CPython has supported multiple
interpreters in one process for two decades, but only through the C API. **PEP 734
exposes them from Python** via the `concurrent.interpreters` module.

The key facts:

- Each interpreter is **isolated**: no shared module state, no shared globals.
- Since 3.12, interpreters **do not share the GIL** — so code in different
  interpreters runs on different cores in parallel.
- Think of them as **"threads with opt-in sharing"** or **"the isolation of processes
  with the efficiency of threads"** (same process — lower startup and memory cost than
  spawning OS processes, though startup is not yet optimized in 3.14).

This gives you a third parallelism story alongside the GIL-build (no CPU parallelism)
and the free-threaded build (shared-memory parallelism): **isolated multi-core
parallelism**, where components communicate only through explicit messages.

---

## Two APIs: the Module and the Executor

| API | Level | Use when |
|---|---|---|
| `concurrent.futures.InterpreterPoolExecutor` | High | You want a familiar pool/`submit`/`map` interface — **start here** |
| `concurrent.interpreters` | Low | You need direct control over interpreter lifecycle, queues, or per-interpreter setup |

They are independent: `InterpreterPoolExecutor` lives in `concurrent.futures` and
provides a pool of interpreters running on a thread each; `concurrent.interpreters`
gives you the building blocks.

---

## InterpreterPoolExecutor (start here)

It mirrors `ThreadPoolExecutor`/`ProcessPoolExecutor` — but each worker runs in its
own subinterpreter on its own thread, so CPU-bound calls parallelize across cores
even on the **default GIL build**.

```python
from concurrent.futures import InterpreterPoolExecutor

def cpu_task(n: int) -> int:
    return sum(i * i for i in range(n))     # pure-Python CPU work

def main() -> list[int]:
    with InterpreterPoolExecutor(max_workers=4) as pool:
        return list(pool.map(cpu_task, [10_000_000] * 4))

if __name__ == "__main__":
    print(main())
```

Because workers are isolated interpreters, the same constraints as `multiprocessing`
apply to what you pass:

- **Arguments and return values cross by pickle** (with a few directly-shared
  immutables). They must be picklable.
- The callable must be importable/picklable too — module-level functions work;
  lambdas and closures generally do not.
- Each worker starts with a fresh interpreter; module-level state is not shared with
  the parent or between workers.

```python
from concurrent.futures import InterpreterPoolExecutor

def analyze(path: str) -> dict[str, int]:
    # Imports happen inside the worker interpreter.
    import collections
    counts: collections.Counter = collections.Counter()
    with open(path, encoding="utf-8") as f:
        for line in f:
            counts.update(line.split())
    return dict(counts)   # picklable return

def run(paths: list[str]) -> list[dict[str, int]]:
    with InterpreterPoolExecutor() as pool:
        futures = [pool.submit(analyze, p) for p in paths]
        return [f.result() for f in futures]
```

You can also give each worker an initializer (e.g., to set up imports or load a model
copy per interpreter), the same way you would for the other executors.

---

## The Low-Level concurrent.interpreters API

When you need lifecycle control, drop to the module.

```python
from concurrent import interpreters

interp = interpreters.create()      # a fresh, idle interpreter

# Run source in the current OS thread (switches to interp, runs, switches back):
interp.exec('print("hello from a subinterpreter")')

# Call a function in the interpreter and get its (picklable) result back:
def square(x: int) -> int:
    return x * x

result = interp.call(square, 12)    # runs in interp, current thread
print(result)                       # 144

interp.close()                      # finalize and destroy
```

### Run in a new thread (this is where parallelism comes from)

`exec`/`call` run in the *current* thread, so they do not give you concurrency on
their own. Use `call_in_thread` (or pair an interpreter with `threading.Thread`) to
get parallel execution:

```python
from concurrent import interpreters

def work() -> None:
    total = sum(i * i for i in range(10_000_000))
    print(total)

interp = interpreters.create()
t = interp.call_in_thread(work)     # new OS thread + this interpreter → parallel
t.join()
interp.close()
```

Spin up several interpreters, each on its own thread, for multi-core CPU work:

```python
from concurrent import interpreters

def heavy(seed: int) -> int:
    return sum((i ^ seed) for i in range(5_000_000))

interps = [interpreters.create() for _ in range(4)]
threads = [it.call_in_thread(heavy, n) for n, it in enumerate(interps)]
for t in threads:
    t.join()
for it in interps:
    it.close()
```

### Module reference (3.14)

| Function / method | Purpose |
|---|---|
| `interpreters.create()` | Create a new idle interpreter, returns `Interpreter` |
| `interpreters.list_all()` | List all existing interpreters |
| `interpreters.get_current()` / `get_main()` | The current / main interpreter |
| `interpreters.create_queue()` | Create a cross-interpreter `Queue` |
| `Interpreter.exec(code)` | Run source in this interpreter (current thread) |
| `Interpreter.call(fn, *args, **kwargs)` | Call a function in this interpreter, return its result |
| `Interpreter.call_in_thread(fn, ...)` | Call in a new OS thread → parallelism |
| `Interpreter.prepare_main(**kwargs)` | Bind objects into the interpreter's `__main__` |
| `Interpreter.close()` | Finalize and destroy |

Exceptions to handle: `InterpreterError`, `InterpreterNotFoundError`,
`ExecutionFailed` (wraps an uncaught exception from the other interpreter, with an
`excinfo` snapshot), and `NotShareableError` (a `TypeError` subclass) when an object
cannot be sent.

```python
from concurrent import interpreters

interp = interpreters.create()
try:
    interp.exec("raise ValueError('boom')")
except interpreters.ExecutionFailed as e:
    print("subinterpreter failed:", e.excinfo)   # snapshot of the remote exception
finally:
    interp.close()
```

---

## Passing Data: Pickle, Shareables, Queues

There is **no shared object graph**. This is the central design constraint — plan your
interface around messages, not shared mutable objects.

### How values cross

- **Most objects are copied via `pickle`.** If it is not picklable, it cannot be sent
  (you get `NotShareableError` / a pickling error).
- A handful of **immutables are shared or copied efficiently**: `None`, `bool`,
  `bytes`, `str`, `int`, `float`, and `tuple`s of such objects.
- Two types actually **share mutable data** across interpreters:
  - `memoryview` (a view over a shared buffer), and
  - the cross-interpreter `Queue` from `create_queue()`.

Because most objects are *copied*, mutating an object in one interpreter does **not**
affect the original in another — exactly like `multiprocessing`.

### Cross-interpreter queues

`create_queue()` returns a `Queue` with the familiar `queue.Queue` interface that
works across interpreters. Items are copied via pickle (with the shareable-immutable
fast paths). This is the idiomatic channel for CSP/actor designs.

```python
from concurrent import interpreters

q = interpreters.create_queue()

producer = interpreters.create()
producer.prepare_main(q=q)          # bind the queue into the worker's __main__
t = producer.call_in_thread(
    lambda: [q.put(f"item-{i}") for i in range(5)]  # illustrative; prefer a named fn
)

for _ in range(5):
    print(q.get())                  # parent consumes copies
t.join()
producer.close()
```

`Queue.get`/`put` raise `QueueEmptyError` / `QueueFullError` (subclasses of
`queue.Empty` / `queue.Full`) for the non-blocking variants, matching the stdlib
queue contract.

### Sharing a buffer with memoryview

For large binary payloads, a `memoryview` over a shared buffer avoids the copy:

```python
from concurrent import interpreters

buf = bytearray(1024 * 1024)
view = memoryview(buf)              # shareable: backed by the same memory

interp = interpreters.create()
interp.prepare_main(view=view)
interp.exec("view[0] = 42")         # mutation is visible in the parent's buffer
print(buf[0])                       # 42
interp.close()
```

Use this only for raw bytes-like buffers; arbitrary Python objects still copy.

---

## Isolation vs. multiprocessing vs. Threads

| Dimension | Threads (GIL build) | Threads (`python3.14t`) | Subinterpreters | multiprocessing |
|---|---|---|---|---|
| CPU parallelism | No | Yes | **Yes** | Yes |
| Memory model | Shared | Shared (locks required) | **Isolated, copy by pickle** | Isolated, copy by pickle |
| Data passing | Direct references | Direct references | pickle / memoryview / Queue | pickle / shared memory |
| Startup cost | Lowest | Lowest | Low (in-process; not yet optimized) | Highest (new OS process) |
| Crash blast radius | Whole process | Whole process | Whole process (same process) | Isolated (separate process) |
| Race risk | GIL hides many | High — needs locks | **None across interpreters** (no sharing) | None across processes |

Choose **subinterpreters** when you want isolation-driven correctness (no shared
mutable state, no data races between components) *and* multi-core CPU parallelism, but
want to stay in one process (lower memory/IPC overhead than `multiprocessing`).

Choose **multiprocessing** instead when you need a hard fault boundary (a worker crash
must not take down the parent) or OS-level isolation, or when you need a mature
ecosystem of shared-memory/IPC tools today.

Choose **free-threading** when components genuinely need to share large mutable state
and you can manage the locking.

> Caution: subinterpreters live in the **same process**, so isolation is best-effort,
> not a security boundary. A misbehaving C extension can violate it. Do **not** use
> subinterpreters to sandbox untrusted code.

---

## Extension Constraints (multi-phase init)

A C extension can only be imported into a subinterpreter if it supports
**multi-phase initialization** (`PyModuleDef` with `m_slots` / `PyModuleDef_Slot`)
and declares per-interpreter support. Single-phase legacy modules (those using only
`PyModule_Create` with module-global state) cannot be loaded into more than one
interpreter and will raise `ImportError`.

The relevant slot signals support for multiple interpreters:

```c
static PyModuleDef_Slot slots[] = {
    {Py_mod_exec, mymodule_exec},
    {Py_mod_multiple_interpreters, Py_MOD_PER_INTERPRETER_GIL_SUPPORTED},
    {0, NULL},
};
```

Notes:

- All **standard-library** C extensions are compatible.
- Many third-party extensions on PyPI are **not yet** compatible — verify each one.
- The work to isolate an extension for subinterpreters overlaps heavily with the work
  to support free-threading, so the two ecosystem efforts advance together (see the
  "Isolating Extension Modules" CPython how-to).
- Binding tools (Cython, pybind11, nanobind, PyO3) are progressively adding support —
  check the tool's current release notes.

If you must use an incompatible extension, keep it in the **main** interpreter and
push only picklable results to/from workers, or fall back to `multiprocessing`.

---

## Limitations in 3.14

PEP 734 is new; the feature is mainstream-ready but still maturing. Known limitations
to design around:

- **Startup is not yet optimized** — creating an interpreter is cheaper than a process
  but not free; reuse interpreters (or the executor's pool) rather than creating one
  per task.
- **Higher-than-necessary memory per interpreter** — internal sharing is still being
  improved.
- **Few sharing options** — beyond pickle, only `memoryview` and the cross-interpreter
  `Queue` share data directly.
- **Limited third-party extension support** — verify your dependency tree.
- **Unfamiliar model** — the CSP/actor approach is new to most Python codebases; budget
  for design time.

Expect these to improve in later releases (and PyPI packages may fill gaps, even back
to 3.12). Verify the current state against your interpreter and dependencies.

---

## Diagnostics

| Symptom / Error | Cause | Fix |
|---|---|---|
| `NotShareableError` / `PicklingError` on `submit`/`put`/`prepare_main` | Argument, return value, or callable is not picklable | Send picklable messages; use module-level functions, not lambdas/closures |
| `ImportError` importing a C extension in a subinterpreter | Extension is single-phase / lacks `Py_mod_multiple_interpreters` | Keep it in the main interpreter; or use `multiprocessing`; or wait for an updated wheel |
| `ExecutionFailed` from `exec`/`call` | Code raised in the other interpreter | Inspect `excinfo`; fix the remote code; wrap in try/except inside the worker |
| No speedup over plain threads (GIL build) | Work runs via `exec`/`call` in the current thread | Use `call_in_thread` or `InterpreterPoolExecutor` so workers run on separate threads |
| High memory / slow startup at scale | One interpreter created per task | Reuse interpreters; prefer the pooled `InterpreterPoolExecutor` |
| Mutation in one interpreter not visible in another | Objects are copied, not shared | Expected; use a cross-interpreter `Queue` or `memoryview` for shared data |
| Worker crash takes down the whole program | Subinterpreters share one process | If you need a fault boundary, use `multiprocessing` instead |

## Related References

- [free-threading.md](free-threading.md) — shared-memory multi-core via the `python3.14t` build
- [asyncio-patterns.md](asyncio-patterns.md) — for I/O-bound concurrency instead
- [_index.md](_index.md) — navigation
