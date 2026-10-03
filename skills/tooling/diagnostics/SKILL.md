---
name: diagnostics
description: >-
  Route a runtime symptom (crash, wrong values, race, leak, slow) to the
  right sanitizer, debugger, or profiler for C, C++, and Python. Use when a
  program crashes, leaks, deadlocks, produces wrong output, or runs too slow
  and you need to pick a tool and the exact flags to run it.
---

# Diagnostics

Pick a tool from the symptom, then run it with the flag set below. Build and link failures belong to [build-systems](../build-systems/SKILL.md).

## Symptom -> Tool Routing

### Correctness

| Symptom | First tool | Notes |
|---------|-----------|-------|
| Crash, `SIGSEGV`, `SIGABRT`, heap corruption, use-after-free | ASan (`-fsanitize=address`) | Combine with UBSan; reports access and allocation sites |
| Wrong values, overflow, bad shifts, misaligned access, behavior changes with `-O` | UBSan (`-fsanitize=undefined`) | `-fno-sanitize-recover=all` aborts on first hit |
| Data race, intermittent wrong results, hang under threads | TSan (`-fsanitize=thread`) | Runs alone |
| Reads of uninitialized memory | MSan (Clang only) or `valgrind --tool=memcheck` | MSan needs every dependency instrumented; valgrind usually wins |
| Memory leaks | ASan (LSan is built in) or `valgrind --leak-check=full` | LSan runs at exit |

### Performance and inspection

| Symptom | First tool |
|---------|-----------|
| Slow / high CPU | perf (Linux), `sample` (macOS), py-spy (Python) — profile before changing code |
| Wall-clock A/B comparison | hyperfine |
| Step through, inspect state, replay | gdb (Linux), lldb (macOS), rr for replay — see [gdb-lldb.md](references/gdb-lldb.md) |

## Ground Rules

- ASan + UBSan combine in one build (`-fsanitize=address,undefined`) — the usual default.
- TSan and MSan each run alone. MSan is Clang-only and only useful when every dependency, libc++ included, is instrumented; for uninitialized reads on real projects, use valgrind first.
- Build sanitized and profiled binaries with `-g -fno-omit-frame-pointer`, or reports lose symbols and frames.
- Rough slowdown: ASan ~2x, TSan ~5-15x, MSan ~5-15x.
- Never sanitize or profile a stripped `Release` build; profile `RelWithDebInfo`.

## Sanitizer Flag Sets

The bundled script emits the exact compile flags, runtime `*_OPTIONS`, or a CMakePresets/Makefile fragment, so don't hand-assemble them:

```bash
# compile flags (default) — the asan+ubsan crash/UB hunt
../../_shared/scripts/sanitizer_flags.sh --lang cpp --sanitizer asan+ubsan
# runtime *_OPTIONS, ready to source
eval "$(../../_shared/scripts/sanitizer_flags.sh --lang c --sanitizer asan+ubsan --output env)"
# a CMakePresets.json v6 entry (or --output make)
../../_shared/scripts/sanitizer_flags.sh --lang cpp --sanitizer asan+ubsan --output cmake
```

`--sanitizer` ∈ {`asan`, `ubsan`, `asan+ubsan`, `tsan`, `msan`}; `--output` ∈ {`flags`, `env`, `cmake`, `make`}; `--lang` ∈ {`c`, `cpp`, `python`} (python emits `CFLAGS`/`CXXFLAGS` for a native-extension build). Paths are relative to this skill's directory; `--help` gives the full contract. The script warns when a set must run alone and reminds you to keep `llvm-symbolizer` on `PATH`.

## gdb / lldb Quickstart

```bash
gdb --args ./prog arg1        # Linux; then: run, bt, frame N, print x
lldb -- ./prog arg1           # macOS; then: run, bt, frame select N, p x
```

Command translation, breakpoint scripting, and pretty-printers: [gdb-lldb.md](references/gdb-lldb.md).

### Core dumps

```bash
ulimit -c unlimited                       # enable core dumps for this shell
gdb ./prog core                            # Linux: open the core
coredumpctl debug                          # Linux (systemd): newest crash
lldb -c /cores/core.<pid> ./prog           # macOS
```

### rr (Linux) — record once, replay deterministically

```bash
rr record ./prog arg1     # overhead ~1.2x
rr replay                 # gdb session; reverse-continue / reverse-next work
```

Use rr for rare or order-dependent crashes: capture once, then `reverse-continue` back to the cause.

## Profiling Quickstart

```bash
perf record -g -- ./prog && perf report                      # Linux CPU profile
py-spy record --native -o profile.svg -- python script.py    # Python + native frames (Linux)
hyperfine './prog --old' './prog --new'                      # before/after wall clock
```

py-spy samples a running or whole Python process with no code change; cProfile gives deterministic per-call counts for pure Python. Flamegraphs, heap profilers, and the measure -> fix -> re-measure loop: [profiling-tools.md](references/profiling-tools.md).

## valgrind's Remaining Niche

valgrind is ~10-50x slower than native and Linux-first (limited or absent on recent macOS). Use it when:

- You can't recompile the binary (sanitizers need instrumentation).
- You want uninitialized-read detection without instrumenting every dependency (`--tool=memcheck`).
- You want call-graph or cache profiling without perf (`--tool=callgrind`, `--tool=cachegrind`).
- You want heap allocation profiling (`--tool=massif`).

## Sanitizer Report Headline -> Diagnosis

Options, suppressions, annotated report: [sanitizers.md](references/sanitizers.md).

| Headline | From | Likely cause | Fix direction |
|---|---|---|---|
| `heap-use-after-free` | ASan | access to freed memory | extend lifetime; clear pointer after free |
| `heap-buffer-overflow` / `stack-buffer-overflow` | ASan | index/size off by N | validate length; `span`/bounds |
| `detected memory leaks` | LSan | no matching free | RAII/free path; suppress only if external |
| `signed integer overflow` | UBSan | result exceeds type range | widen; check first (`<stdckdint.h>`) |
| `load of misaligned address` | UBSan | unaligned cast access | `memcpy` / aligned storage |
| `data race` | TSan | unsynchronized shared access | mutex/atomic; rerun TSan alone |
| `use-of-uninitialized-value` | MSan / valgrind | read before write | initialize at declaration |
| frames show `??` | any | no `-g` or symbolizer | add `-g`; `llvm-symbolizer` on `PATH` |

## Related Skills

- [cpp-concurrency](../../cpp/cpp-concurrency/SKILL.md) — TSan-first workflow for C++ threading
- [python-concurrency](../../python/python-concurrency/SKILL.md) — GIL/free-threading and async behavior
- [c-memory-ownership](../../c/c-memory-ownership/SKILL.md) — the ownership rules ASan/LSan enforce
