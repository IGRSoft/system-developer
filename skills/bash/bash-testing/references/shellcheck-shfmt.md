# ShellCheck and shfmt Reference

Configuring `.shellcheckrc`, severity gates, and directives; fixing a specific
`SCxxxx` code; wiring ShellCheck and shfmt into pre-commit and CI. The quick
workflow is in [SKILL.md](../SKILL.md); bats is in [bats-patterns.md](bats-patterns.md).

## Installation

```bash
brew install shellcheck shfmt                         # macOS
sudo apt-get install -y shellcheck                    # Debian/Ubuntu
go install mvdan.cc/sh/v3/cmd/shfmt@latest            # or a release binary
```

## Running ShellCheck

`../../../_shared/scripts/wrap_lint_command.sh shellcheck [PATH...]` runs the
canonical invocation (`--severity=info --external-sources`; it does the same
for shfmt with `-i 2 -ci -bn`). Raw forms:

```bash
shellcheck bin/*.sh lib/*.sh              # files
shellcheck --shell=bash script            # force dialect (extensionless files)
shellcheck --severity=info *.sh           # gate: error, warning, info
shellcheck --external-sources script.sh   # follow `source`d files (-x)
shellcheck --format=gcc *.sh              # file:line:col for CI / editors
shellcheck --format=json *.sh             # structured output
find . -type f -name '*.sh' -print0 | xargs -0 -P4 -n1 shellcheck
```

Without `--external-sources` or a `# shellcheck source=...` directive, sourced
files aren't followed (SC1091).

## Severity Levels and Tuning

Levels are `error` > `warning` > `info` > `style`; `--severity=LEVEL` reports
that level and above. The gate is `info`: several common bugs (SC2086, SC2059,
SC2162) are `info`, so a `warning` gate would miss them. `style` findings stay
outside the gate (the Gate column below); fix them in review. On a legacy tree,
start at `warning`, drive it to zero, then ratchet to `info`.

Optional checks are off by default; list them with `shellcheck --list-optional`:

```bash
shellcheck --enable=quote-safe-variables,require-variable-braces,check-unassigned-uppercase *.sh
```

## Common ShellCheck Codes

Gate = caught by `--severity=info`.

### Quoting and word splitting

| Code | Gate | Problem | Fix |
|------|------|---------|-----|
| SC2068 | yes | unquoted `$@`/`$*` | `"$@"` |
| SC2145 | yes | string and array mixed in one argument | separate them, or `"${arr[*]}"` deliberately |
| SC2046 | yes | unquoted `$(...)` splits on whitespace | quote it, or `read -ra` / `mapfile` into an array |
| SC2086 | yes | unquoted `$var`: splitting and globbing | `"$var"`; arrays `"${arr[@]}"` |
| SC2128 | yes | array expanded without index gives element 0 | `"${arr[@]}"` or `"${arr[0]}"` |
| SC2207 | yes | `arr=( $(cmd) )` splits unsafely | `mapfile -t arr < <(cmd)` |
| SC2059 | yes | variable in `printf` format string | `printf '%s' "$var"` |
| SC2162 | yes | `read` without `-r` mangles backslashes | `read -r line` |

### Error handling and control flow

| Code | Gate | Problem | Fix |
|------|------|---------|-----|
| SC2164 | yes | `cd` may fail, script continues in the wrong dir | `cd dir \|\| exit 1` (or `\|\| return`) |
| SC2155 | yes | `local x=$(cmd)` masks the exit code | `local x; x=$(cmd)` |
| SC2181 | no | `if [ $? -eq 0 ]` after a command | `if cmd; then` |
| SC2015 | yes | `A && B \|\| C` is not if/then/else | explicit `if A; then B; else C; fi` |
| SC2115 | yes | `rm -rf "$dir/"` becomes `rm -rf /` if empty | `rm -rf "${dir:?}/"` |

### Variables, sourcing, and style

