---
description: Generate or update Doxygen, Python docstring, and Bash header documentation, then verify it with the doc build
argument-hint: [path (default .)] [--lang c|cpp|python|bash] [--public-only] [--readme] [--no-build] [--config]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
estimated-cost:
  min-tokens: 3000
  max-tokens: 24000
  model-distribution:
    haiku: 15%
    sonnet: 75%
    opus: 10%
---

# Generate Code Documentation

Generate or update API documentation in place: Doxygen blocks for C and C++, PEP 257 docstrings for Python, header and contract comments for Bash, plus the README/API-reference sections that describe them. One documenter per language present runs in parallel, then the real doc build verifies the result.

## Rules

- Document the contract and the non-obvious why, never what the next line does (the `corpflow:code-comment-standard` rule). No history or provenance ("was X, now Y", "added for ticket 42"), no call-site lists. Delete narrating comments you come across.
- API doc comments are contract and in scope: Doxygen `@brief`/`@param`/`@return`/`@retval`/`@throws`, docstring summary + Args/Returns/Raises, a script's purpose/usage/exit codes. A `@param n The n` that restates the name is not; omit it or say something real.
- Match the style the project already uses, because mixing styles documents worse than before: Google vs NumPy vs reST for Python, `@param` vs `\param` and `/**` vs `///<` for C/C++. Pick a default only when there is no precedent, and say so in the report.
- Document only what the code does. When a contract is unclear, leave it undocumented and list it under "Needs Manual Review"; a wrong `@return` is worse than none.
- No placeholders: no `TODO`, `Description here`, or empty `@param` lines.
- The doc build is the gate. Coverage counts as verified only after `doxygen` / `sphinx-build -W` pass; under `--no-build` or a missing tool, report it as unverified.
- A missing doc tool never aborts the run: write the docs, print the install hint, mark that language unverified, continue.

## Usage

