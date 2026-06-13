# Asyncio Patterns (TaskGroup Era)

Use this when:

- You are writing or reviewing `async`/`await` code on **CPython 3.14**.
- You need structured concurrency, timeouts, cancellation, or backpressure.
- You must bridge synchronous code (blocking libraries, other threads) into async.
- You are writing tests for coroutines.

Skip if:

- You are deciding *whether* to use asyncio at all → start at [../SKILL.md](../SKILL.md).
- Your bottleneck is CPU-bound pure Python → see `free-threading.md` / `subinterpreters.md`.

Jump to:

- The Modern Baseline (what changed)
- Structured Concurrency with TaskGroup
- Timeouts
- Cancellation and Shielding
- Tasks: References, Fire-and-Forget, Backpressure
- gather vs TaskGroup
- Async Iterators and Streams
- Queues and Producer/Consumer
- Synchronization Primitives
- Bridging Sync and Async
- Running Blocking and CPU Work
- Testing Async Code
- Anti-Patterns

> Baseline: **Python 3.14**. `TaskGroup` and `asyncio.timeout()` arrived in 3.11,
> so these patterns also run on 3.11–3.13. Where 3.14 adds something new, the text
> says "3.14". Verify edge-case behavior against your interpreter (`python3.14 -VV`).

---

## The Modern Baseline (what changed)

If you learned asyncio before 3.11, retire these habits:

| Old pattern | Use instead | Reason |
|---|---|---|
| `asyncio.get_event_loop()` | `asyncio.run(main())`; `asyncio.get_running_loop()` inside coroutines | `get_event_loop()` from sync code is deprecated and error-prone |
| `loop.run_until_complete(...)` | `asyncio.run(...)` | One managed entry point; sets up and tears down the loop |
| `asyncio.gather(*tasks)` for "do these together" | `asyncio.TaskGroup` | Structured: cancels siblings on error, awaits cleanup |
| `asyncio.wait_for(coro, timeout)` | `async with asyncio.timeout(seconds):` | Composes and nests; clearer scope |
| `asyncio.ensure_future(...)` | `asyncio.create_task(...)` or `tg.create_task(...)` | `create_task` is the explicit, current API |
| `@asyncio.coroutine` / `yield from` | `async def` / `await` | Removed long ago |

`asyncio.run()` is the only entry point you need from synchronous code. It creates a
fresh event loop, runs the coroutine, and closes the loop — including an orderly
shutdown of async generators.

```python
import asyncio

async def main() -> None:
    ...

if __name__ == "__main__":
    asyncio.run(main())
```

---

## Structured Concurrency with TaskGroup

`TaskGroup` is the default tool for "run several coroutines concurrently and wait
for all of them." It gives you three guarantees that bare tasks do not:

1. The group does not exit until every child task finishes.
2. If any child raises, the rest are cancelled.
3. Errors surface as an `ExceptionGroup` you handle with `except*`.

```python
import asyncio

async def fetch(name: str) -> str:
    await asyncio.sleep(0.1)
    return f"data:{name}"

async def main() -> None:
    async with asyncio.TaskGroup() as tg:
        a = tg.create_task(fetch("a"))
        b = tg.create_task(fetch("b"))
        c = tg.create_task(fetch("c"))
    # Reached only if all three succeeded. Results are now available.
    print(a.result(), b.result(), c.result())

asyncio.run(main())
```

### Handling partial failure

When one task raises, the group cancels the others and re-raises an
`ExceptionGroup`. Use `except*` to match by type:

```python
async def main() -> None:
    try:
        async with asyncio.TaskGroup() as tg:
            tg.create_task(might_404())
            tg.create_task(might_timeout())
    except* ValueError as eg:
        for exc in eg.exceptions:
            log.warning("validation failed: %s", exc)
    except* TimeoutError as eg:
        log.error("%d operations timed out", len(eg.exceptions))
```

### Dynamic fan-out

Create tasks in a loop; the group still tracks them all.

```python
async def process_all(items: list[str]) -> list[str]:
    async with asyncio.TaskGroup() as tg:
        tasks = [tg.create_task(process(item)) for item in items]
    return [t.result() for t in tasks]
```

**Do not add tasks to a group after its `async with` body has begun unwinding** —
once the group starts shutting down, `create_task` raises `RuntimeError`.

---

## Timeouts

Use `asyncio.timeout()` as a context manager. It bounds *everything* inside the
block, composes with `TaskGroup`, and nests.

```python
import asyncio

async def main() -> None:
    try:
        async with asyncio.timeout(5):
            await slow_operation()
    except TimeoutError:           # asyncio.TimeoutError is an alias of builtin TimeoutError (3.11+)
        log.error("slow_operation exceeded 5s")
```

