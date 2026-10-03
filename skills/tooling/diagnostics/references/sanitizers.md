# Sanitizers Reference

Per-sanitizer flags, combination rules, runtime options, suppressions, CI recipes, and how to read a report. The symptom -> tool decision is in [SKILL.md](../SKILL.md).

## Sanitizer Overview

Sanitizers are GCC/Clang compile-time instrumentation: rebuild with `-fsanitize=`, and the binary checks itself at runtime and reports the first violation with real addresses, sizes, and thread interleavings.

| Sanitizer | Flag | Finds | Slowdown | Memory | Compiler |
|-----------|------|-------|----------|--------|----------|
| ASan | `-fsanitize=address` | UAF, heap/stack/global overflow, double free, use-after-return/scope | ~2x | ~3x | GCC, Clang |
| LSan | `-fsanitize=leak` (or via ASan) | leaks at exit | ~0 | low | GCC, Clang |
| UBSan | `-fsanitize=undefined` | signed overflow, bad shift, misaligned/null deref, bad enum/bool | ~1.2x | low | GCC, Clang |
| TSan | `-fsanitize=thread` | data races, lock-order inversions | ~5-15x | ~5-10x | GCC, Clang |
| MSan | `-fsanitize=memory` | uninitialized reads | ~5-15x | ~2-3x | Clang only |

Figures are order-of-magnitude and workload-dependent.

### Universal build flags

```bash
-g                      # file:line in reports
-fno-omit-frame-pointer # reliable stack traces
-O1                     # readable traces that still exercise optimizer-sensitive bugs
```

Pass the same `-fsanitize=` flags to compile and link; the link step pulls in the runtime. With CMake, `CMAKE_<LANG>_FLAGS` reach the link line too.

## AddressSanitizer (ASan)

The first tool for any crash, heap corruption, or memory error.

```bash
clang -g -O1 -fno-omit-frame-pointer -fsanitize=address prog.c -o prog
./prog        # aborts on first error with a symbolized report
```

Detects heap-use-after-free, heap/stack/global buffer overflow, double/invalid free, stack-use-after-scope, stack-use-after-return, and (with LSan) leaks at exit. A use-after-free report carries three stacks: allocation, free, and access.

Stack-use-after-return is off by default; enable it with `ASAN_OPTIONS=detect_stack_use_after_return=1`.

ASan and `-D_FORTIFY_SOURCE` can conflict; build the sanitized configuration without fortification and keep it in the shipping `Release` build.

## LeakSanitizer (LSan)

LSan reports allocations still unfreed at exit. On Linux it runs automatically under ASan.

```bash
clang -g -fsanitize=address prog.c -o prog     # via ASan (recommended)
clang -g -fsanitize=leak prog.c -o prog        # standalone, Linux, no ASan overhead
```

- macOS: Apple clang's ASan doesn't support leak detection (`detect_leaks=1` can abort at startup); use `leaks <pid>` or upstream LLVM clang.
- An intentional process-lifetime allocation belongs in a suppression file, not a code change.
- Disable for one run with `ASAN_OPTIONS=detect_leaks=0`.

## UndefinedBehaviorSanitizer (UBSan)

Catches signed overflow, oversized/negative shifts, null/misaligned dereference, out-of-range enum/bool loads, and invalid casts — the bugs whose symptoms change between `-O0` and `-O2`. Cheap (~1.2x); almost always combined with ASan.

```bash
clang -g -O1 -fno-omit-frame-pointer \
      -fsanitize=undefined -fno-sanitize-recover=all prog.c -o prog
```

| Flag | Effect |
|------|--------|
| `-fsanitize=undefined` | the umbrella set of UB checks |
| `-fno-sanitize-recover=all` | abort on first violation (default is print and continue) |
| `-fsanitize=integer` | adds unsigned overflow (not UB, often a bug) — Clang |
| `-fsanitize=implicit-conversion` | lossy implicit integer conversions — Clang |
| `-fno-sanitize=alignment` | drop a check that floods on legacy code |

Without the recover flag, `UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1` gives a clean CI signal.

## ThreadSanitizer (TSan)

The practical tool for data races, which are UB even when the code "works".

```bash
clang -g -O1 -fno-omit-frame-pointer -fsanitize=thread prog.c -o prog
```

Reports data races (both accesses, both threads), lock-order inversions, and misuse of pthread/`std::mutex`.

TSan can't be combined with ASan or MSan (incompatible allocator and shadow memory); give it its own build directory and CI job.

