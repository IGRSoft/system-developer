---
name: bash-scripting
description: >-
  Defensive Bash scripting: strict-mode prologue, quoting, arrays, traps,
  and safe resource handling. Use when writing or reviewing a Bash script,
  hardening automation or CI steps, fixing a quoting/word-splitting bug,
  resolving a shellcheck warning, or deciding a task has outgrown shell.
---

# Bash Scripting

Production Bash: fail fast, quote everything, always clean up. If a script
passes ~100 lines, parses JSON/CSV or structured data, needs floating-point
math, or wants rich unit tests, move it to Python (hand off to
`system-developer:python-developer`).

## Canonical Prologue

Use `#!/usr/bin/env bash` (macOS `/bin/bash` is 3.2). `../scripts/prologue_generator.sh`
emits this, optionally with a version guard, INT/TERM traps, or comments:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true   # propagate errexit into subshells (4.4+)
IFS=$'\n\t'                                     # split on newline/tab only, never space

trap 'printf "error: line %d: exit %d\n" "$LINENO" "$?" >&2' ERR
cleanup() { :; }                               # fill in; rm temp files, kill children
trap cleanup EXIT
```

| Flag | Effect |
|------|--------|
| `set -E` | ERR trap inherited by functions, subshells, command substitutions |
| `set -e` | exit on an unhandled non-zero command (see caveats) |
| `set -u` | error on expanding an unset variable |
| `set -o pipefail` | a pipeline fails if any stage fails, not just the last |
| `IFS=$'\n\t'` | drops space from word-splitting; the biggest filename-safety win |

## The `set -e` Caveat Matrix

`set -e` is a backstop for the unanticipated, not a safety net. In these
contexts the non-zero exit is consumed and the script keeps going:

| Context | Do this instead |
|---------|-----------------|
| `if cmd`, `while cmd`, `! cmd` | intended: the condition may fail |
| `cmd \|\| x`, `cmd && x` (lists) | handle the failure explicitly |
| non-last pipeline stage | `set -o pipefail` |
| `local v=$(cmd)` (`local` masks the exit) | split: `local v; v=$(cmd)` |
| `$(...)` or `( ... )` subshell, pre-4.4 | `shopt -s inherit_errexit` |
| a function called as a condition | errexit is off for its whole body; check inside |

Check exit codes explicitly for anything load-bearing:
`if ! deploy "$path"; then log_error "deploy failed"; return 1; fi`.

## Quoting Rules

```bash
cp "$src" "$dst"                  # quote every expansion
for f in "$@"; do ...; done       # "$@" keeps each arg one word
echo "${items[*]}"                # [*]/$* join: display only, never iteration
rm -rf -- "$dir"                  # -- ends options before user data
args=(--flag "$value"); cmd "${args[@]}"   # build commands with arrays, not strings
```

Quote every parameter expansion, command substitution, and glob unless a
comment says why not. Put `--` before user-controlled arguments so a leading
`-` is not parsed as an option.

## Idioms That Replace Pitfalls

```bash
[[ -f "$file" && -r "$file" ]]    # [[ ]] over [ ]: no word-splitting, && and =~
local -r name="$1"                # local in functions; readonly for constants
readonly CONFIG=/etc/app.conf
tmp=$(mktemp -d) || exit 1        # mktemp -d, never a fixed /tmp/foo.$$
trap 'rm -rf -- "$tmp"' EXIT      # register cleanup right after creation
printf '%s\n' "$msg"              # printf over echo (echo -e/-n vary)
mapfile -t lines < <(cmd)         # command output into an array
while IFS= read -r -d '' f; do    # NUL-safe filename iteration
  process "$f"
done < <(find . -type f -print0)
```

Don't iterate over `$(ls)` or `for f in $(find ...)`: both word-split and glob.

## Bash 5.2/5.3 Highlights

| Feature | Win | Fallback |
|---------|-----|----------|
| `${ cmd; }` (5.3) | command substitution in the current shell: no fork, variable changes persist | `$(cmd)` |
| `GLOBSORT` (5.3) | glob order by name/size/mtime, reversible | pipe through `sort` |
| `patsub_replacement` (5.2) | `&` in the replacement reuses the match: `${v/foo/[&]}` | spell the match out |

Gate 5.x features behind a `BASH_VERSINFO` check or they break on macOS 3.2.
Guards, POSIX fallbacks, and GNU vs BSD tools:
[bash-versions-and-portability.md](references/bash-versions-and-portability.md).

## Script Header and Exit Codes

Put a header comment right below the shebang. `Usage` is the real synopsis
the argument parser accepts; `Exit` lists every status the script can return:

```bash
#!/usr/bin/env bash
# Purpose:  rotate and upload the nightly archive.
# Usage:    backup.sh [--dry-run] <src-dir> <dest-bucket>
# Exit:     0 ok | 1 upload failed | 2 bad arguments | 3 lock held
# Requires: aws-cli, gzip
```

| Status | Meaning |
|--------|---------|
| 0 | success |
| 1 | general runtime failure |
| 2 | usage error: unknown flag, missing or invalid argument (as Bash builtins do) |
| 3-125 | script-specific failures, each listed in the header |
| 127 | a required command is missing (the shell's own meaning) |
| 126, 128+N | reserved by the shell (not executable, killed by signal N); don't reuse |

Functions get a short contract comment: positional arguments, what goes to
stdout, return status, and globals read or modified.

## Diagnostic Table

| shellcheck / symptom | Fix | Reference |
|----------------------|-----|-----------|
| SC2086 unquoted `$var` | `"$var"` | Quoting Rules |
| SC2046 unquoted `$(cmd)` as an argument | quote it, or `mapfile`/`read` into an array | Quoting Rules |
| SC2155 `local v=$(cmd)` hides the exit code | `local v; v=$(cmd)` | set -e Caveat Matrix |
| Script continues after a failed command | check the exit code explicitly | set -e Caveat Matrix |
| Paths with spaces break | quote expansions; `IFS=$'\n\t'` | Quoting Rules |
| Temp files left after a crash | `mktemp -d` + EXIT trap | [defensive-patterns.md](references/defensive-patterns.md) |
| Two runs corrupt shared state | `flock` advisory lock | [defensive-patterns.md](references/defensive-patterns.md) |
| Linux-only flags (`sed -i`, `readlink -f`) fail on macOS | portable form or platform wrapper | [bash-versions-and-portability.md](references/bash-versions-and-portability.md) |
| `bad substitution` / `mapfile: command not found` on macOS | `#!/usr/bin/env bash` + version guard | [bash-versions-and-portability.md](references/bash-versions-and-portability.md) |

[defensive-patterns.md](references/defensive-patterns.md) also covers trap
ordering, retries and timeouts, logging, `getopts`/long options, input
validation, dry-run, bounded parallelism, and a full script skeleton.

## Related Skills

- [bash-testing](../bash-testing/SKILL.md): bats-core tests, shellcheck/shfmt gate
- [secure-coding](../../_shared/secure-coding/SKILL.md): no `eval` on input, injection-safe execution
- [version-feature-matrix](../../_shared/version-feature-matrix.md): Bash minimums and the macOS 3.2 caveat
- [python-tooling](../../python/python-tooling/SKILL.md): the target when a script outgrows shell
