# Profiling Tools Reference

Finding where time and memory go, and proving a change helped: perf, sample, py-spy, cProfile, heap profilers, hyperfine, and microbenchmarks. If the program is wrong rather than slow, see [sanitizers.md](sanitizers.md) or [gdb-lldb.md](gdb-lldb.md).

## The Measure -> Fix -> Re-measure Loop

1. Reproduce a representative, repeatable workload (benchmark or fixed input).
2. Measure to find the hot path; don't optimize a function you only suspect.
3. Record a baseline (commit the hyperfine/benchmark JSON).
4. Change one thing.
5. Re-measure against the baseline; keep the win or revert.
6. Stop at the target, or when the next hot path is in someone else's code.

Profile a `RelWithDebInfo` build (`-O2 -g`): `-O0` shows the wrong hot paths and a stripped `Release` has no symbols. The profile changes shape after each fix, so re-profile before the next one. Algorithmic wins (O(n²) -> O(n log n)) beat constant-factor tweaks.

## Tool Selection

| Goal | Tool | Platform |
|------|------|----------|
| CPU hot path, C/C++ | perf | Linux |
| CPU hot path, C/C++ | `sample` / `xctrace` | macOS |
| CPU hot path, Python, no code change | py-spy | Linux/macOS (native frames: Linux) |
| Exact per-call counts, Python | cProfile | all |
| Allocation sites, C/C++ | massif / heaptrack | Linux |
| Allocation sites, Python | tracemalloc | all |
| Whole-command A vs B | hyperfine | all |
| Microbenchmark | Google Benchmark (C++), pytest-benchmark / `timeit` (Python) | all |

## perf (Linux CPU)

```bash
perf record -g -- ./prog --workload big   # profile with call graphs
perf record -g -p <pid> -- sleep 10       # sample a running process for 10s
perf report                               # interactive tree; --stdio for a dump
perf annotate process_node                # hottest function down to source/instructions
perf top                                  # live view
perf stat -- ./prog                       # counters: cycles, cache misses, branch misses
```

Build with `-O2 -g -fno-omit-frame-pointer` for accurate call graphs; without frame pointers use `perf record --call-graph dwarf` (heavier). `perf stat` helps tell cache-bound from CPU-bound before digging in.

If perf reports "Permission denied", check `sysctl kernel.perf_event_paranoid` and lower it with privilege.

## Flamegraphs

Width is time; stacks read from entry (bottom) to leaf (top). The widest top-of-stack box is the hot path.

```bash
perf script | stackcollapse-perf.pl | flamegraph.pl > flame.svg   # Brendan Gregg's scripts
perf script report flamegraph                                     # newer perf -> flamegraph.html
```

py-spy writes SVG flamegraphs directly.

## macOS CPU Profiling (sample)

```bash
sample <pid> 5 1 -file sample.txt    # 5 s at 1 ms intervals -> text call tree
sample prog 5                        # by process name
xctrace record --template 'Time Profiler' --launch -- ./prog   # Instruments trace
```

`sample` needs no setup and answers "which function is eating CPU right now". For allocation and leak timelines, use `leaks <pid>` or the `xctrace` templates.

## py-spy (Python, sampling)

py-spy samples a Python process from outside: no code changes, low overhead, and it attaches to an already-running process, production included.

```bash
py-spy top --pid 12345                                # live view
py-spy record -o profile.svg -- python script.py      # flamegraph for a run
py-spy record --native -o profile.svg -- python script.py   # + C/C++/Cython frames (Linux, Windows)
py-spy dump --pid 12345                               # stack of a hung process
```

`--native` needs the extension built with `-g`; for Cython, keep the generated `.c`/`.cpp` so lines map back to `.pyx`. Attaching may need the process owner or privilege.

## cProfile (Python, deterministic)

cProfile records every call: exact counts and cumulative/total time, at higher overhead than py-spy.

```bash
python -m cProfile -o output.prof script.py
python -m pstats output.prof          # then: sort cumtime, stats 10
```

Around a hot region in code:

```python
import cProfile, pstats
from pstats import SortKey

profiler = cProfile.Profile()
profiler.enable()
main()
profiler.disable()
pstats.Stats(profiler).sort_stats(SortKey.CUMULATIVE).print_stats(10)
```

`line_profiler` (`kernprof -l -v script.py` with `@profile`) attributes time to lines; `snakeviz output.prof` draws an icicle graph.

## py-spy vs cProfile Decision

| Use | Reach for |
|-----|-----------|
| Running / production process, long job, or code you can't edit | py-spy |
| C/Cython frames too | `py-spy --native` (Linux) |
| Exact per-function call counts, reproducible numbers in a test | cProfile |
| Line-by-line time in one function | line_profiler |