### Absolute deadlines

`asyncio.timeout_at()` takes a loop-clock deadline — useful when a deadline is
shared across several stages.

```python
async def staged(deadline: float) -> None:
    async with asyncio.timeout_at(deadline):
        await stage_one()
        await stage_two()   # both must finish before the shared deadline
```

### Reschedulable timeout

The context manager object lets you extend or shorten the deadline mid-flight:

```python
async def main() -> None:
    async with asyncio.timeout(None) as cm:     # start with no deadline
        await connect()
        cm.reschedule(asyncio.get_running_loop().time() + 10)  # 10s for the rest
        await transfer()
```

`asyncio.wait_for(coro, timeout)` still exists and is fine for wrapping a *single*
awaitable, but prefer `timeout()` for anything with more than one statement.

---

## Cancellation and Shielding

Cancellation is delivered as a `CancelledError` raised at the next suspension
point. Treat it as control flow, not an error.

### Always re-raise CancelledError

```python
async def worker() -> None:
    try:
        while True:
            await do_unit_of_work()
    except asyncio.CancelledError:
        await flush_buffers()      # cleanup is fine
        raise                      # MUST re-raise so cancellation propagates
```

Swallowing `CancelledError` (catching it without re-raising) breaks structured
concurrency: the awaiting parent thinks the task is still alive.

### Cancelling a task and waiting for it

```python
task = asyncio.create_task(worker())
...
task.cancel()
try:
    await task
except asyncio.CancelledError:
    pass   # expected
```

### Shielding critical sections

`asyncio.shield()` protects an awaitable from *outer* cancellation. Use it sparingly
— for example, to finish committing a transaction even if the caller times out.

```python
async def save(record: Record) -> None:
    # If the surrounding timeout fires, the DB write still completes.
    await asyncio.shield(db.commit(record))
```

Note: if the *outer* scope is cancelled, the `await` on the shield still raises
`CancelledError` — but the shielded coroutine keeps running to completion. Keep a
reference to the inner task if you need its result afterward.

### Cleanup that must not be cancelled

For teardown, prefer `try/finally` with a fresh `timeout` rather than shielding
everything:

```python
async def session() -> None:
    conn = await open_conn()
    try:
        await use(conn)
    finally:
        async with asyncio.timeout(2):
            await conn.aclose()
```

---

## Tasks: References, Fire-and-Forget, Backpressure

### The unreferenced-task footnote (a real bug)

`asyncio.create_task()` returns a Task the loop holds only **weakly**. If you do not
keep a reference and the local goes out of scope, the task can be garbage-collected
mid-execution and silently disappear.

```python
# WRONG — task may vanish before it finishes
asyncio.create_task(send_metric(event))

# RIGHT (1) — let a TaskGroup own it
async with asyncio.TaskGroup() as tg:
    tg.create_task(send_metric(event))

# RIGHT (2) — keep a strong reference set for genuine fire-and-forget
_background: set[asyncio.Task] = set()

def spawn(coro) -> None:
    task = asyncio.create_task(coro)
    _background.add(task)
    task.add_done_callback(_background.discard)
```

Prefer (1). Reach for (2) only for true background work whose lifetime exceeds the
current scope (e.g., a server-wide telemetry flusher).

### Bounding concurrency with a semaphore

Unbounded fan-out exhausts file descriptors and overwhelms servers. Cap it.

```python
async def fetch_all(urls: list[str], limit: int = 10) -> list[bytes]:
    sem = asyncio.Semaphore(limit)

    async def one(url: str) -> bytes:
        async with sem:
            return await fetch(url)

    async with asyncio.TaskGroup() as tg:
        tasks = [tg.create_task(one(u)) for u in urls]
    return [t.result() for t in tasks]
```

---

## gather vs TaskGroup

| Need | Use | Notes |
|---|---|---|
| Run N, fail fast, cancel the rest | `TaskGroup` | Default choice |
| Run N, collect every result *and* every error | `gather(*aws, return_exceptions=True)` | Returns a list mixing results and exception objects |
| Run N where one failure should NOT cancel siblings | `gather(..., return_exceptions=True)` | Then inspect each item |

`gather` without `return_exceptions=True` cancels the *gather* on first error but
leaves other tasks running if you created them separately — a classic leak. If you
use `gather`, pass the coroutines directly so it owns them.

```python
results = await asyncio.gather(
    fetch("a"), fetch("b"), fetch("c"),
    return_exceptions=True,
)
for r in results:
    if isinstance(r, Exception):
        log.warning("one fetch failed: %r", r)
    else:
        handle(r)
```

