# DR Stage Artifact Template (systems review)

Primary artifact `.context/developer-review-N.md` is owned by corpflow's technical-lead; use this when a system-developer agent takes over DR or contributes the review body. sys-code-fixer appends retry narratives to `.context/errors/sys-code-fixer.md` instead.

```markdown
---
handoff:
  stage: DR
  verdict: pass         # pass | fail
  summary: "<review outcome — ≤200 chars>"
  key_decisions:        # REQUIRED for DR (= findings)
    - id: f1
      summary: "<P0 finding — ≤160 chars>"
      anchor: developer-review-0.md#findings
  files_touched: []     # only when sys-code-fixer applied fixes
  next_stage_focus: "<security surface / test focus for SR/QA — ≤240 chars>"
  refs:
    development: development-0.md#files-changed
---

# Developer Review — <worktask_id>

## findings

| ID | Priority | Area | Location | Issue | Fix |
|----|----------|------|----------|-------|-----|
| f1 | P0 | Memory safety | src/parser.cpp:42 | <issue> | <fix> |

Checked areas (systems criteria — see workflow-integration/SKILL.md § DR Systems Review Criteria):
- [ ] Memory safety: ownership documented, no leaks on error paths, bounds checked
- [ ] UB classes: signed overflow, OOB, strict aliasing, uninitialized reads, data races
- [ ] Error handling: no bare `except:`, no swallowed errno, `set -euo pipefail`, returns checked
- [ ] Unsafe constructs: strcpy/sprintf/gets, eval, pickle.loads, subprocess shell=True
- [ ] Build hygiene: 0 warnings at -Wall -Wextra, lockfiles current, no committed artifacts

## verdict

<pass | fail — with one-line justification tied to findings>

## blockers

- <P0/P1 findings that force verdict: fail — these become metadata.gate_blockers[] verbatim on DV re-dispatch; empty list when pass>

## follow-ups

- <P2/P3 findings deferred to backlog, or "None">
```

## Notes

- `blockers` entries are injected **verbatim** into the DV retry prompt (Gate-Feedback Contract) — write them as self-contained, actionable strings with `file:line`.
- Priorities follow `_shared/severity-matrix.md` (P0 = memory corruption/injection, P1 = leak/race/unchecked failure, P2 = quality, P3 = style).
- sys-code-fixer on a fix-application pass: populate `files_touched`, enforce minimal diff, and record per-blocker resolution in `.context/errors/sys-code-fixer.md`.
