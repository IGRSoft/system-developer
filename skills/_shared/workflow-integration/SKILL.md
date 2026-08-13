---
name: workflow-integration
description: Guide for integrating with corpflow 11-stage pipeline (v4.0.13). Use when participating in structured workflow stages.
---

# Workflow Integration Guide

When invoked from corpflow, follow these guidelines for seamless collaboration.

## 11-Stage Pipeline (Default)

```
PL → AR → TL → DV → DR → SR → QA → DC → RE → FN → ST
          ↑    ↓    ↑    ↑    ↑              ↑
   system-developer agents contribute to AR, DV, DR, SR, QA, and RE
```

| Code | Stage | corpflow Agent | system-developer Contribution |
|------|-------|---------------|-------------------------------|
| PL | Planning | product-manager | — |
| AR | Architecture | software-architector | system-architector (consultation: layering, ownership models, API/ABI design) |
| TL | Team Lead | team-lead | — |
| DV | Development | developer → **system-developer** | **Primary**: system-developer router, c-developer, cpp-developer, python-developer, bash-developer |
| **DR** | **Developer Review** | **technical-lead** | **Support**: sys-code-fixer (fix application), system-architector (pattern consult) |
| SR | Security Review | security-reviewer | Context: sys-security-auditor (sanitizers, CWE mapping, hardening flags) |
| QA | QA Testing | qa-engineer | Support: sys-test-generator |
| DC | Documentation | technical-writer | — |
| RE | Release Engineering | release-engineer | Packaging: sys-dependency-manager (lockfiles, pins), version/tarball/wheel preparation |
| FN | Finalization | project-manager | — |
| ST | Stakeholder | stakeholder | — |

## Worktask Invocation (v4.0.0)

Launch is **only** via the `/worktask` slash command (or `Skill corpflow:worktask`) plus flags. Message-prefix triggers (`micro:`/`quick:`/`worktask:`/`fworktask:`/`emergency:`) are **removed**. PL0 dynamic sizing selects which of the 9 stages run.

| Flag | Effect |
|------|--------|
| `--secure` / `--full` | 11-stage pipeline (adds SR + RE) |
| `--emergency` | Incident pipeline IR→DV→DR→QA→RE→FN (DR enforces minimal-diff) |
| `--auto-plan` | Bypass the PL plan gate |
| `--auto-finalization` | Bypass the FN gate |
| `--ethics-review` | Add ET after PL |
| `--sequential` | DC waits for QA |

Multi-issue batches: `/megatask <milestone#>` or `/megatask --issues 12,15,18` — dependency-DAG ordered, isolated per-issue worktrees.

## Human Checkpoints — PL & FN Gates

Two independent human checkpoints, both carried on PL0 metadata:

| Gate | Carrier | Default | Bypassed by |
|------|---------|---------|-------------|
| PL gate | `PL0.metadata.plan_gate` | `checkpoint` (post-PL0 plan approval) | `--auto-plan` or `--emergency` |
| FN gate | `PL0.metadata.fn_gate` | `checkpoint` (pre-finalization commit/push/PR) | `--auto-finalization` or `--emergency` |

system-developer agents are **invoked specialists that run between the gates** — they do not own gate logic. On a gate loop-back, DV/DR/QA may re-run (`retry_count++`, `run_index` bump).

## DV Contract for Systems Work

The DV agent writes `.context/development-N.md`. Mandatory H2 anchors are fixed by corpflow's anchor allow-list (`handoff-protocol.md#anchor-allow-list`): `## files-changed`, `## tests-added`, `## deviations`, `## follow-ups`. Systems-specific sections nest as H3 under them:

| Section | Anchor level | Content |
|---------|--------------|---------|
| Files Changed | `## files-changed` | File / change / why table |
| Decisions | `### decisions` (under files-changed) | Non-obvious implementation choices with rationale |
| Tool Invocations | `### tool-invocations` (under files-changed) | Exact build/lint commands run (`cmake --build`, `uv run pytest`, `shellcheck`, …) |
| Tests Added | `## tests-added` | Test files + what each covers |
| Build Evidence | `### build-evidence` (under tests-added) | Per-language toolchain + gate result (see below), plus the test transcript path in `.context/logs/` |
| Deviations | `## deviations` | Departures from `analyzing-N.md` decisions |
| Follow-ups | `## follow-ups` | Deferred work, flagged risks |

