# DV Stage Artifact Template (systems work)

Copy this to `.context/development-N.md` (`N` from `task.metadata.run_index`; e.g. `development-0.md`). H2 anchors are fixed by igrsoft's anchor allow-list — keep them exactly as written (kebab-case, H2); systems sections nest as H3.

```markdown
---
handoff:
  stage: DV
  verdict: ok           # ok | blocked | escalate
  summary: "<what was implemented — ≤200 chars>"
  files_touched:        # REQUIRED for DV
    - src/parser.cpp
    - tests/parser_test.cpp
  next_stage_focus: "<hint for DR/QA — ≤240 chars>"
  key_decisions: []
  open_questions: []
  remediation_consumed: []   # rework only (metadata.retry_count>0): gate_blockers[] addressed this run
  refs:
    plan: planning-0.md#requirements
    decisions: analyzing-0.md#decisions
---

# DV Development — <worktask_id>

## files-changed

| File | Change | Why |
|------|--------|-----|
| src/parser.cpp | <summary> | <reason> |

### decisions

- <non-obvious implementation choice + rationale; reference analyzing-N.md anchors>

### tool-invocations

- `cmake --preset default && cmake --build build/default`
- `ctest --test-dir build/default --output-on-failure`

## tests-added

| Test | Framework | Covers |
|------|-----------|--------|
| tests/parser_test.cpp | GoogleTest | <behavior> |

### build-evidence

<!-- Keep only the rows for the language(s) actually changed. -->
<!-- C/C++ -->
- Compiler + standard: <e.g. clang 18, -std=c++23 — verify against your toolchain>
- Warnings at `-Wall -Wextra`: 0 (`-Werror` enforced); `clang-tidy`: <result>
- Sanitizers: ASan+UBSan clean on changed components
<!-- Python -->
- Interpreter: <e.g. python3 3.14.0 via uv 0.9>
- `ruff check`: 0 findings; type check: <pyright / mypy / ty result>
- Sanitizers: <only if a native extension was touched; otherwise omit this row>
<!-- Bash -->
- Shell: <e.g. bash 5.3; macOS /bin/bash floor is 3.2>
- `shellcheck`: 0 findings; `shfmt`: clean
<!-- All languages -->
- Test transcript: .context/logs/<tool>-<worktask_id>.log

## deviations

- <departures from analyzing-N.md, or "None">

## follow-ups

- <deferred work, flagged risks, or "None">
```

## Notes

- **Screenshots**: systems/CLI work defaults `metadata.requires_screenshots: false` — no manifest needed. If the flag is unset/true and cannot be changed, write a **cli-fallback** manifest at `.context/images/<worktask_id>/screenshots.md` (rows with `source: cli-fallback` pointing at terminal-transcript `.txt` files; `screenshot_count` = row count) before returning, or `dv-screenshot-gate.sh` blocks `SubagentStop`. See `workflow-integration/SKILL.md § Screenshot Gate for CLI Work`.
- `remediation_consumed:` is populated only on a rework re-dispatch — list the `metadata.gate_blockers[]` strings (from the DR/QA gate) this run fixed. See `workflow-integration/SKILL.md § Gate-Feedback Contract`.
- Frontmatter budget: ≤200 tokens, ≤30 lines. Emit it unconditionally — it is the state.json merge input regardless of filename.
- **state.json patch**: on completion run `state-patch.sh --stage DV --prev <PREV>` when its path is supplied (`task.metadata.state_patch_script`; ships under igrsoft `skills/worktask/scripts/`) to merge `stages.DV` + the `<PREV>→DV` edge from this frontmatter; if the script/`jq`/`state.json` is absent, skip — never hand-roll the merge; Layers 2/3 repair from the frontmatter. See `workflow-integration/SKILL.md § Artifact Filename Contract`.
- Tee raw build/test output to `.context/logs/` — the Build Evidence transcript path must exist on disk.
- **Build Evidence rows are per-language.** A pure Python or Bash change has no compiler and no `-Wall -Wextra` count; record the interpreter/shell version and the `ruff`/`shellcheck` result instead. Never fabricate a compiler row to fill the template. See `workflow-integration/SKILL.md § DV Contract for Systems Work`.
