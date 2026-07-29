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
<!-- Updated: July 2026 -->

Inventory the technical debt in a C, C++, Python, or Bash codebase, quantify it with real tooling signals, and rank it into a P0-P3 remediation plan where every item names an owning agent and the command that fixes it. Structural debt is assessed by the system architect; per-language debt by one reviewer per language actually present.

This command is **read-only**. It measures and prioritizes; it never edits, formats, builds, or upgrades anything.

[Extended thinking: Debt reports rot when they are opinion dressed as measurement. So this command splits the work in two: a Bash measurement pass that runs only non-mutating analyzers and records honest numbers, and an agent pass that interprets those numbers with language expertise. Systems debt is specific — a C tree pinned at `-std=gnu89`, a C++ layer with naked `new`/`delete` and no ownership story, an untyped Python package with `Any` leaking through its public API, a `#!/bin/sh` script full of bashisms, a hand-rolled Makefile with no `-Werror` and no sanitizer job — and each class has a different owner and a different fix. When a tool is absent the dimension is marked unmeasured with an install hint; a guessed metric is worse than a missing one.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **Read-only, always.** Never edit, format, upgrade, or build. Bash is for non-mutating analyzers and repo inspection only. Remediation is delegated to `/system-developer:fix-refactor`, `/system-developer:fix-modernize`, and `/system-developer:fix-quick` — this command recommends, it does not execute.
2. **Measure before judging.** Run the Measurement Signals pass first and give every agent the concrete numbers. Findings must cite `file:line` or a metric.
3. **Never guess a number.** If a tool is missing or produces no output, print its install hint, mark that dimension **unmeasured** in the report, and continue. A fabricated count, coverage %, or "debt score" is a failure.
4. **One language reviewer per language present.** Launch a reviewer only for a language detected in scope (or forced by `--lang`), and run the eligible reviewers in parallel. The architect pass always runs.
5. **Every item gets an owner and a fix command.** No debt item ships without `{owner agent, remediation command}`. Items with no system-developer remediation path are labeled "manual".
6. **Severity is P0-P3 per `skill: severity-matrix`.** Rank by impact × effort using its quadrant. Do not invent a parallel severity vocabulary or dollar-value ROI.
7. **No manufactured debt.** A healthy codebase gets a short report saying so. Do not pad with P3 style nits.
8. **Never enter plan mode.** This command IS the procedure — execute it.

## Usage

```bash
# Full debt analysis of the current tree
/system-developer:analyze-tech-debt .

# Analyze one subproject
/system-developer:analyze-tech-debt src/engine

# Narrow to a single debt axis
/system-developer:analyze-tech-debt . --focus standards
/system-developer:analyze-tech-debt lib/ --focus memory

# Force a language when detection is ambiguous (extensionless scripts)
/system-developer:analyze-tech-debt scripts/ --lang bash

# Fast single-pass triage, top 10 items only
/system-developer:analyze-tech-debt . --quick --top 10
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | Directory or file to analyze. Scans are rooted here; vendored and build trees are excluded. |
| `--lang c\|cpp\|python\|bash` | auto | Force the reviewer set instead of detecting. Use for extensionless scripts or to scope a mixed repo. |
| `--focus <axis>` | all | Restrict the taxonomy to one axis: `standards`, `memory`, `build`, `typing`, `tests`, `abi`, `deps`. Other axes are still measured but reported as a one-line summary. |
| `--quick` | off | Single architect pass over the measurement output. Skips the per-language fan-out; cheaper, shallower, and marked as such in the report. |
| `--top N` | all | Emit only the N highest-ranked items, plus the full priority counts. |

## Debt Taxonomy: Language-Standard Lag

Legacy standard pinning is the most common systems debt and the cheapest to quantify — read the actual `-std` flag, do not infer it from code style. Cross-check against `skill: version-feature-matrix` before calling a standard "old": the matrix, not this table, decides what a toolchain can support.

| Language | Debt signal | Owner |
|----------|-------------|-------|
| C | `-std=c89/gnu89/c99` pinned, K&R declarations, no `<stdbool.h>`/`<stdint.h>`, hand-rolled overflow checks instead of `<stdckdint.h>` | `c-developer` |
| C++ | `-std=c++98/03/11`, `std::auto_ptr`, raw owning pointers, no `override`/`nullptr`, no `std::optional`/`string_view` where they fit | `cpp-developer` |
| Python | Python 2-isms (`print` statement remnants, `iteritems`), pre-3.12 idioms: `typing.List`/`Dict`, `%`/`.format` over f-strings, `os.path` over `pathlib` | `python-developer` |
| Bash | bashisms under `#!/bin/sh`, GNU-only flags with no BSD fallback, bash 5.x syntax with no guard against macOS `/bin/bash` 3.2 | `bash-developer` |

Remediation: `/system-developer:fix-modernize` (one standard jump at a time, gated on `/system-developer:build-test`).

## Debt Taxonomy: Memory & Error Handling

Native memory and error-handling debt drives the P0 band — these items are latent CVEs, not style.

| Debt | Signal | Owner |
|------|--------|-------|
| Unowned manual allocation | `malloc`/`free` pairs with no documented owner, ownership implied by comment only, frees on some error paths but not others (`skill: c-memory-ownership`) | `c-developer` |
| Missing RAII | Naked `new`/`delete`, manual `close`/`fclose`/`unlock` on exception paths, no Rule of Zero/Five on resource-holding types (`skill: modern-cpp`) | `cpp-developer` |
| Unchecked returns | Ignored `malloc`/`realloc`/`read`/`write`/`snprintf` results, `errno` read after an intervening call, or never checked at all | `c-developer` |
| Swallowed failure | Bare `except:` in Python, unguarded exit status in Bash, `set -euo pipefail` absent | `python-developer` / `bash-developer` |

Remediation: `/system-developer:fix-refactor`; confirm memory findings with `/system-developer:sanitize-check`.

## Debt Taxonomy: Build, CI & Dependencies

| Debt | Signal | Owner |
|------|--------|-------|
| Hand-rolled build | Recursive/hand-written `Makefile` doing compiler invocation, no `CMakeLists.txt`/`meson.build` (`skill: build-systems`) | architect |
| Non-target-based CMake | Global `include_directories`/`link_libraries`/`add_definitions`, no `target_*` scoping, no `CMakePresets.json` | architect |
| No warning gate | Missing `-Wall -Wextra -Werror` (or equivalent) in the build; warnings tolerated in CI | `c-developer` / `cpp-developer` |
| No sanitizer gate | No ASan/UBSan/TSan job in CI for a native tree | architect |
| Dependency debt | No lockfile (`uv.lock` absent), unpinned ranges, vendored copies with no upstream ref, no CVE scan | `sys-dependency-manager` (via `/system-developer:deps`) |

Remediation: `/system-developer:fix-refactor` for build restructuring, `/system-developer:deps` for dependency debt, `/system-developer:sanitize-check` to prove a sanitizer gate is worth adding.

## Debt Taxonomy: Typing, Tests & API/ABI

| Debt | Signal | Owner |
|------|--------|-------|
| Untyped Python | Missing annotations on public functions, `Any` leaking through public signatures, no `mypy`/`ty` gate (`skill: python-typing`) | `python-developer` |
| Absent test framework | No `ctest`/GoogleTest/Catch2/Unity, no `pytest`, no `bats` for a script-heavy tree (`skill: testing-principles`) | `sys-test-generator` |
| Coverage gaps | Measured coverage below the project's floor, or untested error/failure paths in changed hot code | `sys-test-generator` |
| ABI/API debt | Default-visible symbols (no `-fvisibility=hidden`, no export macro), C++ types across a consumer ABI boundary, no semver policy on a shipped library | architect |
| Dead / duplicated code | Unreferenced translation units and functions, copy-pasted parsers or option handling across modules | language reviewer |

Remediation: `/system-developer:gen-tests` for coverage, `/system-developer:fix-refactor` for duplication and API/ABI restructuring, `/system-developer:arch-review` for a deeper structural verdict.

## Measurement Signals

Run these in Phase 1. Every one is non-mutating. If a tool is absent, print the install hint and mark the dimension **unmeasured** — never estimate.

| Dimension | Signal | If missing |
|-----------|--------|------------|
| Size / language mix | `cloc <path>` (fallback: `git ls-files` counted by extension) | `brew install cloc` — fall back to the file count |
| C/C++ static findings | `clang-tidy` finding count over the compile DB (`compile_commands.json`) | `brew install llvm`; note that no compile DB means no clang-tidy pass |
| Warning gate | grep the build config for `-Wall`/`-Wextra`/`-Werror`, `CMAKE_CXX_FLAGS`, CI workflow files | n/a — a config read, always available |
| Python lint / typing | `ruff check --statistics`, `mypy`/`ty` error count | `uv tool install ruff` / `uv tool install mypy` |
| Bash | `shellcheck -f gcc` finding count over discovered scripts | `brew install shellcheck` |
| Coverage | read an existing report (`coverage.xml`, `lcov.info`, `.coverage`, `llvm-cov` output) | no report → unmeasured; suggest `/system-developer:build-test` then `/system-developer:gen-tests` |
| Dependencies | lockfile presence, pinned vs ranged versions; `osv-scanner`/`pip-audit` when installed | `uv tool install pip-audit` |
| Exported symbols | `nm -gU` / `readelf --dyn-syms` on an already-built artifact | no artifact → unmeasured; do not build one |

Tee raw tool output to `.context/logs/techdebt-<timestamp>.log` and cite that path in the report.

## Workflow

### Phase 0: Scope & Detect

1. Confirm `path` exists; otherwise emit the Error Handling message and stop.
2. Enumerate sources, excluding `build/`, `builddir/`, `.venv/`, `node_modules/`, and vendored third-party trees.
3. Detect the languages present using the canonical `skill: language-detection` table — do not fork its rules. `--lang` overrides detection.
4. Print the resolved scope, per-language file counts, and the languages that will get a reviewer.

### Phase 1: Measure (Bash, read-only)

1. Create `.context/logs/` if absent; set `LOG=".context/logs/techdebt-$(date +%Y%m%d-%H%M%S).log"`.
2. Run each applicable Measurement Signal as a single Bash invocation, teeing to `$LOG`. Never `cd`-chain; use each tool's own path/directory flags.
3. Check `command -v` before each tool. Missing → print the install hint, record the dimension as unmeasured, continue.
4. Build the measurement table that Phases 2 and 3 receive verbatim.

### Phase 2: Structural Pass (always)

**Use Task tool with subagent_type="system-developer:system-architector"**
Prompt: "Read-only technical-debt assessment of the project at `{path}` (languages: {languages}). Measurements: {measurement_table}. Assess structural and architectural debt only: module boundaries and layering violations, circular dependencies, build-system debt (hand-rolled Makefiles, non-target-based CMake, no presets, missing `-Wall -Wextra -Werror`, no sanitizer job in CI), API/ABI debt (default symbol visibility, C++ types across a consumer ABI boundary, no semver policy), and dead or duplicated modules. Do NOT edit any file and do NOT build. Return findings as `{area, evidence (file:line or metric), impact, effort (low/med/high), why_it_costs}`. Say so plainly if the structure is sound."

### Phase 3: Per-Language Debt Fan-Out (parallel)

Skipped entirely under `--quick`. Launch one reviewer per detected language, simultaneously, each receiving the same scope and measurement table. All are read-only.

**C — Use Task tool with subagent_type="system-developer:c-developer"**
Prompt: "Read-only C technical-debt inventory for `{path}`. Measurements: {measurement_table}. Inventory: standard lag (pinned `-std=c89/gnu89/c99` vs C17/C23 per `skill: version-feature-matrix`), manual allocation without documented ownership, leaks on error paths, unchecked return values and `errno` handling, hand-rolled checked arithmetic, missing warning gates, and dead/duplicated code. Do NOT edit or build. Return `{category, file:line or metric, impact, effort, fix_sketch}`."

**C++ — Use Task tool with subagent_type="system-developer:cpp-developer"**
Prompt: "Read-only C++ technical-debt inventory for `{path}`. Measurements: {measurement_table}. Inventory: standard lag (C++98/11 vs 17/20/23), missing RAII and naked `new`/`delete`, raw owning pointers and unclear ownership, missing Rule of Zero/Five, `std::auto_ptr` and other removed idioms, exception-safety gaps, ABI exposure in public headers, and dead/duplicated code. Do NOT edit or build. Return `{category, file:line or metric, impact, effort, fix_sketch}`."

**Python — Use Task tool with subagent_type="system-developer:python-developer"**
Prompt: "Read-only Python technical-debt inventory for `{path}`. Measurements: {measurement_table}. Inventory: Python 2-isms and pre-3.12 idioms, missing annotations and `Any` leaking through public APIs, absent `mypy`/`ty` gate, unpinned dependencies or a missing `uv.lock`, missing test framework or coverage gaps, and dead/duplicated modules. Do NOT edit or install anything. Return `{category, file:line or metric, impact, effort, fix_sketch}`."

**Bash — Use Task tool with subagent_type="system-developer:bash-developer"**
Prompt: "Read-only Bash technical-debt inventory for `{path}`. Measurements: {measurement_table}. Inventory: bashisms under a POSIX `#!/bin/sh` shebang, GNU-only flags with no BSD fallback, bash 5.x syntax with no guard for macOS `/bin/bash` 3.2, missing `set -euo pipefail`, unchecked exit statuses, unquoted expansions, and absent `bats` coverage. Do NOT edit any script. Return `{category, file:line or metric, impact, effort, fix_sketch}`."

[SYNC POINT: Wait for the architect and every language reviewer before synthesis.]

### Phase 4: Rank & Report

1. **Merge** architect and language findings; deduplicate at `{file, line}` or at the shared metric, keeping the higher impact.
2. **Filter** speculative items with no evidence. Per Rule 7, do not backfill.
3. **Rank** each survivor by impact × effort into P0-P3 using `skill: severity-matrix` (its quadrant maps high-impact/low-effort → do first, high/high → schedule, low/low → batch, low/high → defer).
4. **Attach** an owning agent and a remediation command to every item; label items with no path "manual".
5. **Partition by `--focus`** if set, per the axis map below.
6. **Apply** `--top N` if set, and emit the Output Format report including the unmeasured dimensions.

#### `--focus` axis map

Measurement and both review phases always run every axis (Rule 7 forbids narrowing the evidence); `--focus` shapes only the report. Assign each finding to one axis, then render the focused axis as the full ranked table and each other axis as one line — `{axis}: {N} findings, worst {P0-P3} — re-run without --focus for detail`.

| Axis | Findings from |
|------|---------------|
| `standards` | Debt Taxonomy: Standards & Language Level |
| `memory` | Debt Taxonomy: Memory & Error Handling |
| `build` | Build, CI & Dependencies — every row except Dependency debt |
| `deps` | Build, CI & Dependencies — the Dependency debt row |
| `typing` | Typing, Tests & API/ABI — Untyped Python |
| `tests` | Typing, Tests & API/ABI — Absent test framework, Coverage gaps |
| `abi` | Typing, Tests & API/ABI — ABI/API debt |

A finding that fits no axis (e.g. dead/duplicated code) stays in the ranked table regardless of `--focus`; say so in the report rather than dropping it.

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

### Analyzer missing (dimension unmeasured)
Print the install hint from Measurement Signals, mark the dimension unmeasured, and continue — never hard-fail and never estimate:
```
Warning: {tool} not found — {dimension} left unmeasured.
Install: {hint}
```

### No coverage report available
```
Note: No coverage artifact found (coverage.xml, lcov.info, .coverage, llvm-cov output).
Coverage is reported as unmeasured — this command does not build.
Suggestion: /system-developer:build-test . then /system-developer:gen-tests
```

### Ambiguous language
Apply the `skill: language-detection` shebang and tie-break rules. If a file is still ambiguous, route it to `system-developer:system-developer` and note the routing in the report.

## See Also

**When to use which:** this command *quantifies and prioritizes* debt; it never fixes anything. To execute what it recommends: `/system-developer:fix-refactor` (structure, duplication, ownership), `/system-developer:fix-modernize` (standard lag, one jump at a time), `/system-developer:fix-quick` (formatter/linter-level P3 batch).

- `skill: severity-matrix` — P0-P3 definitions and the impact × effort quadrant used for ranking.
- `skill: language-detection` — canonical marker → language → agent routing.
- `skill: version-feature-matrix` — authoritative standard/toolchain support before calling a standard "legacy".
- `skill: build-systems` — CMake/Meson target-based idioms and preset expectations behind the build-debt rows.
- `skill: testing-principles` — the coverage and test-type expectations behind the testing-debt rows.
- `/system-developer:review-code` — defect-level review of a change; this command is codebase-level.
- `/system-developer:arch-review` — deeper structural verdict when architecture debt dominates.
- `/system-developer:deps` — execute the dependency-version and CVE remediation listed here.
- `/system-developer:build-test` — the build/test gate every remediation command must pass afterwards.