```bash
/system-developer:gen-docs .                      # whole project, verified by the doc build
/system-developer:gen-docs src/ --public-only     # exported surface only
/system-developer:gen-docs scripts/ --lang bash   # extensionless scripts
/system-developer:gen-docs . --config --readme    # scaffold Doxyfile/conf.py, refresh README API sections
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | Directory or file to document. Detection is rooted here. |
| `--lang c\|cpp\|python\|bash` | auto | Force the documenter set. Use for extensionless scripts or to narrow a mixed repo. |
| `--public-only` | off | Only the exported surface: installed/public headers, non-`_` Python names (or `__all__`), functions a script exposes. Skip statics, internals, private helpers. |
| `--readme` | off | Also update README/API-reference sections to match the API surface, preserving existing structure. |
| `--no-build` | off | Skip the doc-build verification; report coverage as unverified. |
| `--config` | off | Generate a missing `Doxyfile` or Sphinx `conf.py` (+ `sphinx-apidoc` stubs) instead of only reporting it absent. |

`--config` scaffolds inputs to the build; `--no-build` skips running it. They are independent.

## Language Detection

Detect per file under `path`, excluding vendored and build trees (`build/`, `builddir/`, `.venv/`, `third_party/`, generated sources). `--lang` overrides.

| Files | Documenter | Doc form |
|-------|------------|----------|
| `.c`, `.h` | `system-developer:c-developer` | Doxygen `/** */` blocks |
| `.cpp`, `.cc`, `.cxx`, `.hpp`, `.hh`, `.ixx` | `system-developer:cpp-developer` | Doxygen `/** */` blocks |
| `.py`, `.pyi` | `system-developer:python-developer` | PEP 257 docstrings |
| `.sh`, `.bash`, `.bats` | `system-developer:bash-developer` | Script header + function contract comments |

- A bare `.h` counts as C unless the tree has C++ sources or `CMAKE_CXX_STANDARD`. A header shared across the C/C++ boundary, or any file whose language stays ambiguous, goes to `system-developer:system-developer`; note the routing in the report.
- Classify extensionless scripts by shebang.

## Documentation Standards

**C / C++ (Doxygen).** Put blocks on the declaration in the header so the contract lives with the API:

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

Document what the signature doesn't say: ownership, lifetime, thread-safety, error contract, units. C++ adds exception guarantees (`@throws`) and template parameters (`@tparam`).

**Python (docstrings + Sphinx).** One-line imperative summary, blank line, discussion, then the section block in the project's style. Types live in annotations, not the docstring. Document raised exceptions, side effects, and argument mutation. Module docstrings state what the module is for, so autodoc renders it.

**Bash (header + function contracts).** Every script gets a header below the shebang:

```bash
#!/usr/bin/env bash
# Purpose: rotate and upload the nightly archive.
# Usage:   backup.sh <src-dir> <dest-bucket> [--dry-run]
# Exit:    0 ok | 1 bad args | 2 upload failed | 3 lock held
# Requires: aws-cli, gzip
```

Each non-trivial function gets a contract comment: positional arguments, stdout contract, return status, globals read or mutated.

## Workflow

### 1. Scope and detect

1. Confirm `path` exists, else stop with "Path not found".
2. Build the file list and detect languages. If nothing documentable is in scope, stop with "No documentable sources".
3. Detect the existing style per language: grep for `@param` vs `\param` and `/**` vs `///<`; sample Python docstrings for Google/NumPy/reST markers; check for an existing script-header shape.
4. Locate doc config: `Doxyfile`/`Doxyfile.in`, `docs/conf.py`, `docs/Makefile`.
5. Print the file list, languages, styles, and config status before delegating.

### 2. Document in parallel

Launch one documenter per detected language in a single message with the Agent tool (`subagent_type` from the detection table). Each prompt:

> Add or update {doc form} documentation for these {language} files: {file_list}. Existing style: {detected style}; match it exactly and do not convert existing comments to another style. {language focus}. Document only the contract and the non-obvious why: never restate what a line does, never record history or provenance, never list call sites, and delete narrating comments you find. Contract entries (`@param`/`@return`, Args/Returns/Raises, Usage/Exit) are in scope, but an entry that only restates the name is not; omit it. Document only behavior the code has; leave unclear contracts undocumented and list them. No TODO or placeholder text. {If --public-only: public surface only (language rule below).} Report `{file, symbol, action}` plus symbols needing manual review.

| Language | Focus | `--public-only` surface |
|----------|-------|-------------------------|
| C | Blocks on header declarations. Ownership and who frees, lifetime/validity of pointer arguments, thread-safety, units, error contract (`@param`, `@return`, `@retval` with errno values). | Public headers; skip statics and internals. |
| C++ | Blocks on header declarations. Ownership and lifetime (dangling `string_view`/`span`), `@throws` exception guarantees, `@tparam`, const/thread-safety, return contract. | Public/installed headers. |
| Python | PEP 257: imperative summary, blank line, discussion, section block. Raised exceptions, side effects, argument mutation; no types in prose. Add missing module docstrings. | Public names, respecting `__all__`; skip `_` helpers. |
| Bash | Header below the shebang: Purpose, Usage (real synopsis with flags), Exit (each status the script can return), Requires. Function contracts: positional arguments, stdout, return status, globals read or mutated. | Functions the script exposes. |

Wait for all documenters before verifying.

### 3. Verify with the doc build

Skip under `--no-build`. Otherwise run each present language's build with `set -o pipefail`, teeing to `.context/logs/gen-docs-<timestamp>.log`, so the tool's exit status survives `tee`.

- **Doxygen (C/C++).** If no `Doxyfile`: under `--config` run `doxygen -g Doxyfile` and set `INPUT`, `RECURSIVE=YES`, `EXTRACT_ALL=NO`, `WARN_IF_UNDOCUMENTED=YES`, `WARN_AS_ERROR=FAIL_ON_WARNINGS`, `GENERATE_LATEX=NO`, plus `OPTIMIZE_OUTPUT_FOR_C=YES` for C trees; otherwise report it missing and skip. Run `doxygen Doxyfile 2>&1 | tee -a "$LOG"`. Undocumented-symbol, mismatched-`@param`, and undocumented-parameter warnings are defects.
- **Sphinx (Python).** If no `docs/conf.py`: under `--config` run `sphinx-quickstart` non-interactively, add `sphinx.ext.autodoc` (plus `sphinx.ext.napoleon` for Google/NumPy style), and generate stubs with `sphinx-apidoc -o docs/api <package>`; otherwise report it missing and skip. Run `sphinx-build -W -b html docs docs/_build/html 2>&1 | tee -a "$LOG"`; `-W` fails the gate on broken cross-references and malformed sections.
- **Bash.** There is no doc generator. Run `shellcheck --severity=info <touched files>` and check each `Usage:` line against the script's actual argument parsing. Report header coverage as a count, "verified by inspection".

Fix build failures yourself or route them back to that language's documenter, then re-run once. If it fails again, stop and report instead of looping.

### 4. README / API reference (`--readme` only)

Agent tool, `subagent_type: system-developer:system-developer`:

> Update the README/API-reference sections at {path} to match the current public API: {api_surface_summary}. Preserve the existing structure and voice; change only the API reference, usage examples, and build/doc instructions. Every documented symbol must exist in the code. Keep prose factual; no changelog or history narration. Report which sections changed.

### 5. Report

Emit the Output Format, including per-language coverage and every symbol left for manual review.

## Doc Tools

| Missing tool | Effect | Install hint |
|--------------|--------|--------------|
| `doxygen` | C/C++ docs unverified | `brew install doxygen graphviz` |
| `sphinx-build` | Python docs unverified | `uv tool install sphinx` |
| `shellcheck` | Bash headers unverified | `brew install shellcheck` |
| `graphviz`/`dot` | Diagrams skipped; text docs fine | `brew install graphviz` |

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

```
Error: Path not found: {path}
Suggestion: Pass a directory that exists, e.g. /system-developer:gen-docs .
```

```
Note: No C/C++/Python/Bash sources found under {path}.
Suggestion: Pass an explicit subdirectory, or --lang for extensionless scripts.
```

```
Note: No {Doxyfile | docs/conf.py} found — documentation written, build not run.
Re-run with --config to scaffold it, or add the config yourself.
```

```
Error: {doxygen | sphinx-build -W} still failing after one remediation pass.
First error: {one-line summary}
Log: .context/logs/gen-docs-{timestamp}.log
Documentation comments are written; the build gate did NOT pass.
```

## See Also

- `system-developer:python-tooling`: uv/Sphinx environment setup for the Python doc build.
- `system-developer:build-systems`: wiring a `docs` target into CMake or Meson for CI.
- `system-developer:bash-scripting`: script header, usage, and exit-code conventions.
- `/system-developer:build-test`: confirm the code still builds and tests green after doc edits.
- `/system-developer:review-code`: flags comment-standard violations.
- `/system-developer:analyze-tech-debt`: quantify undocumented public API as debt first.
