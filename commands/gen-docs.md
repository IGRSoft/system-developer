---
description: Generate or update Doxygen, Python docstring, and Bash header documentation, then verify it with the doc build
argument-hint: [path (default .)] [--lang c|cpp|python|bash] [--public-only] [--readme] [--no-build] [--config]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
estimated-cost:
  min-tokens: 3000
  max-tokens: 24000
  model-distribution:
    haiku: 15%
    sonnet: 75%
    opus: 10%
---

# Generate Code Documentation
<!-- Updated: July 2026 -->

Generate or update API documentation in place — Doxygen comment blocks for C and C++, PEP 257 docstrings for Python, and header/contract comments for Bash — plus the README/API-reference sections that describe them. One documenter per language actually present, running in parallel, followed by a verification gate that runs the real doc build.

[Extended thinking: Documentation rots when nothing checks it against the code, so this command treats the doc build as the gate rather than the afterthought: `doxygen` and `sphinx-build -W` either accept the generated comments or the run is not done. The other half of the problem is that a doc generator is the single easiest place to violate this plugin's comment standard — it is trivially tempting to emit `// increment the counter` above `i++`. API contract documentation (`@param`, `@return`, docstring Args/Returns/Raises, a script's usage and exit codes) is genuinely contract, so it is in scope; line-by-line narration of what the next statement does is banned and must be removed on sight. Python style is detected from what the project already writes, never imposed, because a NumPy-style codebase that suddenly grows Google-style docstrings is worse documented than before.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **Contract only — never narrate the code.** Per `corpflow:code-comment-standard`, every comment you write documents the non-obvious WHY or the contract. NEVER restate what the next line does, NEVER record history/provenance/before-after ("was X, now Y", "added for ticket 42"), NEVER enumerate call sites. This rule binds you AND every delegated documenter.
2. **API doc comments ARE contract.** Doxygen `@brief`/`@param`/`@return`/`@retval`/`@throws`, Python docstring summary + Args/Returns/Raises, and a Bash header's purpose/usage/exit codes are in scope precisely because they state the contract. A `@param n The n` that restates the name is not contract — omit it or say something real.
3. **Detect the style, never impose one.** Read existing docstrings/comments first and match them: Google vs NumPy vs reST for Python, the project's existing Doxygen dialect (`@param` vs `\param`, `/**` vs `///<`) for C/C++. Only when a tree has no precedent do you pick a default.
4. **One documenter per detected language, in parallel.** Launch a documenter only for a language actually present in scope (or forced by `--lang`). They have no dependencies on each other.
5. **Verify with the real doc build.** After documenting, run `doxygen` and/or `sphinx-build -W` (Phase 3). Warnings-as-errors failures are defects — fix them or report them; a doc build you never ran is not a verified doc build.
6. **Tool-missing never hard-fails.** If `doxygen`, `sphinx-build`, or `shellcheck` is absent, print the install hint, mark that language's coverage as unverified/reduced, and continue. Never abort the whole run over one missing tool.
7. **Do not invent behavior.** Document only what the code actually does. If a function's contract is genuinely unclear, leave it undocumented and list it under "Needs manual review" — a confidently wrong `@return` is worse than none.
8. **No placeholders.** Never emit `TODO`, `Description here`, or an empty `@param` line. Every emitted line carries information.
9. **Never enter plan mode.** This command IS the procedure — execute it.

## Usage

