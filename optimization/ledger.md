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
| commands/analyze-tech-debt.md | command | todo |  | 2806 → | |
| commands/arch-review.md | command | todo |  | 3122 → | |
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
| agents/bash-developer.md | agent | todo |  | 1443 → | |
| agents/c-developer.md | agent | todo |  | 1120 → | |
| agents/cpp-developer.md | agent | todo |  | 1509 → | |
| agents/python-developer.md | agent | todo |  | 1387 → | |
| agents/sys-code-fixer.md | agent | todo |  | 938 → | |
| agents/sys-dependency-manager.md | agent | todo |  | 1100 → | |
| agents/sys-performance-engineer.md | agent | todo |  | 1433 → | |
| agents/sys-security-auditor.md | agent | todo |  | 1170 → | |
| agents/sys-test-generator.md | agent | todo |  | 1225 → | |
| agents/system-architector.md | agent | todo |  | 1506 → | |
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
