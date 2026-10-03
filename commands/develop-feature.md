---
description: Develop a C/C++/Python/Bash feature end-to-end — design, implementation, tests, sanitizers, and a security pass
argument-hint: [feature description or issue ref] [path (default .)] [--lang c|cpp|python|bash] [--tdd] [--resume|--restart]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, Skill
estimated-cost:
  min-tokens: 12000
  max-tokens: 60000
  model-distribution:
    haiku: 10%
    sonnet: 55%
    opus: 35%
---

# Feature Development

Take a feature in a C, C++, Python, or Bash project from a requirement to a built, tested, sanitizer-clean, security-reviewed change, in four phases: design, implementation, tests and verification, security and API/ABI confirmation. The expensive-to-reverse decisions (structure, ownership, concurrency, API/ABI and semver impact) are made in Phase 1, before any code exists.

## Rules

### Flow and checkpoints

- Run phases and steps in order. The only reordering is `--tdd`, which moves step 6 ahead of step 3.
- Each step writes its artifact under `.context/.feature-dev/` before the next begins, and later steps read those files rather than relying on earlier context.
- Stop at every PHASE CHECKPOINT and get approval with AskUserQuestion. A subagent returning is not approval.
- Halt on failure: a red build, failing suite, unresolved sanitizer report, or agent error stops the run. Present the first error and the log path and ask how to proceed.

### Gates and grading

- `/system-developer:build-test` is the only build/test gate. For C, C++, or a Python native extension, `/system-developer:sanitize-check asan` (ASan+UBSan) is part of verification, and a confirmed report is a halt.
- Launch one language agent per language actually present; independent languages run in parallel and reconverge before the gate.
- The API/ABI verdict (public headers, exported symbols, semver step) is a Phase 1 output in `design.md`.
- Grade findings P0–P3: **P0** correctness or security broken (memory corruption, injection, UB with observable impact, unsanctioned ABI break); **P1** defect likely to bite (race, leak on an error path, missing validation at a trust boundary); **P2** edge-case or non-critical path; **P3** cosmetic or hardening-only. P0/P1 block completion; P2/P3 are reported, not auto-fixed.

## Usage

```bash
/system-developer:develop-feature "streaming zstd decoder with bounded memory"
/system-developer:develop-feature "retry with jitter for the upload client" services/uploader
/system-developer:develop-feature "#142"                                   # from an issue
/system-developer:develop-feature "config schema validation" --tdd         # failing suite first
/system-developer:develop-feature "release preflight checks" scripts/ --lang bash
/system-developer:develop-feature --resume
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `feature` | required | Feature description, or an issue reference (`#142`). Carried verbatim into every delegated prompt. |
| `path` | `.` | Project root for detection, build, and test. |
| `--lang c\|cpp\|python\|bash` | auto | Force the implementation agent set instead of detecting. Use for extensionless scripts or to narrow a mixed repo. Repeatable (`--lang c --lang python`). |
| `--tdd` | off | Run step 6 (test generation) before step 3. The suite is expected red until implementation lands; the step 4 gate then requires it green. |
| `--resume` | off | Read `.context/.feature-dev/state.json` and continue from `current_step`. Fails if no session exists. |
| `--restart` | off | Archive any existing session to `.context/.feature-dev/archive-<timestamp>/` and start at step 1. |

`--resume` and `--restart` are mutually exclusive.

## Pre-flight

**Existing session.** If `.context/.feature-dev/state.json` exists and neither flag was passed, ask with AskUserQuestion:

- `status: "in_progress"` or `"halted"`: show `current_phase`, `current_step`, `completed_steps`; resume or restart.
- `status: "complete"`: archive and start fresh, or abort.

Archiving moves the whole directory to `archive-<timestamp>/`; never overwrite a prior session in place.

**Initialize** `.context/.feature-dev/state.json`:

```json
{
  "command": "$ARGUMENTS",
  "status": "in_progress",
  "current_step": 1,
  "current_phase": 1,
  "completed_steps": [],
  "files_created": [],
  "languages": [],
  "started_at": "ISO_TIMESTAMP",
  "last_updated": "ISO_TIMESTAMP"
}
```

