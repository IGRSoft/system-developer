---
description: Generate, register, and verify a runnable test suite for C, C++, Python, or Bash using the project's framework
argument-hint: [path (default .)] [--framework googletest|catch2|cmocka|unity|pytest|bats] [--coverage-gaps]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
estimated-cost:
  min-tokens: 3000
  max-tokens: 22000
  model-distribution:
    haiku: 15%
    sonnet: 75%
    opus: 10%
---

# Generate Tests

Generate tests for C, C++, Python, or Bash code, register them with the project's runner, and prove they build and run. The deliverable is passing, discoverable tests, not test files on disk.

## Rules

### Framework and ownership

- Use the framework already in use; never add a second one (no Catch2 beside GoogleTest, no unittest beside pytest, no other harness beside `tests/*.bats`). `--framework` only chooses when nothing is in use. If it conflicts with an in-use framework, stop with "Framework conflict".
- Match the build system already in use the same way: never add a `CMakeLists.txt` to a Meson or Make project just to register a test.
- `system-developer:sys-test-generator` writes the test bodies. You own detection, registration, and verification.
- Registration is part of the deliverable. Prove it by listing tests (`ctest -N`, `pytest --collect-only`, `bats -c`), not by reading files.

### Success and execution

- Report success only when the new tests build (C/C++), are discovered, and run. Anything less is a gate FAIL, routed back per Gate Failure.
- One command per Bash call, using the tool's directory flag (`cmake -S . -B build`, `ctest --test-dir build`, `uv run --project <path> pytest`, `bats <path>/tests/`), because scoped Bash permissions don't match `cd`/`&&` chains.
- A missing toolchain skips that language with its install hint; the run continues with the others. It fails only when every targeted language is skipped.

## Usage

