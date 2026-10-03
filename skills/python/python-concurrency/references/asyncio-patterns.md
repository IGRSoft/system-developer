# Asyncio Patterns (TaskGroup Era)

`TaskGroup` and `asyncio.timeout()` arrived in 3.11, so these patterns also run on 3.11–3.13; 3.14-only items say so. Choosing a model: [../SKILL.md](../SKILL.md).

## The Modern Baseline (what changed)

| Old pattern | Use instead | Reason |
|---|---|---|
| `asyncio.get_event_loop()` | `asyncio.run(main())`; `asyncio.get_running_loop()` inside coroutines | 3.14: raises `RuntimeError` when no loop is set |
| `loop.run_until_complete(...)` | `asyncio.run(...)` | One managed entry point; sets up and tears down the loop |
| `asyncio.gather(*tasks)` for "do these together" | `asyncio.TaskGroup` | Structured: cancels siblings on error, awaits cleanup |
| `asyncio.wait_for(coro, timeout)` | `async with asyncio.timeout(seconds):` | Composes and nests; clearer scope |
| `asyncio.ensure_future(...)` | `asyncio.create_task(...)` or `tg.create_task(...)` | `create_task` is the explicit, current API |
| `@asyncio.coroutine` / `yield from` | `async def` / `await` | Removed in 3.11 |

`asyncio.run()` is the only entry point needed from synchronous code: it creates a
loop, runs the coroutine, shuts down async generators, and closes the loop.

## Structured Concurrency with TaskGroup

`TaskGroup` is the default for "run several coroutines and wait for all of them."
The group doesn't exit until every child finishes; if any child raises, the rest
are cancelled; errors surface as an `ExceptionGroup` handled with `except*`.

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

Once the group starts shutting down, `create_task` on it raises `RuntimeError`.

## Timeouts

`asyncio.timeout()` bounds everything inside the block, composes with `TaskGroup`,
and nests.

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

## Cancellation and Shielding

Cancellation is delivered as a `CancelledError` raised at the next suspension
point. Treat it as control flow, not an error.

### Re-raise CancelledError

```python
async def worker() -> None:
    try:
        while True:
            await do_unit_of_work()
    except asyncio.CancelledError:
        await flush_buffers()      # cleanup is fine
        raise                      # re-raise so cancellation propagates
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

## Tasks: References, Fire-and-Forget, Backpressure

### Keep a reference to every task

The loop holds tasks only weakly; an unreferenced task can be garbage-collected
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

## gather vs TaskGroup

| Need | Use | Notes |
|---|---|---|
| Run N, fail fast, cancel the rest | `TaskGroup` | Default choice |
| Run N, collect every result *and* every error | `gather(*aws, return_exceptions=True)` | Returns a list mixing results and exception objects |
| Run N where one failure should NOT cancel siblings | `gather(..., return_exceptions=True)` | Then inspect each item |

`gather` without `return_exceptions=True` raises the first error immediately, but
the other awaitables keep running unattended — they are not cancelled.

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

`asyncio.as_completed()` yields results in completion order, to process each as
soon as it lands:

```python
for next_done in asyncio.as_completed(aws):
    handle(await next_done)
```

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

## Queues and Producer/Consumer

A bounded `asyncio.Queue` gives backpressure: producers wait when consumers fall behind.

```python
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

### Stopping consumers

Alternatives to cancelling: a sentinel (`None`) per consumer, or (3.13+)
`q.shutdown()`, after which `get()` raises `QueueShutDown` once the queue drains.

## Synchronization Primitives

asyncio's `Lock`, `Semaphore`, `Event`, and `Condition` coordinate coroutines on
one loop; they are not thread-safe. Across threads, use `threading`/`queue`
primitives plus the bridging functions below.

```python
class Cache:
    def __init__(self) -> None:
        self._lock = asyncio.Lock()
        self._data: dict[str, bytes] = {}

    async def get_or_load(self, key: str) -> bytes:
        async with self._lock:                  # serializes all loads; per-key locks scale better
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

## Bridging Sync and Async

### Sync → async (start a loop)

Call `asyncio.run()` only from genuinely synchronous code (a CLI entry point).
Inside a running loop it raises `RuntimeError: asyncio.run() cannot be called from a
running event loop`; sync code called by a loop that needs async work belongs in an
`async` function instead.

### Async → sync (call blocking code without freezing the loop)

`asyncio.to_thread()` runs a blocking callable in the default thread pool and
returns an awaitable; the loop stays responsive.

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

From a non-loop thread, `run_coroutine_threadsafe` schedules a coroutine on the
loop and returns a `concurrent.futures.Future`.

```python
import asyncio

def on_external_callback(loop: asyncio.AbstractEventLoop, payload: bytes) -> None:
    # Called from a library's own thread.
    future = asyncio.run_coroutine_threadsafe(handle(payload), loop)
    future.result(timeout=5)   # optional: block this worker thread for the result
```

Capture `loop = asyncio.get_running_loop()` on the loop and hand it to the worker;
`get_running_loop()` fails in a non-loop thread.

## Running Blocking and CPU Work

| Work | Mechanism | Caveat |
|---|---|---|
| Blocking I/O (sync driver, file, `requests`) | `asyncio.to_thread` / thread executor | Limited by pool size |
| CPU-bound, default GIL build | `loop.run_in_executor(ProcessPoolExecutor(), ...)` | Picklable args/return; process overhead |
| CPU-bound, `python3.14t` | thread executor | Parallel; shared state needs locks ([free-threading.md](free-threading.md)) |
| CPU-bound, in-process isolation | `InterpreterPoolExecutor` | Data crosses by pickle ([subinterpreters.md](subinterpreters.md)) |

`to_thread` does not parallelize pure-Python CPU work on the default build.

### Process pools

```python
from concurrent.futures import ProcessPoolExecutor

async def crunch(numbers: list[int]) -> int:
    loop = asyncio.get_running_loop()
    with ProcessPoolExecutor() as pool:
        return await loop.run_in_executor(pool, cpu_heavy, numbers)
```

3.14: on Unix other than macOS, the default start method is now `forkserver`, not
`fork`. Code that depends on inherited globals needs an explicit `mp_context`.

## Testing Async Code

Use `pytest` with `pytest-asyncio` (or `anyio`'s pytest plugin), mode set once:

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"          # plain `async def test_*` functions just work
```

```python
import asyncio
import pytest

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

### Tips

- Use small `asyncio.sleep` values or a fake clock, not real seconds.
- Assert cancellation by checking a sibling never completed (an `Event` it would set stays unset).
- 3.14: `python -m asyncio ps <pid>` / `pstree <pid>` dump a running process's task tree when debugging hangs.

## Related References

- [free-threading.md](free-threading.md) — when CPU-bound work should use threads on `python3.14t`
- [subinterpreters.md](subinterpreters.md) — isolated parallelism with `InterpreterPoolExecutor`
- [_index.md](_index.md) — navigation
