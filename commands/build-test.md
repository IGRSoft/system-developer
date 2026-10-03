---
description: Detect the build system, configure, build, and run the test suite for C, C++, Python, or Bash projects
argument-hint: [path (default .)] [--preset NAME] [--type Debug|Release] [--clean] [--no-test]
allowed-tools: Read, Glob, Grep, Bash, Edit, Agent
estimated-cost:
  min-tokens: 1500
  max-tokens: 12000
  model-distribution:
    haiku: 40%
    sonnet: 55%
    opus: 5%
---

# Build & Test

Detect a project's build system, configure it, build it, and run its tests. Other system-developer commands use this as their build/test gate, so the green path stays deterministic, shell-only, and cheap: no agent is involved unless a phase fails, and then only the language agent that owns the failing layer, with a log excerpt.

## Rules

- Resolve exactly one build system per run: the first match in the priority table. To pick a different one, the user re-runs with the path of the subdirectory holding the right manifest.
- On success, report and stop. No delegation.
- Use the toolchain's own directory flags (`cmake -S/-B`, `--test-dir`, `make -C`, `meson -C`, `uv --project`) instead of `cd`.
- Tee every configure/build/test command with `tee -a` to `.context/logs/build-<timestamp>.log`; triage reads the log, not scrollback. Take the command's own exit status, not `tee`'s (`set -o pipefail` works in both bash and zsh).
- A missing toolchain binary never hard-fails: print the install hint, skip that system, try the next eligible marker, and report the skip.

## Usage

