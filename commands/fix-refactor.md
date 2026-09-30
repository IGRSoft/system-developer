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

Restructure C, C++, Python, or Bash code toward clean-code and SOLID shape without changing what it does. `system-developer:system-architector` plans the refactor read-only as a ledger of refactoring classes; `system-developer:sys-code-fixer` applies it one class at a time, each gated on a green `/system-developer:build-test`. `--extract` promotes a cohesive unit into its own CMake/Meson target or Python package instead of restructuring in place.

Separating plan from edit keeps the work from drifting into a rewrite, and one class per commit means a break always points at one named transformation.

## Rules

- Behavior preservation is the contract: return values, side effects, exit codes, emitted diagnostics, and public signatures stay identical. A class that can't preserve them isn't a refactor; drop it from the ledger and report it as a proposed change.
- Start from a green baseline with tests over the target. A red baseline or no tests means there's no oracle for "same behavior", so stop (see Baseline Gate). "It still compiles" is not "it still behaves".
- The architect only plans and edits nothing. The fixer applies exactly the named class with a minimal diff: no extra cleanups, no reformatting untouched code, no redesign. A row it can't apply mechanically escalates to the language developer instead.
- One class per commit, each independently buildable and testable. Run the build + test gate after every class; a class that isn't green is reverted and halts the run.
- Public-surface changes are semver events (see ABI / API Safety). Mark them MAJOR in the ledger and ask the user to confirm the semver plan before applying one.
- `--dry-run` writes the ledger and stops: no source edits, no commits.
- A missing tool never hard-fails: print its install hint (`brew install llvm` for clang-tidy/clang-format, `brew install cmake ninja`, `uv tool install ruff`, `brew install shellcheck shfmt`), skip that class, continue, and report the skip.

## Usage

