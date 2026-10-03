# Subinterpreters (concurrent.interpreters)

`concurrent.interpreters` (PEP 734) and `concurrent.futures.InterpreterPoolExecutor`
are new in 3.14; per-interpreter GILs date from 3.12 (PEP 684). Choosing a model:
[../SKILL.md](../SKILL.md).

## What Subinterpreters Are (PEP 734)

An interpreter is a complete runtime context with its own imports, builtins, and
module objects; PEP 734 exposes them from Python. Interpreters share no module state
or globals, and each has its own GIL, so code in different interpreters runs on
different cores. The result is isolated multi-core parallelism in one process:
components communicate only through explicit messages, at lower startup and memory
cost than OS processes.

## Two APIs: the Module and the Executor

| API | Level | Use when |
|---|---|---|
| `concurrent.futures.InterpreterPoolExecutor` | High | You want a pool/`submit`/`map` interface; start here |
| `concurrent.interpreters` | Low | You need direct control over interpreter lifecycle, queues, or per-interpreter setup |

## InterpreterPoolExecutor (start here)

Like `ThreadPoolExecutor`, but each worker runs in its own subinterpreter on its own
thread, so CPU-bound calls parallelize even on the default GIL build.

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

### What crosses to workers

The `multiprocessing` constraints apply: arguments, return values, and the callable
cross by pickle (module-level functions work; lambdas and closures don't), and each
worker's module state is its own.

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

`initializer`/`initargs` run per worker, as with the other executors.

## The Low-Level concurrent.interpreters API

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

`exec`/`call` run in the current thread, so they give no concurrency on their own.
`call_in_thread` (or a `threading.Thread` running `exec`) does:

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

### Exceptions

`InterpreterError`, `InterpreterNotFoundError`, `ExecutionFailed` (an uncaught
exception in the other interpreter, with an `excinfo` snapshot), and
`NotShareableError` (a `TypeError` subclass) when an object cannot be sent.

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

## Passing Data: Pickle, Shareables, Queues

There is no shared object graph; design the interface around messages.

- Most objects are copied via `pickle`; unpicklable ones can't be sent.
- Shareable immutables cross efficiently: `None`, `bool`, `bytes`, `str`, `int`,
  `float`, and tuples of these.
- Only `memoryview` and the cross-interpreter `Queue` share mutable data.

Copies are independent: mutating one does not affect the original, as with
`multiprocessing`.

### Cross-interpreter queues

`create_queue()` returns a `Queue` with the `queue.Queue` interface that works across
interpreters; items are copied. It is the idiomatic CSP/actor channel.

```python
import threading
from concurrent import interpreters

q = interpreters.create_queue()
producer = interpreters.create()
producer.prepare_main(q=q)          # bind the queue into the worker's __main__
code = "for i in range(5): q.put(f'item-{i}')"
t = threading.Thread(target=producer.exec, args=(code,))
t.start()
for _ in range(5):
    print(q.get())                  # parent consumes copies
t.join()
producer.close()
```

Non-blocking `get`/`put` raise `QueueEmptyError`/`QueueFullError` (subclasses of
`queue.Empty`/`queue.Full`).

### Sharing a buffer with memoryview

For large binary payloads, a `memoryview` avoids the copy (raw buffers only):

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

## Isolation vs. multiprocessing vs. Threads

| Dimension | Threads (GIL build) | Threads (`python3.14t`) | Subinterpreters | multiprocessing |
|---|---|---|---|---|
| CPU parallelism | No | Yes | Yes | Yes |
| Memory model | Shared | Shared (locks required) | Isolated, copy by pickle | Isolated, copy by pickle |
| Data passing | Direct references | Direct references | pickle / memoryview / Queue | pickle / shared memory |
| Startup cost | Lowest | Lowest | Low (in-process; not yet optimized) | Highest (new OS process) |
| Crash blast radius | Whole process | Whole process | Whole process (same process) | Isolated (separate process) |
| Race risk | GIL hides many | High — needs locks | None across interpreters (no sharing) | None across processes |

### Choosing

- Subinterpreters: no shared mutable state plus multi-core CPU, in one process.
- multiprocessing: a hard fault boundary (a worker crash must not take down the
  parent), OS-level isolation, or mature shared-memory/IPC tools.
- Free-threading: components must share large mutable state and you can manage locking.

Subinterpreters share a process, so isolation is best-effort, not a security
boundary; a misbehaving C extension can break it. Don't use them to sandbox
untrusted code.

## Extension Constraints (multi-phase init)

A C extension imports into a subinterpreter only if it uses multi-phase
initialization (`m_slots`) and declares per-interpreter-GIL support; single-phase
modules (`PyModule_Create` with global state) raise `ImportError`.

```c
static PyModuleDef_Slot slots[] = {
    {Py_mod_exec, mymodule_exec},
    {Py_mod_multiple_interpreters, Py_MOD_PER_INTERPRETER_GIL_SUPPORTED},
    {0, NULL},
};
```

Standard-library C extensions are compatible; many third-party ones are not, so check
each (CPython how-to: "Isolating Extension Modules"). Keep an incompatible extension
in the main interpreter and pass picklable results to and from workers, or use
`multiprocessing`.

## Limitations in 3.14

- Startup is not yet optimized: reuse interpreters (or the executor's pool) instead of
  creating one per task.
- Memory per interpreter is higher than necessary.
- Few sharing options beyond pickle, `memoryview`, and `Queue`.
- Limited third-party extension support.

## Diagnostics

| Symptom / Error | Cause | Fix |
|---|---|---|
| `NotShareableError` / `PicklingError` on `submit`/`put`/`prepare_main` | Argument, return value, or callable is not picklable | Send picklable messages; use module-level functions, not lambdas/closures |
| `ImportError` for a C extension in a subinterpreter | Single-phase, or lacks per-interpreter-GIL support | Keep it in the main interpreter, or use `multiprocessing` |
| `ExecutionFailed` from `exec`/`call` | Code raised in the other interpreter | Inspect `excinfo` |
| No speedup (GIL build) | Work runs via `exec`/`call` in the current thread | `call_in_thread` or `InterpreterPoolExecutor` |
| High memory / slow startup at scale | One interpreter per task | Reuse interpreters; prefer the pool |
| Mutation not visible in another interpreter | Objects are copied | Expected; use `Queue` or `memoryview` |
| Worker crash takes down the program | One shared process | Use `multiprocessing` for a fault boundary |

## Related References

- [free-threading.md](free-threading.md) — shared-memory multi-core via the `python3.14t` build
- [asyncio-patterns.md](asyncio-patterns.md) — for I/O-bound concurrency instead
- [_index.md](_index.md) — navigation