`asyncio.as_completed()` yields results in completion order — useful for "process
each as soon as it lands."

```python
async def first_to_finish(coros) -> str:
    for coro in asyncio.as_completed(coros):
        return await coro    # returns the earliest-completing result
    raise RuntimeError("no coroutines")
```

---

## Async Iterators and Streams

### Async generators

```python
from collections.abc import AsyncIterator

async def paginate(url: str, pages: int) -> AsyncIterator[dict]:
    for page in range(1, pages + 1):
        data = await fetch_page(url, page)
        yield data

async def consume() -> None:
    async for page in paginate("https://api.example.com/items", 5):
        handle(page)
```

`asyncio.run()` shuts async generators down cleanly on exit. If you iterate
generators outside `asyncio.run`, close them explicitly with `aclose()` in a
`finally`.

### Async context managers

```python
class Resource:
    async def __aenter__(self) -> "Resource":
        await self._open()
        return self

    async def __aexit__(self, *exc_info: object) -> None:
        await self._close()

async def use() -> None:
    async with Resource() as r:
        await r.do_work()
```

For combining several, `contextlib.AsyncExitStack` stacks them dynamically:

```python
from contextlib import AsyncExitStack

async def open_many(configs: list[Config]) -> None:
    async with AsyncExitStack() as stack:
        conns = [await stack.enter_async_context(connect(c)) for c in configs]
        await run(conns)
```

---

## Queues and Producer/Consumer

`asyncio.Queue` gives you backpressure: a bounded queue makes producers wait when
consumers fall behind.

```python
import asyncio

async def producer(q: asyncio.Queue[int], n: int) -> None:
    for i in range(n):
        await q.put(i)          # blocks when the queue is full → backpressure

async def consumer(q: asyncio.Queue[int]) -> None:
    while True:
        item = await q.get()
        try:
            await handle(item)
        finally:
            q.task_done()

async def main() -> None:
    q: asyncio.Queue[int] = asyncio.Queue(maxsize=100)
    async with asyncio.TaskGroup() as tg:
        tg.create_task(producer(q, 1000))
        workers = [tg.create_task(consumer(q)) for _ in range(5)]
        await q.join()          # wait until every produced item is task_done()
        for w in workers:       # then stop the (otherwise infinite) consumers
            w.cancel()
```

Use a sentinel (`None`) on the queue, or cancel the consumers as above. Prefer
`q.join()` + `task_done()` over manual counting: it tracks outstanding work for you.

---

## Synchronization Primitives

asyncio's `Lock`, `Semaphore`, `Event`, and `Condition` coordinate **coroutines on
one loop** — they are *not* thread-safe and not interchangeable with
`threading.Lock`.

```python
class Cache:
    def __init__(self) -> None:
        self._lock = asyncio.Lock()
        self._data: dict[str, bytes] = {}

    async def get_or_load(self, key: str) -> bytes:
        async with self._lock:                  # serialize loads of the same key
            if key not in self._data:
                self._data[key] = await load(key)
            return self._data[key]
```

`asyncio.Event` for one-shot signaling between coroutines:

```python
ready = asyncio.Event()

async def waiter() -> None:
    await ready.wait()
    proceed()

async def setup() -> None:
    await initialize()
    ready.set()
```

For cross-thread coordination, do **not** use asyncio primitives — use
`threading`/`queue` primitives plus the bridging functions below.

---

## Bridging Sync and Async

### Sync → async (start a loop)

Only from genuinely synchronous code (e.g., a CLI entry point):

```python
def main() -> None:
    asyncio.run(async_main())
```

Never call `asyncio.run()` from inside a coroutine or a running loop — it raises
`RuntimeError: asyncio.run() cannot be called from a running event loop`. To run
async work from within sync code that is *itself* called by a loop, you are in the
wrong layer; refactor so the function is `async`.

### Async → sync (call blocking code without freezing the loop)

`asyncio.to_thread()` runs a blocking callable in the default thread pool and
returns an awaitable. The GIL releases during blocking I/O, so the loop stays
responsive.

```python
import asyncio
from pathlib import Path

async def read_config(path: str) -> str:
    return await asyncio.to_thread(Path(path).read_text)

async def query(sync_db, sql: str) -> list[dict]:
    return await asyncio.to_thread(sync_db.execute, sql)   # blocking driver
```

For pool control (size, type), use a loop executor directly:

```python
from concurrent.futures import ThreadPoolExecutor

async def run_many(fns) -> list:
    loop = asyncio.get_running_loop()
    with ThreadPoolExecutor(max_workers=8) as pool:
        return await asyncio.gather(
            *(loop.run_in_executor(pool, fn) for fn in fns)
        )
```

