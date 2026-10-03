---
description: Build with sanitizers, run the tests under them, and triage the reports for C, C++, or Python native-extension projects
argument-hint: [asan|ubsan|tsan|msan|lsan|all (default all)] [path (default .)] [--fix] [--preset NAME]
allowed-tools: Read, Glob, Grep, Bash, Edit, Agent
estimated-cost:
  min-tokens: 2500
  max-tokens: 18000
  model-distribution:
    haiku: 25%
    sonnet: 65%
    opus: 10%
---

# Sanitize Check

Rebuild a project with the requested runtime sanitizers, run its tests under them, and turn the raw reports into a deduplicated triage table with a fix class per finding. Building and running stay in Bash; a language agent is engaged only to interpret findings or, with `--fix`, to apply mechanical fixes.

## Rules

- A sanitizer instruments the whole binary, so pick a compatible set per build (Compatibility Matrix). TSan never shares a binary with ASan or LSan; `all` is two sequential builds.
- Each kind builds into its own `build-<kind>/` (`build-asan/`, `build-tsan/`, `build-msan/`), never the project's normal `build/`, so instrumented and clean artifacts don't mix.
- Export the kind's `*_OPTIONS` for that run only, so one kind's options don't leak into the next.
- Tee stdout and stderr (`2>&1`) from every build and run to `.context/logs/sanitize-<kind>.log`; triage reads the log, not scrollback. Take the command's own exit status, not `tee`'s (`set -o pipefail` works in bash and zsh).
- A missing compiler or runtime for a kind never hard-fails: print the install hint, skip that kind, continue, and report the skip.
- Suppressions only for a confirmed third-party false positive, each entry with a one-line justification. Real bugs get fixed.

## Compatibility Matrix

| Kind | Flag | Combines with | Exclusive with | Compiler | Notes |
|------|------|---------------|----------------|----------|-------|
| `asan` | `-fsanitize=address` | UBSan | TSan, MSan | GCC, Clang | Includes LSan on Linux (leak check at exit). |
| `ubsan` | `-fsanitize=undefined` | ASan, TSan | — | GCC, Clang | Cheap; stack it onto other runs. |
| `tsan` | `-fsanitize=thread` | UBSan | ASan, MSan, LSan | GCC, Clang | Races and lock order. |
| `msan` | `-fsanitize=memory` | UBSan | ASan, TSan | Clang only | Every linked dependency (incl. libc++) must be instrumented, or it reports false "uninitialized" reads; often impractical. |
| `lsan` | `-fsanitize=leak` | — | TSan, MSan | GCC, Clang | Linux: comes with ASan. macOS ASan has no LSan, so run it standalone. |

### What each kind builds

- `asan` → `-fsanitize=address,undefined -fsanitize-recover=address` (the recover flag lets `halt_on_error=0` keep going past the first error)
- `ubsan` → `-fsanitize=undefined`
- `tsan` → `-fsanitize=thread,undefined`
- `msan` → `-fsanitize=memory,undefined`; always print the MSan warning (Error Handling) before building.
- `lsan` → Linux: same as `asan`; macOS: `-fsanitize=leak`.
- `all` → the `asan` build, then a separate `tsan` build: two logs, one merged report. MSan and LSan run only when requested.

## Build Flags

Every sanitized build is `RelWithDebInfo` with `-g -fno-omit-frame-pointer`, and the `-fsanitize=` flags reach both compile and link (the link pulls in the runtime). This keeps `file:line` and reliable stacks while still exercising optimizer-sensitive bugs.

### Per-build-system configure

| System | Sanitized configure into `build-<kind>/` |
|--------|------------------------------------------|
| CMake | `-DCMAKE_BUILD_TYPE=RelWithDebInfo`, flags on `CMAKE_<LANG>_FLAGS`, `CMAKE_EXE_LINKER_FLAGS`, and `CMAKE_SHARED_LINKER_FLAGS`. With `--preset`, layer them onto that preset. |
| Meson | `meson setup build-<kind> --buildtype debugoptimized -Db_sanitize=<address,undefined\|thread> -Db_lundef=false` (Clang fails to link without `b_lundef=false`); for `asan` add `-Dc_args=-fsanitize-recover=address -Dcpp_args=-fsanitize-recover=address` |
| Make / autotools | `make -C <path> BUILD_DIR=build-<kind> CFLAGS="..." CXXFLAGS="..." LDFLAGS="..."`, with `-fsanitize=` in `LDFLAGS` too |

If the build system can't take per-build flags without editing tracked files, report that and stop rather than changing its config. The `system-developer:diagnostics` skill has the canonical flag sets and per-sanitizer detail.

## Runtime Options