After every step, append to `completed_steps` and `files_created`, advance `current_step`/`current_phase`, and refresh `last_updated`. On a halt set `status: "halted"` with the failing step; on completion set `"complete"`.

## Phase 1: Design

### Step 1 — Inventory (shell + Read, no agent)

Rooted at `path`, excluding `build*/`, `.venv/`, and vendored trees:

| Probe | Read |
|-------|------|
| Build system | `CMakeLists.txt` / `CMakePresets.json`, `meson.build`, `Makefile`, `pyproject.toml` + `uv.lock` |
| Languages | build manifests, then extensions, then shebangs; `--lang` overrides |
| Test framework | GoogleTest / Catch2 / Unity / CMocka registrations, `tests/` + `conftest.py`, `tests/*.bats` |
| Public surface | public header dir, export macros / `-fvisibility`, `__all__`, entry points |
| Current standard | `CMAKE_C_STANDARD` / `CMAKE_CXX_STANDARD` / `cpp_std=`, `requires-python` |

Write `inventory.md` and record the languages in `state.json.languages`. No C/C++/Python/Bash sources → stop (Error Handling).

### Step 2 — Architecture and API/ABI design

Agent tool, `subagent_type="system-developer:system-architector"`:

"Design the implementation of this feature: $ARGUMENTS. Read `.context/.feature-dev/inventory.md` first. Deliver: (1) the structural pattern with the reason it fits; (2) the concurrency and ownership axes, chosen independently, each with a language/version marker and a fallback; (3) the exact module/target/package layout with project-specific names; (4) API/ABI impact: which public headers change, which symbols become exported, source- or binary-incompatible, the semver step (MAJOR/MINOR/PATCH), and SONAME implications for shared libraries; (5) the test seams the structure must expose; (6) migration risks. Write it to `.context/.feature-dev/design.md`. Don't write implementation code."

`design.md` must state an explicit API/ABI verdict before Phase 1 closes.

### PHASE CHECKPOINT 1

Present the pattern, the API/ABI verdict, and the detected languages. Ask: proceed, adjust the design, or abort.

## Phase 2: Implementation

### Step 3 — Implement (parallel, one agent per language)

Launch one agent per language in `state.json.languages`, all in one message:

"Implement the {language} portion of this feature: $ARGUMENTS. Read `.context/.feature-dev/design.md` and `.context/.feature-dev/inventory.md` first and follow them; don't re-architect. Focus: {focus}. Use the project's existing build system and conventions and wire new targets/modules in. Don't export a symbol or change a public struct or signature the design's API/ABI verdict didn't sanction. Don't write tests or run the full suite; later steps own those. Write the files added/changed, public-surface deltas, and any deviation from the design to `.context/.feature-dev/implementation-{lang}.md`."

#### Per-language focus

| Language | `subagent_type` | `{focus}` |
|----------|-----------------|-----------|
| C | `system-developer:c-developer` | ownership and lifetime, checked returns and `errno`, integer overflow safety, cleanup on every error path, header and export-macro discipline |
| C++ | `system-developer:cpp-developer` | RAII / Rule of Zero, a stated exception-safety guarantee per function, `string_view`/`span` lifetimes, the chosen concurrency axis |
| Python | `system-developer:python-developer` | strict typing, the chosen concurrency axis, context-managed resources, `__all__` and public-surface hygiene |
| Bash | `system-developer:bash-developer` | strict-mode prologue and `trap` cleanup, quoting, injection-safe process invocation, shellcheck-clean |

Route a file whose language stays ambiguous to `system-developer:system-developer` and note it. Wait for every agent before the gate.

### Step 4 — Build/test gate

Run `/system-developer:build-test {path}`, teeing to `.context/logs/`.

- Green: record in `state.json`, go to the checkpoint.
- Red: classify the first error (configure / compile / link / test), give that excerpt to the owning language agent for one corrective pass, and re-run. Still red: halt.

