---
description: Inventory, quantify, and rank C/C++/Python/Bash technical debt into a P0-P3 remediation plan
argument-hint: [path (default .)] [--lang c|cpp|python|bash] [--focus standards|memory|build|typing|tests|abi|deps] [--quick] [--top N]
allowed-tools: Read, Glob, Grep, Bash
estimated-cost:
  min-tokens: 5000
  max-tokens: 30000
  model-distribution:
    haiku: 10%
    sonnet: 65%
    opus: 25%
---

# Technical Debt Analysis

Inventory the technical debt in a C, C++, Python, or Bash codebase, quantify it with real tooling signals, and rank it into a P0-P3 remediation plan where every item names an owning agent and the command that fixes it. The system architect assesses structural debt; one reviewer per language present assesses per-language debt.

## Rules

- Read-only. Use Bash only for non-mutating analyzers, repo inspection, and the measurement log; never edit, format, build, or upgrade. Fixes belong to `/system-developer:fix-refactor`, `/system-developer:fix-modernize`, and `/system-developer:fix-quick`.
- Measure before judging, and hand every agent the numbers. Each finding cites `file:line` or a metric.
- When a tool is missing or silent, print its install hint, mark the dimension **unmeasured**, and continue. Never estimate a count, coverage %, or "debt score"; a guessed metric is worse than a missing one.
- Every item gets an owner agent and a remediation command; items with no system-developer path are labeled "manual".
- Rank with the P0-P3 scheme in Phase 3; no dollar-value ROI.
- A healthy codebase gets a short report saying so. Don't pad it with P3 style nits.

## Usage

```bash
/system-developer:analyze-tech-debt .                         # full analysis
/system-developer:analyze-tech-debt src/engine                # one subproject
/system-developer:analyze-tech-debt lib/ --focus memory       # one debt axis
/system-developer:analyze-tech-debt scripts/ --lang bash      # extensionless scripts
/system-developer:analyze-tech-debt . --quick --top 10        # fast triage, top 10
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | Directory or file to analyze. Vendored and build trees are excluded. |
| `--lang c\|cpp\|python\|bash` | auto | Force the reviewer set instead of detecting it. |
| `--focus <axis>` | all | Report one axis in full: `standards`, `memory`, `build`, `typing`, `tests`, `abi`, `deps`. Other axes still get measured and appear as one-line summaries. |
| `--quick` | off | Architect pass only, no per-language fan-out. Cheaper and shallower; the report says so. |
| `--top N` | all | Emit only the N highest-ranked items, plus the full priority counts. |

## Debt Taxonomy

Owners are `system-developer:` agents; "architect" is `system-architector`. The heading of each table is its `--focus` axis.

### standards — language-standard lag

Read the actual `-std` flag or `requires-python`; don't infer the standard from code style.

| Language | Debt signal | Owner |
|----------|-------------|-------|
| C | `-std=c89/gnu89/c99` pinned, K&R declarations, no `<stdbool.h>`/`<stdint.h>`, hand-rolled overflow checks instead of `<stdckdint.h>` | `c-developer` |
| C++ | `-std=c++98/03/11`, `std::auto_ptr`, raw owning pointers, no `override`/`nullptr`, no `std::optional`/`string_view` where they fit | `cpp-developer` |
| Python | Python 2-isms (`iteritems`, `print` remnants), pre-3.12 idioms: `typing.List`/`Dict`, `%`/`.format` over f-strings, `os.path` over `pathlib` | `python-developer` |
| Bash | bashisms under `#!/bin/sh`, GNU-only flags with no BSD fallback, bash 5.x syntax with no guard for macOS `/bin/bash` 3.2 | `bash-developer` |

Remediation: `/system-developer:fix-modernize`.

### memory — memory and error handling

These items are latent CVEs and drive the P0 band.

| Debt | Signal | Owner |
|------|--------|-------|
| Unowned manual allocation | `malloc`/`free` with no documented owner, frees on some error paths but not others | `c-developer` |
| Missing RAII | Naked `new`/`delete`, manual `close`/`unlock` on exception paths, no Rule of Zero/Five on resource-holding types | `cpp-developer` |
| Unchecked returns | Ignored `malloc`/`realloc`/`read`/`write`/`snprintf` results, `errno` read after an intervening call | `c-developer` |
| Swallowed failure | Bare `except:` in Python; unchecked exit status or no `set -euo pipefail` in Bash | `python-developer` / `bash-developer` |

Remediation: `/system-developer:fix-refactor`; confirm memory findings with `/system-developer:sanitize-check`.

### build and deps — build, CI, dependencies

