---
description: Develop a C/C++/Python/Bash feature end-to-end — design, implementation, tests, sanitizers, and a security pass
argument-hint: [feature description or issue ref] [path (default .)] [--lang c|cpp|python|bash] [--tdd] [--resume|--restart]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
estimated-cost:
  min-tokens: 12000
  max-tokens: 60000
  model-distribution:
    haiku: 10%
    sonnet: 55%
    opus: 35%
---

# Feature Development
<!-- Updated: July 2026 -->

Take a feature in a C, C++, Python, or Bash project from a requirement to a built, tested, sanitizer-clean, security-reviewed change. Work is sequenced into four phases — design, implementation, tests and verification, security and API/ABI confirmation — each ending in a checkpoint that stops for explicit approval before the next begins.

Every phase writes its artifact to `.context/.feature-dev/`, and every later phase reads those files rather than trusting context memory. The build/test gate is `/system-developer:build-test`; for C/C++ (and Python native extensions) the memory-safety gate `/system-developer:sanitize-check` runs alongside it. A red build, a failing suite, or an unresolved sanitizer report halts the run.

[Extended thinking: The failure mode of end-to-end feature work in systems code is not writing the feature — it is discovering at merge time that the new public header broke the ABI, that the happy path leaks on the error path, or that the suite was never actually registered with the runner. This command front-loads the two decisions that are expensive to reverse: the structural/ownership/concurrency shape (delegated to `system-developer:system-architector`, which reasons in layered / hexagonal / plugin-registry / pipeline terms and states the API/ABI and semver impact *before* any code exists), and the test seams that shape implies. Implementation then fans out one language developer per language actually present — a mixed C-core-plus-Python-bindings feature is two agents, not one generalist — and reconverges on a hard build+test gate. Tests and sanitizers run as independent sub-steps because `sanitize-check` builds into its own `build-<kind>/` tree and cannot collide with the normal build. The security pass runs last, on real code rather than on a design sketch, in `skill: secure-coding` vocabulary and ranked P0-P3. Phase checkpoints exist because each phase's output is cheap to redirect and expensive to unwind.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **Execute phases and steps in order.** Do NOT skip ahead, reorder, or merge steps. The only sanctioned reordering is `--tdd`, which moves test generation ahead of implementation (see Options).
2. **Write each step's output file before the next step begins.** Every step produces its artifact under `.context/.feature-dev/`. Later steps read those files — do NOT rely on context-window memory for a prior step's decisions.
3. **Stop at every `PHASE CHECKPOINT`.** Use the AskUserQuestion tool to present the phase's findings and get explicit approval before continuing. A subagent returning is not approval.
4. **Halt on failure.** A red build, a failing suite, an unresolved sanitizer report, or an agent error STOPS the run. Present the first error and the log path, ask how to proceed, and do NOT silently continue to the next step.
5. **`/system-developer:build-test` is the only build/test gate.** Never invent another. It runs after implementation and again after tests, and once more after any remediation.
6. **Memory safety is not optional.** For C, C++, or a Python native extension, `/system-developer:sanitize-check` (ASan+UBSan) is part of verification, not an extra. A confirmed report is a halt, not a note.
7. **One developer per language actually present.** Detect languages per `skill: language-detection`; launch a language agent only for a language in scope. Independent-language work runs in parallel, then reconverges at a sync point.
8. **API/ABI impact is decided in Phase 1.** Public headers, exported symbols, and semver implications are design outputs written to `design.md` — never discovered after the code lands.
9. **Severity vocabulary is P0-P3** per `skill: severity-matrix`. P0/P1 block completion; P2/P3 are reported, not silently fixed.
10. **Never enter plan mode. This command IS the procedure — execute it.**

## Usage

```bash
# Develop a feature in the current project
/system-developer:develop-feature "streaming zstd decoder with bounded memory"

# Scope the work to a subproject
/system-developer:develop-feature "retry with jitter for the upload client" services/uploader

# Work from a tracked issue
/system-developer:develop-feature "#142"

# Tests first — generate a failing suite before implementation
/system-developer:develop-feature "config schema validation" --tdd

# Force the language set when detection is ambiguous (extensionless scripts)
/system-developer:develop-feature "release preflight checks" scripts/ --lang bash

# Continue an interrupted run from its recorded step
/system-developer:develop-feature --resume
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `feature` | required | Feature description, or an issue reference (`#142`). Carried verbatim into every delegated prompt. |
| `path` | `.` | Project root for detection, build, and test. All inventory and gates are rooted here. |
| `--lang c\|cpp\|python\|bash` | auto | Force the implementation agent set instead of detecting. Use for extensionless scripts or to narrow a mixed repo. Conceptually repeatable (`--lang c --lang python`). |
| `--tdd` | off | Run test generation (Phase 3 step 6) **before** implementation. The suite is expected RED until implementation lands; the Phase 2 gate then requires it green. |
| `--resume` | off | Read `.context/.feature-dev/state.json` and continue from `current_step`. Fails if no session exists. |
| `--restart` | off | Archive any existing session to `.context/.feature-dev/archive-<timestamp>/` and start at step 1. |

`--resume` and `--restart` are mutually exclusive. Passing neither, with a session already present, triggers the interactive prompt in Pre-flight Checks.

## Pre-flight Checks

### 1. Detect an existing session

Read `.context/.feature-dev/state.json` if it exists:

- `status: "in_progress"` → print `current_phase`, `current_step`, and `completed_steps`, then ask (AskUserQuestion) whether to **resume** from that step or **restart** fresh.
- `status: "complete"` → ask whether to **archive and start fresh** or **abort** (the prior feature's artifacts are still readable).
- `--resume` / `--restart` answer this question non-interactively; honor the flag and skip the prompt.

Archiving moves the whole directory to `.context/.feature-dev/archive-<timestamp>/`. Never overwrite a prior session's artifacts in place.

### 2. Initialize state

Create `.context/.feature-dev/` and write `state.json`:

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

After **every** step: append the step number to `completed_steps`, append the artifact to `files_created`, advance `current_step` / `current_phase`, and refresh `last_updated`. On a halt, set `status: "halted"` and record the failing step. On completion, set `status: "complete"`.

## Phase 1: Design

### Step 1 — Inventory (shell + Read, no agent)

Establish the ground truth the design phase reasons over. Root the scan at `path`.

| Probe | Read |
|-------|------|
| Build system | `CMakeLists.txt` / `CMakePresets.json`, `meson.build`, `Makefile`, `pyproject.toml` + `uv.lock` |
| Languages present | file extensions and shebangs per `skill: language-detection` — do not fork its rules |
| Test framework | GoogleTest / Catch2 / Unity / CMocka registrations, `tests/` + `conftest.py` (pytest), `tests/*.bats` |
| Public surface | public header dir, export macros / `-fvisibility` settings, `__all__`, entry points |
| Current standard | `CMAKE_C_STANDARD` / `CMAKE_CXX_STANDARD` / `cpp_std=`, `requires-python` |

Write `.context/.feature-dev/inventory.md` and record the detected languages in `state.json.languages`. If no C/C++/Python/Bash sources are found, stop with the Error Handling message.

### Step 2 — Architecture and API/ABI design

**Use Task tool with subagent_type="system-developer:system-architector"**

Prompt: "Design the implementation of this feature: $ARGUMENTS. Project inventory (build system, languages, test framework, public surface, current standards) is in `.context/.feature-dev/inventory.md` — read it first. Deliver: (1) the structural pattern — layered libraries, hexagonal/ports-adapters, plugin/registry, or pipeline/dataflow — with the reason it fits; (2) the concurrency axis (event-loop / thread-pool / process-pool) and the ownership axis (arena/region, RAII, refcount, GC-boundary) chosen independently, each with a language/version marker and a fallback per `skill: version-feature-matrix`; (3) the exact module/target/package layout with project-specific names; (4) **API/ABI impact** — which public headers change, which symbols become exported, whether the change is source- or binary-incompatible, and the resulting semver step (MAJOR/MINOR/PATCH) plus SONAME implications for shared libraries; (5) test seams the structure must expose per `skill: testing-principles`; (6) migration/transition risks. Consult `skill: build-systems` for target and visibility mechanics and `skill: ffi-interop` for any C-to-Python boundary. Write the result to `.context/.feature-dev/design.md`. Do NOT write implementation code."

Expected output: `.context/.feature-dev/design.md` with pattern, axes, layout, API/ABI + semver verdict, test seams, risks.

[SYNC POINT: `design.md` must exist and state an explicit API/ABI verdict before Phase 1 closes.]

---

### PHASE CHECKPOINT

**Completed:** Phase 1 — Design (inventory, architecture pattern, ownership/concurrency axes, API/ABI and semver impact, test seams).

**Next:** Phase 2 — Implementation (one language developer per detected language, then the build/test gate).

Stop here. Use the AskUserQuestion tool to present the pattern, the API/ABI verdict, and the detected language set, and ask the user to approve proceeding, adjust the design, or abort.

---

## Phase 2: Implementation

### Step 3 — Implement (parallel, one agent per language)

Launch **one agent per language recorded in `state.json.languages`**, simultaneously — they are independent. Each reads `design.md` and `inventory.md` first and writes `.context/.feature-dev/implementation-<lang>.md`.

The shared prompt below is issued to each launched agent with `{language}`, `{lang}`, and `{focus}` filled from its row:

Prompt: "Implement the {language} portion of this feature: $ARGUMENTS. Read `.context/.feature-dev/design.md` (pattern, ownership/concurrency axes, module layout, API/ABI verdict) and `.context/.feature-dev/inventory.md` first, and follow them — do not re-architect. Focus areas: {focus}. Honor the project's existing build system and conventions; wire new targets/modules in. Respect the API/ABI verdict exactly: do not export a symbol or change a public struct/signature the design did not sanction. Do NOT write tests (a later step owns them). Do NOT run the full suite. Write a summary of files added/changed, public-surface deltas, and any deviation from the design to `.context/.feature-dev/implementation-{lang}.md`."

**C — Use Task tool with subagent_type="system-developer:c-developer"**
- `{focus}`: ownership and lifetime per `skill: c-memory-ownership`, checked returns and `errno`, integer/overflow safety, cleanup on every error path, header and export-macro discipline.

**C++ — Use Task tool with subagent_type="system-developer:cpp-developer"**
- `{focus}`: RAII / Rule of Zero, a stated exception-safety guarantee per function, non-owning-view (`string_view`/`span`) lifetimes, `skill: cpp-concurrency` for the chosen axis.

**Python — Use Task tool with subagent_type="system-developer:python-developer"**
- `{focus}`: strict typing per `skill: python-typing`, `skill: python-concurrency` for the chosen axis, context-managed resources, `__all__` and public-surface hygiene.

**Bash — Use Task tool with subagent_type="system-developer:bash-developer"**
- `{focus}`: strict-mode prologue and `trap` cleanup per `skill: bash-scripting`, quoting, injection-safe process invocation, shellcheck-clean as the exit criterion.

If a file's language is genuinely ambiguous after `skill: language-detection` tie-breaks, route it to `system-developer:system-developer` and note the routing.

[SYNC POINT: Wait for every language agent before running the gate.]

### Step 4 — Build/test gate

Run `/system-developer:build-test {path}`, teeing to `.context/logs/`.

- **Green** → record the result in `state.json`, proceed to the checkpoint.
- **Red** → **halt** (Rule 4). Classify the first error as configure / compile / link / test, hand that excerpt back to the owning language agent for **one** bounded corrective pass, then re-run the gate. Still red: stop and report.

Under `--tdd` the suite from step 6 already exists and MUST be green here — a still-red TDD suite means the implementation is incomplete, not that the gate should be waived.

---

### PHASE CHECKPOINT

**Completed:** Phase 2 — Implementation (per-language changes, public-surface deltas, green build and existing suite).

**Next:** Phase 3 — Tests & Verification (generate and register the suite; run the build/test and sanitizer gates in parallel).

Stop here. Use the AskUserQuestion tool to present the files changed, the public-surface delta versus the design, and the gate result, and ask the user to approve proceeding, request revisions, or abort.

---

## Phase 3: Tests & Verification

Under `--tdd`, step 6 runs **before** step 3 and its suite is expected RED until implementation lands; steps 7a/7b are unchanged.

### Step 6 — Generate and register the suite

**Use Task tool with subagent_type="system-developer:sys-test-generator"**

Prompt: "Generate tests for this feature: $ARGUMENTS. Read `.context/.feature-dev/design.md` (test seams, ownership and concurrency axes) and every `.context/.feature-dev/implementation-*.md` first. Reuse the framework already in use — GoogleTest / Catch2 / Unity / CMocka for C/C++, pytest (with Hypothesis for property-based cases) for Python, bats for Bash — per `.context/.feature-dev/inventory.md`; never introduce a second framework. Cover the happy path, edge cases, failure modes, and the error/cleanup paths the ownership model implies, per `skill: testing-principles` (plus `skill: python-testing` / `skill: bash-testing` where applicable). **Registration is part of the deliverable**: wire tests into the build so the runner discovers them (`add_test` + `gtest_discover_tests`/`catch_discover_tests`, correct `tests/` layout and `conftest.py`, `tests/*.bats`) and prove discovery with `ctest -N` / `pytest --collect-only` / `bats -c`. Write the suite inventory and the discovery proof to `.context/.feature-dev/tests.md`."

### Step 7a — Build/test gate (parallel with 7b)

Run `/system-developer:build-test {path}`. The new suite must build **and** run. A suite that compiles but the runner never discovers is a failure — route it back to `sys-test-generator` for one corrective pass, then halt if still unresolved.

### Step 7b — Memory-safety gate (parallel with 7a)

For C, C++, or a Python native extension, run `/system-developer:sanitize-check asan {path}` (ASan+UBSan). It builds into its own `build-asan/` tree, so it does not collide with step 7a's build — run both simultaneously.

- **Clean** → record in `state.json` and proceed.
- **Findings** → **halt** (Rule 6). Route the deduplicated triage table to the owning language agent, fix, and re-run *both* gates. A confirmed report is never suppressed or downgraded to a note.
- **Pure Python / Bash with no native extension** → record "not applicable" explicitly in the report; do not silently skip.

[SYNC POINT: Both gates must report before the checkpoint.]

---

### PHASE CHECKPOINT

**Completed:** Phase 3 — Tests & Verification (registered suite with discovery proof, green build/test gate, sanitizer result).

**Next:** Phase 4 — Security & API/ABI Confirmation (secure-coding audit, exported-symbol verification, P0/P1 remediation).

Stop here. Use the AskUserQuestion tool to present the suite inventory, both gate results, and any sanitizer findings, and ask the user to approve proceeding, request more coverage, or abort.

---

## Phase 4: Security & API/ABI Confirmation

### Step 8 — Security pass

**Use Task tool with subagent_type="system-developer:sys-security-auditor"**

Prompt: "Read-only security audit of the feature implemented for: $ARGUMENTS. The changed files are listed in `.context/.feature-dev/implementation-*.md`; the design and trust boundaries are in `.context/.feature-dev/design.md`. Audit in `skill: secure-coding` terms: injection-safe process execution (no `shell=True`, no `eval`, argv arrays, `--` separators), memory-corruption classes and their sanitizer mapping, integer safety and overflow-checked arithmetic, path traversal and TOCTOU on any filesystem access, unsafe deserialization, input validation at every trust boundary the design names, and secrets hygiene. Map each finding to a CWE. Rank severity P0-P3 per `skill: severity-matrix`. Do NOT edit any file. Write findings as `{file, line, category (CWE), severity, why, fix, confidence}` to `.context/.feature-dev/security.md`. If there are no material issues, say so directly — do not manufacture findings."

### Step 9 — API/ABI confirmation

**Use Task tool with subagent_type="system-developer:system-architector"**

Prompt: "Confirm the shipped API/ABI matches the verdict recorded in `.context/.feature-dev/design.md` for: $ARGUMENTS. Compare the design's sanctioned public surface against what the implementation actually exposes — public headers, exported symbols (inspect with `nm`/`readelf`/`otool` against the built artifact where a shared library exists), public struct layouts and function signatures, `enum` values, and the Python `__all__` / entry-point surface. Report any unsanctioned export, layout change, or signature change as an ABI break, state the corrected semver step and SONAME implication, and rank it P0-P3. Write the verdict to `.context/.feature-dev/abi.md`."

### Step 10 — Remediation (P0/P1 only)

**Use Task tool with subagent_type="system-developer:sys-code-fixer"**

Prompt: "Apply minimal, targeted fixes for these P0/P1 findings: {findings from security.md and abi.md as `{file, line, category, fix}`}. Minimal-diff gate: change only what each finding requires; do not refactor, reformat untouched code, or touch P2/P3 items. Report each change as `{file, line, finding, change}` and list anything you could NOT safely auto-fix (needs design judgment or an API redesign)."

Then re-run **both** gates (`/system-developer:build-test`, and `/system-developer:sanitize-check asan` where applicable). Findings needing design judgment go back to `system-developer:system-architector`, not to the fixer. Unresolved P0/P1 → halt; the feature is not complete.

## Output Format

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

<!-- on a halt -->
### Halt
- **Phase / step:** {phase} / {step}
- **Cause:** {red build | failing suite | sanitizer report | unresolved P0}
- **Evidence:** {first error line; full log at .context/logs/…}
- **Resume with:** /system-developer:develop-feature --resume
```

## Error Handling

| Failure | Criticality | Action |
|---------|-------------|--------|
| No C/C++/Python/Bash sources at `path` | **fatal** | Stop before step 1. "No reviewable sources found — pass an explicit path, or `--lang` for extensionless scripts." |
| `--resume` with no session | **fatal** | Stop. "No session at `.context/.feature-dev/state.json`. Run without `--resume` to start one." |
| Architect returns no API/ABI verdict (step 2) | **fatal** | Re-prompt once for the verdict; Rule 8 forbids proceeding without it. |
| Build/test RED (step 4, 7a, or post-fix) | **fatal** | One bounded corrective pass with the owning language agent, then halt with the first error and log path. |
| Sanitizer findings (step 7b) | **fatal** | Halt. Route the triage table to the language agent; never suppress or downgrade (Rule 6). |
| Tests generated but not discoverable | **fatal** | One corrective pass with `sys-test-generator`, then halt. Un-run tests are not a deliverable. |
| Unresolved P0/P1 after step 10 | **fatal** | Report `HALTED`; the feature is not complete. |
| Sanitizers not applicable (pure Python/Bash) | degradable | Record "not applicable" with the reason in the report; continue. |
| Toolchain binary missing (`cmake`, `uv`, `bats`, `clang`, `shellcheck`) | degradable | Print the install hint, skip that language's gate, note the reduced coverage in the report, continue. |
| One language agent fails, others succeed | degradable | Record the partial result, continue to the sync point, and surface the failure at the checkpoint for the user to decide. |
| P2/P3 findings only | degradable | Report them; do not auto-fix, do not block completion. |

## See Also

- `skill: language-detection` — canonical marker → language → agent routing used by step 1.
- `skill: build-systems` — target, link-scope, and symbol-visibility mechanics behind the design's API/ABI verdict.
- `skill: testing-principles` — coverage strategy and test seams the generated suite is held to.
- `skill: secure-coding` — the vocabulary of the Phase 4 audit (injection-safe execution, memory-corruption classes, integer safety, TOCTOU, secrets).
- `skill: severity-matrix` — the P0-P3 definitions used across Phases 3 and 4.
- `skill: version-feature-matrix` — standard/version floors and fallbacks the design must state per recommendation.
- `/system-developer:build-test` — the single build/test gate, run after implementation, after tests, and after remediation.
- `/system-developer:sanitize-check` — the ASan/UBSan memory-safety gate for C/C++ and Python native extensions.
- `/system-developer:arch-select` — pattern selection alone, when a feature needs a design decision but not a full build.
- `/system-developer:gen-tests` — the standalone test-generation path for code that already exists.
- `/system-developer:review-code` — the P0-P3 review pass to run on the finished diff before merge.
