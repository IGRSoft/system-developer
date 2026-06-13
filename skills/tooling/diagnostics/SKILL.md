---
name: diagnostics
description: >-
  Route a runtime symptom (crash, wrong values, race, leak, slow) to the
  right sanitizer, debugger, or profiler for C, C++, and Python. Use when a
  program crashes, leaks, deadlocks, produces wrong output, or runs too slow
  and you need to pick a tool and the exact flags to run it.
---

# Diagnostics

**Pick a tool from the symptom, then run it with the flag set below.**

## When to Use

Use this skill when you have a *behavior*, not a tool name:

- It crashes (`SIGSEGV`, `SIGABRT`), corrupts memory, or reads garbage.
- It produces wrong values, or behaves differently with optimization on.
- It hangs, deadlocks, or gives nondeterministic results under load.
- It leaks memory or grows without bound.
- It is too slow and you need to find the hot path before changing code.

Skip if the problem is at build/link time — that is [build-systems](../build-systems/SKILL.md).

## Symptom -> Tool Routing

| Symptom | First tool | Notes |
|---------|-----------|-------|
| Crash, `SIGSEGV`, `SIGABRT`, heap corruption, use-after-free | **ASan** (`-fsanitize=address`) | Combine with UBSan. Reports file:line of access *and* allocation. |
| Wrong values, signed overflow, bad shifts, misaligned access, `optimization changes behavior` | **UBSan** (`-fsanitize=undefined`) | Add `-fno-sanitize-recover=all` to abort on first hit. Combine with ASan. |
| Data race, intermittent wrong results, hang under threads | **TSan** (`-fsanitize=thread`) | Run **alone** — incompatible with ASan/MSan. |
| Reads of uninitialized memory | **MSan** (`-fsanitize=memory`, Clang only) | Needs *all* deps instrumented; usually impractical — prefer `valgrind --tool=memcheck`. |
| Memory leaks | **ASan + LSan** (LSan ships inside ASan) | LSan runs at exit by default under ASan. Or `valgrind --leak-check=full`. |
| Slow / high CPU | **perf** (Linux) or **`sample`** (macOS); **py-spy** (Python) | Profile first, then optimize the measured hot path. |
| Wall-clock A/B comparison | **hyperfine** | Reproducible timing of whole-command runs. |
| Need to step through, inspect state, replay | **gdb** (Linux) / **lldb** (macOS); **rr** for replay | See [gdb-lldb.md](references/gdb-lldb.md). |

## Ground Rules

- **ASan + UBSan combine** in one build — the common default. `-fsanitize=address,undefined`.
- **TSan alone.** It is mutually exclusive with ASan and MSan.
- **MSan alone**, Clang only, and only useful when every dependency (including libc++) is instrumented. For uninitialized-read hunting on real projects, reach for valgrind first.
- **Always** build sanitized/profiled binaries with `-g -fno-omit-frame-pointer`, or the reports lose symbols and frames.
- **Slowdown budget:** ASan ~2x, TSan ~5-15x, MSan ~5-15x (figures are order-of-magnitude; *verify against your toolchain*).
- Never sanitize or profile a stripped `Release` build. Use a debug-info-bearing build (`RelWithDebInfo` for profiling).

## Copy-Paste Flag Sets

```bash
# ASan + UBSan (the default crash/UB hunt)
clang -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined \
      -fno-sanitize-recover=all prog.c -o prog

# TSan (run alone)
clang -g -O1 -fno-omit-frame-pointer -fsanitize=thread prog.c -o prog

# MSan (Clang only; expect to instrument deps too)
clang -g -O1 -fno-omit-frame-pointer -fsanitize=memory \
      -fsanitize-memory-track-origins prog.c -o prog
```

### Debug-sanitize CMake preset

```json
{
  "version": 6,
  "configurePresets": [
    {
      "name": "asan-ubsan",
      "displayName": "Debug + ASan/UBSan",
      "binaryDir": "${sourceDir}/build/asan",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Debug",
        "CMAKE_C_FLAGS": "-g -fno-omit-frame-pointer -fsanitize=address,undefined",
        "CMAKE_CXX_FLAGS": "-g -fno-omit-frame-pointer -fsanitize=address,undefined",
        "CMAKE_EXE_LINKER_FLAGS": "-fsanitize=address,undefined"
      }
    }
  ]
}
```

```bash
cmake --preset asan-ubsan && cmake --build build/asan && ctest --test-dir build/asan
```

### Runtime options

```bash
# Make UBSan abort with a stack trace; surface fast, deterministic failures
export UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1

# ASan: stronger checks, symbolized frames, leak detection at exit
export ASAN_OPTIONS=detect_leaks=1:abort_on_error=1:symbolize=1:strict_string_checks=1
```

If frames show as `??`, ensure `llvm-symbolizer` (Clang) is on `PATH`, or set `ASAN_SYMBOLIZER_PATH`.

