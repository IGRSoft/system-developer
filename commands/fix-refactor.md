---
description: Refactor C, C++, Python, or Bash for clean-code and SOLID structure — architect plans, code fixer applies
argument-hint: [path (default .)] [--extract TARGET] [--dry-run] [--lang c|cpp|python|bash]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
estimated-cost:
  min-tokens: 5000
  max-tokens: 32000
  model-distribution:
    haiku: 20%
    sonnet: 50%
    opus: 30%
---

# Refactor and Clean Code
<!-- Updated: July 2026 -->

Restructure C, C++, Python, or Bash code for clean-code and SOLID-style shape without changing what it does. The command is a strict two-agent split: `system-developer:system-architector` **plans** the refactor (read-only, produces a ledger of refactoring classes); `system-developer:sys-code-fixer` **applies** it, one class at a time, each gated on a green `/system-developer:build-test`.

Behavior preservation is the whole game. A refactor that changes observable behavior is a bug, and the only thing that proves preservation is a test suite that was green before the first edit and is green after the last one. `--extract` promotes a cohesive unit into its own CMake/Meson target (or shared library) or its own Python package, instead of restructuring in place.

[Extended thinking: The two failure modes of an agentic refactor are drifting into a rewrite and losing the ability to attribute a break. This command closes both. It closes the first by separating design from mutation: the architect never edits, so its output is a reviewable plan rather than a fait accompli, and the fixer never redesigns, so each diff is bounded by a named refactoring class. It closes the second by refusing to start on a red or untested baseline — with no coverage over the target there is no oracle for "same behavior", so the honest move is `/system-developer:gen-tests` first, not a hopeful diff — and by walking the ledger one class per commit with a build+test gate between rows, so a break is always bisected to one named transformation. Systems code adds two hazards a generic refactorer misses: moving a function between translation units or changing symbol visibility is a silent ABI event, and extracting code that returns a pointer into a local (or splits an arena's lifetime) converts a working program into a use-after-free that compiles cleanly.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **Behavior preservation is the contract.** Observable behavior — return values, side effects, exit codes, emitted diagnostics, public signatures — MUST be identical before and after. If a class cannot be applied without changing behavior, it is not a refactor: drop it from the ledger and report it as a proposed *change*, separately.
2. **Green baseline first.** Before ANY edit, run `/system-developer:build-test` on the target and record the result. A refactor on a red baseline is not a refactor, it is a rewrite — if the baseline is red, stop and report (Error Handling). Re-establish green, then re-run this command.
3. **No coverage, no refactor.** If the target has no test coverage, do NOT refactor blind. Stop and route to `/system-developer:gen-tests {path}` to establish characterization coverage, then re-run. Never substitute "it still compiles" for "it still behaves".
4. **The architect plans; it MUST NOT edit.** `system-developer:system-architector` runs read-only and returns the ledger only. Any file mutation by the planning phase is a failure.
5. **The fixer applies; it MUST NOT redesign.** `system-developer:sys-code-fixer` applies exactly the named class under a minimal-diff gate — no extra cleanups, no reformatting untouched code, no additional refactorings it thinks are good ideas. If a ledger row cannot be applied mechanically, it escalates back (Rule 9) instead of improvising.
6. **One refactoring class at a time.** Each ledger row is applied, verified, and committed on its own, and must be independently buildable and testable. Never batch unrelated classes into one diff.
7. **Verify after every class.** Run `/system-developer:build-test` after each applied class. Not green -> the class is NOT committed: revert it, mark the row `reverted`, and halt the run. Do not stack classes on a broken build.
8. **Public-surface changes are semver events.** For C/C++, flag any public-header change, public struct layout change, moved function between translation units, or altered symbol visibility as a potential ABI break. For Python, the public surface is `__all__` plus the documented API. Such a class requires an explicit semver-major note in the report and MUST NOT be applied silently.
9. **Escalate, never improvise.** A row the fixer cannot apply mechanically (ownership/lifetime restructuring, exception-safety changes, API-shape changes) routes to the owning language agent — `system-developer:c-developer`, `system-developer:cpp-developer`, `system-developer:python-developer`, or `system-developer:bash-developer` — with the same one-class, minimal-diff, behavior-preserving constraints. The architect is still not allowed to edit.
10. **`--dry-run` produces the ledger only.** Write `.context/.refactor/plan.md` and stop. ZERO source edits, ZERO commits.
11. **Tool-missing never hard-fails.** If a tool a class depends on is absent, print the install hint, skip that class, continue, and report the skip.
12. **Never enter plan mode.** This command IS the procedure — execute it.

## Usage

```bash
# Plan the refactor without touching source (review the ledger first)
/system-developer:fix-refactor src/ --dry-run

# Refactor a single translation unit
/system-developer:fix-refactor src/parser.cpp

# Refactor a Python package
/system-developer:fix-refactor src/ingest/

# Force the language when detection is ambiguous (extensionless scripts)
/system-developer:fix-refactor scripts/ --lang bash

# Extract a cohesive unit into its own build target / package
/system-developer:fix-refactor src/codec/ --extract libcodec
/system-developer:fix-refactor src/app/retry.py --extract retrylib
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | File, directory, or module to refactor. Baseline, coverage check, and detection are rooted here. |
| `--dry-run` | off | Produce `.context/.refactor/plan.md` and stop. No edits, no commits. Review-the-plan mode. |
| `--extract TARGET` | off | Extract the target unit into its own build target / package named `TARGET` (CMake/Meson library, or Python package) instead of restructuring in place. See Extract-to-Module Mode. |
| `--lang c\|cpp\|python\|bash` | auto | Force the language instead of detecting. Use for extensionless scripts or to narrow a mixed repo. |

Language detection is canonical in `skill: language-detection` — detect per file/subtree for mixed repos and do not fork its routing rules. `--lang` overrides detection for the resolved scope.

## Baseline Gate

Before planning, establish that "same behavior" is a checkable claim.

| Check | How | On failure |
|-------|-----|------------|
| Build + tests green | `/system-developer:build-test {path}` | Red -> stop (Rule 2). Report the first error and the log path. |
| Tests exist over the target | Test files/targets that exercise `{path}` (`ctest` test names, `pytest` collection, `.bats` files) | None -> stop and route to `/system-developer:gen-tests {path}` (Rule 3). |
| Coverage is meaningful | `--coverage-gaps` from `/system-developer:gen-tests`, or gcov/lcov/llvm-cov / `coverage` output where already wired | Thin -> report the gap, generate characterization tests first. |

Record the baseline (build status, test count, pass count) in the ledger header. The same numbers must hold after the last class — a test that disappeared is a behavior change, not a cleanup. Characterization-test guidance is in `skill: testing-principles`.

## Refactoring Classes

The ledger is built from named classes, cheapest and most local first. Severity/priority vocabulary is P0-P3 per `skill: severity-matrix`.

| Class | Scope | Typical trigger |
|-------|-------|-----------------|
| Rename for intent | local | misleading identifier, `tmp2`, `do_it` |
| Extract function | local | long function, repeated block, mixed abstraction levels |
| Introduce parameter struct | local | long parameter lists, related out-params |
| Replace magic value with named constant | local | literal repeated across branches |
| Flatten nesting / early return | local | nesting depth > 3, arrow code |
| Replace conditional chain with table/dispatch | file | type/tag switch repeated in several places |
| Split translation unit / module | **boundary** | one file owning several responsibilities (SRP) |
| Introduce interface seam (vtable / `Protocol` / ABC) | **boundary** | untestable direct dependency on I/O, OS, device |
| Invert a dependency | **boundary** | low-level module imported by policy code (DIP) |
| Extract to own target/package | **boundary** | reusable unit — use `--extract` |

Local classes are the fixer's default lane. Boundary classes touch the public surface or the build graph — they carry an explicit ABI/API impact line in the ledger (see next section) and frequently escalate under Rule 9.

## ABI / API Safety

A C/C++ refactor can be source-compatible and still break every consumer at load time. Vocabulary and rules follow the API/ABI Design table in `system-developer:system-architector`.

| Move | Risk | Ledger requirement |
|------|------|--------------------|
| Function moved between translation units | changes which target exports it; can drop or add an exported symbol | state the target and export decision; keep visibility explicit |
| Public struct layout changed (field added/reordered/resized) | silent ABI break — callers compiled against the old layout misread memory | semver-MAJOR note; opaque handle preferred |
| Symbol visibility changed (`static`, `-fvisibility=hidden`, export macro) | a newly visible symbol is a new ABI promise; a hidden one is a removal | state before/after visibility per symbol |
| `enum` value renumbered / member inserted | silent break across the boundary | semver-MAJOR note |
| Header split or include moved | may leak internals into the public tier, or drop a transitively-relied-upon include | keep the public-header tier's contents identical |
| Python: `__all__` entry moved/renamed/removed | public API break regardless of importability | deprecate before removal; note in the report |

If the target ships a shared library, keep the SONAME/ABI version distinct from the marketing version and do not bump either implicitly. See `skill: build-systems` for target/visibility mechanics and `skill: ffi-interop` for `extern "C"` boundary rules.

## Ownership and Lifetime Hazards (C/C++)

These are the refactorings that compile cleanly and crash later. Every ledger row touching them is P0-reviewed before it is applied.

| Refactoring | Hazard |
|-------------|--------|
| Extract function that returns a pointer/reference | the pointee may now be a local of the extracted function — returns a dangling pointer. Return by value, or pass the storage in. |
| Move a `unique_ptr` into a helper | ownership transfers; the caller's pointer is left null. Decide owner vs. borrower and pass `T&`/`T*`/`std::span` for the borrow case. |
| Split an arena/region lifetime across the new boundary | objects outlive the arena that allocated them. Keep allocation and bulk-free in one owner (`skill: c-memory-ownership`). |
| Extract a `string_view`/`span` producer | the non-owning view can outlive its backing store once the backing store becomes a local. |
| Move a `free`/`fclose`/`close` into a helper | double-free or leak on the error path; verify every early return. |
| Hoist a static/global into a parameter | changes initialization order and thread-safety assumptions. |

C++ ownership defaults (RAII, Rule of Zero, no naked `new`/`delete`) are in `skill: modern-cpp`; C ownership conventions in `skill: c-memory-ownership`. Python-side seams follow `skill: python-typing` for the extracted interface; shell function extraction follows `skill: bash-scripting` (`local`, arrays, quoting).

## The Refactor Ledger

The architect's output is `.context/.refactor/plan.md` — an ordered checklist, local classes before boundary classes:

```markdown
# Refactor Ledger
Path: {path} | Language(s): {detected} | Mode: in-place | extract:{TARGET}
Baseline: build GREEN | tests {passed}/{total} | coverage over target: {yes/thin/none}

| # | Refactoring class | Scope | Owner | ABI/API impact | Status |
|---|-------------------|-------|-------|----------------|--------|
| 1 | rename `tmp2` -> `pending_frames` | local | sys-code-fixer | none | pending |
| 2 | extract `parse_header()` from `decode()` | local | sys-code-fixer | none (static) | pending |
| 3 | split `codec.c` into `codec.c` + `codec_io.c` | boundary | sys-code-fixer | exports unchanged; visibility stated | pending |
| 4 | invert `logger` dependency behind a seam | boundary | cpp-developer (escalated) | none | pending |
```

Status transitions: `pending -> applied -> verified -> committed`, or `reverted` on a red gate, or `skipped` (tool missing / behavior-changing). The ledger is the source of truth across resumes — read it rather than relying on context-window memory.

## Extract-to-Module Mode (`--extract`)

Promote a cohesive unit into its own build target or package. Extract only when every check holds:

| Check | Requirement |
|-------|-------------|
| Cohesion | the unit is a self-contained responsibility, not a grab-bag |
| Dependencies | every include/import is classifiable as stdlib, external, or project-internal |
| Interface | a small public surface can be named (headers to publish / `__all__` to declare) |
| Replacement | the original site can be replaced by a link/import with no behavior change |
| Value | there is real reuse or test-isolation value — not modularization for its own sake |

Do NOT extract single-use code welded to app-specific logic, or a unit whose extraction would require publishing internals. Avoid generic names (`utils`, `common`, `helpers`).

### Concrete shapes

| Ecosystem | Result |
|-----------|--------|
| CMake | new `add_library({TARGET} ...)` (STATIC by default; SHARED only if a consumer needs it), `target_include_directories({TARGET} PUBLIC include/)` with the private tier `PRIVATE`, consumers switched to `target_link_libraries(... PRIVATE {TARGET})` |
| Meson | new `library('{TARGET}', ...)` + `declare_dependency(include_directories: ...)`, consumers take the dep object |
| Make | new object group + an archive rule; explicit header install list |
| Python | new package dir with its own `pyproject.toml`, added to the workspace / installed with `uv add --editable ./{TARGET}`, public surface declared in `__all__` |
| Bash | sourceable library (`lib/{TARGET}.sh`) exposing only prefixed functions, `source`d by consumers; no top-level side effects on source |

### Extraction steps

1. Create the target/package skeleton with its manifest (`CMakeLists.txt` / `meson.build` / `pyproject.toml` / `lib/{TARGET}.sh`).
2. Move the code — move, do not copy; a duplicate left behind is a defect.
3. Declare the public surface: published headers with explicit visibility (default-hidden + export macro for SHARED), or `__all__`, or the function-name prefix for shell.
4. Wire dependencies in the new manifest; keep them minimal.
5. Move the unit's existing tests with it and register them with the new target (`add_test`/`pytest` path/`bats` file).
6. Replace the original site with a link/import; delete the moved code.
7. Gate on `/system-developer:build-test` at the repo root — the whole build graph, not just the new target.

## Workflow

### Phase 1: Scope, Baseline, Coverage (Bash + Read)

1. Confirm `path` exists; else emit the "path not found" message and stop.
2. Detect the language(s) per `skill: language-detection`; apply `--lang` if given. Nothing recognized -> report and stop.
3. Run `/system-developer:build-test {path}`, tee to `.context/logs/`. Red -> stop (Rule 2, Error Handling).
4. Check for tests covering the target. None -> stop and route to `/system-developer:gen-tests` (Rule 3).
5. Record the baseline line (build status, tests passed/total, coverage verdict) for the ledger header.

### Phase 2: Plan (read-only)

**Use Task tool with subagent_type="system-developer:system-architector"**
Prompt: "READ-ONLY refactor plan for `{path}` ({languages}; mode: {in-place | extract {TARGET}}). Baseline: {baseline line}. Identify code smells and SOLID violations with `file:line` evidence, then produce an ordered ledger of *refactoring classes* — local classes (rename, extract function, parameter struct, named constant, flatten nesting, dispatch table) before boundary classes (split translation unit/module, interface seam, dependency inversion, extract to target/package). For every row give: class, scope (local|boundary), proposed owner (sys-code-fixer for mechanical; c/cpp/python/bash-developer when it needs judgment), and an explicit ABI/API impact line — public-header change, public struct layout, moved function between translation units, symbol visibility, enum renumbering, or `__all__` change is a semver event and must be marked MAJOR. Call out C/C++ ownership and lifetime hazards per row (returning a pointer to a new local, moving a `unique_ptr`, splitting an arena lifetime, non-owning view outliving its backing store, moved `free`/`close`). Every row must be independently buildable and testable. Drop any class that cannot preserve observable behavior and list it separately as a proposed change. Do NOT edit any file. Return the ledger in the Refactor Ledger table format."

Write the returned ledger to `.context/.refactor/plan.md`, all rows `pending`. **If `--dry-run`: stop here** and report the ledger path.

### Phase 3: Apply, One Class At A Time

Walk the ledger top-down. For each `pending` row, mark it `applied` as you start, then:

**Mechanical rows — Use Task tool with subagent_type="system-developer:sys-code-fixer"**
Prompt: "Apply ONLY refactoring class **{class}** at {file:line refs} in `{path}` ({language}). Minimal-diff gate: change only what this class requires; do NOT reformat untouched code, do NOT apply other ledger rows, do NOT redesign. Observable behavior — return values, side effects, exit codes, emitted diagnostics, public signatures — MUST be identical. ABI/API constraint for this row: {impact line}. {If C/C++: 'Watch the lifetime hazard: {hazard}.'} Do not run the test suite. Report every file and symbol touched, and any part of the class you could not apply without redesigning — escalate rather than improvise."

**Escalated / judgment rows — route by the row's language:**

- C — **Use Task tool with subagent_type="system-developer:c-developer"**
- C++ — **Use Task tool with subagent_type="system-developer:cpp-developer"**
- Python — **Use Task tool with subagent_type="system-developer:python-developer"**
- Bash — **Use Task tool with subagent_type="system-developer:bash-developer"**

Prompt (all four): "Perform ONLY refactoring class **{class}** at {file:line refs} in `{path}`. This row needs judgment ({ownership transfer | exception safety | interface seam design | dependency inversion}). Preserve observable behavior exactly — this is a refactor, not a redesign; no API-shape change beyond what the ledger row states. ABI/API constraint: {impact line}. {C/C++: state the ownership/lifetime decision for every pointer, reference, view, or arena the change crosses.} Do not touch other ledger rows. Return the diff and the ownership/boundary rationale."

Rows marked MAJOR (Rule 8) are surfaced in the report before application and are not applied silently.

### Phase 4: Verify After Every Class

1. Run `/system-developer:build-test {path}`; tee to `.context/logs/`.
2. Compare against the baseline: build green **and** the same tests passing, same count. A vanished or newly-skipped test is a behavior change — treat as red.
3. **Green** -> mark the row `verified`, proceed to commit.
4. **Red** -> revert the row's diff, mark it `reverted`, and **halt the run** (Rule 7). One bounded corrective cycle with the owning agent is allowed for an escalated row before the halt. Do not attempt later rows.

### Phase 5: Commit One Class Per Refactoring

1. Stage only the files that row touched.
2. Commit with a conventional subject naming the class — `refactor: extract parse_header() from decode()`, `refactor: split codec.c into codec.c and codec_io.c`, `refactor: invert logger dependency behind a seam`.
3. Mark the row `committed` and move to the next `pending` row.

> Per the user's git conventions: no `--no-verify`, no AI-attribution footers, follow the repo's commit format, and branch first if on a protected branch. Keep refactoring commits separate from feature commits.

> Rationale and before/after notes belong in the PR or `.context/development-N.md`, NOT in source comments (`corpflow:code-comment-standard`) — source comments carry only the non-obvious WHY and the contract.

### Phase 6: Report

Emit the Output Format: baseline vs. final test numbers, per-row status, every ABI/API event, and anything dropped as behavior-changing.

## Output Format

```markdown
## Refactor Report

**Path:** {path}
**Language(s):** {detected}
**Mode:** in-place | extract {TARGET} | dry-run
**Ledger:** .context/.refactor/plan.md

### Behavior Preservation
| | Baseline | Final |
|---|---|---|
| Build | GREEN | {GREEN/RED} |
| Tests passed | {p}/{t} | {p}/{t} |
| Coverage over target | {yes/thin} | {yes/thin} |

<!-- dry-run: stop after the planned classes -->
### Planned Classes ({count})
{rendered ledger, all rows pending}

<!-- apply mode -->
### Applied Classes
| # | Class | Scope | Owner | ABI/API | Status | Commit |
|---|-------|-------|-------|---------|--------|--------|
| 1 | {class} | local | sys-code-fixer | none | committed | {subject} |
| 3 | {class} | boundary | cpp-developer | MAJOR — {what} | committed | {subject} |

### ABI / API Events
- {symbol/header/`__all__` entry}: {before -> after} — semver {MAJOR|MINOR|none}. {consumer action}

<!-- --extract only -->
### Extracted Unit
- **Target/package:** {TARGET} ({CMake library | Meson library | Python package | sourceable shell lib})
- **Public surface:** {published headers / `__all__` / prefixed functions}
- **Consumers updated:** {n} | **Duplicate code left behind:** none
- **Root build+test:** {GREEN/RED}

**Result:** COMPLETE / PARTIAL / HALTED ({reason})
- Classes committed: {n} | reverted: {n} | skipped: {n}

<!-- on a halt -->
### Halt
- **Class:** {class} — build/test RED: {first error; log in .context/logs/...}
- **Action:** row reverted; later rows not attempted.

<!-- always, when applicable -->
### Dropped As Behavior-Changing
- {class}: {what would change} — proposed as a separate change, not applied.
```

## Error Handling

### Path not found
```
Error: Path not found: {path}
Suggestion: Pass a file or directory that exists, e.g.
  /system-developer:fix-refactor src/ --dry-run
```

### Red baseline
```
Error: Baseline build/tests are RED — refusing to refactor.
First failure: {one line; full log in .context/logs/...}
A refactor on a red baseline is a rewrite: there is no oracle for
"same behavior". Fix the build/tests first, then re-run.
Suggestion: /system-developer:build-test {path}
```
Stop. Do not edit (Rule 2).

### No test coverage over the target
```
Error: No tests exercise {path} — refusing to refactor blind.
Behavior preservation is unverifiable without an oracle.
Suggestion: /system-developer:gen-tests {path} --coverage-gaps
Then re-run: /system-developer:fix-refactor {path}
```
Stop and route (Rule 3). Thin-but-present coverage is a warning, not a halt — generate characterization tests for the uncovered branches first.

### Public-surface change detected
```
Note: This class changes the public surface ({header/struct/symbol/__all__}).
Impact: potential ABI/API break — semver MAJOR.
It is reported, not applied silently. Confirm the semver plan (and the
SONAME/ABI version for a shared library) before proceeding.
```

### Build red after a class
Revert that row's diff, mark it `reverted`, and halt (Rule 7). Report the first error and the log path. One bounded corrective cycle with the owning agent is allowed for an escalated row; never stack later rows on a broken build.

### Extraction rejected
```
Note: {path} does not meet the extraction checklist ({failed check}).
Nothing extracted. Suggestion: run in-place refactoring first
(/system-developer:fix-refactor {path}), then re-evaluate --extract.
```

### Tool missing
Print the install hint (`brew install llvm` for clang-tidy/clang-format, `brew install cmake ninja`, `uv tool install ruff`, `brew install shellcheck shfmt`), skip that class, continue, and note the skip in the ledger and report.

## See Also

- `skill: testing-principles` — characterization tests and the behavior-preservation oracle this command depends on.
- `skill: severity-matrix` — P0-P3 vocabulary for smell severity and ledger prioritization.
- `skill: language-detection` — canonical marker -> language -> agent routing.
- `skill: c-memory-ownership` — ownership conventions, arenas/regions, the lifetime hazards behind extraction.
- `skill: modern-cpp` — RAII, Rule of Zero, vocabulary types, non-owning view lifetime traps.
- `skill: python-typing` — typing the extracted interface seam (`Protocol`, ABCs, `__all__`).
- `skill: bash-scripting` — function extraction, `local` scoping, arrays, sourceable-library shape.
- `skill: build-systems` — CMake/Meson/Make targets, link scope, symbol visibility for `--extract`.
- `skill: ffi-interop` — `extern "C"` boundary rules when the extracted target crosses languages.
- `/system-developer:build-test` — the build + test gate run at baseline and after every class.
- `/system-developer:gen-tests` — establish coverage before refactoring an untested target.
- `/system-developer:review-code` — review the refactored diff for behavioral drift once the ledger is complete.
- `/system-developer:analyze-tech-debt` — quantify and prioritize accumulated debt before choosing what to refactor.
- `/system-developer:arch-review` — structural review when the ledger is dominated by boundary classes.
- `/system-developer:fix-quick` — mechanical formatter/linter pass; clears noise before this command plans.