Build Evidence is non-negotiable, but **which rows apply depends on the language of the change** — a compiler line and a `-Wall -Wextra` count exist only for C/C++:

| Language of change | Toolchain line | Zero-findings gate | Also |
|---|---|---|---|
| C / C++ | compiler + standard (e.g. `clang -std=c++23` — verify against your toolchain) | warning count at `-Wall -Wextra` (target: 0) | sanitizer status |
| Python | `python3 --version` (and `uv --version` if used) | `ruff check` findings (target: 0) + type-checker result | sanitizer status only if a native extension was touched |
| Bash | `bash --version` (note the macOS 3.2 floor) | `shellcheck` findings (target: 0) + `shfmt` clean | — |

Every language needs a toolchain line, its own gate result, and a transcript path; an artifact missing those is incomplete. Never demand a compiler line or a `-Wall -Wextra` count from a pure Python or Bash change, and never satisfy one by fabricating a value — record that language's row instead. Tee raw build/test output to `.context/logs/<tool>-<worktask_id>.log`.

Source comments follow the compact code-documentation standard (`corpflow:code-comment-standard` / corpflow `skills/shared/code-documentation.md`): comment the non-obvious WHY and the contract only — never the WHAT, history, or call sites; rationale lives in the PR / `.context/development-N.md`. DR flags violations.

Copy-paste template: [templates/dv-development.md](templates/dv-development.md).

## Screenshot Gate for CLI Work (HIGHEST INTEGRATION RISK — read this)

corpflow's `dv-screenshot-gate.sh` blocks `SubagentStop` when `metadata.requires_screenshots != false` and no manifest exists at `.context/images/<worktask_id>/screenshots.md`. The corpflow default is **TRUE** — but systems/CLI work has no UI to screenshot. Handle it in this order:

1. **Preferred**: the dispatcher sets `metadata.requires_screenshots: false` for system-developer DV stages (non-UI changes). Then no manifest is required and the gate is skipped. Plugin norm: `requires_screenshots: false` is the **default expectation** for systems work — flag it in your return summary if the metadata says otherwise.
2. **cli-fallback procedure** (when the flag is unset/true and you cannot change it): produce the manifest anyway using terminal transcripts —
   - Capture each meaningful CLI surface as text: build output, test run, `--help`, a representative invocation with real output. Save as `.txt`/`.md` under `.context/images/<worktask_id>/`.
   - Write `.context/images/<worktask_id>/screenshots.md` with one row per capture, `source: cli-fallback`, and a `notes` cell explaining why (e.g. "CLI tool, no UI; transcript capture").
   - Frontmatter `screenshot_count` MUST equal the number of table rows.
3. **Never** fabricate image files or return without either the `false` flag or a cli-fallback manifest — the gate re-dispatches DV until one exists.
4. **Evidence freshness**: every `cli-fallback` transcript row must be produced *this run* from the actual build/test invocation — never reuse a transcript from a prior run or another workdir. corpflow QA direct-reads the evidence files and cross-checks them against the log paths recorded in the DV artifact's `### build-evidence` section; a stale or duplicated transcript is flagged and re-opens DV. This is the text-evidence corollary of rule 3 — the "never fabricate" integrity bar applies to reused transcripts as much as to invented image files.

Manifest row format mirrors corpflow's `dv-screenshot-capture` output: `| name | path | source | design_ref | notes |` with `source` ∈ {`cli-fallback`} for systems work; `design_ref` stays blank (no mockups for CLI).

`ui_visual_check` (the v4.0.0 DV metadata contract field) is **not applicable** to systems/CLI work — leave it `false`; it gates live-driven UI-capture provenance on UI platforms, which have no analog here.

## Per-Agent Error Files

Parallel-safe retry narratives live in `.context/errors/<agent-basename>.md` — basename = last `:`-separated segment of the qualified name (`task-system.md § error_file derivation`):