| Kind | Env | Effect |
|------|-----|--------|
| `asan` / `lsan` | `ASAN_OPTIONS=halt_on_error=0`, plus `:detect_leaks=1` on Linux only | Collect all errors; leak check at exit. Apple clang's ASan has no leak detection and `detect_leaks=1` can abort at startup, so leave it unset on macOS. |
| `ubsan` | `UBSAN_OPTIONS=print_stacktrace=1` | Stack per report instead of location only. |
| `tsan` | `TSAN_OPTIONS=second_deadlock_stack=1` | Both stacks for lock-order reports. |
| `msan` | `MSAN_OPTIONS=halt_on_error=1` | Stop at the first report; with uninstrumented deps the rest is usually noise. |

A combined run (e.g. ASan+UBSan) exports both.

## Python Native-Extension Mode

For a Python project with a C/C++ extension, the extension is what gets instrumented:

- Build the extension under ASan+UBSan into `build-asan/` (via its CMake, scikit-build-core, or Meson config) and run the Python tests against it. A stock `python3` may need the ASan runtime preloaded (`LD_PRELOAD` on Linux, `DYLD_INSERT_LIBRARIES` on macOS); check your toolchain. If preload is needed and unavailable, report it and use only the interpreter checks below.
- Always also run `PYTHONMALLOC=debug uv run python3 -X dev -m pytest`: it surfaces ResourceWarnings, enables allocator checks, and turns on faulthandler.

## Usage

```bash
/system-developer:sanitize-check all .                  # ASan+UBSan, then TSan
/system-developer:sanitize-check asan services/parser   # ASan+UBSan on a subproject
/system-developer:sanitize-check tsan .                 # TSan+UBSan only
/system-developer:sanitize-check lsan .                 # leaks (Linux via ASan, macOS standalone)
/system-developer:sanitize-check asan src/ --fix        # then fix mechanical findings
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `kind` | `all` | `asan`, `ubsan`, `tsan`, `msan`, `lsan`, or `all`. |
| `path` | `.` | Directory to detect, build, and run. |
| `--fix` | off | Route `mechanical` findings to `system-developer:sys-code-fixer`. Other findings still go to the language agent. |
| `--preset NAME` | none | CMake only: layer the sanitizer flags onto this `CMakePresets.json` preset, into `build-<kind>/`. Other systems ignore it with a warning. |

## Workflow

### Phase 1: Detect and plan

1. Confirm `path` exists, else stop with "Path not found".
2. Resolve the build system with `/system-developer:build-test`'s priority table and C/C++ tie-break. Only C, C++, and Python-with-native-extension trees are sanitizable (native extension: `pyproject.toml` plus C/C++ sources built through `CMakeLists.txt`, `setup.py` `ext_modules`, or scikit-build-core/pybind11/nanobind config); for pure Python or Bash, emit "Nothing to sanitize" and stop.
3. Expand `kind` into runs per the matrix, resolving `lsan` by platform.
4. For each run, check the compiler supports it (`msan` needs Clang: `cc --version` / `clang --version`). Drop unsupported runs with the install hint.

### Phase 2: Build each kind

Configure and build into `build-<kind>/` per Build Flags, teeing to the kind's log. A build or link failure is not a sanitizer finding: hand the excerpt to the owning language agent as `/system-developer:build-test` does, and skip running that kind.

### Phase 3: Run under sanitizers

For each built kind, export its `*_OPTIONS` and run the build system's test command from `/system-developer:build-test`'s table against `build-<kind>/`, or the Python native-extension invocations. Capture output from successful tests too: recovering ASan and UBSan reports can leave the exit status at zero.

- CMake: `ctest --test-dir build-<kind> --verbose` (also with a preset); `--output-on-failure` alone hides reports from passing tests.
- Meson: `meson test -C build-<kind> --verbose`.
- Python native extensions: add `-s` to each pytest invocation to disable output capture.
- Make / autotools: include the test harness's per-test logs if it captures output from passing tests.

Append stdout and stderr to the kind's log with `2>&1 | tee -a`. Record non-zero exits and continue to triage; a zero exit status does not establish CLEAN.

### Phase 4: Dedupe and triage

1. Regardless of each run's exit status, extract each report block from the logs: `ERROR: AddressSanitizer`, `runtime error:` (UBSan), `WARNING: ThreadSanitizer`, `ERROR: LeakSanitizer`, `use-of-uninitialized-value` (MSan).
2. Find each report's top user-code frame: the first frame inside the project, skipping the sanitizer runtime, libc, libstdc++/libc++, and system headers.
3. Collapse reports with the same top frame into one row with a hit count, keeping one full stack per row for the agent.
4. Give each row a type, location, allocation/origin summary (ASan allocation site, leak allocation site, TSan other stack), and a fix class from Fix classes.

#### Fix classes

| Fix class | Typical findings | Routing |
|-----------|------------------|---------|
| `mechanical` | Missing free/`delete`, off-by-one bound, missing null check, uninitialized field, missing lock around a known shared field | `sys-code-fixer` with `--fix`, else language agent |
| `interpretation` | Race needing a synchronization redesign, UAF with unclear ownership, UB with ambiguous intent | language agent |
| `false-positive` | Confirmed third-party or runtime artifact (e.g. uninstrumented dep under MSan) | justified suppression |

### Phase 5: Interpret and fix

1. When there are findings, send the triage table (not raw logs) with the Agent tool to the owner: `system-developer:c-developer` for C, `cpp-developer` for C++, or the `system-developer` router (with the detected markers) for a native extension or an ambiguous tree. Prompt:
   "Sanitizer findings for the {language} project at `{path}` ({kinds run}). Deduplicated triage below; full logs at `.context/logs/sanitize-*.log`.\n```\n{triage_table}\n```\nFor each finding explain the root cause and the minimal correct fix. Flag any you believe are false positives and why; suppress only a confirmed third-party false positive. Return analysis and patches; don't re-run the suite."
#### Mechanical fixes and re-run

2. With `--fix`, send only the `mechanical` rows with the Agent tool to `system-developer:sys-code-fixer`:
   "Apply minimal, targeted fixes for these mechanical sanitizer findings: {mechanical_rows}. One fix per finding, smallest diff. Leave `interpretation` findings alone and add no suppression files. Report each fix applied and anything you couldn't fix mechanically."
3. After fixes, re-run only the affected kinds to confirm, and report each cycle.

## Output Format

One report, shown in two parts.

```markdown
## Sanitize Report

