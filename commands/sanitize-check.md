---
description: Build with sanitizers, run the tests under them, and triage the reports for C, C++, or Python native-extension projects
argument-hint: [asan|ubsan|tsan|msan|lsan|all (default all)] [path (default .)] [--fix] [--preset NAME]
allowed-tools: Read, Glob, Grep, Bash
estimated-cost:
  min-tokens: 2500
  max-tokens: 18000
  model-distribution:
    haiku: 25%
    sonnet: 65%
    opus: 10%
---

# Sanitize Check
<!-- Updated: June 2026 -->

Rebuild a project with the requested runtime sanitizers, run its test suite under them, and turn the raw reports into a deduplicated triage table with a fix class per finding. The instrumentation is pure Bash; a language agent is engaged only to interpret confirmed findings or, with `--fix`, to apply mechanical remediations.

[Extended thinking: Sanitizers are the runtime backstop the warnings-as-errors gate cannot replace — they observe real addresses, sizes, and thread interleavings. The hard parts are not running them but choosing a *compatible* combination, building into isolated directories so instrumented and clean artifacts never mix, and reading the reports without drowning in duplicate stacks. This command encodes the compatibility matrix up front (so it never builds an impossible TSan+ASan binary), gives each sanitizer kind its own `build-<kind>/` tree, sets the right `*_OPTIONS` env per run, captures everything to a per-kind log, dedupes by the top user-code frame, and only then hands a language agent a clean triage table. Keep instrumentation deterministic and shell-only; reserve model spend for interpretation and `--fix`.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **Honor the compatibility matrix.** Never combine incompatible sanitizers in one binary (see the matrix). `tsan` is mutually exclusive with `asan`/`lsan`. `all` runs as *two sequential builds* (ASan+UBSan, then TSan) — never one binary.
2. **Isolate build directories.** Each kind gets its own `build-<kind>/` tree (`build-asan/`, `build-tsan/`, `build-msan/`). Instrumented and clean artifacts MUST NOT share a build dir. Do not reuse the project's normal `build/`.
3. **Set the matching `*_OPTIONS` env per run.** Export the kind's runtime options (below) for that run only; do not let one kind's options leak into another's.
4. **Capture to a per-kind log.** Every run tees to `.context/logs/sanitize-<kind>.log`. The log is the source of truth for triage — do not rely on scrollback.
5. **Dedupe before reporting.** Collapse reports by their top user-code frame (the first frame inside the project, not inside libc/libstdc++/the sanitizer runtime). One row per distinct fault, with a hit count.
6. **Instrumentation is shell-only; agents interpret.** Building and running stay in Bash. Delegate to `system-developer:c-developer` / `cpp-developer` only to interpret confirmed findings, and to `system-developer:sys-code-fixer` only under `--fix` for mechanical remediations.
7. **Tool-missing never hard-fails.** If the compiler/runtime for a requested kind is unavailable (notably MSan, which is Clang-only), print the install hint, skip that kind, and continue with the others. Report what was skipped.
8. **Suppressions are a last resort.** Never silence a finding with a suppression file unless it is a confirmed third-party false positive *and* the entry carries a one-line justification. A real bug gets fixed, not suppressed.
9. **Never enter plan mode.** This command IS the procedure — execute it.

## Compatibility Matrix

Read this before building anything. A sanitizer is a *whole-binary* instrumentation mode; you choose a compatible set per build, not per file.

| Kind | Flag(s) | Combines with | Mutually exclusive with | Compiler | Notes |
|------|---------|---------------|-------------------------|----------|-------|
| `asan` | `-fsanitize=address` | `undefined` (UBSan) | `thread`, `memory` | GCC, Clang | Bundles LSan on Linux (leak check at exit). |
| `ubsan` | `-fsanitize=undefined` | `address` (ASan), `thread` | — | GCC, Clang | Cheapest; almost always worth stacking onto another run. |
| `tsan` | `-fsanitize=thread` | `undefined` (UBSan) | `address`, `memory`, `leak` | GCC, Clang | Data races / lock-order. Cannot coexist with ASan — separate build. |
| `msan` | `-fsanitize=memory` | `undefined` (UBSan) | `address`, `thread` | **Clang only** | Needs **every** linked dependency (incl. libc++) instrumented; uninstrumented deps cause false "uninitialized" reports — **often impractical**; warn and recommend a fully instrumented toolchain or skip. |
| `lsan` | `-fsanitize=leak` (standalone) or via ASan | — | (standalone) `thread`, `memory` | GCC, Clang | On Linux LSan ships **inside ASan** (run `asan` to get leaks). On macOS ASan has no LSan — run `lsan` **standalone**. |

**Canonical combinations this command builds:**

- `asan`  → `-fsanitize=address,undefined` (ASan always paired with UBSan — UBSan is nearly free).
- `ubsan` → `-fsanitize=undefined` alone (when you want UBSan without ASan's cost/memory).
- `tsan`  → `-fsanitize=thread,undefined` (TSan paired with UBSan; **never** with ASan).
- `msan`  → `-fsanitize=memory,undefined` (Clang only; gated on instrumented-deps check — see Rule 7).
- `lsan`  → Linux: alias of `asan` (leaks come for free); macOS: `-fsanitize=leak` standalone.
- `all`   → **sequential**: run the `asan` build (ASan+UBSan), then a *separate* `tsan` build (TSan+UBSan). Two logs, two triage passes, merged report. MSan and standalone LSan are **not** part of `all` (MSan's impracticality, LSan's platform split) — request them explicitly.

## Build Flags (every sanitized build)

Configure each `build-<kind>/` as `RelWithDebInfo` with frame pointers preserved and the kind's `-fsanitize=` flags passed to **both** compile and link (the link step pulls the sanitizer runtime):

```
-DCMAKE_BUILD_TYPE=RelWithDebInfo
-fno-omit-frame-pointer -g
-fsanitize=<kind flags>           # on CMAKE_<LANG>_FLAGS and CMAKE_EXE_LINKER_FLAGS (+ shared-lib linker flags)
```

`RelWithDebInfo` keeps `file:line` in reports while still exercising optimizer-sensitive bugs; `-fno-omit-frame-pointer` keeps stacks reliable. See `skill: diagnostics` (sanitizers reference) for the canonical CMake snippet and per-sanitizer detail.

## Runtime Options (`*_OPTIONS`)

Export per run, scoped to that run only:

| Kind | Env | Effect |
|------|-----|--------|
| `asan` / `lsan` | `ASAN_OPTIONS=halt_on_error=0:detect_leaks=1` | Keep going after the first error (collect all), and enable the leak check at exit. |
| `ubsan` | `UBSAN_OPTIONS=print_stacktrace=1` | Print a stack trace for each UB report (otherwise UBSan prints only the location). |
| `tsan` | `TSAN_OPTIONS=second_deadlock_stack=1` | Include the second stack for lock-order/deadlock reports so both sides are visible. |

When a run combines kinds (e.g. ASan+UBSan), export **both** their env vars for that run.

## Python Native-Extension Mode

When the target is a Python project with a C/C++ extension (per `skill: language-detection`, tie-break 4), pure-Python code is not what the sanitizers instrument — the extension is. Two complementary tools:

- Build the extension under ASan/UBSan (via its CMake/scikit-build-core/meson config in `build-asan/`), then run the Python tests against the instrumented extension. On many platforms loading an ASan extension into a stock `python3` needs `LD_PRELOAD` of the ASan runtime (Linux) or `DYLD_INSERT_LIBRARIES` (macOS) — *verify against your toolchain*; if preload is required and unavailable, report it and fall back to the interpreter-level checks below.
- For interpreter-visible allocation and dev-mode checks, run the suite with `PYTHONMALLOC=debug` and `python3 -X dev` (e.g. `PYTHONMALLOC=debug uv run python3 -X dev -m pytest`). `-X dev` surfaces ResourceWarnings, enables the dev-mode allocator checks, and turns on faulthandler — cheap to always add alongside a native-extension sanitize run.

Capture both to `.context/logs/sanitize-<kind>.log` as usual.

## Usage

```bash
# Default: sequential ASan+UBSan then TSan over the current directory
/system-developer:sanitize-check all .

# Just AddressSanitizer (+ UBSan) on a subproject
/system-developer:sanitize-check asan services/parser

# ThreadSanitizer only (separate build, never with ASan)
/system-developer:sanitize-check tsan .

# Leak check (Linux: via ASan; macOS: standalone LSan)
/system-developer:sanitize-check lsan .

# ASan run, then route mechanical fixes to the fixer
/system-developer:sanitize-check asan src/ --fix
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `kind` | `all` | One of `asan` / `ubsan` / `tsan` / `msan` / `lsan` / `all`. `all` = sequential ASan+UBSan then TSan (Rule 1). |
| `path` | `.` | Directory to detect, build, and run under sanitizers. |
| `--fix` | off | After triage, route mechanical findings (the fixable classes) to `system-developer:sys-code-fixer`. Interpretation-heavy findings still go to the language agent. |
| `--preset NAME` | none | For CMake projects, base the sanitized config on a `CMakePresets.json` preset, layering the `-fsanitize=` flags on top of it into `build-<kind>/`. Ignored (with a warning) by non-CMake systems. |

## Workflow

### Phase 1: Detect & Plan (Bash)

1. Confirm `path` exists; if not, emit the Error Handling "path not found" message and stop.
2. Resolve the language and build system via `skill: language-detection` (reuse `/system-developer:build-test` detection — same priority order). Only `c-developer`/`cpp-developer` trees and Python-with-native-extension trees are sanitizable; a pure-Python or Bats project has nothing to instrument → emit the "nothing to sanitize" notice and stop.
3. Expand `kind` into the concrete run plan using the Compatibility Matrix:
   - `asan`/`ubsan`/`tsan`/`msan`/`lsan` → one run each.
   - `lsan` → resolve by platform (Linux: alias `asan`; macOS: standalone `-fsanitize=leak`).
   - `all` → two runs: `[asan(=address,undefined), tsan(=thread,undefined)]`, in that order.
4. Create `.context/logs/` if absent.
5. For each planned run, verify the compiler supports the kind (`msan` requires Clang; check `cc --version` / `clang --version`). If unsupported, print the install hint, drop that run from the plan, and note the skip.

### Phase 2: Build per kind (Bash)

For each run in the plan, into its own `build-<kind>/`:

1. Configure with `RelWithDebInfo`, frame pointers, and the kind's `-fsanitize=` flags on both compile and link (see Build Flags). With `--preset`, layer the flags onto the preset.
2. Build, teeing to `.context/logs/sanitize-<kind>.log`. Capture `${PIPESTATUS[0]}`.
3. If the **build** fails (not a runtime finding), this is a build/link problem, not a sanitizer finding — hand the excerpt to the owning language agent exactly as `/system-developer:build-test` does (configure/compile/link triage), and stop this kind. Do not proceed to run an unbuilt binary.

### Phase 3: Run under sanitizers (Bash)

For each successfully built kind:

1. Export the kind's `*_OPTIONS` (and both env vars when the run combines kinds), scoped to this run.
2. Run the test suite against the instrumented build (`ctest --test-dir build-<kind> --output-on-failure`, or for Python native-extension mode the `PYTHONMALLOC=debug … -X dev … pytest` invocation), teeing to `.context/logs/sanitize-<kind>.log`.
3. A sanitizer finding makes the process exit non-zero (or, with `halt_on_error=0`, prints multiple reports then exits non-zero at the end). Both are expected — collect, don't abort the command.

### Phase 4: Dedupe & Triage (Bash)

1. From each `.context/logs/sanitize-<kind>.log`, extract every sanitizer report block (`==N==ERROR: AddressSanitizer`, `runtime error:` for UBSan, `WARNING: ThreadSanitizer`, `==N==ERROR: LeakSanitizer`, `use-of-uninitialized-value` for MSan).
2. For each report, find the **top user-code frame** — the first `#k` frame whose path is inside the project (skip frames in the sanitizer runtime, libc, libstdc++/libc++, system headers).
3. **Dedupe by that top user-code frame.** Collapse identical-top-frame reports into one row with a hit count. Preserve one full stack per distinct row for the agent.
4. Build the triage table (Output Format). Each row: error type, location (top user-code `file:line`), allocation/origin stack summary (where applicable — ASan UAF/overflow allocation site, leak allocation site, TSan second stack), and a **fix class** from:

   | Fix class | Typical findings | Routing |
   |-----------|------------------|---------|
   | `mechanical` | Missing free/`delete`, off-by-one bound, missing null check, uninitialized field, missing lock around a known shared field | `--fix` → `sys-code-fixer`; else language agent |
   | `interpretation` | Real data race needing a synchronization redesign, UAF whose ownership is unclear, UB whose intent is ambiguous | `c-developer` / `cpp-developer` |
   | `false-positive` | Confirmed third-party/runtime artifact (e.g. uninstrumented dep under MSan) | suppression file with justification (last resort) |

### Phase 5: Interpret / Fix (delegate)

1. Hand the triage table (not the raw logs) to the owning language agent for interpretation:
   - C tree:
     **Use Task tool with subagent_type="system-developer:c-developer"**
     Prompt: "Sanitizer findings for the C project at `{path}` ({kinds run}). Deduplicated triage below; full logs at `.context/logs/sanitize-*.log`.\n```\n{triage_table}\n```\nFor each finding explain the root cause and the minimal correct fix. Flag any you believe are false positives and why. Do not silence anything with a suppression unless it is a confirmed third-party false positive. Return analysis and patches; do not re-run the suite."
   - C++ tree → **subagent_type="system-developer:cpp-developer"** (same prompt shape).
   - Ambiguous compiled language → **subagent_type="system-developer:system-developer"** (router) with the triage table and detected markers.
2. If `--fix`: route only the `mechanical` rows to the fixer:
   **Use Task tool with subagent_type="system-developer:sys-code-fixer"**
   Prompt: "Apply minimal, targeted fixes for these mechanical sanitizer findings: {mechanical_rows}. One fix per finding, smallest diff. Do NOT touch `interpretation`-class findings or add suppression files. Report each fix applied and anything you could not safely fix mechanically."
3. After fixes, re-run only the affected kind(s) to confirm the finding is gone. Report each cycle; do not loop silently.

## Output Format

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

### Triage

| # | Type | Location (top user frame) | Alloc / origin | Hits | Fix class |
|---|------|---------------------------|----------------|------|-----------|
| 1 | heap-use-after-free | parser.c:142 | alloc parser.c:88 | 3 | mechanical |
| 2 | data race on `cache_` | cache.cpp:54 | other write cache.cpp:71 | 1 | interpretation |
| … | | | | | |

**Result:** CLEAN / {K} findings ({mechanical} mechanical, {interp} interpretation, {fp} false-positive)

<!-- When findings exist: -->
### Routing
- Interpretation → system-developer:{c-developer | cpp-developer}
- Mechanical (--fix only) → system-developer:sys-code-fixer
- {fixed/remaining after re-run, per cycle}

<!-- On skipped kinds only: -->
### Skipped
- {kind}: {reason — e.g. MSan needs Clang + fully instrumented deps} — install hint printed above.
```

If a run produced **no** findings, say so plainly ("ASan+UBSan: clean over {N} tests") rather than manufacturing rows.

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
use /system-developer:lint-fix and -X dev; for Bash use /system-developer:lint-fix (shellcheck).
```

### MSan requested without Clang / instrumented deps
```
Warning: MSan requires Clang AND every linked dependency (incl. libc++) built with
-fsanitize=memory; uninstrumented deps produce false "uninitialized" reports.
Install hint: brew install llvm  (use that clang)
Skipping MSan. Recommend ASan+UBSan instead, or a fully instrumented toolchain.
```

### TSan requested alongside ASan
```
Error: ThreadSanitizer cannot share a binary with AddressSanitizer.
Run them separately: /system-developer:sanitize-check tsan .  then  asan .
(Or use `all`, which sequences ASan+UBSan and TSan into two builds.)
```

### Toolchain missing
Print the install hint, skip that kind, continue with the rest. Aggregate skips in the report.

| Missing tool | Install hint |
|--------------|--------------|
| `clang` / `llvm` (sanitizer runtimes, MSan) | `brew install llvm` |
| `cmake` / `ctest` | `brew install cmake ninja` |
| `uv` (Python native-ext run) | `curl -LsSf https://astral.sh/uv/install.sh \| sh` (verify against your toolchain) |

Only when *every* requested kind is skipped does the command report FAIL with the aggregated hints.

## See Also

- `skill: diagnostics` — sanitizer reference: per-sanitizer detail, combination rules, slowdown figures, the canonical CMake flag set, suppression-file format, and annotated report walkthroughs.
- `skill: secure-coding` — the memory-safety and input-validation patterns these findings map back to.
- `skill: language-detection` — language/build-system routing (and the Python native-extension tie-break).
- `/system-developer:build-test` — get a green ordinary build first; reuse its configure/compile/link triage on sanitized build failures.
- `/system-developer:code-review` — pairs static review with this runtime check (QA gate = tests pass AND ASan+UBSan clean).
- `/system-developer:profile-performance` — when the concern is speed, not correctness (also RelWithDebInfo).
