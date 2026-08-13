# Shared Skills Index

Quick navigation for cross-cutting references shared by all system-developer agents, commands, and skills.

## Workflow Integration

| File | Description |
|------|-------------|
| `workflow-integration/SKILL.md` | Guide for integrating with corpflow 11-stage pipeline (v4.0.13) — DV/DR/QA contracts, screenshot cli-fallback, gate feedback |
| `workflow-integration/templates/dv-development.md` | Copy-paste `development-N.md` artifact template (Build Evidence, anchors, frontmatter) |
| `workflow-integration/templates/dr-review.md` | Copy-paste `developer-review-N.md` template with systems review checklist |
| `workflow-integration/templates/qa-testing.md` | Copy-paste `testing-N.md` template with sanitizer-gate evidence |

## Routing & Versions

| File | Description |
|------|-------------|
| `language-detection.md` | Marker → language → agent routing table, detection priority, tie-breaking rules |
| `version-feature-matrix.md` | C17/C23, C++17/20/23, Python 3.12-3.14, Bash 5.2/5.3 → minimum toolchains + headline features |
| `model-selection.md` | Per-agent model/effort/maxTurns assignments and opus+xhigh override paths |

## Quality & Security

| File | Description |
|------|-------------|
| `severity-matrix.md` | Severity levels, P0-P3 review priorities, effort/impact quadrant, coverage requirements |
| `testing-principles.md` | Test pyramid, per-language framework matrix, quality gates, anti-patterns |
| `secure-coding/SKILL.md` | Input validation and command-execution security patterns |
| `secure-coding/references/input-validation-and-parsing.md` | Validation at trust boundaries, parser hardening |
| `secure-coding/references/command-execution-and-injection.md` | Command/shell injection prevention across C, Python, Bash |

## Quick Links by Problem

### "I need to..."

- **Integrate with corpflow worktask** → `workflow-integration/SKILL.md`
- **Write a DV/DR/QA stage artifact** → `workflow-integration/templates/`
- **Handle the screenshot gate for CLI work** → `workflow-integration/SKILL.md § Screenshot Gate for CLI Work`
- **Route a file/repo to the right agent** → `language-detection.md`
- **Check if a feature is available on a toolchain** → `version-feature-matrix.md`
- **Pick model/effort for a delegation** → `model-selection.md`
- **Set severity/priority on a finding** → `severity-matrix.md`
- **Choose a test framework or coverage target** → `testing-principles.md`
- **Review input handling or subprocess calls** → `secure-coding/SKILL.md`