| Code | Gate | Problem | Fix |
|------|------|---------|-----|
| SC2148 | yes | no shebang, dialect unknown | `#!/usr/bin/env bash` or `# shellcheck shell=bash` |
| SC2034 | yes | variable assigned but never used | remove, `export`, or reference it |
| SC2154 | yes | variable referenced but never assigned | define it, or follow the sourced file (`-x`) |
| SC1090 | yes | can't follow non-constant `source "$x"` | `# shellcheck source=path`, or a justified disable |
| SC1091 | yes | sourced file not found in this sandbox | `--external-sources`, a `source=` directive, or a justified disable |
| SC2129 | no | many `echo >>file` in a row | `{ echo a; echo b; } >>file` |
| SC2006 | no | legacy backticks | `$(cmd)` |

## Inline Directives

```bash
# Next command only; justify it:
# shellcheck disable=SC2086  # $flags is an intentional flag list
run_tool $flags "$input"

# Whole file when placed before the first command (use sparingly):
# shellcheck disable=SC1091

# Where a sourced file lives:
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"

# Dialect for one file:
# shellcheck shell=bash
```

Prefer fixing to disabling. When you do disable, name the exact code, scope it
to one line, give the reason, and drop stale disables in review.

## .shellcheckrc

`../../scripts/shellcheck_shfmt_scaffold.sh` emits `.shellcheckrc`,
`.editorconfig`, and (with `--with-precommit`) the pre-commit config. ShellCheck
finds `.shellcheckrc` in the file's directory or an ancestor. It accepts
`shell`, `enable`, `disable`, `external-sources`, and `source-path`; it ignores
`severity`, so pass that via `--severity` or `SHELLCHECK_OPTS='--severity=info'`.

```ini
shell=bash
enable=quote-safe-variables
enable=require-variable-braces
enable=check-unassigned-uppercase
external-sources=true
# Keep project-wide disables short and justified.
# SC1091: helper libs live outside the lint sandbox in CI
disable=SC1091
```

## shfmt Flags

The enforced set is `-i 2 -ci -bn`:

| Flag | Effect |
|------|--------|
| `-i 2` | indent with 2 spaces (0 = tabs) |
| `-ci` | indent `case` arms under `case` |
| `-bn` | binary operators (`&&`, `\|\|`, `\|`) start the next line |

Optional per project: `-sr` (space after redirects), `-kp` (keep alignment
padding), `-s` (simplify), `-ln bash` (force dialect; else inferred from shebang).

```bash
shfmt -d -i 2 -ci -bn .          # diff; nonzero exit if any change (CI gate)
shfmt -l -i 2 -ci -bn .          # list files needing formatting
shfmt -w -i 2 -ci -bn .          # write in place
```

```bash
# after -i 2 -ci -bn
case "$x" in
  a) foo ;;
esac
result=$(long_command_one \
  && long_command_two)
```

## .editorconfig

shfmt reads `.editorconfig` only when no formatting flags are passed. The
scaffold maps `switch_case_indent`/`binary_next_line` to `-ci`/`-bn`, so
`shfmt -d .` honors the same settings; keep the two in sync.

## Pre-commit Hook

`shellcheck_shfmt_scaffold.sh --with-precommit` wires the `shellcheck-precommit`
and `pre-commit-shfmt` hooks with pinned `rev`s. Without the framework:

```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit
set -Eeuo pipefail

mapfile -t files < <(git diff --cached --name-only --diff-filter=ACM \
  | grep -E '\.(sh|bash|bats)$' || true)
[ "${#files[@]}" -eq 0 ] && exit 0

shellcheck --severity=info --external-sources "${files[@]}"
shfmt -d -i 2 -ci -bn "${files[@]}"
```

## CI Wiring

GitHub Actions:

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
          SHELLCHECK_OPTS: --severity=info --external-sources
  shfmt:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: shfmt (diff gate)
        run: shfmt -d -i 2 -ci -bn .
```

GitLab CI:

```yaml
shellcheck:
  stage: lint
  image: koalaman/shellcheck-alpine:stable
  script:
    - find . -type f -name '*.sh' -print0 | xargs -0 -r shellcheck --severity=info

shfmt:
  stage: lint
  image: mvdan/shfmt:latest
  script:
    - shfmt -d -i 2 -ci -bn .
```

## See Also

- [bats-patterns.md](bats-patterns.md): testing the scripts these tools lint
- [bash-scripting](../../bash-scripting/SKILL.md): patterns that are ShellCheck-clean by construction
