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

Run each language's standard linter and formatter over the target and report violations. In `--fix` mode, apply only the safe, deterministic auto-fixes, then re-check. This is the mechanical cleanup pass, not a review: findings that need judgment go to `/system-developer:review-code --fix`.

## Rules

- `--check` (the default) never edits: no `-i`, `--fix`, or `-w`. Any violation makes the result FAIL, so CI can rely on it.
- `--fix` applies formatters and auto-fixable lint rules, then re-runs the linters report-only. Report what was fixed and what remains; only a clean re-check is PASS.
- Honor project config (see Config Discovery) and pass no overrides when one exists. Fall back to defaults only when none is found, and say so in the report.
- clang-tidy needs `compile_commands.json`. If it's missing, generate it with CMake; with no CMake project, skip clang-tidy with a note rather than run it blind.
- Use each tool's own path/recursion flags instead of `cd` or `&&` chains; scoped Bash permissions don't match compound commands.
- A missing tool never hard-fails: print its install hint, skip that language's pass, continue, and report the skip.
- No semantic refactors, API changes, or behavior-changing fixes, and no agent delegation. List judgment items under "Needs review".

## Usage

```bash
/system-developer:fix-quick . --check                      # report only, all detected languages
/system-developer:fix-quick . --fix                        # auto-fix, then re-check
/system-developer:fix-quick src/py --fix --lang python     # Python under one subtree
/system-developer:fix-quick scripts/ --check --lang bash   # shell scripts only
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | Directory or file to lint. Detection and config discovery are rooted here. |
| `--check` | default | Report-only. FAIL if any violation remains. |
| `--fix` | off | Apply mechanical fixes, then re-check. If both flags are passed, `--fix` wins with a warning. |
| `--lang c\|cpp\|python\|bash` | auto | Restrict the run to one language. |

## Language Detection

Detect per file, not one project language, because a mixed repo may need clang-format, ruff, and shfmt in one run. `--lang` overrides detection.

| Language | Files |
|----------|-------|
| C | `*.c`, `*.h` (a bare `.h` counts as C unless the tree has C++ sources or `CMAKE_CXX_STANDARD`) |
| C++ | `*.cpp`, `*.cc`, `*.cxx`, `*.hpp`, `*.hh`, `*.ixx` |
| Python | `*.py`, `*.pyi` |
| Bash | `*.sh`, `*.bash`, `*.bats` |

## Config Discovery

Record which config was found for each language in the report.

| Language | Config files | If missing |
|----------|--------------|------------|
| C / C++ | `.clang-tidy`, `.clang-format`, `compile_commands.json` | clang-format: `--style=file` falls back to LLVM. clang-tidy: generate the compile DB (below) or skip. |
| Python | `[tool.ruff]` / `[tool.mypy]` in `pyproject.toml`, `ruff.toml` / `.ruff.toml`, `mypy.ini` | ruff: defaults. mypy: run only with a config, `py.typed`, or type hints present; else note "mypy skipped (no config)". |
| Bash | `.shellcheckrc` | shellcheck: defaults. The gate is always `--severity=info` (`.shellcheckrc` can't set severity). |
| All | `.editorconfig` | Informational; shfmt and clang-format both read it. |

Generating the compile DB:

```bash
cmake -S "$path" -B "$path/build" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
clang-tidy -p "$path/build" <files>
```

## Per-Language Tools

In `--fix`, formatters run before the final lint re-check so formatting churn doesn't mask real lint findings.

| Language | Lint (check) | Format (check) | Fix (mechanical) |
|----------|--------------|----------------|------------------|
| C / C++ | `clang-tidy -p build <files>` (`-warnings-as-errors=''` keeps it non-fatal) | `clang-format --dry-run --Werror <files>` | `clang-format -i <files>`, then `clang-tidy -p build --fix <files>` |
| Python | `ruff check --statistics <path>` | `ruff format --check --diff <path>` | `ruff check --fix <path>`, then `ruff format <path>` |
| Python (types) | `mypy <path>` if configured; optionally `ty check <path>` | — | none |
| Bash | `shellcheck -f gcc --severity=info <files>` | `shfmt -d <files>` | `shfmt -w <files>`, then apply ShellCheck's suggested fixes (below) |

- Run `clang-tidy --fix` only for checks the project's `.clang-tidy` enables, and only fixes that apply cleanly (`modernize-*`, `readability-*`). Never add checks the project didn't opt into.
- ShellCheck fixes: write `shellcheck -f diff --severity=info <files> > .context/logs/shellcheck-fix.diff`, then `patch -p1 -i .context/logs/shellcheck-fix.diff` (create `.context/logs/` first; the diff uses the paths as passed, so run both from the same directory). The diff only carries ShellCheck's own suggestions, mostly quoting (SC2086). Drop any hunk that quotes a variable meant to split, such as a flag list, and list it under "Needs review".
- mypy and ty are report-only; they have no safe mechanical fixer. `ty` (Astral, beta) is an advisory extra signal, never the gate; mypy/pyright stay authoritative.
- `ruff check --statistics` gives the per-rule counts for the report.

## Workflow

1. **Detect.** Confirm `path` exists and resolve the mode. Detect languages (honoring `--lang`), discover configs, and check tools with `command -v clang-tidy clang-format ruff mypy shellcheck shfmt`. Stop with the matching Error Handling message if the path or sources are missing.
2. **Check mode.** Run the lint and format checks for each language and collect violations per tool with rule codes. Any violation is FAIL; otherwise PASS.
3. **Fix mode.** Run the mechanical fixes for each language, recording each touched file and the rule or category of each fix. Re-run the report-only lint and format checks. PASS only if the re-check is clean, otherwise PARTIAL with the remaining count; mypy/shellcheck items that need judgment go to "Needs review".
4. **Report** in the Output Format.

## Tool Availability

| Missing tool | Install hint |
|--------------|--------------|
| `clang-tidy` / `clang-format` | `brew install llvm` |
| `ruff` | `uv tool install ruff` (or `pipx install ruff`) |
| `mypy` | `uv tool install mypy` |
| `ty` (optional) | `uv tool install ty` |
| `shellcheck` | `brew install shellcheck` |
| `shfmt` | `brew install shfmt` |

Flag spellings vary across tool releases; check `--help` when a flag is rejected.

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

<!-- --fix mode only -->
### Fixes Applied ({total})

| File | Line | Fix |
|------|------|-----|
| src/widget.cpp | 88 | clang-tidy modernize-use-nullptr: `NULL` → `nullptr` |
| app/main.py | 3 | ruff F401: removed unused import `os` |

### Rollback
```bash
git checkout -- {files}
```

<!-- when mechanical fixes cannot resolve everything -->
### Needs review ({count})
- {file}:{line}: {finding that needs judgment}
- Escalate with: `/system-developer:review-code --fix {path}`

<!-- skipped languages or tools only -->
### Skipped
- {language}: {missing tool} — install hint printed above.
- C/C++ clang-tidy: no `compile_commands.json` and no CMake project.
```

In `--check` mode the Violations column carries the count and, for ruff, shellcheck, and clang-tidy, the rule codes, so a CI run shows exactly which rules tripped.

## Error Handling

```
Error: Path not found: {path}
Suggestion: Pass a directory or file that exists, e.g. /system-developer:fix-quick . --check
```

```
Error: No C, C++, Python, or Bash sources found under {path}.
Suggestion: Check the path, or pass --lang to target a specific language.
```

```
Warning: --check and --fix are mutually exclusive; proceeding with --fix.
(Run again with only --check for a CI-safe, no-edit pass.)
```

If every detected language is skipped for missing tools, the result is FAIL with the aggregated install hints.

## See Also

- `/system-developer:build-test`: get the build green first, then lint.
- `/system-developer:review-code --fix`: findings that need judgment.
- `/system-developer:fix-modernize`: standard-level modernization (`clang-tidy modernize-*` at scale, `ruff --select UP`).