```bash
# Document the whole project, verify with the doc build
/system-developer:gen-docs .

# Document one subtree
/system-developer:gen-docs src/parser/

# Public/exported API surface only (headers, __all__, exported functions)
/system-developer:gen-docs . --public-only

# Force a language for extensionless scripts
/system-developer:gen-docs scripts/ --lang bash

# Also refresh README API-reference sections
/system-developer:gen-docs . --readme

# Scaffold missing Doxyfile / Sphinx conf.py, then document
/system-developer:gen-docs . --config

# Write comments but skip the doc-build verification gate
/system-developer:gen-docs src/ --no-build
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | Directory or file to document. The detection scan is rooted here. |
| `--lang c\|cpp\|python\|bash` | auto | Force the documenter set instead of detecting. Use for extensionless scripts or to narrow a mixed repo. |
| `--public-only` | off | Document only the exported surface: installed/public headers, non-`_` Python names (or `__all__`), functions a script exposes. Skip statics, internals, and private helpers. |
| `--readme` | off | Also update the README/API-reference sections to match the regenerated API surface. Preserves existing structure. |
| `--no-build` | off | Skip Phase 3 verification. Report coverage as **unverified**; never report it as verified. |
| `--config` | off | Generate the missing doc config (`Doxyfile`, Sphinx `conf.py` + `sphinx-apidoc` wiring) instead of only reporting it absent. |

`--no-build` and `--config` are independent: `--config` scaffolds inputs to the build, `--no-build` skips running it.

## Language Detection

Detect which languages appear under `path` using the canonical `skill: language-detection` table — do not fork its routing logic. Summary for this command:

| Files in scope | Documenter | Doc form |
|----------------|------------|----------|
| `.c`, `.h` in a C-only tree | `system-developer:c-developer` | Doxygen `/** */` blocks |
| `.cpp`, `.cc`, `.cxx`, `.hpp`, `.hh`, `.ixx` | `system-developer:cpp-developer` | Doxygen `/** */` blocks |
| `.py`, `.pyi` | `system-developer:python-developer` | PEP 257 docstrings |
| `.sh`, `.bash`, `.bats` | `system-developer:bash-developer` | Shell header + function contract comments |

- Bare `.h` headers follow `skill: language-detection` tie-break 2 (C unless C++ markers exist); a cross-boundary API header goes to `system-developer:system-developer`.
- Extensionless scripts are classified by shebang per the same skill.
- If nothing recognized is in scope, report "no documentable C/C++/Python/Bash sources in scope" and stop.
- Exclude vendored/build trees (`build/`, `builddir/`, `.venv/`, `third_party/`, generated sources) from the file list.

## Documentation Standards Per Language

### C / C++ — Doxygen

Block form on the **declaration** (header) so the contract lives with the API, not the implementation:

```c
/**
 * @brief Decode one frame into `out`.
 *
 * Caller owns `out` and must free it with `frame_free`. Returns partial
 * output on truncation because the stream format has no length prefix.
 *
 * @param in   Source buffer; must remain valid for the call.
 * @param len  Byte length of `in`.
 * @param out  Receives the decoded frame; unchanged on failure.
 * @return 0 on success, negative errno on failure.
 * @retval -EINVAL `len` is zero or `in` is NULL.
 */
