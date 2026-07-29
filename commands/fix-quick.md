---
description: Run linters and formatters over C, C++, Python, and Bash code — check-only, or apply the safe mechanical fixes
argument-hint: [path (default .)] [--check | --fix] [--lang c|cpp|python|bash]
allowed-tools: Read, Edit, Glob, Grep, Bash
model: haiku
estimated-cost:
  min-tokens: 500
  max-tokens: 6000
  model-distribution:
    haiku: 90%
    sonnet: 10%
---

# Lint & Fix
<!-- Updated: June 2026 -->

Run each language's standard linter and formatter over the target, report violations, and — in `--fix` mode — apply the safe, deterministic auto-fixes, then re-check. Fast, cheap, and reversible: this is the deterministic-cleanup pass, not a review. Deep, judgment-bearing fixes escalate to `/system-developer:review-code --fix`.

[Extended thinking: This command is the system-developer analogue of a pre-commit hook. It detects which languages are present, discovers each language's config (so it honors project rules instead of imposing its own), and runs linters/formatters in a fixed order per language. `--check` is the CI mode — no edits, exit-code-honest, with a planted-violation count — and `--fix` applies only the mechanical fixes (`clang-format -i`, `ruff check --fix`, `ruff format`, `shfmt -w`) then re-runs the linters to confirm. Anything a formatter or `--fix` rule cannot resolve mechanically is reported, not forced; those land in `review-code --fix`. Keep it on haiku: the work is tool invocation and table assembly, not analysis.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **`--check` never edits.** In `--check` (or default-with-no-flag) mode, run every tool in its report-only variant. Do NOT pass `-i`, `--fix`, or `-w`. If any tool reports a violation, the command result is FAIL — surface the planted/total violation counts.
2. **`--fix` applies only mechanical fixes, then re-checks.** Run formatters and the auto-fixable lint rules, then re-run the linters in report-only mode. Report what was fixed and what still remains. Never claim "clean" without the post-fix re-check passing.
3. **Honor project config, do not impose.** Discover and use `.clang-tidy`, `.clang-format`, `[tool.ruff]`/`[tool.mypy]` in `pyproject.toml`, `.shellcheckrc`, and `.editorconfig` (see Config Discovery). Pass no opinionated overrides when a config exists; fall back to the documented defaults only when none is found, and say so in the report.
4. **clang-tidy requires `compile_commands.json`.** If absent, generate it with `cmake -S <path> -B <path>/build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON` (or symlink an existing one). If it cannot be generated (no CMake), skip clang-tidy with a note — never run it blind.
5. **Single-command Bash invocations.** Use each tool's own path/recursion flags. Never `cd`-chain or `&&`-chain directory changes — scoped Bash patterns do not match compound commands.
6. **Tool-missing never hard-fails.** If a linter/formatter binary is absent, print the install hint, skip that language's pass, and continue. Report what was skipped.
7. **This is the shallow pass.** Do NOT attempt semantic refactors, API redesigns, or fixes that change behavior. When a finding needs judgment, list it under "Needs review" and point to `/system-developer:review-code --fix`. Do not delegate to an agent from this command.
8. **Never enter plan mode.** This command IS the procedure — execute it.

## Usage

```bash
# Report violations across all detected languages (CI-safe, no edits)
/system-developer:fix-quick . --check

# Auto-fix everything fixable, then re-check
/system-developer:fix-quick . --fix

# Fix only the Python sources under a subtree
/system-developer:fix-quick src/py --fix --lang python

# Check just the shell scripts (exit non-zero if any violation)
/system-developer:fix-quick scripts/ --check --lang bash
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | Directory or file to lint. Language detection and tool discovery are rooted here. |
| `--check` | default | Report-only. No edits. FAIL if any violation remains. This is the CI mode. |
| `--fix` | off | Apply mechanical formatter + auto-fix-rule changes, then re-check. Mutually exclusive with `--check`; `--fix` wins if both are passed (with a warning). |
| `--lang c\|cpp\|python\|bash` | auto | Restrict the run to one language. Without it, every detected language is processed. |

When neither `--check` nor `--fix` is given, default to `--check`.

## Language Detection

Detect which languages are present, then run each one's pass. The marker → language map is canonical in `skill: language-detection` — do not fork it. For this command, detect **per file/subtree**, not a single project language, because a mixed repo may need clang-format for `.cpp`, ruff for `.py`, and shfmt for `.sh` in one invocation.

| Language | Files / markers linted |
|----------|------------------------|
| C | `*.c`, `*.h` (C-only trees per `skill: language-detection` tie-break) |
| C++ | `*.cpp`, `*.cc`, `*.cxx`, `*.hpp`, `*.hh`, `*.ixx` |
| Python | `*.py`, `*.pyi` |
| Bash | `*.sh`, `*.bash`, `*.bats` |

`--lang` overrides detection and processes only that language's files.

## Config Discovery

Before running each language's tools, discover its configuration so the run honors project rules. Record which config (if any) was found in the report.

| Language | Config files (in precedence order) | If missing |
|----------|------------------------------------|------------|
| C / C++ | `.clang-tidy`, `.clang-format`, `compile_commands.json` | clang-format: use a minimal default style (`--style=file` falls back to LLVM); clang-tidy: **generate** `compile_commands.json` (Rule 4) or skip with a note |
| Python | `[tool.ruff]` and `[tool.mypy]` in `pyproject.toml` (also `ruff.toml`/`.ruff.toml`, `mypy.ini`) | ruff: documented defaults; mypy: run only if a config or `py.typed`/type hints are present, else note "mypy skipped (no config)" |
| Bash | `.shellcheckrc` | shellcheck: default severity (`style`+); shfmt: read `.editorconfig` if present (`shfmt` honors it) |
| All | `.editorconfig` | informational — shfmt and clang-format both consult it |

**compile_commands.json generation (clang-tidy prerequisite):**

```bash
cmake -S "$path" -B "$path/build" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
# then point clang-tidy at it:
clang-tidy -p "$path/build" <files>
```

If there is no CMake project, clang-tidy is skipped (clang-format still runs — it needs no compile DB).

## Per-Language Tool Order

Run tools in this order. In `--fix`, formatters run **before** the final lint re-check so formatting churn does not mask real lint findings.

| Language | Lint (check) | Format (check) | Fix (mechanical) |
|----------|--------------|----------------|------------------|
| C / C++ | `clang-tidy -p build <files>` (warnings only; `-warnings-as-errors=''` keeps it non-fatal in check) | `clang-format --dry-run --Werror <files>` | `clang-format -i <files>`; clang-tidy auto-fixes via `clang-tidy -p build --fix <files>` (only `modernize-*`/`readability-*` that apply cleanly) |
| Python | `ruff check <path>` | `ruff format --check --diff <path>` | `ruff check --fix <path>` then `ruff format <path>` |
| Python (types) | `mypy <path>` (if configured); optionally `ty check <path>` (Astral, beta — fast, report-only) | — | none (type errors are never auto-fixed — report only) |
| Bash | `shellcheck <files>` (`-f gcc` for parseable output) | `shfmt -d <files>` (diff = would-change) | `shfmt -w <files>`; shellcheck has no safe auto-fix — report SC codes |

Notes:
- **clang-tidy `--fix` is conservative**: only apply it when a `.clang-tidy` enables the relevant checks; never invent checks the project did not opt into. Fixes that touch behavior are out of scope (Rule 7).
- **mypy and shellcheck are report-only.** Neither has a safe mechanical fixer; their findings always land in the report and, when they need judgment, under "Needs review".
- **`ty` is an optional fast type-check (report-only, beta).** `ty` (Astral) is a Rust-based checker still in beta with no stable API — run it only as an additional fast signal, never as the gate. Keep `mypy`/`pyright` as the authoritative type gate; treat `ty` findings as advisory and never auto-fix them.
- `ruff check --statistics` produces the per-rule counts used for the planted-violation summary in `--check`.

## Workflow

### Phase 1: Detect & Discover (Bash)

1. Confirm `path` exists; if not, emit the Error Handling "path not found" message and stop.
2. Resolve mode: `--fix` if present (warn if `--check` also passed), else `--check`.
3. Detect languages present under `path` (honoring `--lang`). If none match, emit "no lintable sources" and stop.
4. For each detected language, run Config Discovery and note which config was found.
5. Verify each language's tools exist (`command -v clang-tidy clang-format ruff mypy shellcheck shfmt`). Missing → print install hint, skip that language's pass, note the skip.
6. For C/C++, if clang-tidy is in scope and `compile_commands.json` is absent, generate it (Rule 4) or mark clang-tidy as skipped.

### Phase 2a: Check mode (`--check`)

1. For each language, run the **lint (check)** and **format (check)** commands from the tool-order table. Do NOT edit.
2. Collect violations per tool. For Python, capture `ruff check --statistics` to count per-rule occurrences (the planted-violation counts).
3. Assemble the Output Format report. If any tool reported a violation, result is FAIL (non-zero — CI-honest). If all clean, PASS.

### Phase 2b: Fix mode (`--fix`)

1. For each language, apply the **fix (mechanical)** commands from the tool-order table, using `Edit`/`Bash` as appropriate:
   - C/C++: `clang-format -i`, then conservative `clang-tidy --fix` (if configured).
   - Python: `ruff check --fix`, then `ruff format`.
   - Bash: `shfmt -w`.
2. Record each file touched and the rule/category of each applied fix (for the File | Line | Fix table).
3. **Re-check**: re-run the report-only lint commands (Phase 2a step 1) to confirm. Anything still failing is reported as remaining, with mypy/shellcheck judgment items routed to "Needs review".
4. Result is PASS only if the re-check is clean; otherwise PARTIAL with the remaining count.

### Phase 3: Report (Bash)

Emit the Output Format. In `--fix`, include the applied-fix table, the rollback hint, and any "Needs review" escalation. In `--check`, include the violation table and per-rule counts.

## Tool Availability

| Missing tool | Install hint |
|--------------|--------------|
| `clang-tidy` / `clang-format` | `brew install llvm` (the `clang-*` tools ship with the LLVM formula) |
| `ruff` | `uv tool install ruff` (or `pipx install ruff`) |
| `mypy` | `uv tool install mypy` |
| `ty` (optional fast type-check, beta) | `uv tool install ty` (report-only — never the gate) |
| `shellcheck` | `brew install shellcheck` |
| `shfmt` | `brew install shfmt` |

Exact flag spellings vary across tool releases — verify against your toolchain when a flag is rejected. Never hard-fail on a missing tool: print the hint, skip that language, continue, and report the skip.

## Output Format

```markdown
## Lint & Fix Report

**Target:** {path}
**Mode:** check | fix
**Languages:** {C, C++, Python, Bash — detected}
**Configs found:** {.clang-tidy ✅ | ruff [tool.ruff] ✅ | .shellcheckrc ❌ (defaults) | ...}

| Language | Tool | Violations | Status |
|----------|------|-----------:|--------|
| C++ | clang-format | 7 | ❌ would reformat |
| C++ | clang-tidy | 3 | ❌ (modernize-use-nullptr ×2, readability ×1) |
| Python | ruff check | 5 | ❌ (F401 ×3, E711 ×1, UP032 ×1) |
| Python | ruff format | 2 files | ❌ would reformat |
| Python | mypy | 1 | ⚠ report-only |
| Bash | shellcheck | 2 | ❌ (SC2086 ×1, SC2046 ×1) |
| Bash | shfmt | 1 file | ❌ would reformat |

**Result:** PASS / FAIL / PARTIAL — {N violations across M tools}

<!-- --fix mode only: applied fixes -->
### Fixes Applied ({total})

| File | Line | Fix |
|------|------|-----|
| src/widget.cpp | 42 | clang-format: reindent + brace style |
| src/widget.cpp | 88 | clang-tidy modernize-use-nullptr: `NULL` → `nullptr` |
| app/main.py | 3 | ruff F401: removed unused import `os` |
| app/main.py | 17 | ruff E711: `== None` → `is None` |
| deploy.sh | 24 | shfmt: normalized indentation |

### Rollback
To undo every change this run made:
```bash
git checkout -- {files}
```

<!-- when mechanical fixes cannot resolve everything -->
### Needs review ({count})
- {file}:{line}: {mypy/shellcheck finding that needs judgment}
- Escalate with: `/system-developer:review-code --fix {path}`

<!-- on skipped languages only -->
### Skipped
- {language}: {missing tool} — install hint printed above.
- C/C++ clang-tidy: no `compile_commands.json` and no CMake project — skipped.
```

In `--check` mode, the "Violations" column doubles as the planted-violation summary: each cell shows the count and (for ruff/shellcheck/clang-tidy) the rule codes, so a CI run surfaces exactly which rules tripped.

## Error Handling

### Path not found
```
Error: Path not found: {path}
Suggestion: Pass a directory or file that exists, e.g. /system-developer:fix-quick . --check
```

### No lintable sources
```
Error: No C, C++, Python, or Bash sources found under {path}.
Suggestion: Check the path, or pass --lang to target a specific language.
```

### Both --check and --fix passed
```
Warning: --check and --fix are mutually exclusive; proceeding with --fix.
(Run again with only --check for a CI-safe, no-edit pass.)
```

### compile_commands.json missing (clang-tidy)
Generate it with `cmake … -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`. If there is no CMake project, skip clang-tidy and note it in the report — clang-format still runs.

### Tool missing
Print the install hint from Tool Availability, skip that language's pass, continue. Only when *every* detected language is skipped does the command report FAIL with the aggregated install hints.

## See Also

- `skill: language-detection` — canonical marker → language → agent routing (keep detection in sync).
- `/system-developer:build-test` — run before building to cut compiler-warning noise; build green first, then lint.
- `/system-developer:review-code --fix` — escalation target for findings that need judgment (semantic refactors, API/behavioral changes) beyond mechanical lint fixes.
- `/system-developer:fix-modernize` — for cross-standard modernization (`clang-tidy modernize-*` at scale, `ruff --select UP`), which goes deeper than this command's mechanical pass.