py-spy finds which function; cProfile or line_profiler explain why, when sampling isn't precise enough.

## Python Optimization Patterns

Highest-yield fixes once profiling names the hot function; confirm each with `timeit`.

```python
squares = [i * i for i in range(n)]       # comprehension over an append loop
total = sum(i * i for i in range(n))      # generator for a single pass
text = "".join(str(x) for x in parts)     # join, not += (quadratic rebuilds)
seen = set(ids); hit = target in seen     # O(1) membership, not a list scan
local_fn = obj.method                     # hoist lookups out of hot loops
for x in data: local_fn(x)

from functools import lru_cache
@lru_cache(maxsize=None)                  # pure, repeatedly called functions
def fib(n): return n if n < 2 else fib(n-1) + fib(n-2)
```

Bigger levers: vectorize numeric work with NumPy, move the inner loop into a C/C++ extension ([ffi-interop](../../ffi-interop/SKILL.md)), or use free-threading or subinterpreters on 3.14 for CPU-bound parallelism ([python-concurrency](../../../python/python-concurrency/SKILL.md)).

## Heap Profiling (massif, heaptrack, tracemalloc)

For memory growth rather than CPU. All need `-g` for readable backtraces.

```bash
valgrind --tool=massif ./prog
ms_print massif.out.<pid>                    # peak, snapshots, top allocators
heaptrack ./prog                             # Linux, lower overhead
heaptrack_print heaptrack.prog.<pid>.gz      # or heaptrack_gui
```

massif shows what was allocated at peak and by whom; heaptrack adds allocation counts, leaks, and temporary-allocation churn. valgrind is Linux-first and limited on recent macOS.

### Python

```python
import tracemalloc
tracemalloc.start()
# ... run the workload ...
snapshot = tracemalloc.take_snapshot()
for stat in snapshot.statistics("lineno")[:10]:
    print(stat)                  # top 10 allocation sites by size
```

Take two snapshots and `compare_to` to find growth between phases.

## hyperfine (wall-clock benchmarking)

hyperfine runs each command many times and reports mean ± σ with outlier detection — the baseline tool for whole-command before/after evidence.

```bash
hyperfine --warmup 3 './prog --old' './prog --new'
hyperfine --warmup 3 --export-json bench.json './prog --new'   # baseline to commit
hyperfine -P threads 1 8 './prog --threads {threads}'          # parameter sweep
hyperfine --prepare 'rm -f cache.bin' './prog'                 # reset state per run
```

It measures end to end, process startup included; time a single function with a microbenchmark instead.

## Google Benchmark / pytest-benchmark (microbenchmarks)

```cpp
#include <benchmark/benchmark.h>

static void BM_Parse(benchmark::State& state) {
    for (auto _ : state) {
        auto r = parse(kInput);
        benchmark::DoNotOptimize(r);   // keep the optimizer from deleting the work
    }
}
BENCHMARK(BM_Parse);
BENCHMARK_MAIN();
```

Build at `-O2`; run with `--benchmark_repetitions=10 --benchmark_report_aggregates_only=true` for mean/median/stddev.

```python
def test_parse_perf(benchmark):
    result = benchmark(parse, SAMPLE_INPUT)
    assert result.ok
```

pytest-benchmark can fail CI on regression with `--benchmark-compare` against a saved baseline. Ad hoc: `python -m timeit -s 'from mod import f' 'f(data)'`.

## Diagnostic Table

| Symptom | Cause | Action |
|---------|-------|--------|
| perf shows `[unknown]` / no call graph | no frame pointers, or stripped | `-O2 -g -fno-omit-frame-pointer`, or `--call-graph dwarf` |
| `perf: Permission denied` | `perf_event_paranoid` too high | lower it (privileged) |
| profile blames trivial functions | profiled `-O0` | profile `RelWithDebInfo` |
| py-spy can't attach | OS attach restriction | run as owner / with privilege |
| `--native` shows no C frames | macOS, or no `-g` | Linux; rebuild with `-g` |
| cProfile far slower than reality | deterministic overhead | py-spy |
| memory grows, no leak reported | retained references / caches | tracemalloc, massif, heaptrack |
| benchmark numbers jump around | cold caches, noisy machine | `--warmup`, pin CPU, repeat |
| Google Benchmark reports ~0 ns | optimizer deleted the work | `DoNotOptimize` / `ClobberMemory` |
| change didn't move the profile | wrong hot path | re-profile; revert |

## Related References

- [gdb-lldb.md](gdb-lldb.md) — native debugging of a hung process
- [cmake-modern.md](../../build-systems/references/cmake-modern.md) > CMakePresets Schema — a `RelWithDebInfo` preset for profilable builds
