---
description: Audit a CLI program's terminal output for NO_COLOR, ANSI contrast, screen-reader friendliness, and --help clarity
argument-hint: [path (default .)] [--lang c|cpp|python|bash] [--check no-color|contrast|output|help]
allowed-tools: Read, Glob, Grep, Bash, Agent
model: haiku
estimated-cost:
  min-tokens: 1500
  max-tokens: 6000
  model-distribution:
    haiku: 85%
    sonnet: 15%
    opus: 0%
---

# CLI Output Accessibility Audit

Audit how a command-line program presents itself in a terminal: `NO_COLOR` and non-TTY handling, ANSI colors that survive any theme, output a screen reader (and `grep`) can follow, and a usable `--help`. Read-only: report findings, edit nothing.

This is not a GUI audit. C/C++/Python/Bash CLIs have no accessibility tree, so make no WCAG conformance claim, cite no success criteria, and check no touch targets or assistive-technology labels. If asked, say "not covered" and point to the apple-developer counterpart for GUI work.

## Rules

- Every finding needs a `file:line` you grepped or read; drop anything you cannot locate.
- A missing guard is itself the finding. Don't assume a program honors `NO_COLOR` without seeing the check.
- A CLI with no color and a clean `--help` is a PASS. Don't pad the report with P3 nits.

## Usage