| File | Purpose |
|------|---------|
| `.context/errors/c-developer.md` | C-specific DV retry narratives |
| `.context/errors/cpp-developer.md` | C++ DV retry narratives |
| `.context/errors/python-developer.md` | Python DV retry narratives |
| `.context/errors/bash-developer.md` | Bash DV retry narratives |
| `.context/errors/sys-code-fixer.md` | DR fix-application retries |
| `.context/errors/<agent-basename>.md` | One file per agent — never overwrite a shared `error.md` |

Derive your own path from `task.metadata.error_file` or your frontmatter `name:`.

## DR Systems Review Criteria

technical-lead reads `development-N.md` + error files and produces `developer-review-N.md` (verdict `pass`/`fail`). system-developer agents support DR and pre-check against these criteria before returning from DV:

| Area | What DR checks |
|------|----------------|
| Memory safety | Ownership documented at every allocation; no leaks on error paths (RAII in C++, `goto cleanup` in C); bounds checked before indexing; no use-after-free/double-free patterns |
| UB classes | Signed overflow, out-of-bounds access, strict-aliasing violations, uninitialized reads, invalid shifts, data races — see `skills/c/c-memory-ownership/references/undefined-behavior-catalog.md` |
| Error-handling discipline | No bare `except:` (Python); no swallowed `errno` / unchecked return values (C); `set -euo pipefail` present and its caveats handled (Bash); no `\|\| true` masking failures |
| Unsafe constructs | `strcpy`/`strcat`/`sprintf`/`gets` (C); `eval`, unquoted expansions (Bash); `pickle.loads` on untrusted data, `subprocess(..., shell=True)`, `yaml.load` without `SafeLoader` (Python); `system()` with user input |
| Build hygiene | 0 warnings at `-Wall -Wextra` (ruff/shellcheck clean for Python/Bash); no committed build artifacts; lockfiles updated with manifest changes; `compile_commands.json` regenerated when targets change |
| Comment hygiene | Comments follow the compact code-documentation standard (`corpflow:code-comment-standard`): WHY/contract only, no design provenance, history, or call-site enumeration; no restated code |

Template: [templates/dr-review.md](templates/dr-review.md).

## QA Gate for Systems Work

QA (`testing-N.md`, verdict `go`/`no-go`) passes only when **both** hold:

1. **All tests pass** — full suite, not just new tests (`ctest --test-dir build`, `uv run pytest`, `bats test/`).
2. **ASan+UBSan clean on changed components** — rebuild changed C/C++ targets with `-fsanitize=address,undefined` and re-run their tests; zero reports. For pure Python/Bash changes the sanitizer clause applies to any native extension touched; otherwise tests + lint clean suffices. TSan runs separately when concurrency code changed (ASan and TSan do not combine).

sys-test-generator supports QA with framework-native generation (GoogleTest/Catch2, Unity/CMocka, pytest/Hypothesis, bats-core). Template: [templates/qa-testing.md](templates/qa-testing.md).

## SR and RE Contributions

- **SR** — sys-security-auditor provides platform context to corpflow's security-reviewer: sanitizer evidence, CWE Top 25 mapping, injection review (command/SQL/path/format-string), secrets scan, supply-chain audit (`pip-audit`, `osv-scanner`), hardening flags (`-D_FORTIFY_SOURCE=3`, RELRO, PIE — verified via `checksec`/`readelf`/`otool`). Review-only: findings route to sys-code-fixer for application.
- **RE** — release-engineer owns the stage; system-developer contributes packaging: sys-dependency-manager freezes lockfiles/pins (vcpkg baselines, Conan lockfiles, `uv.lock`), and the language agents produce release artifacts (tarballs, wheels/sdists via `uv build`, version bumps, changelog entries) recorded in `release-N.md`.

## Artifact Filename Contract (v4.0.0)

**Numbered `<stage>-N.md` names are canonical** per corpflow's authoritative `handoff-protocol.md#stage-artifact-map`. N is allocated by PL0 (same value as `planning-N.md`), shared across all stages within a run, and propagated via `task.metadata.run_index`; it bumps on gate loop-back re-dispatch. Readers fall back to newest-glob (`<basename>-*.md`).

