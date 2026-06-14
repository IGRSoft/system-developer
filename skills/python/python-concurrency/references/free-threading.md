# Free-Threaded Python (3.14t)

Use this when:

- You have **CPU-bound** Python and want real multi-core parallelism with threads.
- You are evaluating whether to adopt the free-threaded build (`python3.14t`).
- You need to verify that your dependencies and C extensions work without the GIL.
- You are debugging crashes or corruption that appear only on the free-threaded build.

Skip if:

- Your bottleneck is I/O → use asyncio or threads on the normal build (`asyncio-patterns.md`).
- You need strong isolation between components → see `subinterpreters.md`.
- You only need to know *which* model to pick → start at [../SKILL.md](../SKILL.md).

Jump to:

- What "Free-Threaded" Means
- The Build Is Separate
- Installing 3.14t (uv and others)
- Verifying You Are Free-Threaded
- Performance Characteristics (hedged)
- Thread-Safety Without the GIL
- Patterns: Parallel CPU Work
- Ecosystem and Extension Compatibility
- When to Stay on the GIL Build
- Diagnostics

> Baseline: **CPython 3.14**, free-threaded build (`python3.14t`). PEP 779 made the
> free-threaded build **officially supported** in 3.14 (it was experimental in 3.13).
> Performance and ecosystem support are still evolving — treat specific numbers as
> "verify against your toolchain," not guarantees.

---

## What "Free-Threaded" Means

The free-threaded build removes the **Global Interpreter Lock (GIL)**, the mutex that
normally lets only one thread execute Python bytecode at a time. Without it,
`threading.Thread`s running pure-Python CPU work can run truly in parallel across
cores — the thing the GIL has prevented for the entire history of CPython.

What it does **not** change:

- The `threading` API is identical. You write the same `Thread`/`Lock`/`Queue` code.
- **Thread safety is now your job.** The GIL incidentally serialized many operations;
  removing it exposes races that were always latent. See "Thread-Safety Without the GIL."
- Pure single-threaded code runs slightly slower (overhead of fine-grained locking).

| | Default build (GIL) | Free-threaded build (`python3.14t`) |
|---|---|---|
| CPU-bound threads | Serialized (one at a time) | Parallel across cores |
| I/O-bound threads | Overlap (GIL releases on I/O) | Overlap |
| `sys._is_gil_enabled()` | `True` | `False` |
| Data-race risk | Low (GIL hides many) | Higher — locks required |
| Single-thread speed | Baseline | ~5–10% slower in 3.14 (down from ~40% in 3.13; verify) |

---

## The Build Is Separate

Free-threading is **not** a flag you flip on a normal interpreter. It is a distinct
build of CPython, conventionally suffixed `t`:

- Interpreter binary: `python3.14t`
- It can coexist with the normal `python3.14` on the same machine.
- Wheels for it carry the `cp314t` ABI tag; ordinary `cp314` wheels do not apply.

You select it by installing and invoking that specific interpreter, then building
your virtual environment against it.

---

## Installing 3.14t (uv and others)

### With uv (recommended)

`uv` can fetch and pin the free-threaded build directly. The free-threaded
interpreter is requested with the `+freethreaded` variant suffix:

```bash
# Install the free-threaded interpreter
uv python install 3.14t

# Or, equivalently, the explicit variant form
uv python install cpython-3.14+freethreaded

# Create a project venv on it
uv venv --python 3.14t
uv sync

# One-off run on the free-threaded interpreter
uv run --python 3.14t python -c "import sys; print(sys._is_gil_enabled())"
```

Pin it for the project so collaborators get the same interpreter:

```toml
# pyproject.toml
[project]
requires-python = ">=3.14"

# .python-version (uv reads this)
# 3.14t
```

> The exact spelling of uv's variant flag has shifted across uv releases
> (`3.14t` vs `cpython-3.14+freethreaded`). Run `uv python list` to see what your
> uv accepts, and verify against your toolchain.

### With pyenv / python.org

- The official python.org macOS and Windows installers offer a "free-threaded"
  option as a separate install.
- `pyenv install 3.14t` installs the free-threaded build where the plugin's
  definitions support it (verify your pyenv version).

### Building from source

```bash
./configure --disable-gil --enable-optimizations
make -j
# Produces a python3.14t binary
```

`--disable-gil` is the configure switch that produces the free-threaded build.

---

## Verifying You Are Free-Threaded

Three independent checks — use more than one when in doubt:

```python
import sys
import sysconfig

# 1. Runtime: is the GIL currently active?
print(sys._is_gil_enabled())            # False on a free-threaded run

# 2. Build-time: was this interpreter compiled GIL-disabled?
print(sysconfig.get_config_var("Py_GIL_DISABLED"))   # 1 on the free-threaded build

# 3. Version banner
print(sys.version)                      # mentions "free-threading build"
```

From the shell:

```bash
python3.14t -VV
# CPython ... free-threading build
python3.14t -c "import sys; print(sys._is_gil_enabled())"
```

**Why two questions?** `Py_GIL_DISABLED` tells you the build *supports* running
without the GIL. `sys._is_gil_enabled()` tells you whether the GIL is *actually off
right now* — because importing a C extension that has not declared free-threading
support can **re-enable** the GIL at runtime (see compatibility below). A program can
be on the free-threaded build (`Py_GIL_DISABLED == 1`) yet have the GIL switched back
on (`sys._is_gil_enabled() == True`). Always check the runtime function before
assuming parallelism.

You can force the GIL on/off for testing on a free-threaded build:

```bash
PYTHON_GIL=0 python3.14t script.py    # keep GIL off even if an extension asks for it
PYTHON_GIL=1 python3.14t script.py    # force GIL on
python3.14t -X gil=0 script.py        # equivalent CLI flag
```

---

## Performance Characteristics (hedged)

Treat these as orientation, not promises — measure your own workload.

- **Single-threaded overhead:** roughly **5–10%** slower than the GIL build in 3.14
  — down from **~40%** in 3.13, because the specializing adaptive interpreter is now
  enabled in free-threaded mode. Platform- and compiler-dependent — verify.
- **Multi-threaded CPU scaling:** near-linear for cleanly partitioned, lock-light
  workloads; sub-linear once threads contend on shared locks or shared data.
- **Memory:** comparable to the GIL build for typical workloads.
- **I/O-bound:** little change — those threads already overlapped under the GIL.

The break-even decision: free-threading wins when your CPU-bound work parallelizes
across cores enough to beat the ~5–10% single-thread tax *and* you can keep lock
contention low. If your hot path is mostly serialized behind one big lock, you gain
little.

```python
# Speedup only materializes if the work is genuinely parallel AND low-contention.
from concurrent.futures import ThreadPoolExecutor

def cpu_task(chunk: list[int]) -> int:
    return sum(x * x for x in chunk)   # pure-Python CPU work

def run(chunks: list[list[int]]) -> int:
    with ThreadPoolExecutor() as pool:        # parallel on python3.14t
        return sum(pool.map(cpu_task, chunks))
```

On the **default** build the same code is serialized by the GIL and shows no speedup —
that is exactly the difference free-threading makes.

---

## Thread-Safety Without the GIL

**"GIL removal does not remove races."** The GIL made many coarse operations appear
atomic by accident. Without it, you must add the synchronization that was always
formally required.

### What is (and isn't) safe

- Individual operations on built-in `dict`/`list`/`set` are made internally
  thread-safe by the free-threaded build (no interpreter crash), but
  **compound** operations are still not atomic. `d[k] += 1` is read-modify-write —
  two threads can interleave and lose an update.
- Your own multi-step invariants (check-then-act, read-modify-write across several
  objects) need explicit locking on *any* build; the bug just shows up far more
  reliably without the GIL.

```python
import threading

class Counter:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._n = 0

    def increment(self) -> None:
        with self._lock:          # required: += is read-modify-write
            self._n += 1

    @property
    def value(self) -> int:
        with self._lock:
            return self._n
```

### Prefer message passing to shared state

The most robust pattern is to not share mutable state at all. Use `queue.Queue`
(thread-safe) to hand work and results between threads:

```python
import queue
import threading

def worker(jobs: queue.Queue, results: queue.Queue) -> None:
    while (job := jobs.get()) is not None:
        results.put(process(job))
        jobs.task_done()

jobs: queue.Queue = queue.Queue()
results: queue.Queue = queue.Queue()
threads = [threading.Thread(target=worker, args=(jobs, results)) for _ in range(8)]
for t in threads:
    t.start()
```

### Other tools

- `threading.Lock` / `RLock` for mutual exclusion.
- `threading.local()` for per-thread state (no sharing, no locking).
- Immutable data: share freely; never needs a lock.
- `concurrent.futures.ThreadPoolExecutor` to avoid manual thread lifecycle.

Do **not** reach for asyncio's `Lock`/`Queue` here — those coordinate coroutines on
one loop and are not thread-safe.

---

## Patterns: Parallel CPU Work

### Partition, compute, combine

```python
from concurrent.futures import ThreadPoolExecutor

def parallel_sum_of_squares(data: list[int], workers: int = 8) -> int:
    size = max(1, len(data) // workers)
    chunks = [data[i:i + size] for i in range(0, len(data), size)]
    with ThreadPoolExecutor(max_workers=workers) as pool:
        partials = pool.map(lambda c: sum(x * x for x in c), chunks)
    return sum(partials)
```

This scales on `python3.14t` and is GIL-bound (no speedup) on the default build —
the same source, different interpreter.

### Releasing the GIL is no longer the trick

On the GIL build, NumPy-style speedups came from C code releasing the GIL. On the
free-threaded build, *pure-Python* threads also parallelize, so you do not need a C
extension to benefit. (You still benefit from vectorized C libraries on either build.)

