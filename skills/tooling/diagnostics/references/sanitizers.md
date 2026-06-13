# Sanitizers Reference

Use this when:

- You have a sanitizer report to read and want to know what each line means.
- You are choosing which sanitizers to build with and how to combine them.
- You are wiring sanitized builds into CI, or need a suppression file.

Skip if:

- You only need the symptom -> tool decision. That is the [diagnostics SKILL.md](../SKILL.md) symptom router.
- The problem is a build/link failure, not a runtime fault. See [build-systems](../../build-systems/SKILL.md).

Jump to:

- Sanitizer Overview
- AddressSanitizer (ASan)
- LeakSanitizer (LSan)
- UndefinedBehaviorSanitizer (UBSan)
- ThreadSanitizer (TSan)
- MemorySanitizer (MSan)
- Combination Rules
- Runtime Options (`*_OPTIONS`)
- Suppression Files
- CI Recipes
- Annotated ASan Use-After-Free Report
- Diagnostic Table

---

## Sanitizer Overview

Sanitizers are compile-time instrumentation in GCC and Clang. You rebuild with a
`-fsanitize=` flag; the resulting binary checks itself at runtime and aborts (or
keeps going) with a detailed report on the first violation. They find bugs that
warnings and code review miss because they observe *actual* runtime addresses,
sizes, and thread interleavings.

| Sanitizer | Flag | Finds | Slowdown | Memory | Compiler |
|-----------|------|-------|----------|--------|----------|
| Address (ASan) | `-fsanitize=address` | UAF, buffer overflow (heap/stack/global), double free, use-after-return/scope | ~2x | ~3x | GCC, Clang |
| Leak (LSan) | `-fsanitize=leak` (or via ASan) | memory leaks at exit | ~0 (exit-time) | low | GCC, Clang |
| Undefined (UBSan) | `-fsanitize=undefined` | signed overflow, bad shift, misaligned/null deref, bad enum/bool, `__builtin_unreachable` | ~1.2x | low | GCC, Clang |
| Thread (TSan) | `-fsanitize=thread` | data races, lock-order inversions, some deadlocks | ~5-15x | ~5-10x | GCC, Clang |
| Memory (MSan) | `-fsanitize=memory` | reads of uninitialized memory | ~5-15x | ~2-3x | **Clang only** |

Slowdown and memory figures are order-of-magnitude and workload-dependent —
*verify against your toolchain and program*.

**Universal build flags.** Every sanitized build wants:

```bash
-g                      # debug info -> file:line in reports
-fno-omit-frame-pointer # reliable stack traces
-O1                     # readable traces while still exercising optimizer-sensitive bugs
```

Pass the same `-fsanitize=` flags to **both compile and link** — the link step
pulls in the sanitizer runtime. With CMake, set both `CMAKE_<LANG>_FLAGS` and
`CMAKE_EXE_LINKER_FLAGS` (and shared-lib linker flags if you build `.so`s).

---

## AddressSanitizer (ASan)

The first tool for any crash, heap corruption, or memory error.

```bash
clang -g -O1 -fno-omit-frame-pointer -fsanitize=address prog.c -o prog
./prog        # aborts on first error with a symbolized report
```

Detects:

- heap-use-after-free, heap-buffer-overflow, double-free, invalid-free
- stack-buffer-overflow, stack-use-after-return, stack-use-after-scope
- global-buffer-overflow
- (with LSan) memory leaks at process exit

ASan poisons "redzones" around every allocation and shadows freed memory so it
can report the *allocation* site, the *free* site, and the *access* site of a
use-after-free — three stacks in one report.

**Stack-use-after-return** is off by default; enable it:

```bash
export ASAN_OPTIONS=detect_stack_use_after_return=1
```

**Hardening interaction.** ASan and `-D_FORTIFY_SOURCE` can conflict; build the
sanitized configuration without `_FORTIFY_SOURCE` and keep fortification in your
shipping `Release` build.

---

## LeakSanitizer (LSan)

LSan finds allocations that are still reachable-but-unfreed at exit. It ships
inside ASan and runs automatically at process exit when ASan is active on Linux.

```bash
# Via ASan (recommended): leak check happens at exit
clang -g -fsanitize=address prog.c -o prog
ASAN_OPTIONS=detect_leaks=1 ./prog

# Standalone LSan (no full ASan overhead), Linux
clang -g -fsanitize=leak prog.c -o prog
```