Under `--tdd` the step 6 suite must be green here; a still-red suite means the implementation is incomplete.

### PHASE CHECKPOINT 2

Present files changed, the public-surface delta versus the design, and the gate result. Ask: proceed, revise, or abort.

## Phase 3: Tests & Verification

### Step 6 — Generate and register the suite

Agent tool, `subagent_type="system-developer:sys-test-generator"`:

"Generate tests for this feature: $ARGUMENTS. Read `.context/.feature-dev/design.md` (test seams, ownership and concurrency axes), `.context/.feature-dev/inventory.md`, and every `.context/.feature-dev/implementation-*.md` first. Use the framework the project already uses. Cover the happy path, edge cases, failure modes, and the error/cleanup paths the ownership model implies. Register the tests so the runner discovers them and prove it from a `/system-developer:build-test` run. Write the suite inventory and the discovery proof to `.context/.feature-dev/tests.md`."

(Under `--tdd` there are no `implementation-*.md` files yet; the agent works from the design.)

### Steps 7a and 7b — Gates (run in parallel)

**7a.** `/system-developer:build-test {path}`. The new suite must build and run. A suite the runner doesn't discover goes back to `sys-test-generator` for one corrective pass, then halt.

**7b.** For C, C++, or a Python native extension, `/system-developer:sanitize-check asan {path}`. It builds into its own `build-asan/` tree, so it can run alongside 7a.

- Clean: record in `state.json`.
- Findings: halt. Route the deduplicated triage table to the owning language agent, fix, and re-run both gates. Never suppress or downgrade a confirmed report.
- Pure Python/Bash with no native extension: record "not applicable" in the report.

Both gates must report before the checkpoint.

### PHASE CHECKPOINT 3

Present the suite inventory, both gate results, and any sanitizer findings. Ask: proceed, add coverage, or abort.

## Phase 4: Security & API/ABI Confirmation

Steps 8 and 9 are independent; launch them in one message.

### Step 8 — Security pass

Agent tool, `subagent_type="system-developer:sys-security-auditor"`:

"Read-only security audit of the feature implemented for: $ARGUMENTS. Changed files are listed in `.context/.feature-dev/implementation-*.md`; the design and trust boundaries are in `.context/.feature-dev/design.md`. Check injection-safe process execution, memory-corruption classes, integer overflow, path traversal and TOCTOU on filesystem access, unsafe deserialization, input validation at every trust boundary the design names, and secrets hygiene. Map each finding to a CWE and rank it P0 (correctness or security broken) to P3 (hardening only). Don't edit files. Write findings as `{file, line, category (CWE), severity, why, fix, confidence}` to `.context/.feature-dev/security.md`. If there are no material issues, say so."

### Step 9 — API/ABI confirmation

Agent tool, `subagent_type="system-developer:system-architector"`:

"Confirm the shipped API/ABI matches the verdict in `.context/.feature-dev/design.md` for: $ARGUMENTS. Compare the sanctioned public surface with what the implementation exposes: public headers, exported symbols (`nm`/`readelf`/`otool` on the built artifact where a shared library exists), public struct layouts and signatures, `enum` values, and the Python `__all__` / entry-point surface. Report any unsanctioned export, layout, or signature change as an ABI break with the corrected semver step and SONAME implication, ranked P0–P3. Write the verdict to `.context/.feature-dev/abi.md`."

### Step 10 — Remediation (P0/P1 only)

Agent tool, `subagent_type="system-developer:sys-code-fixer"`:

"Apply minimal fixes for these P0/P1 findings: {findings from security.md and abi.md as `{file, line, category, fix}`}. Change only what each finding requires; don't refactor, reformat untouched code, or touch P2/P3 items. Report each change as `{file, line, finding, change}` and list anything you couldn't safely fix (needs design judgment or an API redesign)."

Re-run both gates. Findings that need design judgment go to `system-developer:system-architector`, not the fixer. Unresolved P0/P1 → halt; the feature is not complete.

## Output Format

One report, shown in three parts.