```bash
/system-developer:build-test .                                   # detect, configure, build, test
/system-developer:build-test services/parser                     # a subproject
/system-developer:build-test . --preset ci-release               # named CMake preset
/system-developer:build-test . --type Release --clean --no-test  # fresh Release build, no tests
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | Directory to detect and operate on. |
| `--preset NAME` | none | CMake with `CMakePresets.json`: configure/build/test the named preset. Other systems ignore it with a warning. |
| `--type Debug\|Release` | `Debug` | CMake single-config: `-DCMAKE_BUILD_TYPE=`; Meson: `--buildtype debug\|release`. A preset that pins its own config wins. |
| `--clean` | off | Remove `build/` or `builddir/` before configuring; Make runs `make clean` first. No-op for Python/Bats. |
| `--no-test` | off | Configure and build only. |

## Detection: Build-System Priority

Scan `path`; the first match wins.

| Priority | Marker | Build system | Owning agent (on failure) |
|----------|--------|--------------|---------------------------|
| 1 | `CMakePresets.json` | CMake (preset flow) | C or C++ (tie-break below) |
| 2 | `CMakeLists.txt` | CMake (classic `-S`/`-B` flow) | C or C++ |
| 3 | `meson.build` | Meson | C or C++ |
| 4 | `Makefile` / `GNUmakefile` | Make | C or C++ |
| 5 | `configure.ac` / `configure` | Autotools | `c-developer` |
| 6 | `pyproject.toml` / `uv.lock` | Python (uv) | `python-developer` |
| 7 | `*.bats` under `tests/`, no marker above | Bats (Bash) | `bash-developer` |

### Owning agent and tie-breaks

**C vs C++ for CMake/Meson/Make:** only `.c`/`.h` sources (e.g. `project(x C)`, no `CMAKE_CXX_STANDARD`) → `c-developer`; any `.cpp`/`.cc`/`.cxx`/`.hpp` source, `project(x CXX)`, or `CMAKE_CXX_STANDARD` → `cpp-developer`; ambiguous → `system-developer` (router).

- A compiled marker plus `pyproject.toml` (Python with a native extension): the compiled build is primary. Mention the Python layer in the summary and suggest a second run scoped to the Python subdir if its tests matter.
- A `Makefile` with only shell/phony targets and no compiler invocation is repo tooling; use the next real marker.
- `scripts/*.sh` never make a compiled project a Bash project.

## Canonical Command Table

Substitute `path`, build dir, preset, and type.

### CMake

| System | Configure | Build | Test |
|--------|-----------|-------|------|
| CMake (preset) | `cmake --preset <PRESET>` | `cmake --build --preset <PRESET>` (fallback `cmake --build build -j`) | `ctest --preset <PRESET> --output-on-failure` (fallback `ctest --test-dir build --output-on-failure`) |
| CMake (classic) | `cmake -S <path> -B <path>/build -DCMAKE_BUILD_TYPE=<TYPE>` | `cmake --build <path>/build -j` | `ctest --test-dir <path>/build --output-on-failure` |

### Meson, Make, Autotools, Python, Bats

| System | Configure | Build | Test |
|--------|-----------|-------|------|
| Meson | `meson setup <path>/builddir <path> --buildtype <debug\|release>` | `meson compile -C <path>/builddir` | `meson test -C <path>/builddir --print-errorlogs` |
| Make | (none) | `make -C <path> -j` | `make -C <path> check` (fallback `make -C <path> test`) |
| Autotools | `autoreconf -i <path>` then `<path>/configure` | `make -C <path> -j` | `make -C <path> check` |
| Python (uv) | `uv sync --project <path>` | (none; `uv sync` resolves the env) | `uv run --project <path> pytest -x -q` |
| Bats | (none) | (none) | `bats <path>/tests/` |

- Bare `-j` lets the tool choose parallelism; pass a count only if the user asks.
- Use the preset fallbacks when the preset has no build or test stage.
- Make with neither `check` nor `test`: report "no test target" (build PASS, test N/A), not a failure.

## Workflow

1. **Detect.** Stop with the matching Error Handling message if `path` is missing or no marker matches. Create `.context/logs/`, set `LOG=.context/logs/build-$(date +%Y%m%d-%H%M%S).log`, pick the build system, pre-resolve the owning agent, and check the tool with `command -v`.
2. **Configure.** Apply `--clean` first, then run the configure command. Non-zero → Failure Triage, stage `configure`.
3. **Build.** Non-zero → Failure Triage, stage `compile` or `link`.
4. **Test.** Skip with `--no-test` and note it. Non-zero → Failure Triage, stage `test`.
5. **Report** in the Output Format.

## Failure Triage

### Classify the first error

1. Find the first error in the log (`error:` for GCC/Clang, `CMake Error`, `undefined reference`/`Undefined symbols` for the linker, `FAILED`/`not ok`/assertion output for tests) and classify it:

   | Symptom in log | Stage |
   |----------------|-------|
   | `CMake Error`, `Could NOT find <Pkg>`, `meson.build:...:ERROR`, missing manifest/dependency, generator/toolchain not found | `configure` |
   | Compiler `error:`/`note:`, template/concept diagnostics, `fatal error: <header>` not found | `compile` |
   | `undefined reference to`, `Undefined symbols for architecture`, `ld:`/`lld:` errors, duplicate symbol, missing `-l<lib>` | `link` |
   | `ctest` failures, pytest `FAILED`/`ERROR`, bats `not ok`, assertion failures, nonzero test exit | `test` |

### Delegate the fix

2. Extract the first error with about 10 lines of context (the diagnostic and its notes or backtrace), not the whole log.
3. Delegate with the Agent tool to the owning agent only: `system-developer:c-developer`, `cpp-developer`, `python-developer`, `bash-developer`, or `system-developer` (router, also given the detected markers) when the language is ambiguous. Prompt:

   "Build-test failed at the **{stage}** stage for the {language} project at `{path}` (build system: {system}). First error and context from `{LOG}` (read more there if needed):
   ```
   {excerpt}
   ```
   Diagnose the root cause and propose the minimal fix (C/C++: say explicitly if it touches the build configuration; Python: dependency resolution, import error, or failing test). Return the analysis and patch; don't re-run the build or suite."

### Re-run

4. After a fix, re-run from the failing phase (re-configure if configure inputs changed). Report each cycle rather than iterating silently.

## Tool Availability

| Missing tool | Install hint |
|--------------|--------------|
| `cmake` / `ctest` / `clang` / `llvm` utilities | `brew install llvm` (and `brew install cmake ninja`) |
| `meson` | `brew install meson ninja` (or `uv tool install meson`) |
| `make` | platform base build tools (`xcode-select --install` on macOS, `build-essential` on Debian/Ubuntu) |
| `uv` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| `bats` | `brew install bats-core` |

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

### Preset on a non-CMake project
```
Warning: --preset is CMake-only; ignored for {system} project.
Proceeding with --type {type}.
```

### Toolchain missing
Skip and continue as above. Only when every eligible system is skipped, report FAIL with the aggregated install hints.

## See Also

- `skill: build-systems` — CMake presets, Meson/Make idioms, CMake 4.x policy-version compat, FetchContent vs vcpkg vs Conan.
- `/system-developer:fix-quick` — lint/format before building to cut noise.
- `/system-developer:sanitize-check` — ASan/UBSan/TSan once the build is green.
- `/system-developer:gen-tests` — add a suite when there is no test target.
- `/system-developer:deps` — when a configure failure is a missing or outdated dependency.