| Stage | Artifact | Owner |
|-------|----------|-------|
| PL | `planning-N.md` | product-manager |
| AR | `analyzing-N.md` | software-architector |
| TL | `coordination-N.md` | team-lead |
| DV | `development-N.md` | developer / system-developer agents |
| DR | `developer-review-N.md` | technical-lead |
| SR | `security-review-N.md` | security-reviewer |
| QA | `testing-N.md` | qa-engineer |
| DC | `documentation-N.md` | technical-writer |
| RE | `release-N.md` | release-engineer |
| FN | `complete-summary-N.md` | project-manager |
| ST | `retrospective-N.md` | stakeholder |
| IR | `incident-N.md` | incident-responder |
| ET | `ethics-review-N.md` | ethics-reviewer |

**Emit `handoff:` frontmatter unconditionally — it is the merge input regardless of filename.** state.json reconciliation is three-layered: Layer 1 (agent runs `state-patch.sh --stage <CODE> --prev <PREV>` when its path is supplied, else skips — never a hand-rolled `jq`/manual merge), Layer 2 (orchestrator re-reads artifact frontmatter after `Task()` returns), Layer 3 (`SubagentStop` hook auto-merge). Attempt Layer 1; if the script or its path is absent, proceed — Layers 2 and 3 repair from frontmatter. An artifact without `handoff:` YAML breaks the safety net (degrades to F3 fallback: orchestrator derives a minimal handoff and logs WARN).

## Handoff Frontmatter (v4.0.0 schema)

Every stage artifact MUST start with a YAML block between `---` markers. Budgets: ≤200 tokens, ≤30 lines. Base required fields: `stage`, `verdict`, `summary` (≤200 chars), `refs`. Per-stage additions (from `handoff-protocol.md#frontmatter-schema`):

| Stage | Required beyond base | Verdict vocabulary |
|-------|----------------------|--------------------|
| DV | `files_touched`, `next_stage_focus` | ok / blocked / escalate |
| DR | `key_decisions` (= findings) | pass / fail |
| QA | `files_touched` (= tests added), `key_decisions` (= results) | go / no-go |

`key_decisions[].anchor` and `refs.*` MUST resolve to a real `## <kebab-case>` heading in the target file (anchor-lint enforces this at DR and via PostToolUse hook). Copy-paste blocks: `templates/` in this directory.

## Gate-Feedback Contract (v4.0.0)

When DR returns `verdict: fail` or QA returns `verdict: no-go`, the orchestrator re-dispatches DV (`run_index` bumped, `retry_count`++) and carries the upstream remediation **verbatim** into the retry prompt (corpflow `worktask/SKILL.md` step 4.6). system-developer agents **consume** this contract; the injection is orchestrator-owned.

| Surface | Mechanism | system-developer action |
|---------|-----------|-------------------------|
| Orchestrator → DV prompt | On re-dispatch (`metadata.retry_count > 0`) the prompt is prepended with `REMEDIATION (from <DR\|QA> gate — fix these specific findings before re-stop:)`; `metadata.gate_from_stage` ∈ {DR, QA}; `metadata.gate_blockers[]` = DR `blockers[]` / QA `blocking_defects[]` strings. | Read both fields; fix those exact findings *first*; do not re-scope. |
| SubagentStop hook → next dispatch | A blocked gate emits `hookSpecificOutput.additionalContext` telling the next run what to fix. | Treat as additional remediation context; consume the same way. |

On a rework dispatch the DV/sys-code-fixer agent MUST:

1. Read `metadata.gate_from_stage` + `metadata.gate_blockers[]` (and any `REMEDIATION` block in the prompt).
2. Address each listed blocker individually; record per-blocker resolution in `.context/errors/<agent-basename>.md`.
3. Keep the diff minimal — change only what the blockers require; do not re-implement passing code.

## Qualified Agent Names

All Task delegations MUST use the fully-qualified `plugin:agent` form:

| Form | Status |
|------|--------|
| `system-developer:cpp-developer` | Required |
| `corpflow:technical-lead` | Required |
| `cpp-developer` (bare) | Deprecated — back-compat shim prepends `corpflow:` and logs a warning (would resolve to the wrong plugin) |

Task metadata carries qualified names:

```json
{
  "metadata": {
    "agent": "system-developer:cpp-developer",
    "model": "sonnet",
    "error_file": ".context/errors/cpp-developer.md",
    "requires_screenshots": false,
    "plan_file": "planning-0.md",
    "run_index": 0
  }
}
```

