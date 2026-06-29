---
name: bash-scripting
description: >-
  Defensive Bash scripting: strict-mode prologue, quoting, arrays, traps,
  and safe resource handling. Use when writing or reviewing a Bash script,
  hardening automation or CI steps, fixing a quoting/word-splitting bug,
  resolving a shellcheck warning, or deciding a task has outgrown shell.
---

# Bash Scripting

**Production-grade Bash: fail fast, quote everything, clean up always**

## When to Use

- Writing or reviewing a Bash script for automation, CI, or system glue.
- A script silently swallows errors, mangles paths with spaces, or leaks temp files.
- A `shellcheck` finding (SC2086, SC2046, SC2155, ...) needs an idiomatic fix.
- Deciding whether a task should stay in Bash or move to Python.

If the script is over ~100 lines or processes structured data, stop and use
Python instead — see [bash-skills](../SKILL.md) > When to Use Bash At All.

## Canonical Prologue

Every non-trivial Bash script starts with this. Target `#!/usr/bin/env bash`,
not `#!/bin/bash` (macOS `/bin/bash` is 3.2). Generate it — with an optional
version guard, INT/TERM traps, or inline comments — using
`../scripts/prologue_generator.sh` instead of retyping the variants:

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
| `set -E` | ERR trap is inherited by functions, subshells, command substitutions |
| `set -e` | exit on any unhandled non-zero command (errexit) — *see caveats below* |
| `set -u` | error on expansion of an unset variable (nounset) |
| `set -o pipefail` | a pipeline fails if **any** stage fails, not just the last |
| `IFS=$'\n\t'` | removes space from word-splitting; the single most effective filename-safety setting |

## The `set -e` Caveat Matrix (honest)

`set -e` is necessary but **not** a safety net. It does **not** fire in these
contexts — the non-zero exit is consumed and the script keeps going:

| Context | Does `set -e` fire? | Do this instead |
|---------|---------------------|-----------------|
| `if cmd; then ...` | No (condition is allowed to fail) | intended — fine |
| `cmd || true`, `cmd && other` | No (part of a list) | handle the failure explicitly |
| `cmd \| filter` (non-last stage) | No without `pipefail` | add `set -o pipefail` |
| `local v=$(cmd)` | No — `local` masks the exit code | split: `local v; v=$(cmd)` |
| `var=$(cmd)` in a function w/o `inherit_errexit` | Often No in subshells | `shopt -s inherit_errexit` |
| command in a subshell `( ... )` | No (pre-4.4 without `inherit_errexit`) | enable `inherit_errexit` |
| inside `&&`/`||` chains generally | No | use an explicit `if` / trap |

Treat `set -e` as a backstop for the *unanticipated*; check exit codes
explicitly for anything load-bearing.

## Quoting Rules (the core of safety)

```bash
cp "$src" "$dst"                  # ✅ quote every expansion
for f in "$@"; do ...; done       # ✅ "$@" preserves each arg as one word
echo "${items[*]}"                # ✅ $* / [*] join — only for display, never iteration
rm -rf -- "$dir"                  # ✅ -- ends options before user data
grep -- "$pattern" "$file"        # ✅ -- guards args that may start with '-'
```

- Quote **every** parameter expansion, command substitution, and glob unless you
  have a specific, commented reason not to.
- `"$@"` (each arg separately) — **never** `$*` or unquoted `$@` for iteration.
- Build commands with **arrays**, not strings: `args=(--flag "$value"); cmd "${args[@]}"`.
- Put `--` before user-controlled positional args so a leading `-` is not parsed
  as an option.

## Idioms That Replace Pitfalls

