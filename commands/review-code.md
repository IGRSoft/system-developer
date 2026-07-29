---
description: Review C, C++, Python, and Bash changes with per-language reviewers plus a security pass, ranked P0-P3
argument-hint: [scope: file/dir/PR#/branch — default: working changes] [--quick] [--fix] [--lang c|cpp|python|bash] [--security-focus]
allowed-tools: Read, Glob, Grep, Bash
estimated-cost:
  min-tokens: 4000
  max-tokens: 28000
  model-distribution:
    haiku: 15%
    sonnet: 75%
    opus: 10%
---

# Language-Aware Code Review
<!-- Updated: June 2026 -->

Review C, C++, Python, and Bash changes with the right specialist per language, plus a dedicated security pass, then synthesize one deduplicated, prioritized P0-P3 report. Scope defaults to your working changes; reviewers run read-only and in parallel; `--fix` hands the blocking findings to the code fixer under a minimal-diff gate.

[Extended thinking: A C heap overflow, a C++ dangling `string_view`, a Python `shell=True`, and an unquoted Bash expansion are four different review skills — one generalist pass misses most of them. This command resolves the scope once, detects which languages are actually present, fans out one read-only reviewer per detected language (each loaded with the right review focus) alongside one cross-cutting security pass, then merges and ranks the findings. The reviewers never edit; only the explicit `--fix` step does, and only for P0/P1. Keep the synthesis honest — if there are no material issues, say so rather than padding the report.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **Resolve the scope before reviewing.** Apply the scope precedence (explicit args > working diff > branch/PR diff) exactly once, list the concrete files under review, and pass that same file list to every reviewer. Do NOT let reviewers re-scope independently.
2. **Reviewers are read-only.** Phase 1 agents MUST NOT write or edit. They return structured findings only. The single place edits happen is the `--fix` step, after synthesis, and only for P0/P1 findings.
3. **One reviewer per detected language.** Launch a reviewer only for a language that is actually present in the scope (or forced by `--lang`). Do NOT spawn a Python reviewer for a pure-C change. Run the eligible reviewers in parallel — they have no dependencies on each other.
4. **Security pass always runs** (unless `--quick`). The `system-developer:sys-security-auditor` pass is cross-cutting and runs alongside the language reviewers, not after them.
5. **Synthesize, deduplicate, normalize.** In Phase 2 you merge all reviewer outputs, drop duplicates and speculative claims, and normalize every surviving finding to `{file, line, category, severity, why, fix, confidence}` before ranking into P0-P3.
6. **Tool-missing never hard-fails.** If a reviewer's underlying linter/analyzer is unavailable, print the install hint, note the reduced depth for that language, and continue. Never abort the whole review over one missing tool.
7. **No manufactured feedback.** If a reviewer or the synthesis finds no material issue, report that plainly. Do NOT invent P2/P3 nits to fill the report.
8. **Never enter plan mode.** This command IS the procedure — execute it.

## Usage

```bash
# Review your current working changes (staged + unstaged)
/system-developer:review-code

# Review a specific directory
/system-developer:review-code src/

# Review a single file
/system-developer:review-code src/parser.cpp

# Review a branch or PR against the base
/system-developer:review-code feature/zstd-stream
/system-developer:review-code 142            # PR number

# Fast single-agent pass for quick feedback
/system-developer:review-code src/ --quick

# Review, then auto-fix the P0/P1 findings
/system-developer:review-code src/ --fix

# Force a language when detection is ambiguous (e.g. extensionless scripts)
/system-developer:review-code scripts/ --lang bash
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `scope` | working changes | File, directory, PR number, or branch to review. See Scope Resolution. |
| `--quick` | off | Single combined reviewer pass for rapid feedback. Skips parallel fan-out and the dedicated security pass; folds a lightweight security check into the one pass. |
| `--fix` | off | After synthesis, delegate P0/P1 findings to `system-developer:sys-code-fixer` under a minimal-diff gate. P2/P3 are never auto-fixed. |
| `--lang c\|cpp\|python\|bash` | auto | Force the reviewer set instead of detecting. Repeatable conceptually (`--lang c --lang python`); use for extensionless scripts or to narrow a mixed repo. |
| `--security-focus` | off | Raise the security pass priority: instruct `sys-security-auditor` to go deeper (sanitizer-class bugs, injection, secrets, supply chain) and rank its findings first in ties. |

## Scope Resolution

Resolve the set of files under review **once**, top-down — the first applicable rule wins:

1. **Explicit args** — a file, directory, PR number, or branch named on the command line.
   - File or directory → review those paths directly.
   - PR number (bare integer) → `gh pr diff <N> --name-only` for the file list (and `gh pr diff <N>` for the patch). If `gh` is unavailable, print the install hint and fall back to rule 3 against the PR's base branch.
   - Branch name → diff against the merge-base with the default branch: `git diff --name-only $(git merge-base HEAD <branch>)..<branch>`.
2. **Working changes** (no args) — staged and unstaged tracked changes:
   `git diff --name-only HEAD` (plus `git diff --cached --name-only`). This is the default.
3. **Branch/PR diff** (fallback) — when neither explicit paths nor working changes apply, diff the current branch against the default branch's merge-base.

After resolving, **print the concrete file list** and the line ranges (where a diff is involved) before launching any reviewer. Reviewers receive this exact list — they do not re-derive scope. Exclude vendored/build artifacts (`build/`, `builddir/`, `.venv/`, `node_modules/`, vendored third-party trees) from the list.

## Language Detection

Detect which languages appear in the resolved file list using the canonical `skill: language-detection` table — do not fork its routing logic. Summary for this command:

| Files in scope | Reviewer to launch |
|----------------|--------------------|
| `.c`, and `.h` in a C-only tree | `system-developer:c-developer` |
| `.cpp`, `.cc`, `.cxx`, `.hpp`, `.hh`, `.ixx` (or `.h` alongside C++ sources) | `system-developer:cpp-developer` |
| `.py`, `.pyi` | `system-developer:python-developer` |
| `.sh`, `.bash`, `.bats` | `system-developer:bash-developer` |

- A `--lang` flag overrides detection for that language (use it for extensionless scripts identified by shebang, or to scope a mixed repo).
- A change spanning several languages launches **one reviewer per language present** — they run in parallel.
- Bare `.h` headers follow `skill: language-detection` tie-break 2 (count as C unless C++ markers exist; cross-boundary API headers go to the router).
- If nothing recognized is in scope, report "no reviewable C/C++/Python/Bash sources in scope" and stop.

## Workflow

### `--quick` path (single pass)

When `--quick` is set, skip the fan-out entirely:

1. Resolve scope and detect the dominant language.
2. **Use Task tool with subagent_type="system-developer:<dominant-language-agent>"** (e.g. `system-developer:cpp-developer`).
   Prompt: "Quick read-only review of these files: {file_list}. Focus on correctness and security for {language}: {focus_bullets_for_language}. Do NOT edit. Return findings as a list of `{file, line, category, severity (P0-P3), why, fix, confidence}`. If there are no material issues, say so directly."
3. Normalize and print the report (Output Format). Skip the dedicated security pass — the single reviewer folds in a lightweight security check.

`--quick` is for fast feedback on a single-language change; for mixed repos or pre-merge gates, use the full path.

### Phase 1: Parallel Read-Only Review

Launch every eligible reviewer **simultaneously** (one per detected language) plus the security pass. All are read-only and receive the same resolved file list. Each language reviewer gets a language-specific review focus:

**C — Use Task tool with subagent_type="system-developer:c-developer"**
- Focus: buffer bounds and overflow, `malloc`/`free` ownership and double-free/use-after-free, unchecked allocation failure, `errno` handling and unchecked return values, integer overflow and signedness, format-string safety, undefined behavior, POSIX portability (GNU vs BSD), source-comment hygiene (comments that restate what the code does, narrate history/before-after context, or enumerate call sites; per `igrsoft:code-comment-standard`: WHY/contract only).
- Prompt: "Read-only review of the C files: {file_list}. Review for: buffer bounds/overflow, malloc/free ownership (double-free, use-after-free, leaks on error paths), unchecked return values and errno, integer/signedness overflow, format-string safety, undefined behavior, and source-comment hygiene (flag comments that restate the code, narrate design history/before-after, or enumerate callers — WHY/contract-only standard). Do NOT edit any file. Return findings as a list of `{file, line, category, severity (P0-P3), why, fix, confidence}`. If there are no material issues, say so directly."

**C++ — Use Task tool with subagent_type="system-developer:cpp-developer"**
- Focus: RAII and ownership (Rule of Zero/Five, naked `new`/`delete`, leaked resources on exception paths), dangling references (`string_view`/`span` outliving its backing store), exception safety (basic/strong/nothrow guarantees), move/copy correctness, const-correctness, lifetime/iterator invalidation, undefined behavior, source-comment hygiene (comments that restate what the code does, narrate history/before-after context, or enumerate call sites; per `igrsoft:code-comment-standard`: WHY/contract only).
- Prompt: "Read-only review of the C++ files: {file_list}. Review for: RAII/ownership (Rule of Zero/Five, naked new/delete, leaks on exception paths), dangling references (string_view/span lifetime traps), exception safety guarantees, move/copy correctness, const-correctness, iterator/lifetime invalidation, undefined behavior, and source-comment hygiene (flag comments that restate the code, narrate design history/before-after, or enumerate callers — WHY/contract-only standard). Do NOT edit any file. Return findings as a list of `{file, line, category, severity (P0-P3), why, fix, confidence}`. If there are no material issues, say so directly."

**Python — Use Task tool with subagent_type="system-developer:python-developer"**
- Focus: type-annotation correctness and `Any` leaks, async misuse (blocking calls in coroutines, unawaited coroutines, fire-and-forget `create_task` without a reference, `gather` vs `TaskGroup`), resource handling (unclosed files/sockets, missing context managers), mutable default arguments, broad `except:`/swallowed exceptions, error propagation, source-comment hygiene (comments that restate what the code does, narrate history/before-after context, or enumerate call sites; per `igrsoft:code-comment-standard`: WHY/contract only).
- Prompt: "Read-only review of the Python files: {file_list}. Review for: typing correctness and Any leaks, async misuse (blocking calls in async code, unawaited coroutines, unreferenced create_task, gather-vs-TaskGroup), resource handling (unclosed files/sockets, missing context managers), mutable default arguments, broad/swallowed exceptions, error propagation, and source-comment hygiene (flag comments that restate the code, narrate design history/before-after, or enumerate callers — WHY/contract-only standard). Do NOT edit any file. Return findings as a list of `{file, line, category, severity (P0-P3), why, fix, confidence}`. If there are no material issues, say so directly."

**Bash — Use Task tool with subagent_type="system-developer:bash-developer"**
- Focus: quoting (unquoted expansions, word-splitting/glob, SC2086), strict mode (`set -euo pipefail` and its honest caveats), command injection (`eval`, unsanitized input in commands, missing `--` separators), unsafe `PATH`/temp-file handling, portability (bashism vs POSIX, GNU vs BSD), exit-status handling, source-comment hygiene (comments that restate what the code does, narrate history/before-after context, or enumerate call sites; per `igrsoft:code-comment-standard`: WHY/contract only).
- Prompt: "Read-only review of the shell scripts: {file_list}. Review for: quoting/word-splitting (SC2086 and friends), strict mode and its caveats, command injection (eval, unsanitized input, missing `--` separators), unsafe PATH/temp-file handling, portability (bashisms, GNU vs BSD), exit-status handling, and source-comment hygiene (flag comments that restate the code, narrate design history/before-after, or enumerate callers — WHY/contract-only standard). Do NOT edit any file. Return findings as a list of `{file, line, category, severity (P0-P3), why, fix, confidence}`. If there are no material issues, say so directly."

**Security pass (always, unless `--quick`) — Use Task tool with subagent_type="system-developer:sys-security-auditor"**
- Prompt: "Read-only cross-cutting security review of: {file_list} (languages present: {languages}). Cover memory-safety classes (overflow, UAF, double-free), injection (command, SQL, path, format string), unsafe deserialization (pickle, `yaml.load`, `shell=True`), secrets in code/history, input validation at trust boundaries, and supply-chain risk in changed dependencies. Map each finding to a CWE where applicable. Do NOT edit any file. Return findings as a list of `{file, line, category (CWE), severity (P0-P3), why, fix, confidence}`. {If --security-focus: 'Go deep — include sanitizer-class and hardening-flag observations.'} If there are no material issues, say so directly."

[SYNC POINT: Wait for all Phase 1 reviewers before synthesis.]

### Phase 2: Synthesis

1. **Collect** every reviewer's findings (language reviewers + security pass).
2. **Deduplicate** — the security pass and a language reviewer will overlap (e.g. both flag a buffer overflow). Merge duplicates at the same `{file, line}`, keeping the higher severity and the clearer fix; credit both lenses in `why`.
3. **Filter** — drop speculative claims with no concrete evidence and drop pure style nits unless they hide a real defect. Per Rule 7, do not backfill. Source-comment hygiene findings from the language reviewers are not pure style nits — preserve them: they flag comments violating `igrsoft:code-comment-standard` (WHY/contract-only; no restated code, design history/before-after, or call-site enumeration).
4. **Normalize** every survivor to `{file, line, category, severity, why, fix, confidence}` (severity from `skill: severity-matrix` P0-P3; confidence = high/medium/low).
5. **Rank** into P0-P3. With `--security-focus`, security findings win severity ties.
6. **Emit** the Output Format report.

### Optional: `--fix` (P0/P1 only)

If `--fix` is set, after synthesis:

**Use Task tool with subagent_type="system-developer:sys-code-fixer"**
Prompt: "Apply minimal, targeted fixes for these P0/P1 findings from code review: {p0_p1_findings as `{file, line, category, fix}`}. Minimal-diff gate: change only what each finding requires; do not refactor, reformat untouched code, or fix P2/P3 items. Preserve behavior outside the stated defect. After fixing, report each change as `{file, line, finding, change}` and list any finding you could NOT safely auto-fix (needs human judgment, API redesign, or broader change)."

- Only P0/P1 with a concrete, localized fix are eligible. Anything needing design judgment is returned for manual handling.
- Re-run a focused review on the touched files to confirm the fix introduced no regression (a single `--quick` pass over the changed files is sufficient).

## Output Format

```markdown
## Code Review Report

**Scope:** {resolved scope — paths / PR# / branch}
**Files reviewed:** {N} ({languages present})
**Reviewers:** {list of agents run} {+ security pass}
**Mode:** {full | --quick}

### Summary
{One or two sentences. If clean: "No material issues found — the changes look correct, memory-safe, and well-scoped." Otherwise: counts by priority.}

| Priority | Count |
|----------|-------|
| P0 (block merge) | {n} |
| P1 (fix in this change) | {n} |
| P2 (should fix) | {n} |
| P3 (nice to have) | {n} |

### P0 — Must Fix Before Merge
| File:Line | Category | Why | Fix | Confidence |
|-----------|----------|-----|-----|------------|
| {file}:{line} | {category/CWE} | {why it's broken} | {minimal fix} | {high/med/low} |

### P1 — Fix In This Change
{same table shape}

### P2 — Should Fix
{same table shape}

### P3 — Nice To Have
{same table shape}

<!-- When --fix ran: -->
### Fixes Applied
| File:Line | Finding | Change |
|-----------|---------|--------|
| {file}:{line} | {finding} | {what changed} |

**Not auto-fixed (manual):** {findings needing human judgment, or "none"}

<!-- When a tool was unavailable: -->
### Reduced-Depth Notes
- {language}: {missing tool} unavailable — review ran without {analyzer}. Install: {hint}.
```

## Error Handling

### No reviewable sources in scope
```
Note: No C/C++/Python/Bash sources found in the resolved scope.
Resolved scope: {scope}
Suggestion: Pass an explicit path, or check that your changes include reviewable sources.
```

### No changes detected (default scope)
```
Note: No staged or unstaged changes to review.
Suggestion: Name a path, branch, or PR number, e.g. /system-developer:review-code src/
```

### `gh` unavailable for a PR scope
```
Warning: `gh` CLI not found; cannot fetch PR diff directly.
Install: brew install gh   (then `gh auth login`)
Falling back to a branch diff against the default branch.
```

### Reviewer tool missing (reduced depth)
Print the relevant install hint, note reduced depth for that language in the report, and continue — never hard-fail:

| Missing tool | Install hint |
|--------------|--------------|
| `clang-tidy` / `clang-format` / `llvm` analyzers (C/C++) | `brew install llvm` |
| `ruff` (Python) | `uv tool install ruff` |
| `mypy` / `pyright` (Python typing) | `uv tool install mypy` (or `pyright`) |
| `shellcheck` / `shfmt` (Bash) | `brew install shellcheck shfmt` |

### Ambiguous language
If detection cannot classify a file (e.g. extensionless), apply `skill: language-detection` shebang/tie-break rules; if still ambiguous, route it to `system-developer:system-developer` and note the routing in the report.

## See Also

- `skill: language-detection` — canonical marker → language → agent routing (keep this command's detection in sync).
- `skill: severity-matrix` — P0-P3 definitions used by the synthesis ranking.
- `skill: secure-coding` — input-validation and injection patterns the security pass draws on.
- `igrsoft:code-comment-standard` — the compact code-documentation standard the language reviewers check source comments against (WHY/contract-only; no design provenance/history/call-site enumeration).
- `/system-developer:fix-quick` — run formatters/linters first to clear P3 noise before review.
- `/system-developer:build-test` — confirm the change builds and tests green before or after review.
- `/system-developer:sanitize-check` — escalate a memory/UB finding to ASan/UBSan/TSan confirmation.

If there are no material issues, say that directly instead of manufacturing feedback.