```

Document ownership, lifetime, thread-safety, error contract, and units — the things a reader cannot deduce from the signature. Match the project's existing dialect (`@` vs `\`). C++ additionally documents exception guarantees (`@throws`) and template parameters (`@tparam`).

### Python — docstrings + Sphinx

PEP 257 shape: one-line imperative summary, blank line, discussion, then the structured section block **in the style the project already uses** — Google (`Args:`/`Returns:`/`Raises:`), NumPy (`Parameters`/`Returns` with underlines), or reST (`:param:`/`:returns:`). Detect it by reading existing docstrings; when there is no precedent, default to Google and say so in the report.

Type information belongs in annotations, not repeated in the docstring. Document raised exceptions, side effects, and mutation of arguments — never the parameter name restated. Module docstrings state what the module is for; `sphinx-apidoc`/`autodoc` then renders it.

### Bash — header + function contracts

Every script gets a header block below the shebang:

```bash
#!/usr/bin/env bash
# Purpose: rotate and upload the nightly archive.
# Usage:   backup.sh <src-dir> <dest-bucket> [--dry-run]
# Exit:    0 ok | 1 bad args | 2 upload failed | 3 lock held
# Requires: aws-cli, gzip
```

Each non-trivial function gets a contract comment: arguments (positional meaning), stdout contract, return/exit status, and globals it reads or mutates. Do not narrate the body.

## Workflow

### Phase 1: Scope & Detect (Bash)

1. Confirm `path` exists; otherwise emit the "path not found" message and stop.
2. Build the file list (excluding vendored/build trees) and detect the languages present per `skill: language-detection`. `--lang` overrides.
3. Detect the existing style per language: grep for `@param` vs `\param`, `/**` vs `///<`; sample Python docstrings for Google/NumPy/reST markers; check for an existing script header shape.
4. Locate doc config: `Doxyfile`/`Doxyfile.in`, `docs/conf.py`, `docs/Makefile`. Record what exists.
5. **Print** the file list, detected languages, detected styles, and config status before delegating.

### Phase 2: Parallel Documentation

Launch one documenter per detected language **simultaneously**. Each receives the resolved file list, the detected style, and the comment standard.

**C — Use Task tool with subagent_type="system-developer:c-developer"**
Prompt: "Add or update Doxygen documentation for these C files: {file_list}. Existing dialect: {dialect}. Put blocks on declarations in headers. Document ownership/free responsibility, lifetime and validity of pointer arguments, thread-safety, units, and the error contract (`@param`, `@return`, `@retval` with errno values). CRITICAL — per `corpflow:code-comment-standard`: document only the non-obvious WHY and the contract. Never restate what a line does, never record history/provenance/before-after, never enumerate call sites. `@param`/`@return` are contract and are in scope; `@param n The n` restates the name — omit it instead. Do not invent behavior: leave genuinely unclear contracts undocumented and list them. No TODO/placeholder text. {If --public-only: 'Only the public header surface; skip statics and internals.'} Report `{file, symbol, action}` plus a list of symbols needing manual review."

**C++ — Use Task tool with subagent_type="system-developer:cpp-developer"**
Prompt: "Add or update Doxygen documentation for these C++ files: {file_list}. Existing dialect: {dialect}. Put blocks on declarations in headers. Document ownership and lifetime (who owns what, dangling traps for `string_view`/`span`), exception guarantees via `@throws`, template parameters via `@tparam`, const/thread-safety, and the return contract. CRITICAL — per `corpflow:code-comment-standard`: document only the non-obvious WHY and the contract. Never restate what a line does, never record history/provenance/before-after, never enumerate call sites. `@param`/`@return`/`@throws` are contract and are in scope; a `@param` that restates the name is not — omit it. Do not invent behavior: leave unclear contracts undocumented and list them. No TODO/placeholder text. {If --public-only: 'Only the public/installed header surface.'} Report `{file, symbol, action}` plus symbols needing manual review."

**Python — Use Task tool with subagent_type="system-developer:python-developer"**
Prompt: "Add or update PEP 257 docstrings for these Python files: {file_list}. The project already uses **{detected_style}** style — match it exactly; do NOT convert existing docstrings to another style. One-line imperative summary, blank line, discussion, then the structured section block. Document raised exceptions, side effects, argument mutation, and any non-obvious contract. Types live in annotations — do not repeat them in prose. Add module docstrings where missing so autodoc renders them. CRITICAL — per `corpflow:code-comment-standard`: document only the non-obvious WHY and the contract. Never restate what a line does, never record history/provenance/before-after, never enumerate call sites. Docstring Args/Returns/Raises are contract and are in scope; an `Args:` entry that restates the parameter name is not — omit it. Do not invent behavior. No TODO/placeholder text. {If --public-only: 'Only public names (respect `__all__`); skip `_`-prefixed helpers.'} Report `{file, symbol, action}` plus symbols needing manual review."

**Bash — Use Task tool with subagent_type="system-developer:bash-developer"**
Prompt: "Add or update documentation comments for these shell scripts: {file_list}. Every script gets a header below the shebang with Purpose, Usage (real synopsis with flags), Exit codes (each distinct status and its meaning), and Requires (external commands). Every non-trivial function gets a contract comment: positional argument meaning, stdout contract, return status, and globals read or mutated. CRITICAL — per `corpflow:code-comment-standard`: document only the non-obvious WHY and the contract. Never narrate the body, never record history/provenance/before-after, never enumerate call sites. Usage/exit-code/argument contracts are in scope; `# loop over files` above a `for` is not — delete such comments when you find them. Do not invent exit codes the script cannot return. No TODO/placeholder text. Report `{file, function, action}` plus anything needing manual review."

[SYNC POINT: Wait for all documenters before verification.]

### Phase 3: Verify With The Doc Build (Bash)

Skipped entirely under `--no-build` (report coverage as unverified). Otherwise run the build for each language present and tee to `.context/logs/gen-docs-<timestamp>.log`.

**Doxygen (C/C++)**
1. If no `Doxyfile` exists: under `--config` generate one (`doxygen -g Doxyfile`, then set `INPUT`, `RECURSIVE=YES`, `EXTRACT_ALL=NO`, `WARN_IF_UNDOCUMENTED=YES`, `WARN_AS_ERROR=FAIL_ON_WARNINGS`, `GENERATE_LATEX=NO`, `OPTIMIZE_OUTPUT_FOR_C=YES` for C trees); otherwise report it missing and skip.
2. Run `doxygen Doxyfile 2>&1 | tee -a "$LOG"`.
3. Treat `warning: ... is not documented`, mismatched `@param`, and undocumented-parameter warnings as defects. Fix them (or route back to the language documenter) and re-run once.

**Sphinx (Python)**
1. If no `docs/conf.py`: under `--config` scaffold it (`sphinx-quickstart` non-interactive, add `sphinx.ext.autodoc` + `sphinx.ext.napoleon` when the style is Google/NumPy) and generate stubs with `sphinx-apidoc -o docs/api <package>`; otherwise report missing and skip.
2. Run `sphinx-build -W -b html docs docs/_build/html 2>&1 | tee -a "$LOG"`.
3. `-W` makes warnings fatal — a broken cross-reference or malformed docstring section fails the gate. Fix and re-run once.

**Bash**
No doc generator exists. Verify instead that `shellcheck` still passes on the touched scripts (`shellcheck <files>`) and that each documented `Usage:` line matches the script's actual argument parsing. Report header coverage as a count, marked "verified by inspection".

Capture `${PIPESTATUS[0]}`, not `tee`'s status. On a second consecutive failure, stop and report — do not loop.

### Phase 4: README / API Reference (`--readme` only)

**Use Task tool with subagent_type="system-developer:system-developer"**
Prompt: "Update the README/API-reference sections at {path} to match the current public API: {api_surface_summary}. Preserve the existing document structure and voice; update only the API reference, usage examples, and build/doc instructions. Every documented symbol must exist in the code — do not describe aspirational APIs. Keep prose factual and contract-focused; do not add changelog or history narration. Report which sections changed."

### Phase 5: Report

Emit the Output Format summary, including per-language coverage and every symbol left for manual review.

## Doc Build Tooling

| Missing tool | Effect | Install hint |
|--------------|--------|--------------|
| `doxygen` | C/C++ docs written but unverified | `brew install doxygen graphviz` |
| `sphinx-build` | Python docs written but unverified | `uv tool install sphinx` |
| `shellcheck` | Bash headers unverified | `brew install shellcheck` |
| `graphviz`/`dot` | Diagrams skipped; text docs fine | `brew install graphviz` |

Never hard-fail on a missing tool — write the documentation, print the hint, mark that language **unverified**, and continue.

## Output Format

```markdown
## Documentation Report

**Target:** {path}
**Languages:** {C | C++ | Python | Bash}
**Styles detected:** {Doxygen dialect; Python docstring style; Bash header shape}
**Log:** .context/logs/gen-docs-{timestamp}.log

| Language | Symbols documented | Updated | Coverage | Doc build |
|----------|-------------------|---------|----------|-----------|
| {lang} | {n} | {n} | {n}/{total} public | ✅ / ❌ / ⏭ unverified |

### Files Changed
| File | Symbols | Notes |
|------|---------|-------|
| {file} | {n} | {new / updated} |

### Doc Build
- **Doxygen:** {clean | N warnings resolved | not run: reason}
- **Sphinx (`-W`):** {clean | N warnings resolved | not run: reason}
- **Bash:** {N headers verified by inspection}

### Needs Manual Review
| File:Symbol | Why |
|-------------|-----|
| {file}:{symbol} | {contract unclear — behavior could not be determined from the code} |

<!-- When a tool was unavailable: -->
### Unverified
- {language}: {missing tool} — documentation written but not build-verified. Install: {hint}.

<!-- When --readme ran: -->
### README
- Sections updated: {list}
```

## Error Handling

### Path not found
```
Error: Path not found: {path}
Suggestion: Pass a directory that exists, e.g. /system-developer:gen-docs .
```

### No documentable sources
```
Note: No C/C++/Python/Bash sources found under {path}.
Suggestion: Pass an explicit subdirectory, or --lang for extensionless scripts.
```

### Doc config missing (without `--config`)
```
Note: No {Doxyfile | docs/conf.py} found — documentation written, build not run.
Re-run with --config to scaffold it, or add the config yourself.
```

### Doc build fails after one fix cycle
```
Error: {doxygen | sphinx-build -W} still failing after one remediation pass.
First error: {one-line summary}
Log: .context/logs/gen-docs-{timestamp}.log
Documentation comments are written; the build gate did NOT pass.
```

### Doc tool missing
Print the install hint from Doc Build Tooling, mark the language unverified, continue.

### Ambiguous language
Apply `skill: language-detection` shebang/tie-break rules; if still ambiguous, route the file to `system-developer:system-developer` and note the routing in the report.

## See Also

- `corpflow:code-comment-standard` — the WHY/contract-only standard every comment written here must satisfy (no restated code, no history/provenance, no call-site enumeration).
- `skill: language-detection` — canonical marker → language → agent routing; keep the detection table in sync.
- `skill: python-tooling` — uv/Sphinx environment setup for the Python doc build.
- `skill: build-systems` — wiring a `docs` target into CMake or Meson so the doc build runs in CI.
- `skill: bash-scripting` — script header, usage, and exit-code conventions.
- `/system-developer:build-test` — confirm the code still builds and tests green after documentation edits.
- `/system-developer:review-code` — reviewers flag comment-standard violations this command must not introduce.
- `/system-developer:analyze-tech-debt` — quantify undocumented public API as debt before running this.