## gdb / lldb Quickstart

```bash
gdb --args ./prog arg1        # gdb (Linux); then: run, bt, frame N, print x
lldb -- ./prog arg1           # lldb (macOS); then: run, bt, frame select N, p x
```

Stop at the fault, then `bt` (gdb) / `bt` (lldb) for the backtrace. Full command translation, breakpoint scripting, and pretty-printers: [gdb-lldb.md](references/gdb-lldb.md).

### Core dumps

```bash
ulimit -c unlimited                       # enable core dumps for this shell
./prog                                     # crashes -> writes a core file
gdb ./prog core                            # Linux: open the core
coredumpctl debug                          # Linux (systemd): newest crash
lldb -c /cores/core.<pid> ./prog           # macOS: open the core
```

### rr (Linux) — record once, replay deterministically

```bash
rr record ./prog arg1     # records the run (overhead ~1.2x)
rr replay                 # opens under gdb; reverse-continue / reverse-next work
```

Use rr when a crash is rare or order-dependent: capture it once, then `reverse-continue` back to the cause. Linux-only. See [gdb-lldb.md](references/gdb-lldb.md) > rr.

## Profiling Quickstart

```bash
# Linux CPU profile, then a flat report
perf record -g -- ./prog && perf report

# Python, with native (C/C++/Cython) frames; Linux native support only
py-spy record --native -o profile.svg -- python script.py

# Reproducible before/after wall-clock comparison
hyperfine './prog --old' './prog --new'
```

Decision: **py-spy** for sampling a running or whole Python process (low overhead, no code change, sees native frames on Linux); **cProfile** for deterministic per-call counts of pure Python. Full workflow, flamegraphs, and heap profilers: [profiling-tools.md](references/profiling-tools.md).

## valgrind's Remaining Niche

valgrind is slower than ASan (~10-50x) and Linux-first (limited/absent on recent macOS), so it is no longer the default. Reach for it when:

- You **cannot recompile** the binary (ASan/MSan need instrumentation; valgrind does not).
- You need **uninitialized-read detection** without the MSan "instrument every dependency" burden (`--tool=memcheck`).
- You want **call-graph or cache profiling** without perf (`--tool=callgrind`, `--tool=cachegrind`).
- You want **heap allocation profiling** (`--tool=massif`).

## Sanitizer Report Headline -> Diagnosis

| Report headline | Sanitizer | Likely cause | Fix direction | Reference |
|-----------------|-----------|--------------|---------------|-----------|
| `heap-use-after-free` | ASan | dereferencing freed memory | extend lifetime / clear pointer after free | [sanitizers.md](references/sanitizers.md) |
| `heap-buffer-overflow` / `stack-buffer-overflow` | ASan | index/size off by N, missing bounds check | validate length; `span`/bounds | [sanitizers.md](references/sanitizers.md) |
| `detected memory leaks` | LSan (via ASan) | allocation with no matching free | own with RAII/free path; or add suppression if external | [sanitizers.md](references/sanitizers.md) |
| `runtime error: signed integer overflow` | UBSan | arithmetic exceeds type range | widen type / check before op (`<stdckdint.h>`) | [sanitizers.md](references/sanitizers.md) |
| `runtime error: load of misaligned address` | UBSan | unaligned access via cast | use `memcpy` / aligned storage | [sanitizers.md](references/sanitizers.md) |
| `data race` | TSan | unsynchronized shared access | mutex/atomic; rerun TSan **alone** | [sanitizers.md](references/sanitizers.md) |
| `use-of-uninitialized-value` | MSan / valgrind | reading before write | initialize at declaration | [sanitizers.md](references/sanitizers.md) |
| frames show `??` / no file:line | any | missing `-g` / symbolizer | add `-g -fno-omit-frame-pointer`; put `llvm-symbolizer` on PATH | [sanitizers.md](references/sanitizers.md) |

## Related Skills

- [sanitizers.md](references/sanitizers.md) — per-sanitizer flags, env options, suppressions, CI recipes, annotated reports
- [gdb-lldb.md](references/gdb-lldb.md) — gdb/lldb command translation, TUI, core dumps, rr, mixed Python+native
- [profiling-tools.md](references/profiling-tools.md) — perf, py-spy/cProfile, massif/heaptrack, hyperfine, measure->fix->re-measure
- [build-systems](../build-systems/SKILL.md) — wiring a debug-sanitize preset into the build; link-time diagnostics
- [cpp-concurrency](../../cpp/cpp-concurrency/SKILL.md) — TSan-first workflow for C++ threading
- [python-concurrency](../../python/python-concurrency/SKILL.md) — diagnosing GIL/free-threading and async behavior
- [c-memory-ownership](../../c/c-memory-ownership/SKILL.md) — the ownership rules that ASan/LSan enforce
