# Profiling Tools Reference

Use this when:

- A program is too slow or uses too much memory and you need to find *where*.
- You want a reproducible before/after measurement of an optimization.
- You are choosing between perf, py-spy, cProfile, a heap profiler, or hyperfine.

Skip if:

- The program is *wrong*, not slow — that is [sanitizers.md](sanitizers.md) /
  [gdb-lldb.md](gdb-lldb.md).
- You only need the tool-from-symptom decision. See [diagnostics SKILL.md](../SKILL.md).

Jump to:

- The Measure -> Fix -> Re-measure Loop
- Tool Selection
- perf (Linux CPU)
- Flamegraphs
- macOS CPU Profiling (sample)
- py-spy (Python, sampling)
- cProfile (Python, deterministic)
- py-spy vs cProfile Decision
- Python Optimization Patterns
- Heap Profiling (massif, heaptrack, tracemalloc)
- hyperfine (wall-clock benchmarking)
- Google Benchmark / pytest-benchmark (microbenchmarks)
- Diagnostic Table

---

## The Measure -> Fix -> Re-measure Loop

Optimization without measurement is guessing. The loop, every time:

1. **Reproduce** a representative, repeatable workload (a benchmark or fixed input).
2. **Measure** to find the hot path — never optimize a function you only *suspect*.
3. **Record a baseline** number (commit the hyperfine/benchmark JSON).
4. **Change one thing.**
5. **Re-measure** against the baseline. Keep the win or revert.
6. **Stop** when you hit the target or the next hot path is in someone else's code.

Rules that save hours:

- Profile a **RelWithDebInfo** build (`-O2 -g`), never `-O0` (wrong hot paths)
  and never a stripped `Release` (no symbols).
- Most time hides in a few percent of code — fix the top frame, then re-profile;
  the profile changes shape after each fix.
- Algorithmic complexity beats micro-optimization. An O(n²) -> O(n log n) change
  outweighs any constant-factor tweak.

---

## Tool Selection

| Goal | Tool | Platform |
|------|------|----------|
| Find CPU hot path in C/C++ | **perf** (`record`/`report`) | Linux |
| Same on macOS | **`sample`** / `xctrace` | macOS |
| Find CPU hot path in Python (low overhead, no edits) | **py-spy** | Linux/macOS (native frames Linux) |
| Deterministic per-call counts in Python | **cProfile** | all |
| Where memory is allocated (C/C++) | **massif** / **heaptrack** | Linux |
| Where memory is allocated (Python) | **tracemalloc** | all |
| Compare whole-command runtime A vs B | **hyperfine** | all |
| Microbenchmark a single C++ function | **Google Benchmark** | all |
| Microbenchmark Python code | **pytest-benchmark** / `timeit` | all |

---

## perf (Linux CPU)

The default CPU profiler on Linux: low-overhead sampling, hardware counters.

```bash
# Record a profile with call graphs (frame pointers must be present)
perf record -g -- ./prog --workload big
# or sample a running process for 10s:
perf record -g -p <pid> -- sleep 10

# Read it: an interactive, sorted-by-time tree
perf report
perf report --stdio                 # non-interactive dump

# Annotate the hottest function down to instructions/source lines
perf annotate process_node

# A live top-style view
perf top
```

Build with `-O2 -g -fno-omit-frame-pointer` so call graphs are accurate. If
frame pointers are unavailable, use DWARF unwinding (heavier):

```bash
perf record -g --call-graph dwarf -- ./prog
```

perf needs permission to read CPU counters:

```bash
sysctl kernel.perf_event_paranoid     # lower (privileged) if "Permission denied"
```

`perf stat -- ./prog` gives a quick counter summary (cycles, instructions,
cache misses, branch mispredicts) — good for spotting cache-bound vs CPU-bound
before you dig in.

---

## Flamegraphs

A flamegraph turns a profile into one picture: width = time, stacks read bottom
(entry) to top (leaf). The widest top-of-stack box is your hot path.

```bash
# From perf (Brendan Gregg's FlameGraph scripts)
perf record -g -- ./prog
perf script | stackcollapse-perf.pl | flamegraph.pl > flame.svg

# perf can also emit a flamegraph directly on recent versions:
perf script report flamegraph        # -> flamegraph.html  (verify against your perf)
```

py-spy produces SVG flamegraphs natively — see below.

---

## macOS CPU Profiling (sample)

perf is Linux-only. On macOS use the bundled `sample`, or Instruments via
`xctrace` for a GUI timeline.

```bash
# Sample a running process for 5 seconds at 1ms intervals -> text call tree
sample <pid> 5 1 -file sample.txt

# Sample by name
sample prog 5

# Record a Time Profiler trace for Instruments (deeper, GUI)
xctrace record --template 'Time Profiler' --launch -- ./prog
```

