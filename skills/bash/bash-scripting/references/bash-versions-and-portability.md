# Bash Versions and Portability

Bash 5.x feature minimums and fallbacks, macOS 3.2, bashism→POSIX `sh`
translation, bashism linting, GNU vs BSD tools, and BusyBox. Distros backport
and macOS freezes, so check `bash --version` before a hard dependency; canonical
minimums are in [version-feature-matrix](../../../_shared/version-feature-matrix.md).

## The macOS 3.2 Reality

macOS `/bin/bash` is Bash 3.2.57 (the last GPLv2 release). It lacks:

- associative arrays (`declare -A`), `${var,,}` / `${var^^}`
- `mapfile` / `readarray`, `&>>`, `|&`
- negative array indices, `${var@Q}`-style transformations
- `wait -n`; `coproc` is present but buggy

Consequences:

1. Use `#!/usr/bin/env bash` so Homebrew's Bash is found (`/opt/homebrew/bin/bash`
   on Apple Silicon, `/usr/local/bin/bash` on Intel), plus a version guard so a
   3.2 run fails loudly.
2. If the script must run on the system shell with no Homebrew, write POSIX
   `#!/bin/sh` instead.
3. macOS `/bin/sh` is Bash 3.2 in POSIX mode, more permissive than `dash`.
   Validate POSIX scripts against `dash`, or bashisms slip through.

## Version Guard Patterns

```bash
#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 5)); then
  printf 'error: bash >= 5.0 required, found %s\n' "${BASH_VERSION:-unknown}" >&2
  printf 'on macOS: brew install bash, then run with that bash\n' >&2
  exit 1
fi
```

Gate a single feature when a fallback exists:

```bash
if ((BASH_VERSINFO[0] >= 4)); then
  declare -A seen                 # associative arrays need Bash 4
else
  : # delimited-string or temp-file fallback
fi

if ((BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 3))); then
  out=${ generate; }              # no-fork substitution, 5.3+
else
  out=$(generate)
fi
```

`BASH_VERSINFO` is `[major, minor, patch, ...]`. It is unset under non-Bash
shells, so use `${BASH_VERSINFO[0]:-0}` if `sh` might source the script.

## Bash 5.x Feature Catalog

5.2 is a safe Linux CI baseline; 5.3 is current stable. Neither exists in macOS
`/bin/bash`.

### 5.0-5.2

| Feature | What it does | Fallback |
|---------|--------------|----------|
| `EPOCHSECONDS` / `EPOCHREALTIME` (5.0) | timestamps without forking `date` | `date +%s` |
| `${var@U}` `${var@L}` `${var@u}` (5.1) | upper/lower/first-letter case | `${var^^}`/`${var,,}` (4.x), or `tr` |
| `wait -p VAR` (5.1) | store the reaped job's PID in `VAR` | track PIDs in an array |
| `patsub_replacement` (5.2, on by default) | `&` in `${var/pat/rep}` reuses the match: `${v/foo/[&]}` → `[foo]` | spell it out; or `sed 's/foo/[&]/'` |
| `varredir_close` (5.2) | auto-close a `{var}<file` FD when the command ends | `exec {fd}<&-` |
| `globskipdots` (5.2, on by default) | `*` never matches `.` and `..` | filter them out |

### 5.3

| Feature | What it does | Fallback |
|---------|--------------|----------|
| `${ cmd; }` (5.3) | capture stdout in the current shell: no fork, variable changes persist | `$(cmd)` (subshell; changes lost) |
| `${\| cmd; }` (5.3) | run in the current shell; result is `REPLY` | function that sets a global |
| `GLOBSORT` (5.3) | glob order: `name`, `size`, `blocks`, `mtime`, `atime`, `ctime`, `numeric`, `none`; `-` prefix reverses | pipe through `sort` / `ls -t` |

### 5.3 examples