```markdown
## Feature Development Report

**Feature:** {$ARGUMENTS}
**Path:** {path} | **Languages:** {detected} | **Mode:** {standard | --tdd}
**Session:** .context/.feature-dev/ | **Status:** COMPLETE / HALTED ({phase, reason})

### Phase 1 — Design
- **Pattern:** {layered | hexagonal | plugin-registry | pipeline} — {one-line rationale}
- **Ownership / concurrency:** {axis} / {axis} ({version marker}, fallback: {…})
- **API/ABI:** {no change | additive | breaking} → semver **{MAJOR|MINOR|PATCH}** {SONAME note}
- **Artifact:** design.md

### Phase 2 — Implementation
| Language | Agent | Files changed | Public-surface delta |
|----------|-------|---------------|----------------------|
| {lang} | {agent} | {n} | {added exports / none} |

**Build/test gate:** GREEN / RED ({first error}, log: .context/logs/…)
```

### Report: tests, security, and API/ABI

```markdown
### Phase 3 — Tests & Verification
- **Framework:** {googletest | catch2 | unity | cmocka | pytest | bats} | **Tests added:** {n} | **Discovery proof:** {ctest -N | pytest --collect-only | bats -c}
- **Build/test gate:** GREEN / RED
- **Sanitizers (ASan+UBSan):** CLEAN / {n} findings / not applicable ({reason})

### Phase 4 — Security & API/ABI
| Priority | Security | API/ABI |
|----------|----------|---------|
| P0 | {n} | {n} |
| P1 | {n} | {n} |
| P2 / P3 | {n} / {n} | {n} / {n} |

| File:Line | Category (CWE) | Why | Fix | Confidence |
|-----------|----------------|-----|-----|------------|
| {file}:{line} | {cwe} | {why} | {fix} | {high/med/low} |

**Remediated:** {n} P0/P1 | **Left for manual handling:** {list or "none"}
**Post-fix gates:** build/test {GREEN|RED} | sanitizers {CLEAN|findings}
```

### Report: halt block

```markdown
<!-- on a halt -->
### Halt
- **Phase / step:** {phase} / {step}
- **Cause:** {red build | failing suite | sanitizer report | unresolved P0}
- **Evidence:** {first error line; full log at .context/logs/…}
- **Resume with:** /system-developer:develop-feature --resume
```

## Error Handling

### Fatal failures

| Failure | Criticality | Action |
|---------|-------------|--------|
| No C/C++/Python/Bash sources at `path` | fatal | Stop before step 1: "No reviewable sources found — pass an explicit path, or `--lang` for extensionless scripts." |
| `--resume` with no session | fatal | Stop: "No session at `.context/.feature-dev/state.json`. Run without `--resume` to start one." |
| Architect returns no API/ABI verdict (step 2) | fatal | Re-prompt once for the verdict; don't proceed without it. |
| Build/test red (step 4, 7a, or post-fix) | fatal | One corrective pass with the owning language agent, then halt with the first error and log path. |
| Sanitizer findings (step 7b) | fatal | Halt; route the triage table to the language agent. |
| Tests generated but not discoverable | fatal | One corrective pass with `sys-test-generator`, then halt. |
| Unresolved P0/P1 after step 10 | fatal | Report HALTED. |

### Degradable failures

| Failure | Criticality | Action |
|---------|-------------|--------|
| Sanitizers not applicable (pure Python/Bash) | degradable | Record "not applicable" with the reason; continue. |
| Toolchain binary missing (`cmake`, `uv`, `bats`, `clang`, `shellcheck`) | degradable | Print the install hint, skip that language's gate, note the reduced coverage; continue. |
| One language agent fails, others succeed | degradable | Record the partial result and raise it at the checkpoint. |
| P2/P3 findings only | degradable | Report them; don't auto-fix or block. |

## See Also

- `/system-developer:arch-select` — pattern selection alone, without building.
- `/system-developer:gen-tests` — test generation for code that already exists.
- `/system-developer:review-code` — P0-P3 review of the finished diff before merge.