## Token Budgets

- **Incoming compressed context** (from corpflow): 300-500 tokens (planning summary 300, architecture summary 300, development handoff 500)
- **Full stage output**: write to `.context/<stage>-N.md` (no token cap)
- **Outgoing return summary**: 500 tokens max (for the orchestrator)
- **Inter-stage handoffs**: DV→DR 300, DR→QA 300 (`corpflow:context-compression § Context Budget by Handoff`)

## Detecting Workflow Context

1. **Context folder**: `.context/` in project root, or `.worktrees/milestone-{N}/{issue#}/.context/` in worktree mode (resolve via `task.metadata.workspace_path` + `metadata.isolation`).
2. **Plan file**: (1) `task.metadata.plan_file`; (2) newest `.context/planning-*.md`.
3. **State ledger**: read `.context/state.json` for upstream `facts`/`handoffs`/`stages` (≤500-token canonical compressed view). Legacy fallback: `metadata.context_files`.
4. **Architecture document**: newest `.context/analyzing-*.md` — or the anchors named in upstream `next_stage_focus`.
5. **Task System**: TaskList/TaskGet; inspect `task.metadata.{plan_file, agent, model, run_index, error_file, gate_from_stage, gate_blockers, requires_screenshots, workspace_path}`.

## Dynamic Worktask Sizing (v4.0.0)

PL0 assesses complexity (0-50) and creates only the stages needed:

| Score | Complexity | PL0 Creates |
|-------|------------|-------------|
| 0-10 | Low | DV0, DR0, QA0 |
| 11-20 | Medium | AR0, DV0, DR0, QA0 |
| 21-30 | Moderate | AR0, TL0, DV0, DR0, QA0 |
| 31-40 | High | AR0, TL0, DV0, DR0, QA0, DC0, FN0, ST0 |
| 41-50 | Critical | AR0, TL0, DV0, DR0, SR0, QA0, DC0, RE0, FN0, ST0 |

Security-sensitive features (authentication, payment, PII, cryptography, secrets, file uploads) auto-include SR0 regardless of score.

PL0 stamps `metadata.skipped_stages = [{stage, reason}]` for every stage dropped from the full 9-stage pipeline (PL→AR→TL→DV→DR→QA→DC→FN→ST), so `state.json` self-documents the drops. It also stamps `metadata.test_mode` (`build-only` / `scoped` / `full` — defaulted by score and marker coverage) and `metadata.ui_visual_check` (the UI-capture provenance gate, left `false` for systems/CLI work). The stage table above, the `test_mode` defaults, and these stamps are all defined by corpflow `estimation-methodology § PL0 Stage-Set` (the source of truth) — keep them in lockstep with it so the next sync is a mechanical copy.

## MCP Dynamic Inheritance

Subagents inherit the parent session's MCP tools (Context7, Ref, etc.). Do not redeclare MCP tools in agent frontmatter when the parent session already provides them — redeclaration creates duplicates and bloats permission prompts.

## When Not in Workflow

If no workflow context is detected (no `.context/`, no task metadata), proceed with standard implementation: follow the language skills, run the same build/test/sanitizer discipline, and report results directly — no artifacts or frontmatter required.

## Related Skills (corpflow plugin)

| Skill | Purpose |
|-------|---------|
| `corpflow:worktask` | Complete worktask system documentation |
| `corpflow:cross-plugin-handoff` | Handoff protocol between plugins |
| `corpflow:agent-coordination` | Multi-agent coordination patterns |
| `corpflow:context-compression` | Token budgets and compression techniques |
| `corpflow:security-review-process` | SR stage OWASP checklists |
| `corpflow:release-engineering` | RE stage versioning patterns |

## Related Skills (system-developer plugin)

| Skill | Purpose |
|-------|---------|
| `_shared/model-selection.md` | Per-agent model/effort assignments and override paths |
| `_shared/severity-matrix.md` | P0-P3 finding priorities for DR/SR outputs |
| `_shared/testing-principles.md` | Test pyramid, framework matrix, QA coverage expectations |
| `_shared/language-detection.md` | Marker → language → agent routing for DV dispatch |
| `secure-coding` | Input validation and command-execution patterns for SR readiness |
