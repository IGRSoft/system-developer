# ShellCheck and shfmt Reference

Use this when:

- You are configuring `.shellcheckrc`, severity gates, or ShellCheck directives.
- You hit a specific `SCxxxx` code and need the fix.
- You are setting the canonical `shfmt` flag set and wiring both tools into pre-commit/CI.

Skip if:

- You want bats test patterns — see [bats-patterns.md](bats-patterns.md).
- You only need the quick workflow — it is in [SKILL.md](../SKILL.md).

Jump to:

- Installation and Versions
- Running ShellCheck
- Severity Levels and Tuning
- Top-20 ShellCheck Codes (with fixes)
- Inline Directives and Etiquette
- .shellcheckrc
- shfmt Flags (the enforced set)
- .editorconfig
- Pre-commit Hook
- CI Wiring

> Version markers below assume **ShellCheck 0.9+** and **shfmt 3.x**; verify against
> your toolchain (`shellcheck --version`, `shfmt --version`). Optional checks and a
> handful of codes are newer — fallback notes are inline.

## Installation and Versions

```bash
# macOS
brew install shellcheck shfmt

# Debian/Ubuntu
sudo apt-get install -y shellcheck
# shfmt: go install mvdan.cc/sh/v3/cmd/shfmt@latest   (or download a release binary)

shellcheck --version
shfmt --version
```

## Running ShellCheck

```bash
shellcheck script.sh                      # one file
shellcheck bin/*.sh lib/*.sh              # multiple files
shellcheck --shell=bash script            # force dialect (extensionless files)
shellcheck --severity=warning *.sh        # gate: error + warning only
shellcheck --external-sources script.sh   # follow `source`d files (alias: -x)
shellcheck --format=gcc *.sh              # file:line:col for CI / editors
shellcheck --format=json *.sh             # structured output for tooling

# Recurse a tree, fail on first problem:
find . -type f -name '*.sh' -print0 | xargs -0 -P4 -n1 shellcheck
```

`--external-sources` (or a `# shellcheck source=...` directive) lets ShellCheck resolve `source helper.sh` so it can check variables defined there; without it you get SC1091.

## Severity Levels and Tuning

ShellCheck classifies each finding as `error` > `warning` > `info` > `style`. `--severity=LEVEL` reports that level and above.

| Level | Typical meaning | Gate stance |
|-------|-----------------|-------------|
| error | Almost certainly a bug (syntax, wrong test operator) | Always block |
| warning | Probable bug (unquoted expansion, unreachable code) | Block in CI |
| info | Suggestion that improves correctness | Block once clean |
| style | Cosmetic/idiomatic | Optional |

Recommended gate: start at `--severity=warning`, drive to zero, then ratchet to `info`. Enable extra **optional** checks (off by default) deliberately:

```bash
shellcheck --enable=quote-safe-variables,require-variable-braces,check-unassigned-uppercase *.sh
```

List all optional checks with `shellcheck --list-optional`. (Optional-check names vary by version; verify against your toolchain.)

## Top-20 ShellCheck Codes

| Code | Problem | Fix |
|------|---------|-----|
| SC2086 | Unquoted `$var` → word-splitting & globbing | Quote: `"$var"`; arrays: `"${arr[@]}"` |
| SC2046 | Unquoted `$(...)` splits on whitespace | Quote the substitution, or `read -ra` into an array |
| SC2006 | Legacy backtick `` `cmd` `` | Use `$(cmd)` |
| SC2164 | `cd` may fail, script continues in wrong dir | `cd dir || exit 1` (or `cd dir || return`) |
| SC2155 | `local x=$(cmd)` masks the command's exit code | Split: `local x; x=$(cmd)` |
| SC2181 | `if [ $? -eq 0 ]` after a command | Test directly: `if cmd; then` |
| SC2034 | Variable assigned but never used | Remove it, or `export`/reference it; prefix `_` if intentional |
| SC2059 | Variable in `printf` format string | `printf '%s' "$var"`, not `printf "$var"` |
| SC2128 | Expanding an array without an index gives elem 0 | Use `"${arr[@]}"` or `"${arr[0]}"` explicitly |
| SC2145 | Mixing string and array in one argument | Separate them or use `"${arr[*]}"` deliberately |
| SC2115 | `rm -rf "$dir/"` risks `rm -rf /` if `$dir` empty | `rm -rf "${dir:?}/"` to abort on empty |
| SC2129 | Many `echo >>file` in a row | Group: `{ echo a; echo b; } >>file` |
| SC2207 | `arr=( $(cmd) )` splits unsafely | `mapfile -t arr < <(cmd)` |
| SC2068 | Unquoted `$@`/`$*` in a loop/call | Use `"$@"` |
| SC2148 | No shebang → dialect unknown | Add `#!/usr/bin/env bash` or `# shellcheck shell=bash` |
| SC2154 | Variable referenced but never assigned | Define it, or note it comes from a sourced file (`-x`) |
| SC2015 | `A && B || C` is not if/then/else | Use an explicit `if A; then B; else C; fi` |
| SC1090 | Can't follow non-constant `source "$x"` | Add `# shellcheck source=path` or `disable=SC1090` (justified) |
| SC1091 | Sourced file not found in this sandbox | `--external-sources`, a `source=` directive, or justified disable |
| SC2162 | `read` without `-r` mangles backslashes | `read -r line` |

## Inline Directives and Etiquette

Directives are `# shellcheck` comments. Scope matters:

```bash
# Applies to the NEXT command only — always include a justification.
# shellcheck disable=SC2086  # intentional: $flags is a space-separated flag list
run_tool $flags "$input"

# Applies to the whole file if placed before the first command (use sparingly).
# shellcheck disable=SC1091

# Tell ShellCheck where a sourced file lives:
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"

# Override dialect for one file:
# shellcheck shell=bash
```

Etiquette rules:

1. **Prefer fixing over disabling.** A disable is a last resort, not a shortcut.
2. **Justify every disable** with a trailing comment explaining *why* it is safe.
3. **Scope tightly** — disable on the single offending line, never blanket the file to silence one warning.
4. **Disable the exact code**, never `disable=all`.
5. **Re-audit disables** during review; stale ones hide regressions.

## .shellcheckrc

Project-root config so everyone (and CI) shares one ruleset:

```ini
# Dialect for extensionless / sourced files
shell=bash

# Gate at warning and above
severity=warning

# Opt into stricter optional checks
enable=quote-safe-variables
enable=require-variable-braces
enable=check-unassigned-uppercase

# Follow sourced files for cross-file checks
external-sources=true

# Project-wide, justified disables (keep this list short and documented)
# SC1091: helper libs live outside the lint sandbox in CI
disable=SC1091
```

ShellCheck searches for `.shellcheckrc` in the file's directory and ancestors; `SHELLCHECK_OPTS` env var can supply flags too (e.g. `export SHELLCHECK_OPTS='--severity=warning'`).

## shfmt Flags (the enforced set)

The canonical, CI-enforced flag set is **`-i 2 -ci -bn`**:

| Flag | Effect |
|------|--------|
| `-i 2` | Indent with 2 spaces (0 = tabs) |
| `-ci` | Indent switch *cases* under the `case` |
| `-bn` | Put binary operators (`&&`, `\|\|`, `\|`) at the start of the next line |

Common companions (enable per project taste; verify behavior against your shfmt):

| Flag | Effect |
|------|--------|
| `-sr` | Redirect operators followed by a space (`> file`) |
| `-kp` | Keep column alignment padding |
| `-s` | Simplify the code where safe |
| `-ln bash` | Force the bash dialect (else inferred from shebang) |

Usage:

```bash
shfmt -d -i 2 -ci -bn .          # diff mode: prints needed changes, nonzero exit if any (CI gate)
shfmt -l -i 2 -ci -bn .          # list files that need formatting
shfmt -w -i 2 -ci -bn .          # write changes in place (local fix)
shfmt -d -i 2 -ci -bn script.sh  # single file
```

Before/after (`-i 2 -ci -bn`):

```bash
# before
case "$x" in
a) foo ;;
esac
result=$(long_command_one && long_command_two)

# after
case "$x" in
  a) foo ;;
esac
result=$(long_command_one \
  && long_command_two)
```

## .editorconfig

Make editors and shfmt agree so formatting doesn't ping-pong in reviews. shfmt reads `.editorconfig` when no `-i/-ci/-bn` flags are passed:

```ini
root = true

[*.{sh,bash,bats}]
indent_style = space
indent_size = 2
switch_case_indent = true     # = shfmt -ci
binary_next_line = true       # = shfmt -bn
```

With this file present, `shfmt -d .` (no flags) honors the same settings as the explicit flag set — keep both consistent.

## Pre-commit Hook

Catch issues before they reach CI. With the `pre-commit` framework:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/koalaman/shellcheck-precommit
    rev: v0.10.0
    hooks:
      - id: shellcheck
        args: [--severity=warning, --external-sources]
  - repo: https://github.com/scop/pre-commit-shfmt
    rev: v3.10.0-2
    hooks:
      - id: shfmt
        args: [-i, "2", -ci, -bn, -d]
```

Plain git hook (no framework):

```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit
set -Eeuo pipefail

mapfile -t files < <(git diff --cached --name-only --diff-filter=ACM \
  | grep -E '\.(sh|bash|bats)$' || true)
[ "${#files[@]}" -eq 0 ] && exit 0

shellcheck --severity=warning --external-sources "${files[@]}"
shfmt -d -i 2 -ci -bn "${files[@]}"
```

## CI Wiring

### GitHub Actions

```yaml
name: lint-shell
on: [push, pull_request]
jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: ShellCheck
        uses: ludeeus/action-shellcheck@2.0.0
        env:
          SHELLCHECK_OPTS: --severity=warning --external-sources
  shfmt:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: shfmt (diff gate)
        run: |
          shfmt -d -i 2 -ci -bn .
```

`shfmt -d` exits nonzero when any file would change, so the job fails on drift without writing anything.

### GitLab CI

```yaml
shellcheck:
  stage: lint
  image: koalaman/shellcheck-alpine:stable
  script:
    - find . -type f -name '*.sh' -print0 | xargs -0 -r shellcheck --severity=warning

shfmt:
  stage: lint
  image: mvdan/shfmt:latest
  script:
    - shfmt -d -i 2 -ci -bn .
```

### Make target

```makefile
.PHONY: lint fmt fmt-check
lint:
	shellcheck --severity=warning --external-sources $$(find . -name '*.sh')
fmt:
	shfmt -w -i 2 -ci -bn .
fmt-check:
	shfmt -d -i 2 -ci -bn .
```

## See Also

- [SKILL.md](../SKILL.md) — entry: ShellCheck/shfmt quick workflow and the diagnostic table.
- [bats-patterns.md](bats-patterns.md) — testing the scripts these tools lint and format.
- [bash-scripting](../../bash-scripting/SKILL.md) — defensive patterns that make scripts ShellCheck-clean by construction.