`sample` is zero-setup and good for "which function is eating CPU right now". For
allocation/leak timelines on macOS, `leaks <pid>` and `xctrace` templates apply.

---

## py-spy (Python, sampling)

py-spy samples a Python process from *outside* — no code changes, no imports,
trivial overhead, and it works on an already-running process (including
production). It reads frames via the process memory, so it cannot crash the
target.

```bash
# Live top-style view of the busiest Python functions
py-spy top --pid 12345

# Record a flamegraph for a fixed run
py-spy record -o profile.svg -- python script.py

# Include native (C/C++/Cython) frames alongside Python
# Native support: Linux (and Windows); not on macOS — verify against your build.
py-spy record --native -o profile.svg -- python script.py

# One-shot stack dump of a hung process (great for "why is it stuck?")
py-spy dump --pid 12345
```

For `--native` to resolve C/Cython frames, compile the extension with symbols
(`-g`); for Cython, keep the generated `.c`/`.cpp` so line numbers map back to
`.pyx`. py-spy is the right default for **production**, **long-running**, and
**"don't touch the code"** Python profiling.

---

## cProfile (Python, deterministic)

cProfile counts *every* call deterministically — exact call counts and
cumulative/total time per function. Higher overhead than py-spy, but precise.

```bash
# Profile a whole script, save the stats
python -m cProfile -o output.prof script.py

# Inspect interactively
python -m pstats output.prof
# in pstats:  sort cumtime   then   stats 10
```

In code, around a hot region:

```python
import cProfile, pstats
from pstats import SortKey

profiler = cProfile.Profile()
profiler.enable()
main()
profiler.disable()

stats = pstats.Stats(profiler)
stats.sort_stats(SortKey.CUMULATIVE)
stats.print_stats(10)        # top 10 by cumulative time
stats.dump_stats("main.prof")
```

For line-by-line granularity inside one function, `line_profiler`
(`kernprof -l -v script.py` with `@profile`) attributes time to source lines.

Visualize a `.prof` with `snakeviz output.prof` (icicle graph in the browser).

---

## py-spy vs cProfile Decision

| Use | Reach for |
|-----|-----------|
| A running / production process | **py-spy** (`top` / `dump` / `record`) |
| Long job where overhead matters | **py-spy** (sampling, ~negligible) |
| You cannot edit or restart the code | **py-spy** |
| Need C/Cython frames too | **py-spy --native** (Linux) |
| Exact per-function call counts | **cProfile** |
| Deterministic, reproducible numbers in a test | **cProfile** |
| Line-by-line time in one function | **line_profiler** |

Rule of thumb: **py-spy to find *which* function**, then **cProfile/line_profiler
to understand *why* that function is slow** if sampling isn't precise enough.

---

## Python Optimization Patterns

Once profiling names the hot function, these are the highest-yield fixes (each
verified with `timeit`/`pytest-benchmark` before keeping):

```python
# Comprehension over append loop (and map for pure transforms)
squares = [i * i for i in range(n)]          # not: append in a for-loop

# Generator over list when you only iterate once (constant memory)
total = sum(i * i for i in range(n))         # not: sum([... ]) for a one-pass

# "".join over += concatenation (avoids O(n^2) string rebuilds)
text = "".join(str(x) for x in parts)        # not: result += str(x)

# Dict/set membership is O(1); list membership is O(n)
seen = set(ids); hit = target in seen        # not: target in id_list

# Hoist attribute/global lookups out of hot loops into locals
local_fn = obj.method
for x in data: local_fn(x)                    # avoids repeated attribute lookup

# functools.lru_cache for pure, repeatedly-called functions
from functools import lru_cache
@lru_cache(maxsize=None)
def fib(n): return n if n < 2 else fib(n-1) + fib(n-2)
```

Bigger levers when these aren't enough: vectorize numeric work with NumPy; move
the inner loop into a C/C++ extension ([ffi-interop](../../ffi-interop/SKILL.md));
for CPU-bound parallelism on Python 3.14, free-threading or subinterpreters
([python-concurrency](../../../python/python-concurrency/SKILL.md)). Always
re-measure — a "faster" idiom that doesn't move the profile is wasted churn.

---

## Heap Profiling (massif, heaptrack, tracemalloc)

When the problem is memory growth, not CPU.

### C/C++

```bash
# valgrind massif: heap usage over time, with allocation backtraces
valgrind --tool=massif ./prog
ms_print massif.out.<pid>        # text report: peak, snapshots, top allocators

# heaptrack: lower overhead, richer GUI/flamegraph; Linux
heaptrack ./prog
heaptrack_print heaptrack.prog.<pid>.gz     # or open in heaptrack_gui
```

