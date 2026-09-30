# Optimization ledger

## How to run

- One task at a time, in ledger order (commands, then agents, then skills).
- Each task in a fresh Opus context, e.g. a subagent with `model: opus`.
- Prompt: `Process {path} ({type}) following optimization/brief.md`
- Skip rows already marked done: a command task may clean up the agents and skills it uses and mark their rows done.
- No parallel runs: tasks share this ledger and can edit the same agents and skills.

## Files

| path | type | status | done by | words before → after | note |
|---|---|---|---|---|---|
| commands/analyze-accessibility.md | command | done | commands/analyze-accessibility.md | 1654 → 1116 | Merged shouted rules into 3 plain ones, dropped extended-thinking/plan-mode/version lines, Task→Agent tool, judge prompt now carries provisional severities instead of an unreachable skill ref |
| commands/analyze-tech-debt.md | command | done | commands/analyze-tech-debt.md | 2806 → 2019 | Dropped shouted rules/extended-thinking/plan-mode/date lines, merged 4 language prompts into one template + focus table, taxonomy headings now match --focus axes (fixed dead "Standards & Language Level" and "Rule 7" refs), inlined P0-P3 ranking, Task→Agent tool |
| commands/arch-review.md | command | done | commands/arch-review.md | 3122 → 1998 | Plain rules replace CRITICAL list/extended-thinking/plan-mode/date lines; dropped detection-signal and API/ABI tables duplicated in system-architector; inlined P0-P3 (severity-matrix unreachable); fixed wrong `--abi` phase number and trust-boundary prompt that needed a detection result while running in parallel; Task→Agent tool |
| commands/arch-select.md | command | todo |  | 3117 → | |
| commands/build-test.md | command | todo |  | 2369 → | |
| commands/debug.md | command | todo |  | 3145 → | |
| commands/deps.md | command | todo |  | 3293 → | |
| commands/develop-feature.md | command | todo |  | 3355 → | |
| commands/fix-modernize.md | command | todo |  | 4284 → | |
| commands/fix-performance.md | command | todo |  | 4070 → | |
| commands/fix-quick.md | command | todo |  | 2204 → | |
| commands/fix-refactor.md | command | todo |  | 3863 → | |
| commands/gen-docs.md | command | todo |  | 2787 → | |
| commands/gen-tests.md | command | todo |  | 3046 → | |
| commands/review-code.md | command | todo |  | 2693 → | |
| commands/sanitize-check.md | command | todo |  | 2742 → | |
| agents/_base/language-agent.md | agent | todo |  | 775 → | |
| agents/bash-developer.md | agent | done | commands/analyze-tech-debt.md | 1443 → 1252 | Removed BINDING/forbidden emphasis and base restatements, Response Approach reduced to implementation notes |
| agents/c-developer.md | agent | done | commands/analyze-tech-debt.md | 1120 → 919 | Plain-language constraints, Build Outputs + Response Approach merged into Build and Verify, dropped unresolvable version-feature-matrix path and dead base-section list |
| agents/cpp-developer.md | agent | done | commands/analyze-tech-debt.md | 1509 → 1110 | Removed dated "Standard reality 2026" compiler claims and duplicate C++26 paragraph (folded into table row), fixed wrong cpp-skills § refs, Response Approach cut to one paragraph |
| agents/python-developer.md | agent | done | commands/analyze-tech-debt.md | 1387 → 1021 | Condensed constraints and tooling, dropped volatile ty/pyrefly maturity labels and unresolvable matrix path, Response Approach cut to one paragraph |
| agents/sys-code-fixer.md | agent | todo |  | 938 → | |
| agents/sys-dependency-manager.md | agent | todo |  | 1100 → | |
| agents/sys-performance-engineer.md | agent | todo |  | 1433 → | |
| agents/sys-security-auditor.md | agent | done | commands/arch-review.md | 1170 → 998 | One-line role, removed caller-facing Model Notes (in model-selection.md/README) and dead base-section ref, Response Approach cut to one paragraph, output format defers to caller's format/P0-P3 |
| agents/sys-test-generator.md | agent | todo |  | 1225 → | |
| agents/system-architector.md | agent | done | commands/analyze-tech-debt.md | 1506 → 1319 | Merged 6-step workflow into modes + guardrails, plain-language complexity triage (no MANDATORY/NO), removed dead Workflow Stage Participation ref |
| agents/system-developer.md | agent | done | commands/analyze-accessibility.md | 831 → 428 | Merged agent table into routing tables, removed dead refs (Return Verification contract, Workflow Stage Participation in base), cut verbose Response Approach |
| skills/SKILL.md | skill | todo |  | 1317 → | |
| skills/_shared/secure-coding/SKILL.md | skill | todo |  | 1359 → | |
| skills/bash/SKILL.md | skill | todo |  | 593 → | |
| skills/bash/bash-scripting/SKILL.md | skill | todo |  | 1180 → | |
| skills/bash/bash-testing/SKILL.md | skill | todo |  | 1351 → | |
| skills/c/SKILL.md | skill | todo |  | 513 → | |
| skills/c/c-memory-ownership/SKILL.md | skill | todo |  | 1404 → | |
| skills/c/modern-c/SKILL.md | skill | todo |  | 1136 → | |
| skills/cpp/SKILL.md | skill | todo |  | 800 → | |
| skills/cpp/cpp-concurrency/SKILL.md | skill | todo |  | 1658 → | |
| skills/cpp/modern-cpp/SKILL.md | skill | todo |  | 1415 → | |
| skills/embedded/SKILL.md | skill | todo |  | 737 → | |
| skills/embedded/embedded-cpp/SKILL.md | skill | todo |  | 1580 → | |
| skills/embedded/embedded-systems/SKILL.md | skill | todo |  | 2111 → | |
| skills/python/SKILL.md | skill | todo |  | 498 → | |
| skills/python/modern-python/SKILL.md | skill | todo |  | 1232 → | |
| skills/python/python-concurrency/SKILL.md | skill | todo |  | 1057 → | |
| skills/python/python-testing/SKILL.md | skill | todo |  | 1324 → | |
| skills/python/python-tooling/SKILL.md | skill | todo |  | 1611 → | |
| skills/python/python-typing/SKILL.md | skill | todo |  | 1500 → | |
| skills/tooling/SKILL.md | skill | todo |  | 775 → | |
| skills/tooling/build-systems/SKILL.md | skill | todo |  | 1153 → | |
| skills/tooling/diagnostics/SKILL.md | skill | todo |  | 1168 → | |
| skills/tooling/ffi-interop/SKILL.md | skill | todo |  | 1634 → | |

