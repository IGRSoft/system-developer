---
name: model-selection
description: Model and effort selection for system-developer agents — cost tiers, per-agent assignments, and opus+xhigh override paths. Reference when delegating to or overriding a system-developer specialist.
effort: low
---

# Model & Effort Selection (system-developer)

Companion to igrsoft's `skills/shared/model-selection.md`. This file pins the
**system-developer** per-agent assignments and the override paths the language
agents expose. Frontmatter in `agents/*.md` is the source of truth — keep this
table in sync with it.

## Cost Tiers

| Model | Relative Cost | Use For |
|-------|---------------|---------|
| **haiku** | 1x (baseline) | Mechanical remediation, dependency operations, formatting |
| **sonnet** | ~10x haiku | Language implementation, review, test generation, routing |
| **opus** | ~50x haiku | Architecture selection, deep trace/threat analysis |

## Effort Levels

`low` ○, `medium` ◐, `high` ●, `xhigh` ⬣.

- `xhigh` is honored **only on Opus** — Sonnet/Haiku silently fall back to
  `high`, so raising effort without raising the model is a no-op.
- Reserve `xhigh` for the hardest long-chain reasoning (architecture trade-offs,
  root-causing a sanitizer report that spans subsystems, threat modeling).

## Per-Agent Assignment

| Agent | Model | Effort | maxTurns | Override path |
|-------|-------|--------|----------|---------------|
| `system-developer` (router) | sonnet | medium | 40 | — routes work to specialists |
| `c-developer` | sonnet | high | 50 | → `opus` + `xhigh` for novel design / cross-subsystem work |
| `cpp-developer` | sonnet | high | 50 | → `opus` + `xhigh` for novel design / template-heavy refactors |
| `python-developer` | sonnet | high | 50 | → `opus` + `xhigh` for free-threading / C-extension boundary work |
| `bash-developer` | sonnet | high | 50 | — sonnet sufficient for shell work |
| `system-architector` | opus | xhigh | 60 | already top tier; self-limits scope at Low complexity per § Complexity Triage |
| `sys-test-generator` | sonnet | high | 50 | — sonnet sufficient for pattern work |
| `sys-performance-engineer` | sonnet | high | 50 | → `opus` + `xhigh` for deep trace analysis (review-only: `disallowed-tools: Write, Edit`) |
| `sys-security-auditor` | sonnet | high | 50 | → `opus` + `xhigh` for deep threat modeling (review-only: `disallowed-tools: Write, Edit`) |
| `sys-code-fixer` | haiku | medium | 30 | — deterministic minimal-diff remediation |
| `sys-dependency-manager` | haiku | low | 20 | — mechanical lockfile/manifest operations |

## Applying an Override

Pass `model`/`effort` on the Task() call (per-invocation, does not edit
frontmatter). Callers of `sys-performance-engineer` and `sys-security-auditor`
may override to `opus` + `xhigh` when the investigation spans multiple
subsystems or requires long-chain causal reasoning:

```
Task({ subagent_type: "system-developer:sys-performance-engineer",
       model: "opus", effort: "xhigh",
       prompt: "Root-cause the 40% throughput regression across the parser and allocator perf traces…" })
```

Only override when complexity warrants it — the sonnet/high default covers the
overwhelming majority of systems work. Both review-only agents keep their
`disallowed-tools: Write, Edit` restriction regardless of model: fixes route to
`system-developer:sys-code-fixer`.