```bash
/system-developer:fix-refactor src/ --dry-run                 # review the ledger first
/system-developer:fix-refactor src/parser.cpp                 # one translation unit
/system-developer:fix-refactor src/ingest/                    # a Python package
/system-developer:fix-refactor scripts/ --lang bash           # extensionless scripts
/system-developer:fix-refactor src/codec/ --extract libcodec  # own build target
/system-developer:fix-refactor src/app/retry.py --extract retrylib
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | File, directory, or module to refactor. Baseline, coverage check, and detection are rooted here. |
| `--dry-run` | off | Write `.context/.refactor/plan.md` and stop. |
| `--extract TARGET` | off | Extract the unit into its own build target / package named `TARGET` instead of restructuring in place. See Extract-to-Module Mode. |
| `--lang c\|cpp\|python\|bash` | auto | Force the language for the resolved scope. |

Language detection, per file or subtree in mixed repos: `.c` is C; `.cpp`/`.cc`/`.cxx`/`.hpp` is C++; a bare `.h` is C unless the tree has C++ sources or `CMAKE_CXX_STANDARD`; `.py` is Python; `.sh` or a bash/sh shebang is Bash.

## Baseline Gate

| Check | How | On failure |
|-------|-----|------------|
| Build + tests green | `/system-developer:build-test {path}` | Stop with "Red baseline". |
| Tests exercise the target | `ctest` test names, `pytest` collection, `.bats` files covering `{path}` | Stop with "No test coverage". |
| Coverage is meaningful | gcov/lcov/llvm-cov or `coverage` output, where already wired | Warning, not a halt: report the gap and recommend `/system-developer:gen-tests {path} --coverage-gaps`. |

Record build status, tests passed/total, and the coverage verdict in the ledger header. The same numbers must hold after the last class: a test that disappeared or became skipped is a behavior change.

## Refactoring Classes

Order the ledger cheapest and most local first.

| Class | Scope | Typical trigger |
|-------|-------|-----------------|
| Rename for intent | local | misleading identifier, `tmp2`, `do_it` |
| Extract function | local | long function, repeated block, mixed abstraction levels |
| Introduce parameter struct | local | long parameter lists, related out-params |
| Replace magic value with named constant | local | literal repeated across branches |
| Flatten nesting / early return | local | nesting depth > 3 |
| Replace conditional chain with table/dispatch | file | type/tag switch repeated in several places |
| Split translation unit / module | boundary | one file owning several responsibilities (SRP) |
| Introduce interface seam (vtable / `Protocol` / ABC) | boundary | untestable direct dependency on I/O, OS, device |
| Invert a dependency | boundary | low-level module imported by policy code (DIP) |
| Extract to own target/package | boundary | reusable unit; use `--extract` |

Local classes are the fixer's lane. Boundary classes touch the public surface or build graph, carry an ABI/API impact line, and often need the language developer.

## ABI / API Safety

A C/C++ refactor can be source-compatible and still break every consumer at load time.

| Move | Risk | Ledger requirement |
|------|------|--------------------|
| Function moved between translation units | can drop or add an exported symbol | state the target and export decision; keep visibility explicit |
| Public struct layout changed | callers compiled against the old layout misread memory | MAJOR; prefer an opaque handle |
| Symbol visibility changed (`static`, `-fvisibility=hidden`, export macro) | newly visible = new ABI promise; hidden = removal | before/after visibility per symbol |
| `enum` value renumbered / member inserted | silent break across the boundary | MAJOR |
| Header split or include moved | leaks internals into the public tier or drops a relied-upon include | public-header tier contents unchanged |
| Python `__all__` entry moved/renamed/removed | public API break | deprecate before removal; note in the report |

For a shared library, keep the SONAME/ABI version distinct from the marketing version and bump neither implicitly.

## Ownership and Lifetime Hazards (C/C++)

These compile cleanly and crash later. Any row touching one names the hazard and the ownership decision, and goes to the language developer.

| Refactoring | Hazard |
|-------------|--------|
| Extract function that returns a pointer/reference | pointee may now be a local: dangling. Return by value or pass the storage in. |
| Move a `unique_ptr` into a helper | ownership transfers and the caller's pointer is null. Pass `T&`/`T*`/`std::span` for a borrow. |
| Split an arena/region lifetime across the new boundary | objects outlive their arena. Keep allocation and bulk-free in one owner. |
| Extract a `string_view`/`span` producer | the view can outlive a backing store that became a local. |
| Move a `free`/`fclose`/`close` into a helper | double-free or leak on an error path; check every early return. |
| Hoist a static/global into a parameter | changes initialization order and thread-safety assumptions. |

## The Refactor Ledger

`.context/.refactor/plan.md` is the source of truth across resumes; read it rather than relying on context memory.

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

Status: `pending -> applied -> verified -> committed`, or `reverted` on a red gate, or `skipped` (tool missing / behavior-changing).

## Extract-to-Module Mode (`--extract`)

Extract only when all hold: the unit is one self-contained responsibility; every include/import is classifiable as stdlib, external, or project-internal; a small public surface can be named; the original site can be replaced by a link/import with no behavior change; and there's real reuse or test-isolation value. Don't extract single-use code welded to app logic or a unit that would need its internals published. Avoid names like `utils`, `common`, `helpers`.

| Ecosystem | Result |
|-----------|--------|
| CMake | `add_library({TARGET} ...)` (STATIC unless a consumer needs SHARED), `target_include_directories({TARGET} PUBLIC include/)` with the private tier `PRIVATE`, consumers use `target_link_libraries(... PRIVATE {TARGET})` |
| Meson | `library('{TARGET}', ...)` + `declare_dependency(include_directories: ...)`; consumers take the dep object |
| Make | new object group + archive rule; explicit header install list |
| Python | package dir with its own `pyproject.toml`, added via `uv add --editable ./{TARGET}`, public surface in `__all__` |
| Bash | sourceable `lib/{TARGET}.sh` exposing only prefixed functions, no top-level side effects on source |

Steps:

1. Create the skeleton and manifest.
2. Move the code; a copy left behind is a defect.
3. Declare the public surface: published headers with explicit visibility (default-hidden + export macro for SHARED), `__all__`, or the shell function prefix.
4. Wire minimal dependencies in the new manifest.
5. Move the unit's tests with it and register them with the new target.
6. Replace the original site with a link/import.
7. Gate on `/system-developer:build-test` at the repo root, not just the new target.

## Workflow

### 1. Scope and baseline

1. Stop with "Path not found" if `path` doesn't exist.
2. Detect language(s), applying `--lang`. Nothing recognized: report and stop.
3. Run the Baseline Gate, teeing output to `.context/logs/`.

### 2. Plan

Agent tool, `subagent_type: system-developer:system-architector`:

```
Read-only refactor plan for `{path}` ({languages}; mode: {in-place | extract {TARGET}}).
Baseline: {baseline line}. Don't edit any file.
Identify code smells and SOLID violations with file:line evidence, then return an
ordered ledger of refactoring classes, local (rename, extract function, parameter
struct, named constant, flatten nesting, dispatch table) before boundary (split
translation unit/module, interface seam, dependency inversion, extract to
target/package). Per row: class, scope (local|boundary), owner (sys-code-fixer if
mechanical; c/cpp/python/bash-developer if it needs judgment), and an ABI/API impact
line. Public-header change, public struct layout, function moved between translation
units, symbol visibility, enum renumbering, or `__all__` change is MAJOR.
For C/C++, name any ownership/lifetime hazard per row (pointer to a new local, moved
unique_ptr, split arena lifetime, view outliving its backing store, moved free/close).
Every row must be independently buildable and testable. List classes that can't
preserve observable behavior separately as proposed changes.
Return the ledger as a table: # | Refactoring class | Scope | Owner | ABI/API impact | Status.
```

Write the ledger to `.context/.refactor/plan.md`, all rows `pending`. With `--dry-run`, report the ledger path and stop.

### 3. Per class, top-down

For each `pending` row: mark it `applied`, delegate, verify, commit. Before a MAJOR row, show the "Public-surface change" note and wait for confirmation.

**Delegate.** Agent tool with the row's owner:

| Row | `subagent_type` |
|-----|-----------------|
| mechanical | `system-developer:sys-code-fixer` |
| judgment, C / C++ / Python / Bash | `system-developer:c-developer` / `cpp-developer` / `python-developer` / `bash-developer` |

Prompt:

```
Apply only refactoring class **{class}** at {file:line refs} in `{path}` ({language}).
Minimal diff: change only what this class requires; don't reformat untouched code,
apply other ledger rows, or redesign. Observable behavior (return values, side effects,
exit codes, emitted diagnostics, public signatures) must stay identical; no API-shape
change beyond what the row states. ABI/API constraint: {impact line}.
{C/C++: Lifetime hazard: {hazard}. State the ownership decision for every pointer,
reference, view, or arena the change crosses.}
Don't run the test suite. Return every file and symbol touched, the rationale for
judgment rows, and any part you couldn't apply without redesigning.
```

If the fixer reports a row it can't apply mechanically, re-route that row to the language developer.

**Verify.** Run `/system-developer:build-test {path}`, teeing to `.context/logs/`. Green means the build passes and the same tests pass at the same count; then mark `verified`. Red: for an escalated row, give the failing excerpt back to the same agent for one corrective pass. Still red, or red on a mechanical row: revert the diff, mark `reverted`, and halt. Later rows aren't attempted.

**Commit.** Stage only the row's files and commit with a conventional subject naming the class, e.g. `refactor: extract parse_header() from decode()`. Follow the repo's commit format; no `--no-verify`, no AI-attribution trailers; branch first if on a protected branch; keep refactoring commits separate from feature commits. Mark the row `committed`.

Rationale and before/after notes go in the commit or PR, not in source comments.

### 4. Report

Emit the Output Format.

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

<!-- when applicable -->
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
Without a green baseline there is no oracle for "same behavior".
Fix the build/tests first, then re-run.
Suggestion: /system-developer:build-test {path}
```

### No test coverage over the target
```
Error: No tests exercise {path} — refusing to refactor blind.
Suggestion: /system-developer:gen-tests {path}
Then re-run: /system-developer:fix-refactor {path}
```

### Public-surface change
```
Note: This class changes the public surface ({header/struct/symbol/__all__}).
Impact: potential ABI/API break — semver MAJOR.
Confirm the semver plan (and the SONAME/ABI version for a shared library)
before it is applied.
```

### Extraction rejected
```
Note: {path} does not meet the extraction checklist ({failed check}).
Nothing extracted. Suggestion: run in-place refactoring first
(/system-developer:fix-refactor {path}), then re-evaluate --extract.
```

## See Also

- `/system-developer:build-test` — the gate run at baseline and after every class.
- `/system-developer:gen-tests` — establish coverage before refactoring an untested target.
- `/system-developer:review-code` — review the refactored diff for behavioral drift.
- `/system-developer:analyze-tech-debt` — prioritize debt before choosing what to refactor.
- `/system-developer:arch-review` — structural review when the ledger is mostly boundary classes.
- `/system-developer:fix-quick` — formatter/linter pass to clear noise before planning.
