# Bash Versions and Portability

Use this when:

- You want to use a Bash 5.2 or 5.3 feature and need to know the minimum version
  and a fallback for older shells.
- A script works on Linux but breaks on macOS (`sed -i`, `readlink -f`, `date`,
  `/bin/bash` being 3.2).
- You must write portable POSIX `sh` and need the bashism→POSIX translation table.
- You are wiring `checkbashisms` / shellcheck portability checks into CI.

Skip this file if:

- You need defensive patterns (traps, locking, retries). Use
  [defensive-patterns.md](defensive-patterns.md).
- You only need the prologue and quoting rules. Use [../SKILL.md](../SKILL.md).

Jump to:

- The macOS 3.2 Reality
- Version Guard Patterns
- Bash 5.2 Feature Catalog
- Bash 5.3 Feature Catalog
- Bashism → POSIX sh Fallback Table
- POSIX sh Constraints (what you give up)
- Detecting and Linting Bashisms (checkbashisms, shellcheck)
- GNU vs BSD Coreutils Divergence
- Portable Patterns for the Common Divergences
- Quick Reference Card

Version minimums below reflect first usable releases as commonly documented;
distros backport and macOS freezes, so for any hard dependency **verify against
your toolchain** (`bash --version`, and the GNU Bash release NEWS) before relying
on a feature in CI. Canonical minimums: [version-feature-matrix](../../../_shared/version-feature-matrix.md).

## The macOS 3.2 Reality

`/bin/bash` on macOS is **Bash 3.2.57**, frozen at the last GPLv2 release Apple
will ship. It lacks nearly everything from Bash 4 and 5:

- No associative arrays (`declare -A`).
- No `${var,,}` / `${var^^}` case conversion.
- No `mapfile` / `readarray`.
- No `&>>` append-both-streams, no `|&`.
- No negative array indices, no `${var@Q}`-style transformations.
- No `wait -n`, no `coproc` (technically present but buggy).

Consequences:

1. **Never `#!/bin/bash` for a script you intend to be portable on macOS.** Use
   `#!/usr/bin/env bash` so it picks up Homebrew's modern Bash (installed to
   `/opt/homebrew/bin/bash` on Apple Silicon, `/usr/local/bin/bash` on Intel),
   and add a version guard so a 3.2 fallback fails loudly.
2. If the script genuinely must run under the system shell with no Homebrew,
   write **POSIX sh** (`#!/bin/sh`) instead — see the constraints section.
3. macOS's default `/bin/sh` is itself Bash-in-POSIX-mode (3.2), which is *more*
   permissive than `dash`. Validate POSIX scripts against `dash`, not macOS `sh`,
   or you will ship accidental bashisms.

## Version Guard Patterns

Fail fast when run on too old a Bash:

```bash
#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 5)); then
  printf 'error: bash >= 5.0 required, found %s\n' "${BASH_VERSION:-unknown}" >&2
  printf 'on macOS: brew install bash, then run with that bash\n' >&2
  exit 1
fi
```

Gate a single feature rather than the whole script when you can fall back:

```bash
# associative arrays need Bash 4
if ((BASH_VERSINFO[0] >= 4)); then
  declare -A seen
else
  : # use a delimited-string or temp-file fallback
fi

# ${ cmd; } no-fork substitution needs Bash 5.3
if ((BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 3))); then
  out=${ generate; }
else
  out=$(generate)
fi
```

`BASH_VERSINFO` is an array: `[0]`=major, `[1]`=minor, `[2]`=patch. It is unset
under non-Bash shells, so guard with `${BASH_VERSINFO[0]:-0}` if a script might be
sourced by `sh`.

## Bash 5.2 Feature Catalog

Bash 5.2 ships in most current Linux distributions and Homebrew.