`${ cmd; }` is a syntax error on Bash < 5.3 and POSIX shells, so guard it (see
above). It fixes the "variable set in `$(...)` is lost" bug:

```bash
collect() { total=$((total + 1)); printf '%d' "$total"; }
sum=${ collect; }         # total is really incremented; with $(...) it would not be
```

`GLOBSORT`, newest file first without forking `ls`:

```bash
GLOBSORT='-mtime'
for f in ./*.log; do printf '%s\n' "$f"; done
unset GLOBSORT            # back to name, ascending
# pre-5.3: while IFS= read -r f; do ...; done < <(ls -t ./*.log)   (newline caveats)
```

## Bashism → POSIX sh Fallback Table

For `#!/bin/sh` targets (dash, BusyBox ash, `configure` scripts):

### Syntax, tests, and arithmetic

| Bashism | POSIX sh replacement |
|---------|----------------------|
| `[[ ... ]]` | `[ ... ]` with quoting, `&&`/`||` between tests |
| `[[ $s =~ re ]]` | `case "$s" in pattern) ... esac`, or `expr` / `grep` |
| `local var` | unique names, or a subshell function |
| `source file` / `function name {` | `. file` / `name() {` |
| `((expr))` command | `[ "$((expr))" -ne 0 ]` (`$((...))` is POSIX) |
| `{1..10}` | counter loop (`seq` isn't POSIX) |
| `+=` | `var="$var$more"`; `set -- "$@" x` for lists |

### Arrays and string operations

| Bashism | POSIX sh replacement |
|---------|----------------------|
| arrays / `"${arr[@]}"` / `${arr[0]}` | positional params (`set -- a b; for x; do ...; done`) or delimited strings |
| `declare -A map` | `case`, files, or a `key=val` string |
| `${var,,}` / `${var^^}` | `printf '%s' "$var" \| tr '[:upper:]' '[:lower:]'` |
| `${var//old/new}` | `printf '%s' "$var" \| sed 's/old/new/g'` |
| `mapfile` / `readarray` / `read -a` | `while IFS= read -r line; do set -- "$@" "$line"; done < f`; `IFS=... read -r a b c` |

### I/O, output, and pipelines

| Bashism | POSIX sh replacement |
|---------|----------------------|
| `<(cmd)` | temp file: `tmp=$(mktemp); cmd > "$tmp"; ... < "$tmp"` |
| `&>file`, `&>>file`, `\|&` | `>file 2>&1`, `>>file 2>&1`, `2>&1 \|` |
| `echo -e` / `echo -n` | `printf` |
| `$RANDOM` | `awk 'BEGIN{srand();print int(rand()*32768)}'` or `/dev/urandom` |
| `set -o pipefail` | none; check each stage (below) |

## POSIX sh Patterns

Strict mode is `set -eu`; there is no `pipefail`. Use POSIX sh deliberately
(init scripts, container entrypoints), otherwise prefer Bash with a guard.

```bash
#!/bin/sh
set -eu

set -- alpha beta "gamma with space"   # "array" via positional params
for item; do printf 'item: %s\n' "$item"; done
set -- "$@" delta                      # append

# Instead of `producer | consumer` (only consumer's exit is seen):
tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp"' EXIT INT TERM
producer > "$tmp"                      # producer's failure now aborts
consumer < "$tmp"
```

## Detecting and Linting Bashisms

- `checkbashisms script.sh` (Debian `devscripts`) flags Bash-only constructs in
  a `#!/bin/sh` script.
- shellcheck follows the shebang: `#!/bin/sh` switches to POSIX rules (SC3xxx
  "In POSIX sh, X is undefined"). Force a dialect with `# shellcheck shell=sh`.
- Check syntax with `dash -n script.sh`, and run the suite under `dash` (and
  BusyBox `ash` for embedded) rather than macOS `sh`. Config details:
  [shellcheck-shfmt.md](../../bash-testing/references/shellcheck-shfmt.md).

## GNU vs BSD Coreutils Divergence

`../../scripts/probe_toolchain.sh` reports your flavor; `--wrappers` emits
`sed_i` / `canonical` / epoch shims to source
(`eval "$(probe_toolchain.sh --wrappers)"`).

### Text and paths

| Task | GNU (Linux) | BSD (macOS) | Portable approach |
|------|-------------|-------------|-------------------|
| in-place edit | `sed -i 's/a/b/' f` | `sed -i '' 's/a/b/' f` | temp file + `mv` (below), or `perl -i -pe` |
| canonical path | `readlink -f` | no `-f` | `realpath` if present, else `cd && pwd -P` |
| regex grep | `grep -E` / `-P` | `grep -E` only | `-E`, never `-P` |
| `find` regex | `-regextype ...` | other dialect | `-name`/`-path` globs |
| base64 no-wrap | `base64 -w0` | no `-w` | `\| tr -d '\n'` |

### Dates, sizes, and flags

| Task | GNU (Linux) | BSD (macOS) | Portable approach |
|------|-------------|-------------|-------------------|
| date math | `date -d '+1 day'` | `date -v+1d` | `$(( ))` on epoch seconds, or require `gdate` |
| file size | `stat -c '%s' f` | `stat -f '%z' f` | `wc -c < f` |
| skip empty input | `xargs -r` | no `-r` (skips by default) | guard with a count, or `find -print0 \| xargs -0` |
| other flags (`cp` reflink, `mktemp`) | GNU extensions | absent | POSIX-specified flags only |

Homebrew exposes GNU tools as `gsed`, `gdate`, `grealpath`, but a portable
script can't assume them.

### Portable `sed -i`

`sed -i` is the most common break, and no single form works on both: GNU takes
an optional attached suffix, BSD requires one (`''` = no backup), so GNU treats
`''` as a script/file and BSD treats the script as the suffix. Branch on the
platform or use temp file + `mv`, which is portable and atomic:

```bash
edit_in_place() {                 # edit_in_place 's/a/b/' file
  local -r expr="$1" file="$2"
  local tmp
  tmp=$(mktemp -- "${file}.XXXXXX") || return 1
  sed "$expr" "$file" > "$tmp" && mv -f -- "$tmp" "$file"
}
```

## Containers and BusyBox ash

Alpine images ship BusyBox `ash` as `/bin/sh` and no Bash unless you
`apk add bash`, so `#!/bin/bash` fails with `not found`. Make container
entrypoints `#!/bin/sh` and POSIX-clean.

- BusyBox applets have fewer flags than GNU or BSD, and some utilities may be
  missing; probe with `command -v` and use the fallbacks below.
- `/tmp` may be read-only or absent; honor `$TMPDIR` and fail clearly if nothing
  is writable.
- Test on the target image (`docker run --rm -v "$PWD":/w -w /w alpine sh
  ./script.sh`) and lint with `shellcheck -s sh` plus `checkbashisms`.

### Substitutes for missing utilities

| Missing | Portable substitute |
|---------|---------------------|
| `seq 1 N` | `i=1; while [ "$i" -le N ]; do ...; i=$((i+1)); done` |
| `timeout` | background the command, then `kill` it from a sleeping watchdog subshell |
| `flock` | atomic `mkdir lockdir` ([defensive-patterns.md](defensive-patterns.md) > Locking) |
| `mktemp` | `(umask 077; : > "${TMPDIR:-/tmp}/name.$$")`: weaker, predictable name |
| `realpath` / `readlink -f` | `cd -- "$(dirname -- "$f")" && printf '%s/%s\n' "$(pwd -P)" "${f##*/}"` |
| `nproc` | `getconf _NPROCESSORS_ONLN` |
| `tac` | `sed '1!G;h;$!d'` |
| GNU `date -d` | epoch math: `now=$(date +%s); then=$((now + delta))` |

Document the minimum environment (shell, utilities, versions) in the script
header.