```bash
/system-developer:analyze-accessibility                        # whole project
/system-developer:analyze-accessibility src/cli/               # one tool's sources
/system-developer:analyze-accessibility . --check no-color     # one check area
/system-developer:analyze-accessibility bin/ --lang bash       # extensionless scripts
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | Directory or file to audit. |
| `--lang c\|cpp\|python\|bash` | auto | Force the language instead of detecting it. |
| `--check no-color\|contrast\|output\|help` | all four | Run one check area only. |

## Check 1: NO_COLOR and TTY Detection

Per [no-color.org](https://no-color.org), when `NO_COLOR` is set to any value, including empty, the program emits no ANSI color. It should also honor `TERM=dumb` and drop color when stdout is not a TTY.

Grep for color emission (`\033[`, `\x1b[`, `\e[`, `tput`, `colorama`, `termcolor`, ANSI constants) and for the guards (`getenv("NO_COLOR")`, `os.environ`/`NO_COLOR`, `${NO_COLOR`, `isatty`, `sys.stdout.isatty()`, `[ -t 1 ]`, `TERM`). Emission with no guard on its path is the finding.

Severity: color on non-TTY stdout (pipes get escape codes) **P0**; no `NO_COLOR` check anywhere **P1**; `NO_COLOR` read as a boolean so `NO_COLOR=0` re-enables color **P2**; `TERM=dumb` ignored **P3**.

## Check 2: Contrast-Safe ANSI

Prefer the 16 basic colors (SGR 30-37 / 90-97): the user's theme controls them. 256-color (`38;5;N`) and truecolor (`38;2;R;G;B`) values are picked against the author's background and can vanish on the opposite one.

Never encode meaning in color alone. Each color-carried signal also needs a glyph, prefix, or word (`ERROR:`, `[warn]`, `✗`) so monochrome, color-blind, and `NO_COLOR` readers lose nothing.

Severity: status shown by color alone **P1**; hardcoded 256/truecolor for semantic status, bright-on-bright or dim-gray-on-default pairs, and a background color set without a matching foreground are each **P2**.

## Check 3: Screen-Reader-Friendly Output

A screen reader reads a terminal linearly, so redraws, spinners, and box art become noise. The same stream discipline makes output greppable.

- **Streams:** diagnostics, progress, and prompts go to stderr; data to stdout.
- **Redraws:** no spinners, progress bars, `\r` overwrites, or cursor-movement escapes when stdout is not a TTY.
- **Structure:** no ASCII art, box-drawing borders, or banners; one record per line.
- **Escape hatch:** a `--quiet`/`--plain` or `--json` mode.

Severity: errors or progress on stdout, and `\r` redraws on a non-TTY, are each **P1**; box-drawing or ASCII-art framing, and no `--quiet`/`--plain`/`--json` path, are each **P2**.

## Check 4: `--help` Readability

`--help` should exist, print a usage synopsis first, describe every option, wrap near 80 columns, and exit 0. Also note whether a man page or usage block exists and whether exit codes are documented.

Run `<program> --help` when it is directly runnable; otherwise judge from the parser setup (`argparse`, `getopt`/`getopt_long`, `usage()`).

Severity: `--help` absent or exiting non-zero **P1**; no usage synopsis, or options without descriptions, **P2**; over-wide lines, no man page or usage block, and undocumented exit codes are each **P3**.

## Workflow

1. **Scope.** Confirm `path` exists. Detect languages from extensions and shebangs (`--lang` overrides; a bare `.h` is C unless the tree has C++ sources or `CMAKE_CXX_STANDARD`). Find CLI entry points: `main()`, `if __name__ == "__main__"`, `[project.scripts]` in `pyproject.toml`, executable `*.sh`, `bin/` targets. Stop with the matching Error Handling message if the path, sources, or entry points are missing.
2. **Sweep.** Run the greps for each in-scope check, recording hits as `file:line` with a provisional severity from the check's guide. For each color-emission site, read enough context to tell whether a `NO_COLOR`/`isatty`/`TERM` guard actually dominates it. Try `<program> --help`, capturing output, line widths, and exit code.
3. **Judge.** With zero hits, report PASS directly. Otherwise delegate as below.
4. Emit the Output Format.

### Judge delegation

Delegate with the Agent tool, `subagent_type="system-developer:system-developer"`, prompt:

"Classify these CLI accessibility findings: {hits with file:line and provisional P0-P3}. For each, confirm the site is reachable in normal output, judge whether an existing guard covers it, keep or adjust the priority with a reason, and give a one-line fix. Scope is only NO_COLOR/TTY handling, ANSI contrast and color-alone signaling, stream discipline and redraws, and --help usability. Make no WCAG or GUI-accessibility claim. Drop any finding you cannot locate at file:line; return none if none hold."

## Output Format

```markdown
## CLI Accessibility Audit

**Target:** {path}
**Languages:** {detected}
**Entry points:** {main.c:212, cli/__main__.py, bin/deploy.sh}
**Checks run:** NO_COLOR/TTY | contrast | output | --help

| Check | Status | Findings |
|-------|--------|---------:|
| NO_COLOR / TTY detection | ❌ | 3 |
| Contrast-safe ANSI | ⚠ | 2 |
| Screen-reader-friendly output | ✅ | 0 |
| `--help` readability | ⚠ | 1 |

### Findings

| Priority | File:Line | Issue | Fix |
|----------|-----------|-------|-----|
| P0 | src/log.c:88 | `\033[31m` on stdout with no `isatty` guard | Gate on `isatty(STDOUT_FILENO)` and `getenv("NO_COLOR")` |
| P1 | src/log.c:91 | Errors marked by red only, no `ERROR:` prefix | Prefix the text; keep color decorative |

**Result:** PASS / FAIL — {N findings: P0×0 P1×2 P2×2 P3×1}

**Not covered:** GUI accessibility, WCAG conformance, screen-reader API annotation.
```

## Error Handling

### Path not found
```
Error: Path not found: {path}
Suggestion: Pass a directory or file that exists, e.g. /system-developer:analyze-accessibility .
```

### No sources or no CLI entry point
```
Note: No CLI entry point detected under {path} (no main(), __main__, [project.scripts], or executable script).
This command audits terminal-facing programs only; a library has no output surface to audit. Stopping.
```

### `--help` not runnable
Don't fail. Audit the parser source and mark Check 4 findings "static analysis only — `--help` was not executed".

### No findings
Report PASS with the per-check table and one line saying no issues were found.

## See Also

- `/system-developer:review-code` — general code review.
- `/system-developer:gen-docs` — write the missing `--help` text, usage block, or man page.