| Feature | What it does | Fallback (≤5.1 / POSIX) |
|---------|--------------|-------------------------|
| `patsub_replacement` (shopt, on by default) | `&` in the replacement of `${var/pat/rep}` reuses the matched text: `${v/foo/[&]}` → `[foo]` | spell the match out literally; or `sed 's/foo/[&]/'` |
| `varredir_close` (shopt) | auto-close a `{var}<file` redirection FD when the command finishes | `exec {fd}<&-` manually |
| `globskipdots` (shopt, on by default) | `*` never matches `.` and `..` | filter them out explicitly |
| `wait -p VAR` improvements | store the PID of the reaped job in `VAR` | track PIDs in an array yourself |
| `EPOCHREALTIME` / `EPOCHSECONDS` (from 5.0) | sub-second / second timestamps without forking `date` | `date +%s` (forks) |
| `${var@U}` `${var@L}` `${var@u}` (from 5.0/5.1) | upper/lower/title-case transformations | `tr`, or `${var^^}`/`${var,,}` (4.x) |

Treat 5.2 as a safe modern baseline on Linux CI; on macOS it requires Homebrew bash.

## Bash 5.3 Feature Catalog

Bash 5.3 is **current stable** — widely shipped in distros and Homebrew by
mid-2026. Treat it as a modern Linux baseline; the only place it is absent is
macOS's frozen `/bin/bash` (3.2.57), so keep the macOS fallback and a version
guard for any script that might run under the system shell.

| Feature | What it does | Fallback |
|---------|--------------|----------|
| `${ cmd; }` command substitution | runs `cmd` in the **current shell** (no fork/subshell), capturing its stdout — faster in tight loops and on embedded systems, and the command can set shell variables that persist | `$(cmd)` (forks a subshell; variable changes are lost) |
| `${\| cmd; }` variant | runs `cmd` in the current shell; result is whatever `cmd` left in `REPLY` | a function that sets a global, then read it |
| `GLOBSORT` variable | controls glob result ordering: `name`, `size`, `blocks`, `mtime`, `atime`, `ctime`, `numeric`, or `none`, ascending/descending | pipe glob output through `sort` / `ls -t` |
| Readline case-insensitive search | interactive only | n/a for scripts |
| C23 build conformance | build-time only | n/a for scripts |

The no-fork command substitution is the headline: it removes subshell overhead
and the "variables set inside `$(...)` are invisible outside" footgun. But code
written with `${ cmd; }` will be a **syntax error** on any Bash < 5.3 and on
POSIX shells, so guard it or keep a `$(...)` fallback.

Worked example — the classic "variable set in a subshell is lost" bug, and the
5.3 fix:

```bash
# ❌ count++ runs in the $(...) subshell; the outer `total` never changes
total=0
process() { echo "$((total + 1))"; }
sum=$(process)            # subshell: any assignment to total is discarded

# ✅ Bash 5.3: ${ cmd; } runs in the current shell, so side effects persist
collect() { total=$((total + 1)); printf '%d' "$total"; }
sum=${ collect; }         # total is now actually incremented

# Portable shim: prefer ${ cmd; } on 5.3+, else $(...) with a global
if ((BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 3))); then
  out=${ build_payload; }
else
  out=$(build_payload)
fi
```

`GLOBSORT` example — iterate files newest-first without forking `ls`:

```bash
# Bash 5.3+
GLOBSORT='-mtime'         # leading '-' = descending; mtime = modification time
for f in ./*.log; do printf '%s\n' "$f"; done   # newest log first
unset GLOBSORT            # restore default (name, ascending)

# Pre-5.3 fallback (forks ls; quoting/newline caveats apply)
while IFS= read -r f; do printf '%s\n' "$f"; done < <(ls -t ./*.log)
```

## Bashism → POSIX sh Fallback Table

When the target is `#!/bin/sh` (dash, BusyBox ash, `configure` scripts), every
construct on the left must become the right.