A race that needs a specific schedule may not show every run. Repeat the suspect test: `ctest --repeat until-fail:50`, or `pytest -k race --count=50` with pytest-repeat.

## MemorySanitizer (MSan)

Detects uninitialized reads. Clang only.

```bash
clang -g -O1 -fno-omit-frame-pointer \
      -fsanitize=memory -fsanitize-memory-track-origins prog.c -o prog
```

`-fsanitize-memory-track-origins` reports where the value came from (slower). MSan reports false positives unless every linked library, the C++ standard library included, is instrumented. On a real codebase use `valgrind --tool=memcheck` instead; reserve MSan for projects that already build an instrumented toolchain.

## Combination Rules

| Want | Build flag | Combine? |
|------|-----------|----------|
| Crash + UB hunt (default) | `-fsanitize=address,undefined` | yes |
| Leaks | `-fsanitize=address` | LSan included |
| Data races | `-fsanitize=thread` | alone |
| Uninitialized reads | `-fsanitize=memory` (Clang) | alone |

Practical matrix — separate build directories and CI jobs, never one binary:

- Build A: `address,undefined` — the whole suite.
- Build B: `thread` — threaded/concurrent tests.
- Build C (optional): `memory` with instrumented deps, or valgrind memcheck.

## Runtime Options (`*_OPTIONS`)

Colon-separated environment variables read at startup.

### ASAN_OPTIONS

| Key | Value | Effect |
|-----|-------|--------|
| `detect_leaks` | `1`/`0` | LSan at exit |
| `abort_on_error` | `1` | `abort()` (core dump) instead of `_exit` |
| `halt_on_error` | `0` | keep going after an error; needs `-fsanitize-recover=address` |
| `detect_stack_use_after_return` | `1` | stack-use-after-return checks |
| `symbolize` | `1` | symbolized frames (needs `llvm-symbolizer`) |
| `strict_string_checks` | `1` | stricter `str*`/`mem*` bounds checks |
| `log_path` | `asan.log` | write to `asan.log.<pid>` |
| `suppressions` | `file` | suppression file |

```bash
export ASAN_OPTIONS=detect_leaks=1:abort_on_error=1:symbolize=1:strict_string_checks=1
```

### UBSAN_OPTIONS, TSAN_OPTIONS, LSAN_OPTIONS

| Variable | Key | Effect |
|----------|-----|--------|
| `UBSAN_OPTIONS` | `print_stacktrace=1` | backtrace with each report |
| `UBSAN_OPTIONS` | `halt_on_error=1` | stop on first UB |
| `TSAN_OPTIONS` | `halt_on_error=1` | stop on first race |
| `TSAN_OPTIONS` | `history_size=0..7` | longer access history (more memory) |
| `TSAN_OPTIONS` | `second_deadlock_stack=1` | both stacks in lock-order reports |
| all | `suppressions=file` | suppression file |

```bash
export UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1
export TSAN_OPTIONS=halt_on_error=1:history_size=7:second_deadlock_stack=1
export LSAN_OPTIONS=suppressions=lsan.supp:print_suppressions=0
```

### Symbolizer

If frames print as `??` or raw addresses, build with `-g`, install `llvm-symbolizer` (Clang) or binutils' `addr2line` (GCC), and point at it: `export ASAN_SYMBOLIZER_PATH=$(command -v llvm-symbolizer)`.

## Suppression Files

A last resort for failures you can't fix (third-party code, intentional process-lifetime allocations). Suppress narrowly, never a whole category you own.

```
# lsan.supp — leak:<substring matched against a frame in the leak stack>
leak:libthirdparty.so
leak:known_singleton_init

# ubsan.supp — <check>:<file-or-function substring>
alignment:legacy_packed.c
shift:vendor_crypto

# tsan.supp
race:vendor_logging
deadlock:third_party_pool
```

```bash
LSAN_OPTIONS=suppressions=$PWD/lsan.supp ./prog    # likewise UBSAN_/TSAN_OPTIONS
```

Check suppression files in next to the build config, each line commented with why and a link to the upstream issue.

## CI Recipes

Run ASan+UBSan as one job and TSan as another; any report fails the build.

### Two-config CMake + CTest

```bash
# Job 1: ASan + UBSan
cmake -S . -B build/asan -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_FLAGS="-g -fno-omit-frame-pointer -fsanitize=address,undefined" \
  -DCMAKE_CXX_FLAGS="-g -fno-omit-frame-pointer -fsanitize=address,undefined"
cmake --build build/asan
ASAN_OPTIONS=abort_on_error=1 UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
  ctest --test-dir build/asan --output-on-failure

# Job 2: TSan (separate runner)
cmake -S . -B build/tsan -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_FLAGS="-g -fno-omit-frame-pointer -fsanitize=thread" \
  -DCMAKE_CXX_FLAGS="-g -fno-omit-frame-pointer -fsanitize=thread"
cmake --build build/tsan
TSAN_OPTIONS=halt_on_error=1 ctest --test-dir build/tsan --output-on-failure
```

