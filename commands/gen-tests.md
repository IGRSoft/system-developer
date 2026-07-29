---
description: Generate, register, and verify a runnable test suite for C, C++, Python, or Bash using the project's framework
argument-hint: [path (default .)] [--framework googletest|catch2|cmocka|unity|pytest|bats] [--coverage-gaps]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
estimated-cost:
  min-tokens: 3000
  max-tokens: 22000
  model-distribution:
    haiku: 15%
    sonnet: 75%
    opus: 10%
---

# Generate Tests
<!-- Updated: June 2026 -->

Generate a runnable test suite for C, C++, Python, or Bash code, register it with the project's build/test runner, and prove it compiles and runs before reporting success. The product is *passing, discoverable tests* — not test source files on disk.

[Extended thinking: The hard part of test generation is not writing assertions — it is honoring the project's existing framework, wiring the tests into the build so the runner discovers them, and proving they actually execute. This command refuses to introduce a second framework into a project that already has one, delegates the actual test authoring to sys-test-generator (which knows happy-path + edge-case + failure-mode coverage per language), then runs a verification gate that reuses build-test's detect-configure-build-test logic. A generated test that does not compile, or compiles but the runner never discovers, is a defect, not a deliverable. The command halts and routes the failure back rather than declaring victory.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **Detect the framework FIRST — never introduce a second one.** Before generating anything, scan for the framework already in use (see Phase 1). If the project already tests with GoogleTest, do NOT generate Catch2; if it uses pytest, do NOT add unittest; if `tests/*.bats` exists, do NOT write a different harness. `--framework` only *disambiguates* when detection is empty or genuinely ambiguous — it does NOT override an in-use framework. If `--framework` conflicts with what is already wired in, STOP and report the conflict.
2. **Delegate generation to sys-test-generator.** Do NOT author test bodies yourself. The agent owns happy-path + edge-case + failure-mode coverage. You own detection, registration, and verification.
3. **Registration is part of the deliverable.** A test that the runner cannot discover does not exist. After generation you MUST wire tests in: `add_executable`/`add_test` + `gtest_discover_tests`/`catch_discover_tests` (CMake), `conftest.py` fixtures + correct `tests/` layout (pytest), `setup()`/`teardown()` + `tests/*.bats` (bats). Verify registration by listing tests (`ctest -N`, `pytest --collect-only`, `bats -c`), not by eyeballing files.
4. **Verification gate is mandatory.** Generated tests MUST compile (C/C++) and MUST run (all languages). Reuse the detection + build + test logic from `/system-developer:build-test`. A suite that does not build, or builds but does not run, is a FAILURE — report it as such and route the error back to the matching language agent. Do NOT report success on un-run tests.
5. **Single-command Bash invocations.** Use toolchain directory flags (`cmake -S . -B build`, `ctest --test-dir build`, `uv run --project <path> pytest`, `bats <path>/tests/`). Never `cd`-chain or `&&`-chain directory changes — scoped Bash patterns do not match compound commands.
6. **Tool-missing never hard-fails.** If the framework's toolchain binary is absent, print the install hint, skip that language, and continue with the others. Report what was skipped. Never hard-fail the whole command for one missing tool.
7. **Never enter plan mode.** This command IS the procedure — execute it.

## Usage

```bash
# Detect the framework and generate + register + verify tests for the current dir
/system-developer:gen-tests .

# Generate tests for one module, picking the framework explicitly (empty project)
/system-developer:gen-tests src/parser --framework catch2

# Target untested branches surfaced by a coverage run
/system-developer:gen-tests . --coverage-gaps

# Bash CLI under test
/system-developer:gen-tests scripts/deploy.sh --framework bats
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | File, module, or directory to generate tests for. Detection scan is rooted at its enclosing project. |
| `--framework googletest\|catch2\|cmocka\|unity\|pytest\|bats` | auto-detect | Disambiguates ONLY when no framework is already in use. If a framework is already wired in, the in-use one wins and a mismatched `--framework` is an error (rule 1). `googletest`/`catch2` → C++; `cmocka`/`unity` → C; `pytest` → Python; `bats` → Bash. |
| `--coverage-gaps` | off | Run a coverage pass first (llvm-cov/gcovr for C/C++, `uv run pytest --cov` for Python, kcov for Bash) and target generation at uncovered branches/lines instead of generating broadly. Requires a buildable, already-runnable existing suite to measure against. |

## Framework Detection

Detection is the first and most important step. Scan top-down; the **in-use** framework always wins over `--framework`.

| Language | Scan for (in priority order) | Resolved framework |
|----------|------------------------------|--------------------|
| C++ | `find_package(GTest)` / `GTest::gtest_main` link in `CMakeLists.txt`; `FetchContent` of `googletest` | GoogleTest |
| C++ | `find_package(Catch2)` / `Catch2::Catch2WithMain`; `FetchContent` of `catchorg/Catch2` | Catch2 v3 |
| C | `find_package(cmocka)` / `-lcmocka`; CMocka headers (`<cmocka.h>`) | CMocka |
| C | `unity.c` / `<unity.h>` in tree | Unity |
| Python | `[tool.pytest.ini_options]` in `pyproject.toml`; `pytest` in `[dependency-groups]`/dev deps; existing `tests/test_*.py` using `pytest` fixtures | pytest |
| Bash | existing `tests/*.bats`; `bats` in CI config | bats-core |

Resolution rules:

- **In-use beats requested.** If the scan finds GoogleTest and the user passed `--framework catch2`, STOP — do not mix frameworks (Error Handling → "framework conflict").
- **Empty project + `--framework`.** No framework markers found and `--framework` given → use it, and the registration step scaffolds the dependency (FetchContent pin / `find_package` / `[tool.pytest.ini_options]` / `tests/` dir).
- **Empty project, no `--framework`.** Pick the framework matrix default for the detected language (`skill: testing-principles`): C++ → GoogleTest, C → CMocka, Python → pytest, Bash → bats. Announce the choice in the report.
- **Mixed-language repo.** Detect per language and generate per language; never cross frameworks. Language ownership follows `skill: language-detection`.

This routing is a specialization of the shared detection table — keep it in sync with `skill: language-detection`, do not fork it.

## Workflow

### Phase 1: Detect (Bash + Read)

1. Confirm `path` exists. If not, emit the Error Handling "path not found" message and stop.
2. Resolve the language(s) of `path` via `skill: language-detection` (extension census + manifest markers).
3. For each language, run Framework Detection. Record the **in-use** framework, or the resolved default when empty.
4. If `--framework` conflicts with an in-use framework, STOP and emit "framework conflict".
5. Verify the framework's toolchain exists (`command -v cmake`/`ctest` for GoogleTest/Catch2/CMocka builds; `command -v uv`/`pytest` for pytest; `command -v bats` for bats). If missing, print the install hint (Tool Availability), skip that language, continue.
6. Identify the units under test: public functions/classes (C/C++ headers), exported module symbols (Python `__all__`/public defs), and CLI entry points / functions (Bash). Read them so the generation prompt carries real signatures.

### Phase 2: Coverage Baseline (Bash) — only with `--coverage-gaps`

1. Require an existing suite that already builds and runs (otherwise there is nothing to measure). If none, fall back to broad generation and note it.
2. Run the coverage pass, teeing to `.context/logs/`:

   | Language | Coverage command |
   |----------|------------------|
   | C/C++ (CMake) | configure with coverage flags (`-DCMAKE_CXX_FLAGS="--coverage"` or `-fprofile-instr-generate -fcoverage-mapping`), build, `ctest --test-dir <path>/build`, then `gcovr -r <path>` or `llvm-cov report` |
   | Python | `uv run --project <path> pytest --cov=<package> --cov-report=term-missing` |
   | Bash | `kcov <path>/coverage <path>/tests/run.sh` (or per-script kcov), read the HTML/JSON summary |

3. Parse uncovered lines/branches. Build a gap list (`{file, symbol, uncovered branch/line}`) to hand the generator, so it targets the gaps rather than re-covering covered code.

### Phase 3: Generate (delegate to sys-test-generator)

Delegate per language. Pass the units under test, the resolved framework, and (if any) the coverage gap list. The agent must cover, for each unit: **happy path + edge cases + failure modes** — explicitly including allocation failure, `EINTR` / interrupted syscalls and partial reads, empty input, and non-UTF-8 / unicode paths where applicable.

- C++ tree:
  **Use Task tool with subagent_type="system-developer:sys-test-generator"**
  Prompt: "Generate {framework} tests for the C++ units in `{path}`: {signatures}. Framework is already in use / chosen: {framework} — do NOT introduce any other framework. Cover, per unit: happy path; edge cases (empty input, boundary sizes, max values, non-UTF-8 / unicode paths); failure modes (allocation failure, `EINTR`/partial reads, error-return paths, invalid arguments). Use AAA structure and `test_[unit]_[scenario]_[expected]` naming per `skill: testing-principles`. {coverage_gaps_block} Return the test source files and the exact CMake registration snippet (`add_executable` + link `{framework_target}` + `gtest_discover_tests`/`catch_discover_tests`). Do not run the build yourself; I run the verification gate."
- C tree → **subagent_type="system-developer:sys-test-generator"** (same prompt; framework = CMocka/Unity; registration = `add_executable` + `cmocka`/`unity` link + `add_test`).
- Python → **subagent_type="system-developer:sys-test-generator"**
  Prompt: "Generate pytest tests for the Python module(s) in `{path}`: {symbols}. pytest is the project framework — do NOT add unittest or another runner. Cover happy path; edge cases (empty/`None` input, boundary values, non-UTF-8 / unicode paths, large inputs); failure modes (exceptions, `EINTR`/interrupted I/O via mocked boundaries, resource-exhaustion paths). Use `@pytest.mark.parametrize` for input families and place shared fixtures in `conftest.py`. {coverage_gaps_block} Follow `skill: python-testing`. Return test files plus any new `conftest.py`; do not run the suite."
- Bash → **subagent_type="system-developer:sys-test-generator"**
  Prompt: "Generate bats-core tests for the Bash script(s)/functions in `{path}`: {entry_points}. bats is the project test harness — do NOT introduce another. Cover happy path; edge cases (empty args, paths with spaces and non-UTF-8 bytes, missing files); failure modes (nonzero exit codes, interrupted/`EINTR` reads, unset-variable paths). Use `setup()`/`teardown()` with `mktemp -d` for hermetic temp dirs. Follow `skill: bash-testing`. Return the `*.bats` files and any `setup`/`teardown` helpers; do not run them."

If the generator returns tests for a unit you did not ask for, or in a framework other than the resolved one, reject that portion and re-prompt — do not accept framework drift.

### Phase 4: Register (Write/Edit + Bash)

Wire the generated tests into the runner so it discovers them. Registration is verified by *listing*, not by reading source.

| Framework | Registration edits | Discovery check |
|-----------|--------------------|-----------------|
| GoogleTest | `add_executable(<name> <test>.cpp)` + `target_link_libraries(<name> PRIVATE <lib> GTest::gtest_main)` + `gtest_discover_tests(<name>)` (after `include(GoogleTest)`) | `ctest --test-dir <path>/build -N` lists the new cases |
| Catch2 v3 | `add_executable` + link `Catch2::Catch2WithMain` + `include(Catch)` + `catch_discover_tests(<name>)` | `ctest --test-dir <path>/build -N` |
| CMocka / Unity | `add_executable` + link `cmocka`/`unity` + `add_test(NAME <name> COMMAND <name>)` | `ctest --test-dir <path>/build -N` |
| pytest | place files as `tests/test_*.py`; add/extend `conftest.py`; ensure `[tool.pytest.ini_options] testpaths = ["tests"]` if absent | `uv run --project <path> pytest --collect-only -q` |
| bats | place files as `tests/*.bats`; add `setup()`/`teardown()` | `bats <path>/tests/ --count` (or `-c`) lists the new tests |

The C/C++ registration edits above are the **CMake** form. On a Meson project register with `test('<name>', executable('<name>', '<test>.cpp', dependencies: <dep>))` and discover with `meson test -C builddir --list`; on a plain Make project add the test binary to the `check` target and discover by running it. Never add a `CMakeLists.txt` to a project that builds with Meson or Make just to register a test — match the build system already in use, exactly as Rule 1 requires you to match the test framework already in use.

For empty-project scaffolding, also pin the dependency: FetchContent block (CMake), a `subprojects/*.wrap` (Meson), or the `[tool.pytest.ini_options]` / dev-dependency entry (Python). Keep the pin in step with `skill: build-systems` and `skill: python-tooling`.

### Phase 5: Verification Gate (Bash) — MANDATORY

Reuse `/system-developer:build-test`'s detect → configure → build → test logic. Tee to `.context/logs/gen-tests-<timestamp>.log`.

1. **Build (C/C++ only):** configure + build the test target with the **detected** build system's commands — take the pair from `/system-developer:build-test`'s Canonical Command Table (CMake, Meson, Make, or Autotools), not from this example.
   ```bash
   # CMake projects; use the Meson/Make row instead when that is what was detected
   cmake -S "$path" -B "$path/build" -DCMAKE_BUILD_TYPE=Debug 2>&1 | tee -a "$LOG"
   cmake --build "$path/build" -j 2>&1 | tee -a "$LOG"
   ```
   Capture `${PIPESTATUS[0]}`. If the test build does NOT compile → gate FAIL (stage `compile`/`link`). Route back per "Gate Failure."
2. **Discover:** run the framework's list/collect command (Phase 4 column). If the new tests are NOT discovered → gate FAIL (registration defect). Fix registration and re-list.
3. **Run:**

   | Framework | Run command |
   |-----------|-------------|
   | GoogleTest / Catch2 / CMocka / Unity | `ctest --test-dir <path>/build --output-on-failure` (Meson: `meson test -C builddir --print-errorlogs`; Make: `make -C <path> check`) |
   | pytest | `uv run --project <path> pytest -x -q` — on a non-uv project use its own runner (`pytest -x -q` inside the active venv, `tox`, …); never introduce uv into a project that does not use it |
   | bats | `bats <path>/tests/` |

   Capture `${PIPESTATUS[0]}`. **A suite that does not run is a FAILURE, not a deliverable.** New tests that fail because they expose a real bug → report as a finding (the test is correct, the code is not); new tests that fail because they are wrong → route back to the generator.
4. Only when the suite **builds, is discovered, and runs** do you report success.

### Phase 6: Report (Bash)

Emit the Output Format summary. State pass/fail of the verification gate explicitly — never imply success without it.

## Gate Failure (route back, do not declare victory)

When the verification gate fails, classify and delegate, then re-run from the failing phase:

| Failure | Cause | Route to |
|---------|-------|----------|
| Test build does not compile (C/C++) | Bad include, wrong link, API misuse in test | `system-developer:sys-test-generator` (fix the test) or `system-developer:cpp-developer` / `c-developer` (if the test exposed a header/API issue) |
| Tests not discovered | Missing `gtest_discover_tests`/`catch_discover_tests`/`add_test`, wrong `tests/` layout, missing `conftest.py` | Fix registration yourself (Phase 4), re-list |
| Test runs but a new test is wrong | Bad assertion / fixture | `system-developer:sys-test-generator` |
| Test runs and exposes a real bug | The code under test is broken | Report as a finding; route the fix to the owning language agent (`c-developer`/`cpp-developer`/`python-developer`/`bash-developer`) — do NOT weaken the test to make it pass |

Delegation prompt shape: "Generated-test verification failed at the **{stage}** stage for `{path}` ({framework}). Error and context from `{LOG}`:\n```\n{excerpt}\n```\nFix the {test|registration|code} minimally so the suite builds, is discovered, and runs. Return the patch; I re-run the gate." Re-run the gate after each fix; report each cycle. Never silently auto-iterate.

## Tool Availability

| Missing tool | Install hint |
|--------------|--------------|
| `cmake` / `ctest` / `clang` / `llvm-cov` | `brew install llvm` (and `brew install cmake ninja`) |
| GoogleTest / Catch2 / CMocka | fetched via FetchContent or `find_package`; ensure the package manager (`vcpkg`/`conan`) or `FetchContent` pin is present — see `skill: build-systems` |
| `gcovr` | `uv tool install gcovr` (verify against your toolchain) |
| `uv` / `pytest` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` (verify against your toolchain); pytest installs via `uv add --dev pytest` |
| `kcov` | `brew install kcov` |
| `bats` | `brew install bats-core` |

Never hard-fail on a missing tool — print the hint, skip that language, continue.

## Output Format

```markdown
## Generate Tests Report

**Target:** {path}
**Language(s):** {C | C++ | Python | Bash}
**Framework:** {GoogleTest | Catch2 | CMocka | Unity | pytest | bats} ({detected in-use | chosen via --framework | matrix default})
**Coverage mode:** {broad | --coverage-gaps targeting N gaps}
**Log:** .context/logs/gen-tests-{timestamp}.log

### Tests Generated ({count})

| File | Cases | Coverage focus |
|------|-------|----------------|
| tests/test_parser.cpp | 7 | happy path, empty input, alloc failure, non-UTF-8 path |
| ... | ... | ... |

### Registration
- {Wired into CMake via gtest_discover_tests | conftest.py + testpaths | tests/*.bats}
- Discovery check: {N tests now listed by ctest -N / pytest --collect-only / bats -c}

### Verification Gate
| Step | Result | Notes |
|------|--------|-------|
| Build (C/C++) | ✅ / ❌ / N/A | {warnings, or compile error} |
| Discover | ✅ / ❌ | {N new tests discovered} |
| Run | ✅ / ❌ | {N passed, M failed} |

**Gate:** PASS / FAIL ({failing step})

<!-- On gate failure only: -->
### Gate Failure
- **Stage:** {compile | link | discover | run}
- **Cause:** {one-line}
- **Routed to:** system-developer:{agent}
- **Status:** {patch applied + re-run PASS | awaiting fix | real bug surfaced — see finding}

<!-- When a new test exposed a real bug: -->
### Findings (tests correct, code under test failing)
- {file:line} — {what the test proved is broken} → fix routed to system-developer:{language-agent}

<!-- On skipped languages only: -->
### Skipped
- {language}: {missing tool} — install hint printed above.
```

## Error Handling

### Path not found
```
Error: Path not found: {path}
Suggestion: Pass a file or directory that exists, e.g. /system-developer:gen-tests src/
```

### Framework conflict
```
Error: --framework {requested} conflicts with the framework already in use ({detected}).
Mixing frameworks fragments the suite and the runner config.
Suggestion: Drop --framework to use {detected}, or migrate the whole suite first
(out of scope for this command).
```

### No framework, no language signal
```
Error: Could not resolve a language for {path} (no source extensions, manifests, or shebangs).
Suggestion: Point at the source file/module to test, or pass --framework to fix the language.
```

### --coverage-gaps with no runnable suite
```
Warning: --coverage-gaps needs an existing suite that already builds and runs to measure.
None found — falling back to broad generation. Run `/system-developer:gen-tests` once, then re-run
with --coverage-gaps to target the remaining gaps.
```

### Verification gate fails
Not silently ignored. The suite is reported FAIL with the failing step, the failure is routed back per "Gate Failure," and success is NOT reported until the suite builds, is discovered, and runs.

### Toolchain missing
Print the install hint from Tool Availability, skip that language, continue. Only when *every* targeted language is skipped does the command report FAIL with the aggregated install hints.

## See Also

- `/system-developer:build-test` — the detect/configure/build/test logic the verification gate reuses; run it first to confirm the project builds before adding tests.
- `/system-developer:sanitize-check` — run the new tests under ASan/UBSan/TSan once they are green (a first-class test type for C/C++).
- `/system-developer:review-code` — review the code before adding tests to it; `--coverage-gaps` pairs well after a review.
- `skill: testing-principles` — test pyramid, framework matrix, coverage targets, AAA/naming conventions.
- `skill: language-detection` — canonical marker → language → agent routing (keep the framework table in sync).
- `skill: python-testing`, `skill: bash-testing` — per-language test deep dives.
- `skill: diagnostics` — coverage tooling (llvm-cov/gcovr/kcov) and sanitizer integration.