massif answers "what was allocated at peak and who allocated it"; heaptrack adds
allocation *counts*, leaks, and temporary-allocation churn with flamegraphs.
Both need `-g` for readable backtraces. (massif is Linux-first; *verify
valgrind availability on your macOS toolchain*.)

### Python

```python
import tracemalloc
tracemalloc.start()
# ... run the workload ...
snapshot = tracemalloc.take_snapshot()
for stat in snapshot.statistics("lineno")[:10]:
    print(stat)                  # top 10 allocation sites by size
```

`tracemalloc` attributes live memory to the source line that allocated it — the
go-to for "what is growing?" in a Python service. Take two snapshots and
`compare_to` to find growth between phases.

---

## hyperfine (wall-clock benchmarking)

For "did my change actually make the *whole command* faster?" hyperfine runs each
command many times, warms caches, and reports mean ± σ with outlier detection.

```bash
# A vs B, with warmup runs excluded
hyperfine --warmup 3 './prog --old' './prog --new'

# Save a machine-readable baseline to commit / diff later
hyperfine --warmup 3 --export-json bench.json './prog --new'

# Parameter sweep
hyperfine -P threads 1 8 './prog --threads {threads}'

# Reset state between runs (e.g. drop a cache file)
hyperfine --prepare 'rm -f cache.bin' './prog'
```

hyperfine is the canonical baseline tool for `--bench`-style workflows: record
JSON before a change, record after, and the delta is your evidence. It measures
*end to end* (process startup included) — for in-process function timing use a
microbenchmark library instead.

---

## Google Benchmark / pytest-benchmark (microbenchmarks)

For timing a single function in isolation, with statistical rigor.

### C++ — Google Benchmark

```cpp
#include <benchmark/benchmark.h>

static void BM_Parse(benchmark::State& state) {
    for (auto _ : state) {
        auto r = parse(kInput);
        benchmark::DoNotOptimize(r);   // stop the optimizer deleting the work
    }
}
BENCHMARK(BM_Parse);
BENCHMARK_MAIN();
```

Build at `-O2`; `DoNotOptimize`/`ClobberMemory` prevent the optimizer from
eliding the code under test. Run with `--benchmark_repetitions=10
--benchmark_report_aggregates_only=true` for mean/median/stddev.

### Python — pytest-benchmark

```python
def test_parse_perf(benchmark):
    result = benchmark(parse, SAMPLE_INPUT)
    assert result.ok
```

`pytest-benchmark` reports min/mean/median/stddev and can fail CI on regression
(`--benchmark-compare` against a saved baseline). For ad-hoc checks, `timeit`:

```bash
python -m timeit -s 'from mod import f' 'f(data)'
```

---

## Diagnostic Table

| Symptom | Cause | Action | Reference |
|---------|-------|--------|-----------|
| perf shows mostly `[unknown]` / no call graph | no frame pointers / stripped | `-O2 -g -fno-omit-frame-pointer`, or `--call-graph dwarf` | this file > perf |
| `perf: Permission denied` | `perf_event_paranoid` too high | lower it (privileged) or run as owner | this file > perf |
| Profile blames trivial functions | profiled an `-O0` build | profile RelWithDebInfo (`-O2 -g`) | this file > The Loop |
| py-spy: "permission denied" attaching | OS attach restriction | run as the process owner / with privilege | this file > py-spy |
| py-spy `--native` shows no C frames | macOS, or extension lacks symbols | use Linux for native; build ext with `-g` | this file > py-spy |
| cProfile run is far slower than reality | deterministic-profiler overhead | switch to py-spy sampling for realistic timing | this file > py-spy vs cProfile |
| memory grows but no leak reported | retained references / caches, not a leak | `tracemalloc` (Py) / `massif`/`heaptrack` (C/C++) | this file > Heap Profiling |
| benchmark numbers jump around | cold caches / no warmup / noisy machine | `hyperfine --warmup`; pin CPU; repetitions | this file > hyperfine |
| Google Benchmark reports ~0 ns | optimizer deleted the work | `DoNotOptimize` / `ClobberMemory` | this file > microbenchmarks |
| "optimized" change didn't move the profile | wrong hot path / measurement error | re-profile; revert; trust the measurement | this file > The Loop |

## Related References

- [sanitizers.md](sanitizers.md) — when the issue is correctness, not speed
- [gdb-lldb.md](gdb-lldb.md) — `py-spy dump` / native debugging for a hung process
- [diagnostics SKILL.md](../SKILL.md) — symptom -> tool router and profiling quickstart
- [ffi-interop](../../ffi-interop/SKILL.md) — moving a Python hot path into C/C++
- [python-concurrency](../../../python/python-concurrency/SKILL.md) — parallelism for CPU-bound Python (3.14 free-threading, subinterpreters)
- [build-systems references](../../build-systems/references/_index.md) — RelWithDebInfo presets for profilable builds