| Debt | Signal | Owner | Axis |
|------|--------|-------|------|
| Hand-rolled build | Hand-written or recursive `Makefile` invoking the compiler, no `CMakeLists.txt`/`meson.build` | architect | build |
| Non-target-based CMake | Global `include_directories`/`link_libraries`/`add_definitions`, no `target_*` scoping, no `CMakePresets.json` | architect | build |
| No warning gate | No `-Wall -Wextra -Werror` or equivalent; warnings tolerated in CI | `c-developer` / `cpp-developer` | build |
| No sanitizer gate | No ASan/UBSan/TSan job in CI for a native tree | architect | build |
| Dependency debt | No lockfile, unpinned ranges, vendored copies with no upstream ref, no CVE scan | `sys-dependency-manager` | deps |

Remediation: `/system-developer:fix-refactor` for build restructuring, `/system-developer:deps` for dependencies, `/system-developer:sanitize-check` to show a sanitizer gate is worth adding.

### typing, tests, abi

| Debt | Signal | Owner | Axis |
|------|--------|-------|------|
| Untyped Python | Unannotated public functions, `Any` in public signatures, no `mypy`/`ty` gate | `python-developer` | typing |
| Absent test framework | No `ctest`/GoogleTest/Catch2/Unity, no `pytest`, no `bats` for a script-heavy tree | `sys-test-generator` | tests |
| Coverage gaps | Measured coverage below the project's floor, or untested failure paths in hot code | `sys-test-generator` | tests |
| ABI/API debt | Default-visible symbols (no `-fvisibility=hidden` or export macro), C++ types across a consumer ABI boundary, no semver policy on a shipped library | architect | abi |
| Dead / duplicated code | Unreferenced translation units and functions, copy-pasted parsers or option handling | language reviewer | none |

Remediation: `/system-developer:gen-tests` for coverage, `/system-developer:fix-refactor` for duplication and API/ABI restructuring, `/system-developer:arch-review` for a deeper structural verdict.

## Measurement Signals

All non-mutating. Check `command -v` first; a missing tool leaves its dimension unmeasured.

| Dimension | Signal | If missing |
|-----------|--------|------------|
| Size / language mix | `cloc <path>` (fallback: `git ls-files` counted by extension) | `brew install cloc`; use the file count |
| C/C++ static findings | `clang-tidy` finding count over `compile_commands.json` | `brew install llvm`; no compile DB means no clang-tidy pass |
| Warning gate | grep build config and CI workflows for `-Wall`/`-Wextra`/`-Werror`, `CMAKE_CXX_FLAGS` | always available |
| Python lint / typing | `ruff check --statistics`, `mypy`/`ty` error count | `uv tool install ruff` / `uv tool install mypy` |
| Bash | `shellcheck -f gcc` finding count over discovered scripts | `brew install shellcheck` |
| Coverage | an existing `coverage.xml`, `lcov.info`, `.coverage`, or `llvm-cov` report | unmeasured; suggest `/system-developer:build-test` then `/system-developer:gen-tests` |
| Dependencies | lockfile presence, pinned vs ranged versions; `osv-scanner`/`pip-audit` if installed | `uv tool install pip-audit` |
| Exported symbols | `nm -gU` / `readelf --dyn-syms` on an already-built artifact | unmeasured; don't build one |

## Workflow

### Phase 0: Scope

Confirm `path` exists. Enumerate sources, excluding `build/`, `builddir/`, `.venv/`, `node_modules/`, and vendored third-party trees. Detect languages from build manifests, extensions, and shebangs (`--lang` overrides; tie-breaks in `skills/_shared/language-detection.md`). Print the scope, per-language file counts, and which languages get a reviewer. Stop with the matching Error Handling message if the path or sources are missing.

### Phase 1: Measure

Set `LOG=".context/logs/techdebt-$(date +%Y%m%d-%H%M%S).log"` (create the directory). Run each applicable signal, teeing raw output to `$LOG`, and build the measurement table the agents receive verbatim.

### Phase 2: Review (parallel)

Launch the architect and, unless `--quick`, one reviewer per detected language, all in one message with the Agent tool. Wait for all of them before Phase 3.

**Architect** — `subagent_type="system-developer:system-architector"`:

"Read-only technical-debt assessment of `{path}` (languages: {languages}). Measurements: {measurement_table}. Assess structural debt only: module boundaries and layering violations, circular dependencies, build-system debt (hand-rolled Makefiles, non-target-based CMake, no presets, no `-Wall -Wextra -Werror`, no sanitizer job in CI), API/ABI debt (default symbol visibility, C++ types across a consumer ABI boundary, no semver policy), and dead or duplicated modules. Don't edit or build anything. Return findings as `{area, evidence (file:line or metric), impact, effort (low/med/high), why_it_costs}`, or say plainly that the structure is sound."

**Language reviewers** — `subagent_type` is the agent in the table below:

"Read-only {language} technical-debt inventory of `{path}`. Measurements: {measurement_table}. Look for: {focus}. Don't edit, build, or install anything. Return `{category, file:line or metric, impact, effort (low/med/high), fix_sketch}`, or nothing if there is no debt."

