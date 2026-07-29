---
description: Audit a CLI program's terminal output for NO_COLOR, ANSI contrast, screen-reader friendliness, and --help clarity
argument-hint: [path (default .)] [--lang c|cpp|python|bash] [--check no-color|contrast|output|help]
allowed-tools: Read, Glob, Grep, Bash
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
<!-- Updated: July 2026 -->

Audit how a command-line program presents itself in a terminal: whether it honors `NO_COLOR` and non-TTY output, whether its ANSI usage survives a theme the author did not pick, whether its output is readable by a screen reader and by `grep`, and whether `--help` is actually usable. Read-only — it reports, it does not edit.

**Out of scope, deliberately.** This is not a GUI accessibility audit. There is no view hierarchy, no accessibility tree, and no screen-reader API to annotate in a C/C++/Python/Bash program, so this command makes **no WCAG conformance claim**, checks no touch targets, and does not evaluate assistive-technology labels. For GUI work use the apple-developer counterpart. What is checked here is exactly the four things below, all of which are mechanically greppable.

[Extended thinking: The honest accessible-CLI surface is small and concrete, so this command is small and concrete. Nearly every finding comes from a grep for a hardcoded escape sequence, a missing `isatty`/`NO_COLOR` guard, a diagnostic written to stdout, or an absent usage block — pattern matching, not reasoning. Padding it with borrowed GUI vocabulary would make it look thorough while checking nothing, so the scope is stated as a refusal up front and the model stays on haiku. The one judgment call — is this color pair actually low-contrast, is this output line-oriented enough — goes to a single router delegation at the end, not a fan-out.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **Read-only.** Never write or edit a file from this command. Report findings; remediation is the caller's decision.
2. **Claim nothing about GUI accessibility or WCAG.** Do not report a conformance level, do not cite WCAG success criteria, do not mention screen-reader APIs. Say "not covered" when asked.
3. **Every finding needs `file:line`.** A finding without a concrete source location is not a finding — drop it.
4. **Only report what you grepped or read.** Never infer that a program honors `NO_COLOR` because it "probably does" — absence of the check IS the finding.
5. **Rank with `skill: severity-matrix`** into P0-P3.
6. **No manufactured findings.** A CLI with no color and a clean `--help` is a PASS. Report that plainly rather than inventing P3 nits.
7. **Never enter plan mode.** This command IS the procedure — execute it.

## Usage

```bash
# Audit the whole project's CLI surface
/system-developer:analyze-accessibility

# Audit one tool's sources
/system-developer:analyze-accessibility src/cli/

# Only the NO_COLOR / TTY-detection check
/system-developer:analyze-accessibility . --check no-color

# Force a language when scripts are extensionless
/system-developer:analyze-accessibility bin/ --lang bash
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | Directory or file to audit. Detection is rooted here. |
| `--lang c\|cpp\|python\|bash` | auto | Force the language instead of detecting. See `skill: language-detection` — do not fork its rules. |
| `--check no-color\|contrast\|output\|help` | all four | Run only one check area. Useful in CI when only one regression matters. |

## Check 1: NO_COLOR and TTY Detection

Per [no-color.org](https://no-color.org): when `NO_COLOR` is present in the environment **with any value, including empty**, the program must emit no ANSI color. Also expected: honor `TERM=dumb`, and suppress color when stdout is not a TTY so redirected or piped output stays clean.

Grep for color emission (`\033[`, `\x1b[`, `\e[`, `tput`, `colorama`, `termcolor`, ANSI constants) and for the guards that should gate it (`getenv("NO_COLOR")`, `os.environ`/`NO_COLOR`, `${NO_COLOR`, `isatty`, `sys.stdout.isatty()`, `[ -t 1 ]`, `TERM`). Unconditional emission with no guard on the path is the finding.

Severity guide: color on a non-TTY stdout (pipes get escape codes) is **P0**; no `NO_COLOR` check anywhere is **P1**; `NO_COLOR` treated as a boolean so `NO_COLOR=0` re-enables color is **P2**; `TERM=dumb` ignored is **P3**.

## Check 2: Contrast-Safe ANSI

Prefer the 16 basic colors (SGR 30-37 / 90-97) — the user's terminal theme controls those, so they adapt to the user's background. Hardcoded 256-color (`38;5;N`) or truecolor (`38;2;R;G;B`) values are chosen against the author's background and can vanish on the opposite one.

The load-bearing rule: **never encode meaning in color alone.** Every color-carried signal must also carry a glyph, prefix, or word (`ERROR:`, `[warn]`, `✗`) so a monochrome, color-blind, or `NO_COLOR` reader loses nothing.

Severity guide: a status distinguished by color alone with no textual prefix is **P1**; hardcoded truecolor/256-color for semantic status, bright-on-bright or dim-gray-on-default pairs, and background colors set without a matching foreground are each **P2**.

## Check 3: Screen-Reader-Friendly Output

A screen reader reads a terminal linearly. Redraws, spinners, and box art become noise; stream discipline is what makes output navigable — and greppable, which is the same property.

- **Streams:** diagnostics, progress, and prompts to stderr; data to stdout. A tool whose data is polluted by status lines cannot be piped.
- **Redraws:** no spinners, progress bars, `\r` overwrites, or cursor-movement escapes when stdout is not a TTY.
- **Structure:** avoid ASCII art, box-drawing borders, and banner blocks; keep one record per line so each line stands alone.
- **Escape hatch:** provide `--quiet`/`--plain` or machine-readable `--json` output.

Severity guide: errors or progress on stdout instead of stderr and `\r` redraws emitted on a non-TTY are each **P1**; box-drawing or ASCII-art framing and the total absence of a `--quiet`/`--plain`/`--json` path are each **P2**.

## Check 4: `--help` Readability

Verify `--help` exists, prints a usage synopsis first, lists every option with a description, wraps to a sensible width (~80 columns), and **exits 0** (help is not an error). Note whether a man page or at least a usage block exists, and whether exit codes are documented.

Run `<program> --help` when the binary or script is directly runnable; otherwise read the argument-parser setup (`argparse`, `getopt`/`getopt_long`, `usage()`) and judge from source.

Severity guide: `--help` absent or exiting non-zero is **P1**; a missing usage synopsis or options listed without descriptions is **P2**; over-wide lines, no man page or usage block, and undocumented exit codes are each **P3**.

## Workflow

### Phase 1: Scope and Detect (Bash)

1. Confirm `path` exists; if not, emit the Error Handling message and stop.
2. Detect the language(s) present per `skill: language-detection`, honoring `--lang`. If nothing matches, stop with "no sources".
3. Identify the CLI entry points: `main()`, `if __name__ == "__main__"`, `[project.scripts]` in `pyproject.toml`, executable `*.sh`, `bin/` targets. If none, stop — there is no CLI surface to audit.

### Phase 2: Grep Sweep (Grep, Read)

1. Run the greps for each in-scope check area (skip the others when `--check` is given), recording every hit as `file:line`.
2. For each color-emission site, read enough surrounding lines to determine whether a `NO_COLOR`/`isatty`/`TERM` guard actually dominates it.
3. Attempt `<program> --help` if directly runnable; capture output, line widths, and exit code. If it is not runnable, fall back to reading the parser setup and say so in the report.

### Phase 3: Judge and Report

**Use Task tool with subagent_type="system-developer:system-developer"**
Prompt: "Review these CLI accessibility grep hits and classify them. Findings: {phase2_hits}. Use skill: severity-matrix to rank P0-P3. For each: confirm the site is reachable in normal output, judge whether an existing guard actually covers it, and give a one-line fix. Cover only NO_COLOR/TTY handling, ANSI contrast and color-alone signaling, stream discipline and redraw behavior, and --help usability. Make no WCAG or GUI-accessibility claim. Every finding needs file:line; drop anything you cannot locate. Report no finding if there is none."

Then emit the Output Format. Skip this delegation entirely when Phase 2 produced zero hits — report PASS directly.

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
| P0 | src/log.c:88 | `\033[31m` on stdout with no `isatty` guard — pipes receive escape codes | Gate on `isatty(STDOUT_FILENO)` and `getenv("NO_COLOR")` |
| P1 | src/log.c:91 | Errors distinguished by red only — no `ERROR:` prefix | Prefix the text; keep color decorative |
| P3 | bin/deploy.sh:1 | No usage block, no exit-code documentation | Add a `usage()` and document exit codes |

**Result:** PASS / FAIL — {N findings: P0×0 P1×2 P2×2 P3×1}

**Not covered:** GUI accessibility, WCAG conformance, screen-reader API annotation.
```

## Error Handling

### Path not found
```
Error: Path not found: {path}
Suggestion: Pass a directory or file that exists, e.g. /system-developer:analyze-accessibility .
```

### No CLI entry point found
```
Note: No CLI entry point detected under {path} (no main(), __main__, [project.scripts], or executable script).
This command audits terminal-facing programs only — a library has no output surface to audit. Stopping.
```

### `--help` not runnable
Do not fail. Audit the argument-parser source instead and mark Check 4 findings as "static analysis only — `--help` was not executed" in the report.

### No findings
Report PASS with the per-check table and a one-line statement that no issues were found. Do not pad with P3 nits (Rule 6).

## See Also

- `skill: severity-matrix` — canonical P0-P3 ranking used by the Findings table.
- `skill: language-detection` — canonical marker → language routing; this command does not fork it.
- `skill: bash-scripting` — usage blocks, argument parsing, and exit-code conventions for shell entry points.
- `/system-developer:review-code` — general code review; this command covers only the terminal-output surface.
- `/system-developer:gen-docs` — the place to actually write the missing `--help` text, usage block, or man page.