UBSan exits 0 after a report unless it halts, so keep `halt_on_error=1` (or `-fno-sanitize-recover=all`) in CI.

### Python C extensions under sanitizers

`python` isn't linked with the ASan runtime, so preload it:

```bash
# Linux, Clang: older layouts name it libclang_rt.asan-x86_64.so, newer ones
# libclang_rt.asan.so under `clang -print-runtime-dir`. GCC: libasan.so.
LD_PRELOAD=$(clang -print-file-name=libclang_rt.asan-x86_64.so) \
  ASAN_OPTIONS=detect_leaks=0 python -m pytest
```

`-print-file-name` echoes the name back unchanged when the file isn't found, so check the path exists. `detect_leaks=0` hides CPython's intentional allocations. On macOS use `DYLD_INSERT_LIBRARIES` with the `.dylib` runtime.

## Annotated ASan Use-After-Free Report

```
==2451==ERROR: AddressSanitizer: heap-use-after-free on address 0x602000000050
    at pc 0x0001047c READ of size 4 thread T0
    #0 0x10a3 in process_node list.c:42:12
    #1 0x10f7 in run_pipeline pipeline.c:88:5
    #2 0x7f...  in __libc_start_main

0x602000000050 is located 0 bytes inside of 4-byte region
freed by thread T0 here:
    #0 0x4d2 in free
    #1 0x108b in release_node list.c:31:5
    #2 0x10ee in run_pipeline pipeline.c:85:5

previously allocated by thread T0 here:
    #0 0x4a1 in malloc
    #1 0x1052 in make_node list.c:18:14
    #2 0x10cc in run_pipeline pipeline.c:80:9

SUMMARY: AddressSanitizer: heap-use-after-free list.c:42:12 in process_node
```

### Reading it

1. The headline names the bug class, the access (`READ of size 4`), and the address. `SUMMARY` repeats the access site, `list.c:42`.
2. "freed by" is where the memory was released: `release_node` (`list.c:31`), called from `pipeline.c:85`.
3. "previously allocated by" is where it was born: `make_node` (`list.c:18`), from `pipeline.c:80`.

The pipeline freed the node at line 85 and read it at line 88. Fix by reordering so the read comes first, nulling the pointer after `free` and guarding the read, or settling who owns the node. "0 bytes inside of 4-byte region" means a plain dereference of the object's base, not an out-of-bounds index.

To deduplicate many reports, group by the top user-code frame in `SUMMARY` and ignore differing libc frames.

## Diagnostic Table

### Memory and UB reports

| Report | Cause | Fix |
|--------|-------|-----|
| `heap-use-after-free` | access after `free`/`delete` | reorder, null after free, fix ownership |
| `heap-buffer-overflow` | index/size past allocation | bounds check; `span`/`vector::at` |
| `stack-buffer-overflow` | local array overrun | fix index math or buffer size |
| `stack-use-after-return` | returned pointer to a local | return by value or heap-own |
| `detected memory leaks` | unfreed allocation at exit | RAII / matching free; suppress only if external |
| `signed integer overflow` | arithmetic exceeds range | widen; checked add (`<stdckdint.h>`) |
| `load of misaligned address` | unaligned cast access | `memcpy` into aligned storage |
| `data race` | unsynchronized shared access | mutex/atomic; rerun TSan alone, repeatedly |
| `use-of-uninitialized-value` | read before initialization | initialize at declaration |

### Setup problems

| Symptom | Cause | Fix |
|---------|-------|-----|
| ASan + TSan won't link / odd crashes | incompatible sanitizers combined | separate build dirs |
| frames are `??` | missing `-g` or symbolizer | see Symbolizer |
| extension UAF invisible under pytest | `python` lacks the ASan runtime | preload it (Python C extensions) |
| MSan floods with false positives | uninstrumented dependency | valgrind memcheck |

## Related References

- [gdb-lldb.md](gdb-lldb.md) — step into the frame a sanitizer named; replay flaky races under rr
- [profiling-tools.md](profiling-tools.md) — speed or memory pressure rather than correctness
- [cmake-modern.md](../../build-systems/references/cmake-modern.md) > CMakePresets Schema — sanitized presets