```bash
/system-developer:gen-tests .                                   # detect, generate, register, verify
/system-developer:gen-tests src/parser --framework catch2       # empty project: pick the framework
/system-developer:gen-tests . --coverage-gaps                   # target uncovered branches
/system-developer:gen-tests scripts/deploy.sh --framework bats
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | File, module, or directory to test. Detection is rooted at its enclosing project. |
| `--framework googletest\|catch2\|cmocka\|unity\|pytest\|bats` | auto | Used only when no framework is in use. `googletest`/`catch2` → C++, `cmocka`/`unity` → C, `pytest` → Python, `bats` → Bash. |
| `--coverage-gaps` | off | Measure coverage of the existing suite first and generate only for uncovered branches/lines. Needs a suite that already builds and runs. |

## Framework Detection

| Language | Markers (priority order) | Framework |
|----------|--------------------------|-----------|
| C++ | `find_package(GTest)` / `GTest::gtest_main` in `CMakeLists.txt`; `FetchContent` of `googletest` | GoogleTest |
| C++ | `find_package(Catch2)` / `Catch2::Catch2WithMain`; `FetchContent` of `catchorg/Catch2` | Catch2 v3 |
| C | `find_package(cmocka)` / `-lcmocka`; `<cmocka.h>` | CMocka |
| C | `unity.c` / `<unity.h>` in tree | Unity |
| Python | `[tool.pytest.ini_options]` in `pyproject.toml`; `pytest` in `[dependency-groups]`/dev deps; `tests/test_*.py` using pytest fixtures | pytest |
| Bash | `tests/*.bats`; `bats` in CI config | bats-core |

### When nothing is in use

- No framework and `--framework` given: use it; registration scaffolds the dependency.
- No framework, no flag: C++ → GoogleTest, C → Unity, Python → pytest, Bash → bats. Announce the choice.
- Language comes from file extensions and manifests (shebang for extensionless scripts). A bare `.h` is C unless the tree has C++ sources or `CMAKE_CXX_STANDARD`. In a mixed repo, detect and generate per language; never cross frameworks.

## Workflow

### 1. Detect

1. Confirm `path` exists, else stop with "Path not found".
2. Resolve the language(s), else stop with "No language signal". Run Framework Detection per language; stop on a `--framework` conflict.
3. Check the toolchain (`cmake`/`ctest`, or the detected Meson/Make tool, for C/C++; `uv`/`pytest`; `bats`). Missing → install hint, skip that language.
4. Read the units under test so the prompt carries real signatures: public functions/classes in C/C++ headers, public Python symbols (`__all__` or non-`_` defs), Bash CLI entry points and functions.

### 2. Coverage baseline (`--coverage-gaps` only)

If no existing suite builds and runs, fall back to broad generation with the "--coverage-gaps with no runnable suite" warning. Otherwise run coverage, teeing to `.context/logs/`:

| Language | Coverage |
|----------|----------|
| C/C++ (CMake) | configure with `--coverage` (GCC) or `-fprofile-instr-generate -fcoverage-mapping` (Clang), build, `ctest --test-dir <path>/build`, then `gcovr -r <path>` or `llvm-cov report` |
| Python | `uv run --project <path> pytest --cov=<package> --cov-report=term-missing` |
| Bash | `kcov <path>/coverage <path>/tests/run.sh` (or per script), read the summary |

Turn uncovered lines/branches into a gap list (`{file, symbol, uncovered branch/line}`) for the generator.

### 3. Generate

One Agent tool call per language, `subagent_type: system-developer:sys-test-generator`:

> Generate {framework} tests for the {language} units in `{path}`: {signatures}. {framework} is the project's framework; do not introduce any other. Cover each unit's happy path, edge cases, and failure modes: {language focus}. Use Arrange-Act-Assert and `test_[unit]_[scenario]_[expected]` naming. {If --coverage-gaps: Target only these gaps: {gap_list}.} Write the files into the project's test tree, but don't register or run them; I do both. Return the files written, case count per file with coverage focus, and {registration need}.

#### Focus: C and C++

| Language | Focus | Registration need |
|----------|-------|-------------------|
| C++ | empty input, boundary sizes, max values, non-UTF-8/unicode paths; allocation failure, `EINTR`/partial reads, error returns, invalid arguments | the exact build snippet (`add_executable` + link `{framework_target}` + `gtest_discover_tests`/`catch_discover_tests`, or the Meson/Make equivalent) |
| C | same as C++ | the build snippet (`add_executable` + link `cmocka`/`unity` + `add_test`, or the Meson/Make equivalent) |

#### Focus: Python and Bash

| Language | Focus | Registration need |
|----------|-------|-------------------|
| Python | empty/`None` input, boundary values, non-UTF-8/unicode paths, large inputs; exceptions, interrupted I/O via mocked boundaries, resource exhaustion. `@pytest.mark.parametrize` for input families, shared fixtures in `conftest.py` | any new `conftest.py` |
| Bash | empty args, paths with spaces and non-UTF-8 bytes, missing files; nonzero exits, interrupted reads, unset-variable paths. `setup()`/`teardown()` with `mktemp -d` | any shared helpers |

Reject output for units you didn't ask for or in another framework, and re-prompt.

### 4. Register

| Framework | Edits | Discovery check |
|-----------|-------|-----------------|
| GoogleTest | `include(GoogleTest)`, `add_executable(<name> <test>.cpp)`, `target_link_libraries(<name> PRIVATE <lib> GTest::gtest_main)`, `gtest_discover_tests(<name>)` | `ctest --test-dir <path>/build -N` |
| Catch2 v3 | `add_executable`, link `Catch2::Catch2WithMain`, `include(Catch)`, `catch_discover_tests(<name>)` | `ctest --test-dir <path>/build -N` |
| CMocka / Unity | `add_executable`, link `cmocka`/`unity`, `add_test(NAME <name> COMMAND <name>)` | `ctest --test-dir <path>/build -N` |
| pytest | files as `tests/test_*.py`, extend `conftest.py`, add `[tool.pytest.ini_options] testpaths = ["tests"]` if absent | `uv run --project <path> pytest --collect-only -q` |
| bats | files as `tests/*.bats` with `setup()`/`teardown()` | `bats <path>/tests/ --count` |

#### Meson, Make, and empty projects

The C/C++ rows are the CMake form. Meson: `test('<name>', executable('<name>', '<test>.cpp', dependencies: <dep>))`, discovered with `meson test -C builddir --list`. Plain Make: add the binary to the `check` target and discover by running it.

For an empty project, also pin the dependency: a FetchContent block (CMake), a `subprojects/*.wrap` (Meson), or the `[tool.pytest.ini_options]` + dev-dependency entry (Python).

### 5. Verification gate

Run each command with `set -o pipefail`, teeing to `.context/logs/gen-tests-<timestamp>.log`, so the tool's exit status survives `tee`.

1. **Build (C/C++).** Configure and build with the detected build system's pair from `/system-developer:build-test`'s Canonical Command Table (CMake, Meson, Make, or Autotools), e.g. for CMake:
   ```bash
   set -o pipefail; cmake -S "$path" -B "$path/build" -DCMAKE_BUILD_TYPE=Debug 2>&1 | tee -a "$LOG"
   set -o pipefail; cmake --build "$path/build" -j 2>&1 | tee -a "$LOG"
   ```
   A compile or link failure fails the gate.
2. **Discover.** Run the step 4 discovery check. New tests missing from the list is a registration defect: fix it and re-list.
#### Run

3. **Run.**

   | Framework | Run |
   |-----------|-----|
   | GoogleTest / Catch2 / CMocka / Unity | `ctest --test-dir <path>/build --output-on-failure` (Meson: `meson test -C builddir --print-errorlogs`; Make: `make -C <path> check`) |
   | pytest | `uv run --project <path> pytest -x -q`; on a non-uv project use its own runner (`pytest -x -q` in the active venv, `tox`) and don't introduce uv |
   | bats | `bats <path>/tests/` |

   A new test that fails because it exposes a real bug is a finding (the test is right, the code isn't). A new test that is itself wrong goes back to the generator.

### 6. Report

Emit the Output Format, stating the gate result explicitly.

## Gate Failure

Classify, delegate, then re-run the gate from the failing step. Report each cycle; don't loop silently.

| Failure | Route to |
|---------|----------|
| Test build doesn't compile (bad include, wrong link, API misuse) | `system-developer:sys-test-generator`, or `system-developer:cpp-developer` / `c-developer` if the test exposed a header/API issue |
| Tests not discovered (missing discover/`add_test`, wrong `tests/` layout, missing `conftest.py`) | Fix registration yourself (step 4) and re-list |
| A new test is wrong (bad assertion or fixture) | `system-developer:sys-test-generator` |
| A new test exposes a real bug | Report as a finding and route the fix to the owning agent (`c-developer`, `cpp-developer`, `python-developer`, `bash-developer`). Don't weaken the test to make it pass. |

### Delegation prompt

> Generated-test verification failed at the **{stage}** stage for `{path}` ({framework}). Error from `{LOG}`:
> ```
> {excerpt}
> ```
> Fix the {test | registration | code} minimally so the suite builds, is discovered, and runs. Return the patch; I re-run the gate.

## Tool Availability

| Missing tool | Install hint |
|--------------|--------------|
| `cmake` / `ctest` / `clang` / `llvm-cov` | `brew install llvm cmake ninja` |
| GoogleTest / Catch2 / Unity / CMocka | fetched via FetchContent or `find_package`; ensure the `vcpkg`/`conan` entry or FetchContent pin exists |
| `gcovr` | `uv tool install gcovr` |
| `uv` / `pytest` | `curl -LsSf https://astral.sh/uv/install.sh \| sh`; then `uv add --dev pytest` |
| `kcov` | `brew install kcov` |
| `bats` | `brew install bats-core` |

## Output Format

One report, shown in two parts.

```markdown
## Generate Tests Report

**Target:** {path}
**Language(s):** {C | C++ | Python | Bash}
**Framework:** {GoogleTest | Catch2 | CMocka | Unity | pytest | bats} ({detected in-use | chosen via --framework | default})
**Coverage mode:** {broad | --coverage-gaps targeting N gaps}
**Log:** .context/logs/gen-tests-{timestamp}.log

### Tests Generated ({count})

| File | Cases | Coverage focus |
|------|-------|----------------|
| tests/test_parser.cpp | 7 | happy path, empty input, alloc failure, non-UTF-8 path |

### Registration
- {Wired into CMake via gtest_discover_tests | conftest.py + testpaths | tests/*.bats}
- Discovery check: {N tests now listed by ctest -N / pytest --collect-only / bats -c}
```

### Report: gate, failures, and skips

```markdown
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

**Path not found**
```
Error: Path not found: {path}
Suggestion: Pass a file or directory that exists, e.g. /system-developer:gen-tests src/
```

**Framework conflict**
```
Error: --framework {requested} conflicts with the framework already in use ({detected}).
Mixing frameworks fragments the suite and the runner config.
Suggestion: Drop --framework to use {detected}, or migrate the whole suite first
(out of scope for this command).
```

**No language signal**
```
Error: Could not resolve a language for {path} (no source extensions, manifests, or shebangs).
Suggestion: Point at the source file/module to test, or pass --framework to fix the language.
```

**--coverage-gaps with no runnable suite**
```
Warning: --coverage-gaps needs an existing suite that already builds and runs to measure.
None found — falling back to broad generation. Run `/system-developer:gen-tests` once, then re-run
with --coverage-gaps to target the remaining gaps.
```

## See Also

- `/system-developer:build-test` — confirm the project builds before adding tests; its Canonical Command Table drives the gate.
- `/system-developer:sanitize-check` — run the new tests under ASan/UBSan/TSan once green.
- `/system-developer:review-code` — review the code first; `--coverage-gaps` pairs well after a review.
- `system-developer:python-testing`, `system-developer:bash-testing` — pytest and bats patterns.
