# Free-Threaded Python (3.14t)

PEP 779 made the free-threaded build officially supported in 3.14 (experimental in
3.13). Choosing a model: [../SKILL.md](../SKILL.md).

## What "Free-Threaded" Means

The free-threaded build removes the GIL, so threads running pure-Python CPU work run
in parallel across cores. The `threading` API is unchanged. The GIL incidentally
serialized many operations, so removing it exposes races that were always latent.

| | Default build (GIL) | Free-threaded build (`python3.14t`) |
|---|---|---|
| CPU-bound threads | Serialized (one at a time) | Parallel across cores |
| I/O-bound threads | Overlap (GIL releases on I/O) | Overlap |
| `sys._is_gil_enabled()` | `True` | `False` |
| Data-race risk | Low (GIL hides many) | Higher — locks required |
| Single-thread speed | Baseline | ~5–10% slower in 3.14 (~40% in 3.13) |

## The Build Is Separate

Free-threading is a distinct CPython build, not a flag on a normal interpreter. The
binary is `python3.14t`; it coexists with `python3.14`. Its wheels carry the
`cp314t` ABI tag; ordinary `cp314` wheels do not apply. Create the virtual
environment against that interpreter.

## Installing 3.14t (uv and others)

### With uv

```bash
uv python install 3.14t        # or: cpython-3.14+freethreaded
uv python pin 3.14t            # writes .python-version for collaborators
uv sync                        # project venv on the pinned interpreter
uv run --python 3.14t python -c "import sys; print(sys._is_gil_enabled())"
```

### With pyenv / python.org

- The python.org macOS and Windows installers offer free-threaded binaries as an option.
- `pyenv install 3.14t`.

### Building from source

```bash
./configure --disable-gil --enable-optimizations   # produces python3.14t
make -j
```

## Verifying You Are Free-Threaded

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

### Build vs runtime

`Py_GIL_DISABLED` says the build can run without the GIL; `sys._is_gil_enabled()`
says whether it is off right now. Importing an extension that hasn't declared
free-threading support re-enables the GIL at runtime, so check the runtime function
before assuming parallelism.

Force the GIL on/off for testing on a free-threaded build:

```bash
PYTHON_GIL=0 python3.14t script.py    # keep GIL off even if an extension asks for it
PYTHON_GIL=1 python3.14t script.py    # force GIL on
python3.14t -X gil=0 script.py        # equivalent CLI flag
```

## Performance Characteristics

Orientation only; measure your workload.

- Single-threaded: about 5–10% slower than the GIL build in 3.14 (the specializing
  interpreter is now enabled in free-threaded mode; it was ~40% in 3.13).
- Multi-threaded CPU: near-linear for partitioned, lock-light work; sub-linear once
  threads contend on shared locks or data.
- Memory: somewhat higher than the GIL build.
- I/O-bound: little change; those threads already overlapped under the GIL.

Free-threading wins when CPU work parallelizes enough to beat the single-thread tax
and lock contention stays low; a hot path behind one big lock gains little.

## Thread-Safety Without the GIL

The GIL made many coarse operations look atomic by accident. Without it, add the
synchronization that was always formally required.

### What is (and isn't) safe

- Individual operations on built-in `dict`/`list`/`set` are internally thread-safe
  (no interpreter crash), but compound operations are not atomic: two threads
  running `d[k] += 1` can lose an update.
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

The most robust pattern shares no mutable state; `queue.Queue` hands work and results
between threads:

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
- Not asyncio's `Lock`/`Queue`: they coordinate coroutines on one loop and aren't thread-safe.

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

This scales on `python3.14t` and shows no speedup on the default build: same source,
different interpreter. Pure-Python threads parallelize without a C extension
releasing the GIL.

## Ecosystem and Extension Compatibility

The highest-risk part of adoption: one incompatible C extension switches the GIL
back on for the whole process.

### How an extension declares support

A C extension opts in via a module slot in its multi-phase init:

```c
static PyModuleDef_Slot module_slots[] = {
    {Py_mod_exec, module_exec},
    {Py_mod_gil, Py_MOD_GIL_NOT_USED},   /* "I am safe without the GIL" */
    {0, NULL},
};
```

Without `Py_MOD_GIL_NOT_USED`, importing the module re-enables the GIL and emits a
warning; `Py_MOD_GIL_USED` requests the GIL explicitly. On Windows in 3.14 the build
backend must define `Py_GIL_DISABLED` for free-threaded extension builds; the
compiler no longer infers it.

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
on. Upgrade to a release with a `cp314t` wheel that declares support, replace it, or
keep the GIL on deliberately (`PYTHON_GIL=1`), which keeps correctness but loses the
parallelism.

### Pure-Python packages

Pure-Python packages import fine, but their thread-safety assumptions may not hold
once threads run in parallel. Audit global mutable state in libraries called
concurrently.

### Ecosystem coverage

Standard-library C extensions are all compatible. Third-party `cp314t` wheel coverage
is uneven (tracker: https://py-free-threading.github.io/tracking/), so check the whole
dependency tree before pinning `3.14t` for production; one missing wheel builds from
sdist or re-enables the GIL. Cython, pybind11, nanobind, and PyO3 support it; check
the release that added support.

## When to Stay on the GIL Build

Choose the **default** build when:

| Situation | Reason |
|---|---|
| Workload is I/O-bound | asyncio/threads already overlap; free-threading adds tax, not throughput |
| A required C extension lacks `cp314t` support | It would re-enable the GIL anyway |
| Single-threaded latency is critical | Avoid the ~5–10% per-op overhead |
| Code relies on GIL-induced atomicity and has not been audited | Races would surface; audit first |
| Production stability matters more than the parallelism win | Ecosystem support is still maturing |

Rollout: test on both `python3.14` and `python3.14t` in CI, keep shared-state access
locked, and switch production only once dependencies and tests are green on `3.14t`.

## Diagnostics

| Symptom | Cause | Fix |
|---|---|---|
| `sys._is_gil_enabled()` is `True` on `python3.14t` | An imported extension re-enabled the GIL | Find it (import-and-check); upgrade/replace, or accept `PYTHON_GIL=1` |
| Segfault only on the free-threaded build | C extension unsafe despite declaring support, or your own unsafe C | Rerun with `PYTHON_GIL=1` to confirm; isolate the module; report upstream |
| Deadlock | Lock-ordering inversion or non-reentrant re-acquire | Global lock order; `RLock` if re-entry is intended |
| Slower than the GIL build | Workload is I/O-bound, single-threaded, or lock-contended | Re-check the decision table |
| Install builds from sdist or fails | No `cp314t` wheel for that release | Upgrade to a release with `cp314t` wheels, or provide a build toolchain |

## Related References

- [asyncio-patterns.md](asyncio-patterns.md) — for I/O-bound concurrency instead
- [subinterpreters.md](subinterpreters.md) — multi-core without removing the GIL, via isolation
- [_index.md](_index.md) — navigation
