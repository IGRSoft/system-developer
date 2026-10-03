Clean up one command, agent, or skill in this repo, together with the files it pulls in: remove deprecated and over-engineered rules and cut tokens. What it does must stay the same.

Read optimization/ledger.md first.

## Scope
- Command: the command plus the agents and skills it uses, directly or through its agents.
- Agent: the agent plus the skills it uses.
- Skill: its SKILL.md and the other files in its folder.

Rows marked done are finished: don't edit them, and read them only if you need their interface. If your target is already done, say so and stop.

## Remove or rewrite
Deprecated:
- References to files, commands, agents, skills, tools, or MCP servers that no longer exist (check the repo).
- Instructions about Claude Code features, tool names, or frontmatter fields that have changed (check the current docs when unsure).
- Workarounds for older models: "think step by step", reminders repeated just in case, rules restated at the end.

Over-engineered:
- CRITICAL / MUST / NEVER and all-caps emphasis. Current models follow plain instructions and over-apply shouted ones, so keep the rule and state it plainly.
- Rules for what the model does anyway: read before editing, write clean code, be thorough.
- Step-by-step procedures where a goal plus constraints would do. Keep steps only where order matters.
- The same rule in several files: keep it only where it's acted on (a subagent doesn't see its command's text).
- Persona build-ups (one line of role is enough), extra examples, speculative edge cases, history and long justifications (a short "because" is worth keeping).

Token cost:
- Agent and skill descriptions load in every session, and skill descriptions get truncated when too many compete. Keep each to what it does and when to use it, main use case first. Add an example only if routing needs it.
- Move bulky material that's needed only sometimes (long templates, reference tables) into a separate file that's read on demand. For a skill, put it in a file in its folder.
- An agent without a `tools` field inherits every tool, MCP included. When its body makes clear what it needs, list only those.

## Keep
- Names, arguments, and output formats that users or other files rely on. Before cutting from a shared agent or skill, check its other callers.
- Any rule whose purpose you can't confirm: leave it and add it to "Needs decision" in the ledger.
- File layout: don't delete, rename, or convert files (commands stay commands). List files that look unused under "Needs decision".

## Finish
- Update the ledger row of every file in your scope: status done, "done by" your target, words after, a one-line note.
- Commit this task's changes on their own.
- Reply in a few lines: what you cut and what you flagged.