## Needs decision

- `inherits: _base/language-agent.md` (all 11 agents) is not a Claude Code frontmatter field, so the base file is never loaded into subagents; its Constraints/Mandatory Requirements only reach agents that restate them. Decide: inline what matters per agent, or keep as documentation only. (found by commands/analyze-accessibility.md)
- Several agents still cite a "Workflow Stage Participation" section in `_base/language-agent.md` that no longer exists (moved to CORPFLOW.md): bash-, c-, cpp-, python-developer, system-architector, sys-*. Fix in their own rows. (found by commands/analyze-accessibility.md)
- `skill: severity-matrix` / `skill: language-detection` point at `skills/_shared/*.md`, which are not registered skills (no SKILL.md), so the `skill:` form can't be loaded by name; subagents running in a user project can't resolve them by path either. (found by commands/analyze-accessibility.md)
- `mcp__Ref__*` tools in agent `tools:` lists: confirm the Ref MCP server is still expected; it is not bundled by this plugin. (found by commands/analyze-accessibility.md)
- `estimated-cost` command frontmatter is not a Claude Code field; kept because README/MEMORY/CHANGELOG document it as a convention. Confirm whether anything consumes it. (found by commands/analyze-accessibility.md)
- `skill: version-feature-matrix` / `skill: testing-principles` (and path refs to `skills/_shared/*.md`) have the same problem as severity-matrix/language-detection: not registered skills and not reachable by relative path from a user project. Removed from analyze-tech-debt and the 4 language agents; still used elsewhere. (found by commands/analyze-tech-debt.md)
- Agent "DR Focus" sections and system-architector's complexity triage name worktask artifacts (`development-N.md`, `metadata.complexity_score`, AR stage) although CORPFLOW.md says only it should know corpflow. Kept; decide whether they move to CORPFLOW.md. (found by commands/analyze-tech-debt.md)
- Skills referenced by the processed agents (build-systems, ffi-interop, diagnostics, modern-c, c-memory-ownership, modern-cpp, cpp-skills, cpp-concurrency, modern-python, python-typing, python-concurrency, python-testing, secure-coding) are pointers only, not preloaded (no `skills:` frontmatter), so they were left for their own rows. (found by commands/analyze-tech-debt.md)
- `disallowed-tools: Write, Edit` on sys-security-auditor and sys-performance-engineer: Claude Code's subagent field is `disallowedTools`, so the kebab-case key is likely ignored; harmless because `tools:` already omits Write/Edit. Decide whether to rename (README, MEMORY, model-selection.md document the kebab form) or drop it. (found by commands/arch-review.md)
