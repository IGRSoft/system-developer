---
description: Detect the build system, configure, build, and run the test suite for C, C++, Python, or Bash projects
argument-hint: [path (default .)] [--preset NAME] [--type Debug|Release] [--clean] [--no-test]
allowed-tools: Read, Glob, Grep, Bash
estimated-cost:
  min-tokens: 1500
  max-tokens: 12000
  model-distribution:
    haiku: 40%
    sonnet: 55%
    opus: 5%
---

# Build & Test
<!-- Updated: June 2026 -->

Detect a project's build system, configure it, build it, and run its tests with a single command. The happy path is pure Bash — no agent delegation. Agents are only engaged when the build or tests fail, and only the language agent that owns the failing layer is consulted, with the relevant log excerpt.

[Extended thinking: This command is the detection-and-execution workhorse other system-developer commands reuse. It resolves exactly one build system per invocation via a strict priority order, runs the canonical configure/build/test sequence for that system, and tees everything to a timestamped log. Because configure/build/link/test failures have sharply different fixes, on failure it parses the first error, classifies the stage, and hands the matching language agent a tight excerpt instead of the whole log. Keep the green path deterministic and shell-only so it stays cheap and scriptable.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **Resolve exactly one build system.** Walk the detection priority order top-down and stop at the first match. Do NOT run two build systems in one invocation. If the user disagrees with the auto-detected system, they re-run with an explicit path to the subdirectory that holds the right manifest.
2. **Happy path is shell-only.** When configure, build, and test all succeed, do NOT delegate to any agent. Report the result and stop.
3. **Single-command Bash invocations.** Use the toolchain's own directory flags (`cmake -S . -B build`, `cmake --build build`, `ctest --test-dir build`, `make -C dir`, `meson -C builddir`, `uv run`, `bats tests/`). Never `cd`-chain or `&&`-chain directory changes — scoped Bash patterns do not match compound commands.
4. **Tee every phase to the log.** Each configure/build/test command pipes through `tee -a` to `.context/logs/build-<timestamp>.log`. The log is the single source of truth for triage; do not rely on terminal scrollback.
5. **On failure, classify before delegating.** Parse the first error from the log, classify it as configure / compile / link / test, then delegate ONLY to the matching language agent with the excerpt — never the whole log, never a second agent "just in case."
6. **Tool-missing never hard-fails.** If the required toolchain binary is absent, print the install hint, skip that build system, and continue to the next eligible one in the priority order. Report what was skipped.
7. **Never enter plan mode.** This command IS the procedure — execute it.

## Usage

```bash
# Detect, configure, build, and test the current directory
/system-developer:build-test .

# Build a specific subproject
/system-developer:build-test services/parser

# Use a named CMake preset
/system-developer:build-test . --preset ci-release

# Release build, fresh configure, no tests
/system-developer:build-test . --type Release --clean --no-test
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | Directory to detect and operate on. The detection scan is rooted here. |
| `--preset NAME` | none | For CMake projects with `CMakePresets.json`, configure/build/test the named preset (`cmake --preset NAME`). Ignored by non-CMake systems with a warning. |
| `--type Debug\|Release` | `Debug` | Single-config generators: passes `-DCMAKE_BUILD_TYPE=`; Meson: `--buildtype debug\|release`. Ignored when `--preset` carries its own config. |
| `--clean` | off | Remove the build directory (`build/`, `builddir/`) before configuring, forcing a fresh configure. For Make, run `make clean` first. Python/Bats: no-op. |
| `--no-test` | off | Configure and build only; skip the test phase. |

`--preset` and `--type` are mutually informative: a preset that fixes `CMAKE_BUILD_TYPE` wins; `--type` only applies when the chosen path does not already pin a config.

## Detection: Build-System Priority

Scan `path` and apply the **first** match top-down. This is the canonical priority for this plugin; the marker → language → agent map lives in `skill: language-detection` — keep this list in sync with it, do not fork the routing logic.

| Priority | Marker | Build system | Owning agent (on failure) |
|----------|--------|--------------|---------------------------|
| 1 | `CMakePresets.json` | CMake (preset flow) | C or C++ — see language tie-break |
| 2 | `CMakeLists.txt` | CMake (classic `-S`/`-B` flow) | C or C++ — see language tie-break |
| 3 | `meson.build` | Meson | C or C++ — see language tie-break |
| 4 | `Makefile` / `GNUmakefile` | Make | C or C++ — see language tie-break |
| 5 | `configure.ac` / `configure` | Autotools | C (default) |
| 6 | `pyproject.toml` / `uv.lock` | Python (uv) | `python-developer` |
| 7 | `*.bats` under `tests/` (and no compiled-build marker above) | Bats (Bash) | `bash-developer` |

**Language tie-break for CMake / Meson / Make** (per `skill: language-detection`): a tree whose targets/sources are only `.c`/`.h` (e.g. `project(x C)`, no `CMAKE_CXX_STANDARD`) routes failures to `c-developer`; any `.cpp`/`.cc`/`.cxx`/`.hpp` source, `project(x CXX)`, or `CMAKE_CXX_STANDARD` routes to `cpp-developer`. When ambiguous, route to `system-developer:system-developer`.

**Tie-break notes:**

- A repo can carry both a compiled-build marker and `pyproject.toml` (Python with a native extension). The compiled marker wins for *this* command's primary build; mention the Python layer in the summary and suggest a second `--no-test`-free run scoped to the Python subdir if its tests matter. FFI coordination itself is the router's job (`skill: language-detection`, tie-break 4).
- A `Makefile` that only wraps shell/phony targets is repo tooling, not a C/C++ build — if no compiler invocation appears, treat it as a thin wrapper and prefer the next real marker.
- Auxiliary `scripts/*.sh` never make a compiled project a Bash project.

## Canonical Command Table

Run these verbatim (substituting `path`, build dir, preset, and type). Every command is single-invocation and tees to the log.

| System | Configure | Build | Test |
|--------|-----------|-------|------|
| CMake (preset) | `cmake --preset <PRESET>` | `cmake --build --preset <PRESET>` (fallback `cmake --build build -j`) | `ctest --preset <PRESET> --output-on-failure` (fallback `ctest --test-dir build --output-on-failure`) |
| CMake (classic) | `cmake -S <path> -B <path>/build -DCMAKE_BUILD_TYPE=<TYPE>` | `cmake --build <path>/build -j` | `ctest --test-dir <path>/build --output-on-failure` |
| Meson | `meson setup <path>/builddir <path> --buildtype <debug\|release>` | `meson compile -C <path>/builddir` | `meson test -C <path>/builddir --print-errorlogs` |
| Make | (none; or `./configure` for Autotools) | `make -C <path> -j` | `make -C <path> check` (fallback `make -C <path> test`) |
| Autotools | `autoreconf -i <path>` then `<path>/configure` (run from `path` via `make -C`-style flags where possible) | `make -C <path> -j` | `make -C <path> check` |
| Python (uv) | `uv sync --project <path>` | (no separate build; `uv sync` resolves the env) | `uv run --project <path> pytest -x -q` |
| Bats | (none) | (none) | `bats <path>/tests/` |

Notes:
- `-j` with no argument lets the tool pick a parallelism level; pass an explicit count only if the user requests it.
- For CMake presets, prefer the `--preset` variants; fall back to the classic `build/`-dir variants when the preset lacks a build or test stage.
- `make check` is the GNU convention; if the project has no `check` target, fall back to `test`, and if neither exists, report "no test target" rather than failing.

## Workflow

### Phase 1: Detect (Bash)

1. Confirm `path` exists. If not, emit the Error Handling "path not found" message and stop.
2. Create `.context/logs/` if absent. Compute `TS="$(date +%Y%m%d-%H%M%S)"` and `LOG=".context/logs/build-${TS}.log"`.
3. Walk the detection priority table top-down; record the first matching marker and its build system. If nothing matches, emit "no recognized build system" and stop.
4. For CMake / Meson / Make, apply the language tie-break to pre-resolve the owning agent (used only if a later phase fails).
5. Verify the required tool is installed (`command -v cmake`/`meson`/`make`/`ctest`/`uv`/`bats`). If missing, print the install hint (see Tool Availability), skip to the next eligible marker, and note the skip in the summary.

### Phase 2: Configure (Bash)

1. If `--clean`: remove `build/` or `builddir/` (CMake/Meson) or run `make -C <path> clean` (Make) before configuring. No-op for Python/Bats.
2. Run the configure command from the table, teeing to the log:
   ```bash
   cmake -S "$path" -B "$path/build" -DCMAKE_BUILD_TYPE="$type" 2>&1 | tee -a "$LOG"
   ```
3. Capture the exit status (`${PIPESTATUS[0]}`, not `tee`'s). On non-zero, go to Failure Triage with stage `configure`.

### Phase 3: Build (Bash)

1. Run the build command from the table, teeing to the log.
2. Capture `${PIPESTATUS[0]}`. On non-zero, classify the first error as `compile` or `link` (see Failure Triage classification) and go to Failure Triage with that stage.

### Phase 4: Test (Bash)

1. If `--no-test`: skip this phase; record "tests skipped (--no-test)" in the summary.
2. Run the test command from the table, teeing to the log.
3. Capture `${PIPESTATUS[0]}`. On non-zero, go to Failure Triage with stage `test`.

### Phase 5: Report (Bash)

Emit the Output Format summary. On full success, stop — no delegation.

## Failure Triage

Triggered only when a phase exits non-zero. Steps:

1. **Parse the first error** from the log. Search top-down for the first line matching the active toolchain's error format (e.g. `error:` for GCC/Clang, `CMake Error` for CMake, `undefined reference`/`Undefined symbols` for the linker, `FAILED`/`assert`/`Error:` for tests).
2. **Classify the stage:**

   | Symptom in log | Stage |
   |----------------|-------|
   | `CMake Error`, `Could NOT find <Pkg>`, `meson.build:...:ERROR`, `No such file or directory` for a manifest/dependency, generator/toolchain not found | `configure` |
   | Compiler `error:` / `note:`, template/concept diagnostics, `fatal error: <header>` not found in a source TU | `compile` |
   | `undefined reference to`, `Undefined symbols for architecture`, `ld: ` / `lld: ` errors, duplicate symbol, missing `-l<lib>` | `link` |
   | `ctest` failures, `pytest` `FAILED`/`ERROR`, `bats` `not ok`, assertion/expectation failures, nonzero test exit | `test` |

3. **Extract a tight excerpt** — the first error plus ~10 surrounding lines of context (the diagnostic and its `note:`/backtrace), not the whole log. Include the log path so the agent can read more if needed.
4. **Delegate to the matching language agent** with the excerpt. Use the agent resolved by the language tie-break (Phase 1) for compiled systems; Python failures go to `python-developer`; Bats failures go to `bash-developer`.

   - configure / compile / link / test on a C tree:
     **Use Task tool with subagent_type="system-developer:c-developer"**
     Prompt: "Build-test failed at the **{stage}** stage for the C project at `{path}` (build system: {system}). First error and context from `{LOG}`:\n```\n{excerpt}\n```\nDiagnose the root cause and propose the minimal fix. If the fix touches the build configuration, say so explicitly. Do not run the full build yourself; return the analysis and patch."
   - C++ tree → **subagent_type="system-developer:cpp-developer"** (same prompt shape).
   - Python (`pyproject.toml`/`uv.lock`) → **subagent_type="system-developer:python-developer"**
     Prompt: "Build-test failed at the **{stage}** stage for the Python project at `{path}` (uv). First error and context from `{LOG}`:\n```\n{excerpt}\n```\nDiagnose and propose the minimal fix (dependency resolution, import error, or failing test). Return analysis and patch; do not re-run the suite."
   - Bats (`*.bats`) → **subagent_type="system-developer:bash-developer"** (same prompt shape, stage will be `test`).
   - Ambiguous language for a compiled system → **subagent_type="system-developer:system-developer"** (router) with the excerpt and detected markers.

5. After the agent returns a fix, re-run from the failing phase (re-configure if the fix touched configure inputs, otherwise rebuild/retest). Do NOT auto-apply across multiple iterations silently — report each cycle.

## Tool Availability

Before running each system, confirm its tool exists. If missing, print the hint, skip the system, continue down the priority list, and note the skip.

| Missing tool | Install hint |
|--------------|--------------|
| `cmake` / `ctest` / `clang` / `llvm` utilities | `brew install llvm` (and `brew install cmake ninja`) |
| `meson` | `brew install meson ninja` (or `uv tool install meson`) |
| `make` | install your platform's base build tools (`xcode-select --install` on macOS / distro `build-essential`) |
| `uv` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` (verify against your toolchain) |
| `bats` | `brew install bats-core` |

Never hard-fail on a missing tool — skip and report.

## Output Format

```markdown
## Build & Test Report

**Target:** {path}
**Build system:** {system} ({marker})
**Owning language:** {C | C++ | Python | Bash}
**Log:** .context/logs/build-{timestamp}.log

| Phase | Result | Notes |
|-------|--------|-------|
| Configure | ✅ / ❌ / ⏭ skipped | {preset/type, or skip reason} |
| Build | ✅ / ❌ / ⏭ | {warnings count, if any} |
| Test | ✅ / ❌ / ⏭ | {N passed, M failed, or "--no-test"} |

**Result:** PASS / FAIL ({failing stage})

<!-- On failure only: -->
### Failure Triage
- **Stage:** {configure | compile | link | test}
- **First error:** {one-line summary}
- **Delegated to:** system-developer:{agent}
- **Proposed fix:** {summary from agent, or "see agent output"}

<!-- On skipped systems only: -->
### Skipped
- {system}: {missing tool} — install hint printed above.
```

## Error Handling

### Path not found
```
Error: Path not found: {path}
Suggestion: Pass a directory that exists, e.g. /system-developer:build-test .
```

### No recognized build system
```
Error: No build system detected under {path}.
Looked for: CMakePresets.json, CMakeLists.txt, meson.build, Makefile,
configure.ac, pyproject.toml/uv.lock, tests/*.bats.
Suggestion: Run from the directory that holds the manifest, or scaffold one.
```

### No test target (Make)
Not an error. Report "no `check`/`test` target found — build succeeded, tests skipped" and treat the run as PASS for build, N/A for test.

### Preset on a non-CMake project
```
Warning: --preset is CMake-only; ignored for {system} project.
Proceeding with --type {type}.
```

### Toolchain missing
Print the install hint from Tool Availability, skip the system, continue. Only when *every* eligible system is skipped does the command report FAIL with the aggregated install hints.

## See Also

- `skill: language-detection` — canonical marker → language → agent routing (keep the priority table in sync).
- `skill: build-systems` — CMake presets, Meson/Make idioms, CMake 4.x policy-version compat, FetchContent vs vcpkg vs Conan.
- `/system-developer:fix-quick` — run linters/formatters before building to cut noise.
- `/system-developer:sanitize-check` — once the build is green, run ASan/UBSan/TSan over it.
- `/system-developer:gen-tests` — add a test suite when detection finds no test target.
- `/system-developer:deps` — when a `configure`-stage failure is a missing or outdated dependency.