| Bashism | POSIX sh replacement |
|---------|----------------------|
| `[[ ... ]]` | `[ ... ]` (with proper quoting and `&&`/`||` between tests) |
| `[[ $s =~ re ]]` | `case "$s" in pattern) ... esac`, or `expr` / `grep` |
| `local var` | no `local`; use a subshell function or unique var names |
| arrays `arr=(a b)` / `"${arr[@]}"` | positional params: `set -- a b; for x; do ...; done`, or delimited strings |
| `declare -A map` | no associative arrays; emulate with `case`, or files, or a `key=val` string |
| `${var,,}` / `${var^^}` | `printf '%s' "$var" \| tr '[:upper:]' '[:lower:]'` |
| `${var//old/new}` | `printf '%s' "$var" \| sed 's/old/new/g'` (or POSIX `case`/loop) |
| `mapfile -t a < f` / `readarray` | `while IFS= read -r line; do set -- "$@" "$line"; done < f` |
| process substitution `<(cmd)` | a temp file: `tmp=$(mktemp); cmd > "$tmp"; ... < "$tmp"` |
| `&>file`, `&>>file` | `>file 2>&1`, `>>file 2>&1` |
| `cmd1 \|& cmd2` | `cmd1 2>&1 \| cmd2` |
| `source file` | `. file` |
| `function name {` | `name() {` |
| `echo -e` / `echo -n` | `printf` (always — `echo` flags are non-portable) |
| `$RANDOM` | `awk 'BEGIN{srand();print int(rand()*32768)}'` or `/dev/urandom` |
| `set -o pipefail` | not in POSIX; restructure to check each stage, or accept last-exit semantics |
| `${arr[0]}` indexing | positional `$1`, or `cut`/`awk` on a delimited string |
| `+=` on strings/arrays | `var="$var$more"` for strings; `set --` for lists |
| `((expr))` / `$((expr))` arithmetic command | `$(())` is POSIX; the bare `((...))` *command* is not — use `[ "$((expr))" -ne 0 ]` |
| `read -a arr` | `read` into separate vars, or `IFS=... read -r a b c` |

## POSIX sh Constraints (what you give up)

Writing `#!/bin/sh` means committing to the POSIX subset. The big absences:

- **No arrays** (use positional parameters or delimited strings).
- **No `[[ ]]`** — only `[ ]` / `test`; no `=~` regex (use `case` or `grep`).
- **No `local`** — variables are global; isolate with subshells or naming.
- **No process substitution** `<()` / `>()` — use temp files.
- **No `set -o pipefail`** — a pipeline's exit is the last stage's only.
- **No brace expansion** `{1..10}` — use `seq` (itself non-POSIX; loop with a counter).
- **`set -eu`** is the strict-mode you get; there is no `pipefail`.

Use POSIX sh deliberately (init scripts, container entrypoints, max portability),
not by accident. For anything richer, prefer `#!/usr/bin/env bash` with a guard.

Worked example — emulating an array with positional parameters:

```bash
#!/bin/sh
set -eu

# "array" of arguments via positional params
set -- alpha beta "gamma with space"
for item; do                       # iterates "$@" safely
  printf 'item: %s\n' "$item"
done
printf 'count: %d\n' "$#"

# Append to the "array"
set -- "$@" delta
```

Worked example — reading a file into iterable form without `mapfile`:

```bash
#!/bin/sh
set -eu
# POSIX: build a newline list, then iterate with read
while IFS= read -r line; do
  printf 'line: %s\n' "$line"
done < input.txt
```

Worked example — emulating an associative lookup with `case`:

```bash
#!/bin/sh
lookup() {
  case "$1" in
    host) printf 'localhost' ;;
    port) printf '8080' ;;
    *)    printf '' ;;
  esac
}
printf '%s:%s\n' "$(lookup host)" "$(lookup port)"
```

Strict mode in POSIX sh is `set -eu` — there is no `pipefail`, so for pipelines
whose intermediate stages can fail, restructure to check each stage or capture an
intermediate result:

```bash
#!/bin/sh
set -eu
# Instead of `producer | consumer` (only consumer's exit is seen):
tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp"' EXIT INT TERM
producer > "$tmp"           # now producer's failure aborts under set -e
consumer < "$tmp"
```

## Detecting and Linting Bashisms (checkbashisms, shellcheck)

- **`checkbashisms`** (from Debian `devscripts`): flags Bash-only constructs in a
  script declared as `#!/bin/sh`. Run `checkbashisms script.sh`.
