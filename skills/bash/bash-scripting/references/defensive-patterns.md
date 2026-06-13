# Bash Defensive Patterns

Use this when:

- You are writing production automation, a CI step, or a system utility that must
  fail predictably and clean up after itself.
- You need the precise behavior of `set -e`, traps, and signal handling.
- You need copy-paste-correct patterns for temp files, locking, retries,
  timeouts, structured logging, or `getopts` argument parsing.

Skip this file if:

- You only need the prologue and quoting rules. Use [../SKILL.md](../SKILL.md).
- Your question is about a Bash version feature or POSIX portability. Use
  [bash-versions-and-portability.md](bash-versions-and-portability.md).
- You are writing tests. Use [../../bash-testing/SKILL.md](../../bash-testing/SKILL.md).

Jump to:

- The Prologue, Explained
- The `set -e` Caveat Matrix in Depth
- Traps and Signal Interplay (EXIT / ERR / INT / TERM)
- Safe Temporary Files and Directories
- Locking with flock
- Retries and Timeouts
- Structured Logging
- Argument Parsing with getopts
- Long-Option Parsing (manual loop)
- Input Validation and Required Variables
- Dependency and Platform Checks
- Dry-Run and Idempotency
- Checklist

Assumes Bash 4.4+ unless noted. Where a feature needs a newer Bash or differs
on macOS 3.2, the portability reference is cross-linked.

## The Prologue, Explained

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_NAME="${BASH_SOURCE[0]##*/}"

trap 'printf "%s: error on line %d (exit %d)\n" "$SCRIPT_NAME" "$LINENO" "$?" >&2' ERR
trap cleanup EXIT
cleanup() { :; }   # defined below; runs on every exit path
```

- `set -E` makes the ERR trap inherited by functions, command substitutions, and
  subshells. Without it, an error inside a function would not trigger the trap.
- `shopt -s inherit_errexit` (Bash 4.4+) makes `set -e` apply inside
  command-substitution subshells (`v=$(false; echo x)` will fail). The
  `2>/dev/null || true` guard keeps the line harmless on shells that lack it.
- `IFS=$'\n\t'` drops space from word-splitting. This single change neutralizes
  the most common class of "filename with spaces" bugs. Restore a default `IFS`
  locally if a specific block needs space-splitting.
- `SCRIPT_DIR` via `cd -- ... && pwd -P` resolves symlinks and works regardless
  of the caller's working directory. `pwd -P` gives the physical path.

Why `#!/usr/bin/env bash`: it finds the first `bash` on `PATH` (a modern 5.x from
Homebrew on macOS), rather than the frozen 3.2 at `/bin/bash`. Pair it with a
version guard — see [bash-versions-and-portability.md](bash-versions-and-portability.md).

## The `set -e` Caveat Matrix in Depth

`set -e` (errexit) is the backstop for *unanticipated* failures. It is silently
suppressed in many contexts. Memorize where it does not fire:

| Context | errexit fires? | Why / what to do |
|---------|----------------|------------------|
| Last command of a pipeline fails | Yes | — |
| Non-last stage of a pipeline fails | **No** unless `set -o pipefail` | always set `pipefail` |
| `if cmd; then` / `while cmd; do` | **No** (by design) | the condition is allowed to fail |
| `cmd && other`, `cmd \|\| other` | **No** (it's a list) | handle both branches explicitly |
| `!cmd` | **No** | negation suppresses errexit |
| `local v=$(failing)` | **No** | `local`'s own exit (0) masks `$(...)`. Split the declaration |
| `var=$(failing)` in a subshell | **No** pre-4.4 | enable `inherit_errexit` |
| `(subshell; commands)` | **No** pre-4.4 | enable `inherit_errexit` |
| command inside `$(...)` | depends | governed by `inherit_errexit` |
| a function called in a condition | **No** for the whole function | the function runs with errexit "off" semantics in that position |

Split declaration from assignment so the command's exit code is visible
(also fixes shellcheck SC2155):

```bash
# ❌ exit code of mktemp is lost; errexit will not fire
local tmp=$(mktemp)

# ✅ assignment failure now propagates
local tmp
tmp=$(mktemp)
```

For anything load-bearing, do not rely on `set -e` — check explicitly:

```bash
if ! deploy_artifact "$path"; then
  log_error "deploy failed for $path"
  return 1
fi
```

## Traps and Signal Interplay (EXIT / ERR / INT / TERM)

A robust script wires four traps and understands their ordering.

```bash
cleanup() {
  local rc=$?            # capture the triggering exit code FIRST
  rm -rf -- "${tmp:-}"   # use :- in case we die before tmp is set
  [[ -n "${child_pid:-}" ]] && kill "$child_pid" 2>/dev/null || true
  return "$rc"
}
trap cleanup EXIT                       # runs on ANY exit: normal, error, or signal
trap 'log_error "line $LINENO: $?"' ERR # runs on each uncaught error (with set -E)
trap 'exit 130' INT                     # Ctrl-C → exit 128+SIGINT(2)=130
trap 'exit 143' TERM                    # SIGTERM → 128+15=143
```

Key facts about trap ordering and behavior:

- **EXIT runs once, last, on every exit path.** Put cleanup there; do not
  duplicate cleanup in INT/TERM handlers — let them `exit`, which fires EXIT.
- **Capture `$?` as the first line of the EXIT handler.** Any command inside the
  handler overwrites `$?`; grab the real exit code before running cleanup, and
  `return`/`exit` it so the script's exit status is preserved.
- **ERR needs `set -E`** to fire inside functions/subshells. It runs *before*
  EXIT when `set -e` aborts.
- **INT/TERM**: the conventional exit codes are `130` (128 + SIGINT) and `143`
  (128 + SIGTERM). Exiting from the handler triggers EXIT, so cleanup still runs.
- **Resetting a trap**: `trap - EXIT` clears it (e.g., to skip cleanup on a known
  good path). `trap '' INT` ignores a signal.
- **Reap children on signal** so you do not orphan background jobs:

```bash
pids=()
start_worker() { worker "$1" & pids+=("$!"); }

shutdown() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
}
trap shutdown INT TERM
```

## Safe Temporary Files and Directories

Never hardcode a temp path (`/tmp/foo.$$` is predictable and racy). Always
`mktemp`, and register the cleanup trap *immediately* after creation:

```bash
tmp=$(mktemp -d) || { log_error "mktemp failed"; exit 1; }
trap 'rm -rf -- "$tmp"' EXIT

workfile="$tmp/work.json"   # all temp artifacts live under $tmp
```

- `mktemp -d` makes a private directory (mode 0700); put all scratch files inside
  it so one `rm -rf -- "$tmp"` cleans everything.
- Quote and `--`: `rm -rf -- "$tmp"` resists a `$tmp` that is empty or starts with `-`.
- For a single file, `tmp=$(mktemp)` works; still trap its removal.
- **Atomic write** (never leave a half-written target): write to a temp file in
  the same directory, then `mv` (rename is atomic within a filesystem):

```bash
atomic_write() {            # atomic_write /etc/app.conf < newdata
  local -r target="$1"
  local tmp
  tmp=$(mktemp -- "${target}.XXXXXX") || return 1
  cat > "$tmp" && mv -f -- "$tmp" "$target"
}
```

- Restrict permissions for secrets at creation with a subshell umask:
  `(umask 077; : > "$secret")`.

## Locking with flock

Prevent two instances from racing on shared state. `flock` (util-linux; on macOS
install via Homebrew `flock` or use `mkdir` as a fallback) takes an advisory lock
on a file descriptor:

```bash
exec 9>"/var/lock/$SCRIPT_NAME.lock"   # open FD 9 on the lock file
if ! flock -n 9; then                  # -n = non-blocking; fail fast if held
  log_error "another instance is running"
  exit 1
fi
# lock auto-releases when FD 9 closes (i.e., when the script exits)
```

- The lock is released automatically when the holding process exits and FD 9
  closes — no manual unlock, no stale lock after a crash.
- Use `flock -w 30 9` to wait up to 30 seconds instead of failing immediately.
- Portable fallback where `flock` is absent (`mkdir` is atomic):

```bash
lockdir="/tmp/$SCRIPT_NAME.lock.d"
if mkdir -- "$lockdir" 2>/dev/null; then
  trap 'rmdir -- "$lockdir"' EXIT
else
  log_error "locked by another instance"; exit 1
fi
```

## Retries and Timeouts

Bound external calls so a hung dependency cannot wedge the script.

```bash
# Bound a single command's wall-clock time (coreutils `timeout`)
timeout 30s curl -fsS "$url" -o "$out" || { log_error "curl timed out/failed"; exit 1; }
```

Retry with exponential backoff for transient failures:

```bash
retry() {                    # retry <max> <base_delay_s> -- cmd args...
  local -r max="$1" base="$2"; shift 3   # skip max, base, and the literal --
  local attempt=1 delay="$base"
  until "$@"; do
    if ((attempt >= max)); then
      log_error "command failed after $max attempts: $*"
      return 1
    fi
    log_warn "attempt $attempt failed; retrying in ${delay}s"
    sleep "$delay"
    ((attempt++)); ((delay *= 2))
  done
}

retry 5 1 -- curl -fsS "$url" -o "$out"
```

- Use `curl -fsS` (`-f` fail on HTTP errors, `-sS` quiet but show errors) so a 500
  is a non-zero exit, not a "successful" download of an error page.
- On macOS, `timeout` comes from coreutils as `gtimeout` unless symlinked —
  detect and adapt (see [bash-versions-and-portability.md](bash-versions-and-portability.md)).

## Structured Logging

Log to stderr (so stdout stays reserved for the script's actual output/data),
with timestamps and levels controlled by an env var:

```bash
log()       { printf '%s [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" "${*:2}" >&2; }
log_info()  { log INFO  "$@"; }
log_warn()  { log WARN  "$@"; }
log_error() { log ERROR "$@"; }
log_debug() { [[ "${DEBUG:-0}" == 1 ]] && log DEBUG "$@" || true; }
```

- **stderr, always.** Logging to stdout corrupts pipelines and command
  substitution that capture the script's real output.
- Gate verbosity with an env var (`DEBUG=1 ./script`) rather than a global edit.
- Optional system integration: `logger -t "$SCRIPT_NAME" "$msg"` writes to syslog.
- For machine consumption, emit one JSON object per line via `jq -nc` rather than
  hand-building JSON (quoting is a security and correctness hazard):

```bash
log_json() { jq -nc --arg level "$1" --arg msg "$2" '{ts: now|todate, level: $level, msg: $msg}' >&2; }
```

## Argument Parsing with getopts

For short options, `getopts` is the built-in, POSIX-friendly parser:

```bash
verbose=0 output="" jobs=4
usage() {
  cat >&2 <<EOF
Usage: $SCRIPT_NAME [-v] [-o FILE] [-j N] [--] ARGS...
  -v        verbose
  -o FILE   output path (required)
  -j N      parallel jobs (default: 4)
  -h        help
EOF
  exit "${1:-0}"
}

while getopts ':vo:j:h' opt; do
  case "$opt" in
    v) verbose=1 ;;
    o) output="$OPTARG" ;;
    j) jobs="$OPTARG" ;;
    h) usage 0 ;;
    :) log_error "option -$OPTARG requires an argument"; usage 1 ;;
    \?) log_error "unknown option: -$OPTARG"; usage 1 ;;
  esac
done
shift $((OPTIND - 1))    # drop parsed options; "$@" now holds positional args
```

- The **leading colon** in `':vo:j:h'` enables silent error handling, giving you
  the `:` (missing argument) and `\?` (unknown option) cases to report cleanly.
- A trailing colon after a letter (`o:`) means that option takes an argument,
  available in `$OPTARG`.
- `shift $((OPTIND - 1))` removes the consumed options so `"$@"` holds only the
  remaining positional arguments — then validate them quoted.

`getopts` does **not** handle long options (`--output`). For those, write a manual loop.

## Long-Option Parsing (manual loop)

```bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) verbose=1; shift ;;
    -o|--output)  output="${2:?--output needs a value}"; shift 2 ;;
    --output=*)   output="${1#*=}"; shift ;;
    -h|--help)    usage 0 ;;
    --)           shift; break ;;     # everything after -- is positional
    -*)           log_error "unknown option: $1"; usage 1 ;;
    *)            break ;;            # first non-option → positional args
  esac
done
# remaining "$@" are positional arguments
```

- Support both `--output VALUE` and `--output=VALUE` forms.
- `--` terminates option parsing — required so user data starting with `-` is not
  misread as a flag.
- `${2:?msg}` errors with a message if the value is missing.

## Input Validation and Required Variables

```bash
: "${API_TOKEN:?API_TOKEN must be set}"          # fail immediately if unset/empty
[[ -n "$output" ]] || { log_error "-o/--output is required"; usage 1; }
[[ "$jobs" =~ ^[0-9]+$ ]] || { log_error "jobs must be numeric: $jobs"; exit 2; }
[[ -r "$input" ]] || { log_error "cannot read: $input"; exit 2; }
```

- `${VAR:?message}` is the canonical "required env var or die" idiom.
- Validate numerics with a regex (`=~ ^[0-9]+$`) before using them in arithmetic.
- Validate file preconditions (`-r`, `-w`, `-d`, `-x`) before operating, with a
  clear error — do not let a deep command fail cryptically.
- **Never** interpolate unvalidated input into `eval`, a glob, or a path. For
  command construction with dynamic args, use an array
  (`cmd=(rsync -a -- "$src" "$dst"); "${cmd[@]}"`). Injection defense lives in
  [secure-coding](../../../_shared/secure-coding/SKILL.md).

## Dependency and Platform Checks

```bash
require() {                  # require jq curl git
  local missing=()
  local cmd
  for cmd in "$@"; do command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd"); done
  if ((${#missing[@]})); then
    log_error "missing required commands: ${missing[*]}"
    exit 127
  fi
}
require jq curl git

case "$(uname -s)" in
  Linux*)  sed_inplace() { sed -i "$@"; } ;;
  Darwin*) sed_inplace() { sed -i '' "$@"; } ;;   # BSD sed needs an explicit backup suffix
  *)       log_error "unsupported OS"; exit 1 ;;
esac
```

- Use `command -v`, never `which` (which is an external, non-portable program).
- Abstract GNU/BSD divergence behind a wrapper function — see the full divergence
  table in [bash-versions-and-portability.md](bash-versions-and-portability.md).

## Dry-Run and Idempotency

```bash
DRY_RUN="${DRY_RUN:-0}"
run() {                      # run cp -- "$src" "$dst"
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '[dry-run] %s\n' "$*" >&2
    return 0
  fi
  "$@"
}

ensure_dir() { [[ -d "$1" ]] || run mkdir -p -- "$1"; }  # idempotent
```

- Make destructive operations reversible-preview via `DRY_RUN=1`.
- Design for re-runs: check-then-act so a second invocation is a no-op, not a
  duplicate or an error.

## Bounded Parallelism

When work items are independent, run them concurrently but cap concurrency so you
do not fork-bomb the machine. Prefer `xargs -P` driven by NUL-delimited input:

```bash
# Process every *.log with up to N parallel workers, NUL-safe for odd filenames
find . -name '*.log' -print0 \
  | xargs -0 -P "$(getconf _NPROCESSORS_ONLN)" -I{} -- compress_log {}
```

When you need shell logic per item rather than a single command, throttle a
background-job pool manually with `wait -n` (Bash 4.3+):

```bash
max_jobs=4
for item in "${items[@]}"; do
  process "$item" &
  # block until at least one slot frees up
  while (( $(jobs -rp | wc -l) >= max_jobs )); do wait -n; done
done
wait    # drain the remaining jobs
```

- Use `getconf _NPROCESSORS_ONLN` (portable) or `nproc` (GNU) for the CPU count.
- `wait -n` waits for *any* one job; the loop keeps the in-flight count bounded.
- A failure in a backgrounded job will not abort the parent under `set -e` —
  collect statuses explicitly if each job's success matters.

## Annotated Script Skeleton

A complete, defensible starting point combining the patterns above:

```bash
#!/usr/bin/env bash
#
# deploy.sh — copy build artifacts to a target, atomically and idempotently.
# Requires: bash >= 4, rsync, flock. Honors DRY_RUN=1 and DEBUG=1.

set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true
IFS=$'\n\t'

readonly SCRIPT_NAME="${BASH_SOURCE[0]##*/}"
DRY_RUN="${DRY_RUN:-0}"

log()       { printf '%s [%s] %s\n' "$(date '+%FT%T%z')" "$1" "${*:2}" >&2; }
log_info()  { log INFO  "$@"; }
log_error() { log ERROR "$@"; }

cleanup() { local rc=$?; rm -rf -- "${tmp:-}"; return "$rc"; }
trap cleanup EXIT
trap 'log_error "line $LINENO: exit $?"' ERR
trap 'exit 130' INT
trap 'exit 143' TERM

usage() { printf 'usage: %s -s SRC -d DST\n' "$SCRIPT_NAME" >&2; exit "${1:-0}"; }

main() {
  local src="" dst="" opt
  while getopts ':s:d:h' opt; do
    case "$opt" in
      s) src="$OPTARG" ;;
      d) dst="$OPTARG" ;;
      h) usage 0 ;;
      :) log_error "-$OPTARG requires a value"; usage 1 ;;
      \?) log_error "unknown option -$OPTARG"; usage 1 ;;
    esac
  done
  shift $((OPTIND - 1))

  [[ -n "$src" && -n "$dst" ]] || usage 1
  [[ -d "$src" ]] || { log_error "src not a directory: $src"; exit 2; }
  command -v rsync >/dev/null 2>&1 || { log_error "rsync required"; exit 127; }

  exec 9>"/tmp/$SCRIPT_NAME.lock"
  flock -n 9 || { log_error "another deploy is running"; exit 1; }

  tmp=$(mktemp -d)
  log_info "staging in $tmp"

  local cmd=(rsync -a --delete -- "$src/" "$tmp/")
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '[dry-run] %s\n' "${cmd[*]}" >&2
  else
    "${cmd[@]}"
    rm -rf -- "$dst"            # replace target directory atomically-ish
    mv -f -- "$tmp" "$dst"      # rename is atomic within one filesystem
    tmp=""   # ownership transferred; nothing to clean
  fi
  log_info "done"
}

main "$@"
```

This skeleton demonstrates: the full prologue, four traps with exit-code capture,
stderr logging, `getopts` parsing, input/dependency validation, `flock`,
`mktemp -d` with cleanup, array-built commands, `--` separators, dry-run support,
and atomic publish via rename.

## Checklist

- [ ] `#!/usr/bin/env bash`, `set -Eeuo pipefail`, `inherit_errexit`, `IFS=$'\n\t'`.
- [ ] EXIT trap captures `$?` first, then cleans temp files and reaps children.
- [ ] ERR/INT/TERM traps wired; INT→130, TERM→143.
- [ ] Every expansion quoted; `"$@"` for iteration; `--` before user data.
- [ ] No reliance on `set -e` for load-bearing failures — explicit checks.
- [ ] `mktemp -d` + immediate cleanup trap; atomic `mv` for target writes.
- [ ] `flock` (or `mkdir`) guards shared state.
- [ ] External calls bounded with `timeout`; transient ones wrapped in `retry`.
- [ ] Logs go to stderr with levels; `DEBUG` gate.
- [ ] Required vars via `${VAR:?}`; numerics regex-validated; files precondition-checked.
- [ ] Dependencies verified with `command -v`; GNU/BSD differences abstracted.
- [ ] `shellcheck` clean (or each suppression justified inline) — see
      [shellcheck-shfmt.md](../../bash-testing/references/shellcheck-shfmt.md).
- [ ] If it crossed ~100 lines or grew structured-data handling — port to Python.
