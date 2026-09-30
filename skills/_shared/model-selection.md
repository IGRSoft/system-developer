---
name: model-selection
description: Model and effort selection for system-developer agents — cost tiers, per-agent assignments, and opus+xhigh override paths. Reference when delegating to or overriding a system-developer specialist.
effort: low
---

# Model & Effort Selection (system-developer)

Per-agent model/effort assignments and override paths for system-developer.
Frontmatter in `agents/*.md` is the source of truth; keep this table in sync.

## Cost Tiers

| Model | Relative Cost | Use For |
|-------|---------------|---------|
| haiku | 1x (baseline) | Mechanical remediation, dependency operations, formatting |
| sonnet | ~10x haiku | Language implementation, review, test generation, routing |
| opus | ~50x haiku | Architecture selection, deep trace/threat analysis |

## Effort Levels

`low` ○, `medium` ◐, `high` ●, `xhigh` ⬣.

- `xhigh` is honored only on Opus; Sonnet/Haiku fall back to `high`, so raising
  effort without raising the model does nothing.
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

Pass `model` on the Agent tool call; it applies to that invocation only and
leaves frontmatter unchanged. The Agent tool takes no per-call effort, so an
agent runs at its frontmatter effort (`xhigh` needs opus to take effect).
Override only when the work spans multiple subsystems or needs long-chain
causal reasoning; the sonnet/high default covers most systems work. Review-only
agents stay review-only under any model: fixes route to
`system-developer:sys-code-fixer`.
