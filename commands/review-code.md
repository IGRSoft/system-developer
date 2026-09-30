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

Review C, C++, Python, and Bash changes with one specialist per language present plus a cross-cutting security pass, then merge the findings into one deduplicated P0-P3 report. Reviewers run read-only and in parallel; only `--fix` edits, and only for P0/P1.

## Rules

- Resolve the scope once, print the file list, and pass that same list to every reviewer; reviewers don't re-scope.
- Launch a reviewer only for a language present in scope (or forced by `--lang`).
- A missing linter or analyzer reduces depth for that language; print the install hint and continue.
- If nothing material is found, say so. Don't pad the report with P2/P3 nits.

## Usage

```bash
/system-developer:review-code                        # working changes (staged + unstaged)
/system-developer:review-code src/parser.cpp         # file or directory
/system-developer:review-code feature/zstd-stream    # branch vs default branch
/system-developer:review-code 142                    # PR number
/system-developer:review-code src/ --quick           # single-agent pass
/system-developer:review-code src/ --fix             # review, then fix P0/P1
/system-developer:review-code scripts/ --lang bash   # force language (extensionless scripts)
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `scope` | working changes | File, directory, PR number, or branch. See Scope Resolution. |
| `--quick` | off | One combined reviewer with a light security check; no fan-out, no dedicated security pass. |
| `--fix` | off | After synthesis, send P0/P1 findings to `system-developer:sys-code-fixer`. P2/P3 are never auto-fixed. |
| `--lang c\|cpp\|python\|bash` | auto | Force the reviewer set instead of detecting; may be given more than once. |
| `--security-focus` | off | Deeper security pass (sanitizer-class bugs, hardening flags, injection, secrets, supply chain); security findings win severity ties. |

## Scope Resolution

First matching rule wins:

1. **Explicit arg.**
   - File or directory: review those paths.
   - PR number: `gh pr diff <N> --name-only` for files, `gh pr diff <N>` for the patch. Without `gh`, warn and fall back to rule 3 against the PR's base branch.
   - Branch: `git diff --name-only <default>...<branch>` (merge-base with the default branch).
2. **Working changes** (no arg): `git diff --name-only HEAD` (staged and unstaged tracked changes).
3. **Branch diff** (no arg, clean tree): current branch vs the default branch's merge-base.

Exclude `build/`, `builddir/`, `.venv/`, `node_modules/`, and vendored third-party trees. Print the file list, with line ranges where a diff is involved, before launching reviewers.

## Language Detection

| Files in scope | Reviewer |
|----------------|----------|
| `.c`; `.h` in a tree with no C++ sources | `system-developer:c-developer` |
| `.cpp`, `.cc`, `.cxx`, `.hpp`, `.hh`, `.ixx`; `.h` alongside C++ sources | `system-developer:cpp-developer` |
| `.py`, `.pyi` | `system-developer:python-developer` |
| `.sh`, `.bash`, `.bats` | `system-developer:bash-developer` |

Classify extensionless files by shebang. A file still unclassified goes to `system-developer:system-developer`; note that routing in the report. If nothing reviewable is in scope, print the error below and stop.

## Review Focus

| Language | Focus |
|----------|-------|
| C | buffer bounds and overflow; `malloc`/`free` ownership (double-free, use-after-free, leaks on error paths); unchecked return values and `errno`; integer and signedness overflow; format-string safety; undefined behavior; POSIX portability (GNU vs BSD) |
| C++ | RAII and ownership (Rule of Zero/Five, naked `new`/`delete`, leaks on exception paths); dangling `string_view`/`span`; exception-safety guarantees; move/copy correctness; const-correctness; iterator and lifetime invalidation; undefined behavior |
| Python | typing correctness and `Any` leaks; async misuse (blocking calls in coroutines, unawaited coroutines, unreferenced `create_task`, `gather` vs `TaskGroup`); unclosed files/sockets and missing context managers; mutable default arguments; broad or swallowed exceptions; error propagation |
| Bash | quoting and word-splitting (SC2086 and friends); strict mode and its caveats; command injection (`eval`, unsanitized input, missing `--`); unsafe `PATH` and temp-file handling; portability (bashisms, GNU vs BSD); exit-status handling |

Every language reviewer also checks source-comment hygiene against `corpflow:code-comment-standard`: flag comments that restate the code, narrate design history or before/after, or enumerate callers (comments carry WHY and contract only).

## Severity

| Priority | Meaning |
|----------|---------|
| P0 | Block merge: correctness or security broken (overflow, UAF, injection, observable UB, failing tests) |
| P1 | Fix in this change: defect likely to bite (leak on error path, data race, bare `except:`, unquoted expansion of user input) |
| P2 | Should fix: quality and maintainability |
| P3 | Nice to have: style and polish |

## Workflow

### `--quick`

Resolve scope, pick the dominant language, and launch its reviewer alone with the Agent tool using the reviewer prompt below, prefixed with "Quick" and with "Include a light security check." appended. Normalize and print the report. Use the full path for mixed-language changes or pre-merge gates.

### Phase 1: Parallel review

In one message, launch with the Agent tool one reviewer per detected language plus the security pass.

**Language reviewer** (`subagent_type` from Language Detection):

"Read-only review of the {language} files: {file_list}. Review for: {focus row}; and source-comment hygiene (flag comments that restate the code, narrate design history or before/after, or enumerate callers; WHY/contract only). Don't edit any file. Return findings as `{file, line, category, severity (P0-P3), why, fix, confidence}`. If there are no material issues, say so."

**Security pass** (skipped with `--quick`; `subagent_type="system-developer:sys-security-auditor"`):

"Read-only cross-cutting security review of: {file_list} (languages: {languages}). Cover memory-safety classes (overflow, UAF, double-free), injection (command, SQL, path, format string), unsafe deserialization (pickle, `yaml.load`, `shell=True`), secrets in code or history, input validation at trust boundaries, and supply-chain risk in changed dependencies. Map findings to CWE where applicable. {If --security-focus: 'Go deep: include sanitizer-class and hardening-flag observations.'} Don't edit any file. Return findings as `{file, line, category (CWE), severity (P0-P3), why, fix, confidence}`. If there are no material issues, say so."

### Phase 2: Synthesis

After all reviewers return:

1. Merge duplicates at the same `{file, line}` (the security pass and a language reviewer often overlap), keeping the higher severity and clearer fix and crediting both lenses in `why`.
2. Drop speculative claims without concrete evidence and pure style nits that hide no defect. Comment-hygiene findings are not style nits; keep them.
3. Normalize survivors to `{file, line, category, severity, why, fix, confidence}` (confidence high/medium/low), rank by the Severity table, and print the Output Format.

### `--fix` (P0/P1 only)

`subagent_type="system-developer:sys-code-fixer"`:

"Apply minimal, targeted fixes for these P0/P1 code-review findings: {findings as `{file, line, category, fix}`}. Change only what each finding requires; don't refactor, reformat untouched code, or fix P2/P3 items. Preserve behavior outside the stated defect. Report each change as `{file, line, finding, change}` and list findings you could not safely auto-fix (needs human judgment, API redesign, or broader change)."

Send only findings with a concrete, localized fix; return the rest for manual handling. Then run a `--quick` pass over the touched files to confirm no regression.

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

### Reviewer tool missing

| Missing tool | Install hint |
|--------------|--------------|
| `clang-tidy` / `clang-format` (C/C++) | `brew install llvm` |
| `ruff` (Python) | `uv tool install ruff` |
| `mypy` / `pyright` (Python) | `uv tool install mypy` (or `pyright`) |
| `shellcheck` / `shfmt` (Bash) | `brew install shellcheck shfmt` |

## See Also

- `/system-developer:fix-quick` — clear formatter/linter noise before review.
- `/system-developer:build-test` — confirm the change builds and tests green.
- `/system-developer:sanitize-check` — confirm a memory/UB finding under ASan/UBSan/TSan.