Notes:

- On macOS, standalone LSan support is limited — *verify against your toolchain*;
  prefer ASan-driven leak detection or `leaks`/valgrind alternatives.
- A "leak" that is intentionally never freed (e.g. a process-lifetime singleton)
  belongs in a suppression file, not a code change. See Suppression Files.
- Disable for one run with `ASAN_OPTIONS=detect_leaks=0`.

---

## UndefinedBehaviorSanitizer (UBSan)

Catches the silent corruptors: signed overflow, oversized/negative shifts,
null/misaligned dereference, out-of-range enum/bool loads, invalid casts. UB is
exactly the class of bug whose symptoms change when you flip `-O0` to `-O2`.

```bash
clang -g -O1 -fno-omit-frame-pointer \
      -fsanitize=undefined -fno-sanitize-recover=all prog.c -o prog
```

| Flag | Effect |
|------|--------|
| `-fsanitize=undefined` | the umbrella set of UB checks |
| `-fno-sanitize-recover=all` | **abort** on first violation (default is print-and-continue) |
| `-fsanitize=integer` | adds *unsigned* overflow (not UB, but often a bug) — Clang |
| `-fsanitize=implicit-conversion` | lossy implicit integer conversions — Clang |
| `-fsanitize=undefined -fno-sanitize=alignment` | drop a check that floods on legacy code |

By default UBSan reports and continues. For a clean CI signal set
`UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1` (and/or compile with
`-fno-sanitize-recover=all`).

UBSan is cheap (~1.2x) and almost always combined with ASan.

---

## ThreadSanitizer (TSan)

The only practical tool for data races. A data race is undefined behavior even
when "it works" — TSan finds the window before it corrupts in production.

```bash
clang -g -O1 -fno-omit-frame-pointer -fsanitize=thread prog.c -o prog
./prog
```

Reports:

- data races (the two conflicting accesses + the threads + the missing happens-before)
- lock-order inversions (potential deadlock)
- misuse of pthread/`std::mutex` primitives

**TSan runs alone.** It cannot be combined with ASan or MSan — they replace the
allocator and shadow memory in incompatible ways. Maintain a separate TSan build
directory and run those tests in their own job.

TSan is sampling-free but interleaving-dependent: a race that needs a specific
schedule may not surface every run. Run the suspect test repeatedly (`ctest
--repeat until-fail:50`, `pytest -k race --count=50` with `pytest-repeat`).

---

## MemorySanitizer (MSan)

Detects reads of uninitialized memory. **Clang only.**

```bash
clang -g -O1 -fno-omit-frame-pointer \
      -fsanitize=memory -fsanitize-memory-track-origins prog.c -o prog
```

The catch that makes MSan impractical on most projects: it reports false
positives unless **every** library linked in is also MSan-instrumented —
including the C++ standard library. That means an instrumented libc++ build.

| Flag | Effect |
|------|--------|
| `-fsanitize=memory` | uninitialized-read detection |
| `-fsanitize-memory-track-origins` | report *where* the uninitialized value originated (slower) |

**Default recommendation:** for uninitialized-read hunting on a real codebase,
use `valgrind --tool=memcheck` instead — it requires no instrumentation of
dependencies. Reserve MSan for projects that already build a fully instrumented
toolchain (some browser/runtime projects do).

---

## Combination Rules

| Want | Build flag | Allowed together? |
|------|-----------|-------------------|
| Crash + UB hunt (the default) | `-fsanitize=address,undefined` | Yes — ASan + UBSan combine |
| Leaks | `-fsanitize=address` (LSan included) | Yes — LSan is part of ASan |
| Data races | `-fsanitize=thread` | **Alone** — never with ASan/MSan |
| Uninitialized reads | `-fsanitize=memory` (Clang) | **Alone** — never with ASan/TSan |

Practical matrix:

- **Build A:** `address,undefined` — run the whole suite here.
- **Build B:** `thread` — run threaded/concurrent tests here.
- **Build C (optional):** `memory` (Clang + instrumented deps) *or* valgrind memcheck.

Three build directories, three CI jobs. Do not try to fold them into one binary.

---

## Runtime Options (`*_OPTIONS`)

Behavior is controlled by colon-separated environment variables read at startup.

### ASAN_OPTIONS