**Target:** {path}
**Language:** {C | C++ | Python native ext}
**Kinds run:** {asan(+ubsan), tsan(+ubsan), …}
**Logs:** .context/logs/sanitize-{asan,tsan,…}.log

| Kind | Build | Findings (deduped) | Log |
|------|-------|--------------------|-----|
| asan+ubsan | ✅ / ❌ / ⏭ skipped | {N} | sanitize-asan.log |
| tsan+ubsan | ✅ / ❌ / ⏭ | {M} | sanitize-tsan.log |
```

### Report: triage, routing, and skips

```markdown
### Triage

| # | Type | Location (top user frame) | Alloc / origin | Hits | Fix class |
|---|------|---------------------------|----------------|------|-----------|
| 1 | heap-use-after-free | parser.c:142 | alloc parser.c:88 | 3 | mechanical |
| 2 | data race on `cache_` | cache.cpp:54 | other write cache.cpp:71 | 1 | interpretation |

**Result:** CLEAN / {K} findings ({mechanical} mechanical, {interp} interpretation, {fp} false-positive)

<!-- When findings exist: -->
### Routing
- Interpretation → system-developer:{c-developer | cpp-developer | system-developer}
- Mechanical (--fix only) → system-developer:sys-code-fixer
- {fixed/remaining after re-run, per cycle}

<!-- On skipped kinds only: -->
### Skipped
- {kind}: {reason} — install hint printed above.
```

A clean run says so plainly ("ASan+UBSan: clean over {N} tests").

## Error Handling

### Path not found
```
Error: Path not found: {path}
Suggestion: Pass a directory that exists, e.g. /system-developer:sanitize-check asan .
```

### Nothing to sanitize
```
Notice: No sanitizable code under {path} (pure-Python or Bash project).
Sanitizers instrument C/C++ (or a Python native extension). For pure Python
use /system-developer:fix-quick and -X dev; for Bash use /system-developer:fix-quick (shellcheck).
```

### MSan requested
```
Warning: MSan requires Clang AND every linked dependency (incl. libc++) built with
-fsanitize=memory; uninstrumented deps produce false "uninitialized" reports.
Install hint: brew install llvm  (use that clang)
```
Without Clang, add "Skipping MSan. Recommend ASan+UBSan instead, or a fully instrumented toolchain." and skip it.

### Preset on a non-CMake project
```
Warning: --preset is CMake-only; ignored for {system} project.
Proceeding with the {system} sanitizer flags for build-{kind}/.
```

### TSan requested alongside ASan
```
Error: ThreadSanitizer cannot share a binary with AddressSanitizer.
Run them separately: /system-developer:sanitize-check tsan .  then  asan .
(Or use `all`, which sequences ASan+UBSan and TSan into two builds.)
```

### Toolchain missing

| Missing tool | Install hint |
|--------------|--------------|
| `clang` / `llvm` (sanitizer runtimes, MSan) | `brew install llvm` |
| `cmake` / `ctest` | `brew install cmake ninja` |
| `uv` (Python native-ext run) | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |

Report FAIL with the aggregated hints only when every requested kind was skipped.

## See Also

- `system-developer:diagnostics` skill — per-sanitizer detail, slowdown figures, suppression-file format, annotated reports.
- `system-developer:secure-coding` skill — the memory-safety patterns these findings map back to.
- `/system-developer:build-test` — get a green ordinary build first; its triage also covers sanitized build failures.
- `/system-developer:review-code` — static review to pair with this runtime check.
- `/system-developer:fix-performance` — when the concern is speed, not correctness.