---

## Ecosystem and Extension Compatibility

This is the highest-risk part of adopting free-threading. A single non-compatible C
extension can switch the GIL back on for the whole process.

### How an extension declares support

A C extension opts in via a module slot in its multi-phase init:

```c
static PyModuleDef_Slot module_slots[] = {
    {Py_mod_exec, module_exec},
    {Py_mod_gil, Py_MOD_GIL_NOT_USED},   /* "I am safe without the GIL" */
    {0, NULL},
};
```

If a module does **not** include `Py_mod_gil = Py_MOD_GIL_NOT_USED`, importing it on a
free-threaded interpreter re-enables the GIL (and, by default, emits a warning). The
opposite value, `Py_MOD_GIL_USED`, explicitly requests the GIL.

> On Windows in 3.14, the build backend must define the `Py_GIL_DISABLED`
> preprocessor variable when compiling extensions for the free-threaded build — it is
> no longer inferred by the compiler. Verify with your build backend.

### Checking your dependencies

```bash
# Which interpreter / GIL state am I on?
python3.14t -c "import sys; print(sys._is_gil_enabled())"

# Import a suspect module and re-check: did it flip the GIL back on?
python3.14t -c "import sys, numpy; print('gil enabled after import:', sys._is_gil_enabled())"

# Surface the re-enable warning explicitly
PYTHONWARNINGS=always python3.14t -c "import some_extension"
```

If `sys._is_gil_enabled()` becomes `True` after an import, that module forced the GIL
on. Strategies:

- Upgrade the dependency to a `cp314t` wheel that declares support.
- Replace it with a pure-Python or already-compatible alternative.
- Keep the GIL on deliberately (`PYTHON_GIL=1`) if you cannot avoid the extension —
  you then lose free-threading's benefit but keep correctness.

### Pure-Python packages

Pure-Python packages generally "just work" — but their *thread-safety assumptions*
may not hold once threads run in parallel. Audit any global mutable state in
libraries you call concurrently.

### Adoption status (2026)

Free-threaded wheels are no longer niche: roughly **~51% of the top native-wheel
packages ship `cp314t` wheels** (about 183 of the ~360 most-downloaded native
packages), and **NumPy 2.3.4 ships `cp314t` wheels**. That makes a free-threaded
production build realistic for many stacks — but coverage is uneven, so **verify
your dependency tree before pinning `3.14t` for production** (one missing `cp314t`
wheel either builds from sdist or re-enables the GIL for the whole process).

### Tooling status

Major binding tools (Cython, pybind11, nanobind, PyO3) have free-threading support in
progress or shipped; check each project's current release notes rather than assuming.
Standard-library C extensions are all compatible.

---

## When to Stay on the GIL Build

Choose the **default** build when:

| Situation | Reason |
|---|---|
| Workload is I/O-bound | asyncio/threads already overlap; free-threading adds tax, not throughput |
| A required C extension lacks `cp314t` support | It would re-enable the GIL anyway |
| Single-threaded latency is critical | Avoid the ~5–10% per-op overhead |
| Code relies on GIL-induced atomicity and has not been audited | Races would surface; audit first |
| Production stability matters more than the parallelism win | Ecosystem support is still maturing — verify before committing |

A pragmatic rollout: develop and test on **both** builds in CI (`python3.14` and
`python3.14t`), keep all shared-state access locked, and switch the production
interpreter only once your dependency tree and tests are green on `3.14t`.

---

## Diagnostics

| Symptom | Cause | Fix |
|---|---|---|
| `sys._is_gil_enabled()` is `True` on `python3.14t` | An imported extension re-enabled the GIL | Find it (import-and-check loop); upgrade/replace, or accept `PYTHON_GIL=1` |
| Crash/segfault only on the free-threaded build | C extension not actually free-thread-safe despite declaring support, or your own unsafe C | Report upstream; isolate the module; run with GIL forced on to confirm |
| Wrong results / lost updates under threads | Unsynchronized read-modify-write (race) | Add `threading.Lock`; prefer `queue.Queue` message passing |
| Deadlock | Lock-ordering inversion or non-reentrant re-acquire | Establish a global lock order; use `RLock` if re-entry is intended; never hold a lock across a blocking call you also need elsewhere |
| Slower than the GIL build | Workload is I/O-bound, single-threaded, or lock-contended | Re-check the decision table — free-threading may be the wrong tool here |
| `pip install` picks the wrong wheel | Building against `cp314` instead of `cp314t` | Run under `python3.14t`; ensure the package ships `cp314t` wheels or builds from source |

## Related References

- [asyncio-patterns.md](asyncio-patterns.md) — for I/O-bound concurrency instead
- [subinterpreters.md](subinterpreters.md) — multi-core without removing the GIL, via isolation
- [_index.md](_index.md) — navigation