| Key | Value | Effect |
|-----|-------|--------|
| `detect_leaks` | `1`/`0` | enable/disable LSan at exit |
| `abort_on_error` | `1` | call `abort()` (core dump) instead of `_exit` |
| `halt_on_error` | `0` | keep going after a non-fatal error (rare) |
| `detect_stack_use_after_return` | `1` | enable stack-use-after-return checks |
| `symbolize` | `1` | symbolized frames (needs `llvm-symbolizer` on PATH) |
| `strict_string_checks` | `1` | stricter `str*`/`mem*` bounds checks |
| `log_path` | `asan.log` | write reports to `asan.log.<pid>` |
| `suppressions` | `file` | path to a suppression file |

```bash
export ASAN_OPTIONS=detect_leaks=1:abort_on_error=1:symbolize=1:strict_string_checks=1
```

### UBSAN_OPTIONS

| Key | Value | Effect |
|-----|-------|--------|
| `print_stacktrace` | `1` | include a backtrace with each report |
| `halt_on_error` | `1` | stop on first UB |
| `suppressions` | `file` | suppression file (function/file matchers) |

```bash
export UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1
```

### TSAN_OPTIONS

| Key | Value | Effect |
|-----|-------|--------|
| `halt_on_error` | `1` | stop on first race |
| `history_size` | `0`..`7` | longer access history (more memory, deeper reports) |
| `second_deadlock_stack` | `1` | show both stacks for lock-order reports |
| `suppressions` | `file` | suppression file |

```bash
export TSAN_OPTIONS=halt_on_error=1:history_size=7:second_deadlock_stack=1
```

### LSAN_OPTIONS

```bash
export LSAN_OPTIONS=suppressions=lsan.supp:print_suppressions=0
```

### Symbolizer

If frames print as `??` or raw addresses:

```bash
export ASAN_SYMBOLIZER_PATH=$(command -v llvm-symbolizer)
```

Ensure `llvm-symbolizer` (Clang) or `addr2line`/`binutils` (GCC) is installed
and on `PATH`, and that the binary was built with `-g`.

---

## Suppression Files

Suppressions are a **last resort** for failures you cannot fix (third-party
libraries, intentional process-lifetime allocations). Suppress narrowly; never
blanket-suppress a category you own.

### LSan suppression (`lsan.supp`)

```
# Format: leak:<substring matched against a frame in the leak stack>
leak:libthirdparty.so
leak:known_singleton_init
```

```bash
LSAN_OPTIONS=suppressions=$PWD/lsan.supp ./prog
```

### UBSan suppression (`ubsan.supp`)

```
# Format: <check>:<file-or-function substring>
alignment:legacy_packed.c
shift:vendor_crypto
```

```bash
UBSAN_OPTIONS=suppressions=$PWD/ubsan.supp ./prog
```

### TSan suppression (`tsan.supp`)

```
# Suppress a known-benign race in a vendored lib
race:vendor_logging
deadlock:third_party_pool
```

```bash
TSAN_OPTIONS=suppressions=$PWD/tsan.supp ./prog
```

Check suppression files into the repo next to the build config, with a comment
on every line explaining *why* it is suppressed and a link to the upstream issue.
An undocumented suppression is a hidden bug.

---

## CI Recipes

Run the combinable sanitizers as one job and TSan as a separate job. Treat any
report as a failing build.

### Two-config CMake + CTest

```bash
# Job 1: ASan + UBSan
cmake -S . -B build/asan -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_FLAGS="-g -fno-omit-frame-pointer -fsanitize=address,undefined" \
  -DCMAKE_CXX_FLAGS="-g -fno-omit-frame-pointer -fsanitize=address,undefined" \
  -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined"
cmake --build build/asan
ASAN_OPTIONS=abort_on_error=1 UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
  ctest --test-dir build/asan --output-on-failure

# Job 2: TSan (separate runner)
cmake -S . -B build/tsan -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_FLAGS="-g -fno-omit-frame-pointer -fsanitize=thread" \
  -DCMAKE_CXX_FLAGS="-g -fno-omit-frame-pointer -fsanitize=thread" \
  -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=thread"
cmake --build build/tsan
TSAN_OPTIONS=halt_on_error=1 ctest --test-dir build/tsan --output-on-failure
```

### Make a report fail the job

By default ASan exits non-zero on error, but a `_exit`-based teardown can swallow
it. Force it:

```bash
export ASAN_OPTIONS=abort_on_error=1:exitcode=1
export UBSAN_OPTIONS=halt_on_error=1:exitcode=1
export TSAN_OPTIONS=halt_on_error=1:exitcode=1
```

### Python C extensions under sanitizers

A C/C++ extension imported by CPython needs the interpreter to preload the ASan
runtime (the main program — `python` — was not linked with it):

```bash
# Find the runtime your clang ships, then preload it (Linux example).
LD_PRELOAD=$(clang -print-file-name=libclang_rt.asan-x86_64.so) \
  ASAN_OPTIONS=detect_leaks=0 \
  python -m pytest
```

`detect_leaks=0` avoids drowning in CPython's own intentional allocations. On
macOS use `DYLD_INSERT_LIBRARIES` with the `.dylib` runtime. *Verify the runtime
filename against your toolchain* (`clang -print-file-name=` lists it).

---

## Annotated ASan Use-After-Free Report

A representative report and how to read it top to bottom:

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

Read it in three passes:

1. **The headline** names the bug class (`heap-use-after-free`), the access kind
   (`READ of size 4`), and the address. `SUMMARY` repeats the *access* site —
   `list.c:42` — which is where your program touched freed memory.
2. **"freed by thread T0 here"** is where the memory was released:
   `release_node` at `list.c:31`, called from `pipeline.c:85`.
3. **"previously allocated by thread T0 here"** is where it was born:
   `make_node` at `list.c:18`, called from `pipeline.c:80`.

The fix is dictated by the gap between *free* (line 85) and *use* (line 42 via
line 88): the pipeline freed the node at line 85 and then read it at line 88. So
either reorder so the read precedes the free, or null the pointer after `free`
and guard the read, or rethink ownership (who is allowed to free this node, and
when). The "READ of size 4" tells you it was a 4-byte field read (likely an
`int`), and "0 bytes inside of 4-byte region" confirms the access started at the
freed object's base — a plain dereference, not an out-of-bounds index.

To deduplicate many reports, group by the **top user-code frame** in the
`SUMMARY` line (`list.c:42:12 in process_node`); ignore differing libc frames.

---

## Diagnostic Table

| Report / symptom | Cause | Fix | Reference |
|------------------|-------|-----|-----------|
| `heap-use-after-free` | read/write after `free`/`delete` | reorder, null-after-free, fix ownership | this file > Annotated report |
| `heap-buffer-overflow` | index/size past allocation | bounds check; `span`/`vector::at` in C++ | this file > ASan |
| `stack-buffer-overflow` | local array overrun | fix index math; size the buffer correctly | this file > ASan |
| `stack-use-after-return` | returned pointer to a local | return by value / heap-own; enable `detect_stack_use_after_return` | this file > ASan |
| `detected memory leaks` | unfreed allocation at exit | RAII / matching free; suppress only if external | this file > LSan, Suppression Files |
| `signed integer overflow` | arithmetic exceeds range | widen type; checked add (`<stdckdint.h>`) | this file > UBSan |
| `load of misaligned address` | unaligned cast access | `memcpy` into aligned storage | this file > UBSan |
| `data race` | unsynchronized shared access | mutex/atomic; rerun TSan **alone** repeatedly | this file > TSan |
| `use-of-uninitialized-value` | read before initialization | initialize at declaration | this file > MSan |
| `ASan + TSan` won't link / weird crashes | incompatible sanitizers combined | separate build dirs; TSan alone | this file > Combination Rules |
| frames are `??` / addresses only | missing `-g` or symbolizer | `-g -fno-omit-frame-pointer`; `llvm-symbolizer` on PATH | this file > Symbolizer |
| extension UAF invisible under pytest | python not linked with ASan runtime | `LD_PRELOAD`/`DYLD_INSERT_LIBRARIES` the runtime | this file > Python C extensions |
| MSan floods with false positives | uninstrumented dependency | use valgrind memcheck instead | this file > MSan |

## Related References

- [gdb-lldb.md](gdb-lldb.md) — step into the frame a sanitizer pointed at; replay flaky races under rr
- [profiling-tools.md](profiling-tools.md) — when the problem is speed/memory pressure, not correctness
- [diagnostics SKILL.md](../SKILL.md) — the symptom -> tool router
- [build-systems references](../../build-systems/references/_index.md) — wiring sanitized presets and CI