```bash
[[ -f "$file" && -r "$file" ]]    # ✅ [[ ]] over [ ] in Bash: no word-splitting, supports && and =~
local -r name="$1"                # ✅ local in functions; readonly for constants
readonly CONFIG=/etc/app.conf     # ✅ prevent accidental reassignment
tmp=$(mktemp -d) || exit 1        # ✅ mktemp -d, never a hardcoded /tmp/foo.$$
trap 'rm -rf -- "$tmp"' EXIT      # ✅ register cleanup immediately after creation
printf '%s\n' "$msg"              # ✅ printf over echo (echo -e/-n vary by shell)
mapfile -t lines < <(cmd)         # ✅ read command output into an array safely
while IFS= read -r -d '' f; do    # ✅ NUL-safe filename iteration
  process "$f"
done < <(find . -type f -print0)
```

Never iterate over `$(ls)` or `for f in $(find ...)` — both word-split and glob.

## Bash 5.3 Highlights

| Feature | Win | Fallback |
|---------|-----|----------|
| `${ cmd; }` no-fork command substitution | runs `cmd` in the current shell, no subshell — faster, lets the command set variables | `$(cmd)` (forks a subshell) |
| `GLOBSORT` | control glob expansion order (name/size/mtime, reversible) | pipe through `sort` |
| `patsub_replacement` (5.2) | `&` in the replacement reuses the match: `${v/foo/[&]}` | spell the match out literally |

Gate any 5.x feature behind a `BASH_VERSINFO` check, or it breaks on macOS 3.2.
Details and the full POSIX fallback table:
[bash-versions-and-portability.md](references/bash-versions-and-portability.md).

## When NOT to Use Bash

- Over ~100 lines, or growing nested logic → Python.
- Parsing or emitting JSON/CSV/structured data → Python (`json`, `csv`, `argparse`).
- Floating-point math, statistics → Python.
- Needs unit-testable functions with rich assertions → Python (`pytest`).

Hand off: `Task(system-developer:python-developer)`.

## Diagnostic Table

| shellcheck / symptom | Cause | Fix | Reference |
|----------------------|-------|-----|-----------|
| **SC2086** "Double quote to prevent globbing and word splitting" | unquoted `$var` | `"$var"` | [defensive-patterns.md](references/defensive-patterns.md) |
| **SC2046** "Quote this to prevent word splitting" | unquoted `$(cmd)` in arg position | quote it, or `mapfile`/`read` into an array | [defensive-patterns.md](references/defensive-patterns.md) |
| **SC2155** "Declare and assign separately to avoid masking return values" | `local v=$(cmd)` hides `cmd`'s exit code | `local v; v=$(cmd)` | this file > set -e Caveat Matrix |
| Script keeps going after a failed command | `set -e` doesn't fire in this context | see set -e Caveat Matrix; check exit code explicitly | this file |
| Paths with spaces break | unquoted expansion + space in `IFS` | quote expansions; `IFS=$'\n\t'` | this file > Quoting Rules |
| Temp files left behind on crash | no EXIT trap | `trap 'rm -rf -- "$tmp"' EXIT` after `mktemp -d` | [defensive-patterns.md](references/defensive-patterns.md) |
| Two runs corrupt shared state | no locking | `flock` advisory lock | [defensive-patterns.md](references/defensive-patterns.md) |
| Works on Linux, fails on macOS (`sed -i`, `readlink -f`) | GNU vs BSD coreutils | detect platform / use portable form | [bash-versions-and-portability.md](references/bash-versions-and-portability.md) |
| `bad substitution` / `mapfile: command not found` on macOS | running under `/bin/bash` 3.2 | `#!/usr/bin/env bash` + version guard | [bash-versions-and-portability.md](references/bash-versions-and-portability.md) |

## Related Skills

- [bash-testing](../bash-testing/SKILL.md) — bats-core tests, shellcheck/shfmt gate
- [secure-coding](../../_shared/secure-coding/SKILL.md) — no `eval` on input, `--` separators, injection-safe execution
- [version-feature-matrix](../../_shared/version-feature-matrix.md) — Bash 5.2/5.3 minimums and the macOS 3.2 caveat
- [python-tooling](../../python/python-tooling/SKILL.md) — the target when a script has outgrown shell