- **shellcheck honors the shebang**: declare `#!/bin/sh` and shellcheck switches to
  POSIX rules, reporting bashisms (e.g. SC2039 / SC3xxx "in POSIX sh, X is
  undefined"). To force a dialect regardless of shebang, add a directive at the
  top of the file:

```bash
# shellcheck shell=sh
```

- **Validate against `dash`, not macOS `sh`.** `dash -n script.sh` checks syntax;
  running the suite under `dash` (and BusyBox `ash` for embedded targets) catches
  bashisms that macOS's permissive 3.2-based `/bin/sh` lets through.
- Full shellcheck/shfmt configuration:
  [shellcheck-shfmt.md](../../bash-testing/references/shellcheck-shfmt.md).

## GNU vs BSD Coreutils Divergence

Linux ships GNU coreutils; macOS/BSD ship the BSD variants. The same command name
takes different flags. Common traps:

| Task | GNU (Linux) | BSD (macOS) | Portable approach |
|------|-------------|-------------|-------------------|
| in-place edit | `sed -i 's/a/b/' f` | `sed -i '' 's/a/b/' f` (needs an explicit, possibly empty, backup suffix) | detect OS; or `perl -i -pe`; or write-to-temp + `mv` |
| canonical path | `readlink -f path` | no `-f` (use `realpath`, or `grealpath`) | `realpath` if present; else a `cd && pwd -P` helper |
| extended regex grep | `grep -E` | `grep -E` (both OK; avoid GNU `grep -P` PCRE) | stick to `-E`, never `-P` for portability |
| date math | `date -d '+1 day'` | `date -v+1d` | compute with `$(( ))` on epoch seconds, or require GNU `gdate` |
| base64 wrap | `base64 -w0` | `base64` (no `-w`; wraps differently) | pipe through `tr -d '\n'` |
| stat fields | `stat -c '%s' f` | `stat -f '%z' f` | branch on `uname`, or use `wc -c < f` for size |
| `find` regex | `find . -regextype ...` | different regex dialect | use `-name`/`-path` globs instead |
| `xargs` no-run-if-empty | `xargs -r` | no `-r` (BSD xargs already skips empty) | guard with a count, or `find -print0 \| xargs -0` |
| `cp` reflink, `mktemp` flags | GNU extensions | absent | stick to POSIX-specified flags |

Homebrew can install GNU coreutils on macOS (`brew install coreutils gnu-sed
grep`), exposing them as `g`-prefixed names (`gsed`, `gdate`, `grealpath`) — but a
*portable* script cannot assume they are installed.

The `sed -i` trap is the single most common cross-platform break. GNU `sed -i`
takes an *optional* suffix attached to the flag (`-i.bak` or none); BSD `sed -i`
*requires* a suffix argument, where an empty string `''` means "no backup". The
two forms are mutually incompatible:

```bash
sed -i    's/a/b/' f   # GNU: edits in place, no backup     | BSD: ERROR, treats 's/a/b/' as the suffix
sed -i '' 's/a/b/' f   # GNU: creates a backup named '' ... | BSD: edits in place, no backup
```

There is no single invocation that does the right thing on both — you must branch
on the platform (next section) or sidestep `sed -i` entirely with a temp-file +
`mv`, which is portable and also atomic:

```bash
edit_in_place() {                 # edit_in_place 's/a/b/' file
  local -r expr="$1" file="$2" tmp
  tmp=$(mktemp -- "${file}.XXXXXX") || return 1
  sed "$expr" "$file" > "$tmp" && mv -f -- "$tmp" "$file"
}
```

## Portable Patterns for the Common Divergences

Abstract the divergence behind a function chosen once at startup:

```bash
# Portable in-place sed
case "$(uname -s)" in
  Darwin*) sed_i() { sed -i '' "$@"; } ;;   # BSD: empty backup suffix
  *)       sed_i() { sed -i "$@"; } ;;       # GNU
esac
sed_i 's/foo/bar/' "$file"

# Portable canonical path
canonical() {
  if command -v realpath >/dev/null 2>&1; then realpath -- "$1"
  else (cd -- "$(dirname -- "$1")" && printf '%s/%s\n' "$(pwd -P)" "${1##*/}")
  fi
}

# Portable epoch arithmetic (avoid date -d / date -v entirely)
now=$(date +%s)
tomorrow=$((now + 86400))
```

Better yet, where the operation is one-shot, prefer the OS-neutral form: write to
a temp file and `mv` instead of `sed -i`; use `wc -c < f` for size instead of
`stat`; compute dates from epoch seconds.

## Containers and Embedded Shells (BusyBox ash)

Alpine-based container images ship **BusyBox `ash`**, not Bash, as `/bin/sh`.
This is the most common "my script ran locally but died in CI/the container" trap.

- `#!/bin/bash` fails outright (`bash: not found`) — Alpine has no Bash unless you
  `apk add bash`. Container entrypoints should be `#!/bin/sh` and POSIX-clean.
- BusyBox applets are leaner than GNU *and* than BSD: many flags simply do not
  exist. Test against `busybox sh` / an `alpine` image, not just your laptop.
- Some utilities may be missing entirely (`mktemp`, `seq`, `timeout`, `flock`).
  Probe and provide fallbacks:

```bash
# Portable mktemp shim for environments that lack it
if ! command -v mktemp >/dev/null 2>&1; then
  mktemp() {
    # Minimal fallback: caller passes a template ending in X's is ignored;
    # uses PID + time for uniqueness. Not as strong as real mktemp.
    _t="${TMPDIR:-/tmp}/tmp.$$.$(date +%s)"
    ( umask 077; : > "$_t" ) && printf '%s\n' "$_t"
  }
fi

# Portable integer sequence without seq
i=1
while [ "$i" -le 5 ]; do printf '%d\n' "$i"; i=$((i + 1)); done
```

- Read-only root filesystems: `/tmp` may be unwritable or absent. Honor `$TMPDIR`
  and fail clearly if no writable scratch directory exists.
- Validate the whole suite on the *target* image in CI (`docker run --rm -v
  "$PWD":/w -w /w alpine sh ./script.sh`), and lint POSIX scripts with
  `shellcheck -s sh` plus `checkbashisms`.

## Portable Fallbacks for Missing Utilities

| Missing | Portable substitute |
|---------|---------------------|
| `seq 1 N` | counter loop: `i=1; while [ "$i" -le N ]; do ...; i=$((i+1)); done` |
| `timeout` | background the command, sleep, then `kill` the PID (with a watchdog subshell) |
| `flock` | atomic `mkdir lockdir` (see [defensive-patterns.md](defensive-patterns.md) > Locking) |
| `realpath`/`readlink -f` | `cd -- "$(dirname -- "$f")" && printf '%s/%s\n' "$(pwd -P)" "${f##*/}"` |
| `nproc` | `getconf _NPROCESSORS_ONLN` |
| `tac` | `sed '1!G;h;$!d'` or `awk '{a[NR]=$0} END{for(i=NR;i;i--) print a[i]}'` |
| GNU `date -d` arithmetic | epoch math: `now=$(date +%s); then=$((now + delta))` |

Always probe with `command -v` before assuming a utility exists, and document the
minimum environment (shell, utilities, versions) in the script header.

## Quick Reference Card

- **Shebang**: `#!/usr/bin/env bash` for Bash (+ version guard); `#!/bin/sh` only
  for deliberate POSIX portability.
- **macOS `/bin/bash` is 3.2** — assume nothing from Bash 4/5 under it.
- **Bash 5.2** is a safe Linux baseline; **5.3** (`${ cmd; }`, `GLOBSORT`) is
  current stable — widely shipped, but still guard `${ cmd; }` for macOS 3.2 / POSIX.
- **Validate POSIX scripts under `dash`**, not macOS `sh`; run `checkbashisms` and
  shellcheck with `# shellcheck shell=sh`.
- **GNU≠BSD**: `sed -i`, `readlink -f`, `date`, `stat`, `base64 -w` all differ —
  abstract them or use OS-neutral forms.

## Related Skills

- [bash-scripting](../SKILL.md) — strict-mode prologue, quoting, the Bash 5.3 highlights table
- [defensive-patterns](defensive-patterns.md) — traps, locking, retries, logging
- [bash-testing](../../bash-testing/SKILL.md) — running the suite under `dash`/`ash` in CI
- [version-feature-matrix](../../../_shared/version-feature-matrix.md) — canonical Bash 5.2/5.3 + macOS 3.2 minimums