### Worker thread → loop (call a coroutine from another thread)

When a non-loop thread needs to schedule a coroutine on the running loop, use
`run_coroutine_threadsafe`. It returns a `concurrent.futures.Future` (not an
asyncio Future).

```python
import asyncio

def on_external_callback(loop: asyncio.AbstractEventLoop, payload: bytes) -> None:
    # Called from a library's own thread.
    future = asyncio.run_coroutine_threadsafe(handle(payload), loop)
    future.result(timeout=5)   # optional: block this worker thread for the result
```

Capture `loop = asyncio.get_running_loop()` while on the loop and hand it to the
worker; never call `get_running_loop()` from the non-loop thread.

---

## Running Blocking and CPU Work

| Work | Mechanism | Caveat |
|---|---|---|
| Blocking I/O (sync driver, file, `requests`) | `asyncio.to_thread` / thread executor | Limited by pool size; fine because the GIL releases during I/O |
| CPU-bound, default GIL build | `loop.run_in_executor(ProcessPoolExecutor(), ...)` | Picklable args/return; process overhead |
| CPU-bound, free-threaded build (`python3.14t`) | thread executor *can* parallelize | See `free-threading.md`; still needs locks for shared state |
| CPU-bound, in-process isolation | `InterpreterPoolExecutor` | See `subinterpreters.md`; data crosses by pickle |

Wrapping CPU work in `to_thread` on the **default** build does *not* parallelize it —
the GIL serializes pure-Python CPU. Use processes or (on 3.14t) the free-threaded
build instead.

```python
import asyncio
from concurrent.futures import ProcessPoolExecutor

async def crunch(numbers: list[int]) -> int:
    loop = asyncio.get_running_loop()
    with ProcessPoolExecutor() as pool:
        return await loop.run_in_executor(pool, cpu_heavy, numbers)
```

> 3.14 note: on Unix (except macOS), `ProcessPoolExecutor` now defaults to the
> `forkserver` start method instead of `fork`. If you depend on inherited mutable
> globals, pass an explicit `mp_context`. Verify against your platform.

---

## Testing Async Code

Use `pytest` with `pytest-asyncio` (or `anyio`'s pytest plugin). Configure the mode
once in `pyproject.toml` so you do not decorate every test:

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"          # plain `async def test_*` functions just work
```

```python
import asyncio
import pytest

async def test_fetch_returns_payload() -> None:
    result = await fetch("ok")
    assert result == "data:ok"

async def test_timeout_raises() -> None:
    with pytest.raises(TimeoutError):
        async with asyncio.timeout(0.01):
            await asyncio.sleep(1)

async def test_taskgroup_cancels_siblings() -> None:
    started = asyncio.Event()

    async def slow() -> None:
        started.set()
        await asyncio.sleep(10)

    async def boom() -> None:
        await started.wait()
        raise ValueError("fail")

    with pytest.raises(ExceptionGroup):
        async with asyncio.TaskGroup() as tg:
            tg.create_task(slow())
            tg.create_task(boom())
```

Tips:

- Control time with small `asyncio.sleep` values or a fake clock; do not sleep for
  real seconds in unit tests.
- Assert cancellation behavior by checking that a sibling never completed (e.g., an
  `Event` it would have set stays unset).
- 3.14 adds asyncio introspection (`python -m asyncio ps <pid>` / `pstree`) for
  inspecting the running task tree when debugging hangs — verify availability on
  your build.

---

## Anti-Patterns

| Anti-pattern | Why it breaks | Fix |
|---|---|---|
| `time.sleep()` / blocking call in a coroutine | Freezes the whole loop | `await asyncio.sleep()` or `to_thread` |
| Unreferenced `create_task(...)` | Task may be GC'd mid-run | `TaskGroup` or a strong reference set |
| Swallowing `CancelledError` | Cancellation never propagates | Always `raise` after cleanup |
| `asyncio.run()` inside a running loop | `RuntimeError` | `await` the coroutine; refactor to async |
| Sharing an awaitable/Future across loops | "attached to a different loop" | One loop per thread; bridge with `run_coroutine_threadsafe` |
| Unbounded `gather` over N inputs | FD/socket exhaustion | Cap with a `Semaphore` |
| asyncio `Lock` used across threads | Not thread-safe | `threading.Lock` + bridging |
| Mixing sync DB driver directly in async | Hidden blocking | `to_thread`, or switch to an async driver |

## Related References

- [free-threading.md](free-threading.md) — when CPU-bound work should use threads on `python3.14t`
- [subinterpreters.md](subinterpreters.md) — isolated parallelism with `InterpreterPoolExecutor`
- [_index.md](_index.md) — navigation