| Language | Agent | Focus |
|----------|-------|-------|
| C | `system-developer:c-developer` | standard lag (`-std=c89/gnu89/c99` vs C17/C23), manual allocation without a documented owner, leaks on error paths, unchecked returns and `errno` handling, hand-rolled checked arithmetic, missing warning gates, dead/duplicated code |
| C++ | `system-developer:cpp-developer` | standard lag (C++98/11 vs 17/20/23), naked `new`/`delete` and raw owning pointers, missing Rule of Zero/Five, `std::auto_ptr` and other removed idioms, exception-safety gaps, ABI exposure in public headers, dead/duplicated code |
| Python | `system-developer:python-developer` | Python 2-isms and pre-3.12 idioms, missing annotations and `Any` in public APIs, no `mypy`/`ty` gate, unpinned dependencies or no `uv.lock`, missing tests or coverage gaps, dead/duplicated modules |
| Bash | `system-developer:bash-developer` | bashisms under `#!/bin/sh`, GNU-only flags with no BSD fallback, bash 5.x syntax with no guard for macOS `/bin/bash` 3.2, missing `set -euo pipefail`, unchecked exit statuses, unquoted expansions, no `bats` coverage |

### Phase 3: Rank and report

1. Merge all findings, deduplicating on `{file, line}` or the shared metric and keeping the higher impact. Drop items with no evidence.
2. Rank each by impact × effort: correctness or security defects are **P0** at any effort; high impact / low effort **P1** (do first); high / high **P2** (schedule); low / low **P3** (batch); low / high is deferred and left out of the tables.
3. Attach the owner and remediation command from the taxonomy, or "manual".
4. With `--focus`, assign each finding to its taxonomy axis. Render the focused axis as the full ranked table and each other axis as one line: `{axis}: {N} findings, worst {P0-P3}. Re-run without --focus for detail.` Findings with no axis (dead/duplicated code) stay in the ranked table; say so in the report.
5. Apply `--top N`, then emit the Output Format, including unmeasured dimensions.

## Output Format

```markdown
## Technical Debt Report

**Scope:** {path} — {N} files ({languages and per-language counts})
**Mode:** {full | --quick} {focus: <axis> if set}
**Measurement log:** .context/logs/techdebt-{timestamp}.log

### Measured Signals
| Dimension | Value | Source |
|-----------|-------|--------|
| {dimension} | {number or "unmeasured"} | {tool or config read} |

### Summary
{One or two sentences. If clean: "No material technical debt found — standards are current, ownership is explicit, and the build gates are in place." Otherwise: counts by priority and the dominant axis.}

| Priority | Count |
|----------|-------|
| P0 (fix now — correctness/security) | {n} |
| P1 (quick win — high impact, low effort) | {n} |
| P2 (schedule — high impact, high effort) | {n} |
| P3 (batch — low impact, low effort) | {n} |

### P0 — Fix Now
| Item | Evidence | Impact | Effort | Owner | Remediation |
|------|----------|--------|--------|-------|-------------|
| {debt item} | {file:line or metric} | {cost paid today} | {low/med/high} | system-developer:{agent} | {remediation command, or "manual"} |

### P1 — Quick Wins
{same table shape}

### P2 — Schedule
{same table shape}

### P3 — Batch Opportunistically
{same table shape}

### Unmeasured Dimensions
- {dimension}: {missing tool or artifact} — not estimated. Install/produce: {hint}.

### Suggested Sequence
1. {first remediation command, scoped} — clears {n} items.
2. {next} — …
```

## Error Handling

### Path not found
```
Error: Path not found: {path}
Suggestion: Pass a directory that exists, e.g. /system-developer:analyze-tech-debt .
```

### No analyzable sources
```
Note: No C/C++/Python/Bash sources found under {path}.
Suggestion: Point at the source root, or pass --lang for extensionless scripts.
```

### Analyzer missing
Mark the dimension unmeasured and continue:
```
Warning: {tool} not found — {dimension} left unmeasured.
Install: {hint}
```

### No coverage report
```
Note: No coverage artifact found (coverage.xml, lcov.info, .coverage, llvm-cov output).
Coverage is reported as unmeasured — this command does not build.
Suggestion: /system-developer:build-test . then /system-developer:gen-tests
```

### Ambiguous language
Route files that detection can't place to `system-developer:system-developer` and note it in the report.

## See Also

- `/system-developer:fix-refactor`, `/system-developer:fix-modernize`, `/system-developer:fix-quick` — execute what this report recommends.
- `/system-developer:review-code` — defect-level review of a change; this command is codebase-level.
- `/system-developer:arch-review` — deeper structural verdict when architecture debt dominates.
- `/system-developer:deps` — dependency-version and CVE remediation.
- `/system-developer:build-test` — the gate every remediation must pass afterwards.
