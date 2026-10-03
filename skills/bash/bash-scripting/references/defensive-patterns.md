# Bash Defensive Patterns

Copy-paste patterns for traps, temp files, locking, retries, logging, argument
parsing, validation, and parallelism. Assumes Bash 4.4+; version and GNU/BSD
differences are in [bash-versions-and-portability.md](bash-versions-and-portability.md).

## Script Location

Add these after the [prologue](../SKILL.md) when a script needs its own path:

```bash
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_NAME="${BASH_SOURCE[0]##*/}"
```

`cd -- ... && pwd -P` resolves symlinks and works from any caller directory.

## Traps and Signal Interplay (EXIT / ERR / INT / TERM)


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

- EXIT runs once, last, on every exit path. Keep cleanup there only; INT/TERM
  handlers just `exit`, which fires EXIT.
- Capture `$?` on the handler's first line (any command overwrites it) and
  return it so the exit status survives cleanup.
- ERR needs `set -E` to fire inside functions/subshells; it runs before EXIT.
- `trap - EXIT` clears a trap; `trap '' INT` ignores a signal.

### Reaping background children

Reap children on signal so background jobs are not orphaned:

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

A fixed path like `/tmp/foo.$$` is predictable and racy. Use `mktemp` and
register cleanup right after creation:

```bash
tmp=$(mktemp -d) || { log_error "mktemp failed"; exit 1; }
trap 'rm -rf -- "$tmp"' EXIT

workfile="$tmp/work.json"   # all temp artifacts live under $tmp
```

- `mktemp -d` is private (0700); keep all scratch files inside so one `rm -rf`
  cleans everything. A single `mktemp` file still needs its trap.
- Atomic write: write a temp file in the same directory, then `mv` (rename is
  atomic within a filesystem), so the target is never half-written:

```bash
atomic_write() {            # atomic_write /etc/app.conf < newdata
  local -r target="$1"
  local tmp
  tmp=$(mktemp -- "${target}.XXXXXX") || return 1
  cat > "$tmp" && mv -f -- "$tmp" "$target"
}
```

- Create secret files with restricted permissions: `(umask 077; : > "$secret")`.

## Locking with flock

`flock` (util-linux; Homebrew on macOS) takes an advisory lock on a file
descriptor so two instances can't race on shared state:

```bash
exec 9>"/var/lock/$SCRIPT_NAME.lock"   # open FD 9 on the lock file
if ! flock -n 9; then                  # -n = non-blocking; fail fast if held
  log_error "another instance is running"
  exit 1
fi
# lock auto-releases when FD 9 closes (i.e., when the script exits)
```

- No stale lock after a crash: it releases when FD 9 closes.
- `flock -w 30 9` waits up to 30 seconds instead of failing.
- Where `flock` is absent, `mkdir` is atomic:

```bash
lockdir="/tmp/$SCRIPT_NAME.lock.d"
if mkdir -- "$lockdir" 2>/dev/null; then
  trap 'rmdir -- "$lockdir"' EXIT
else
  log_error "locked by another instance"; exit 1
fi
```

## Retries and Timeouts

Bound external calls so a hung dependency can't wedge the script:

```bash
timeout 30s curl -fsS "$url" -o "$out" || { log_error "curl timed out/failed"; exit 1; }
```

Exponential backoff for transient failures:

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

- `curl -fsS` makes an HTTP error a non-zero exit instead of a saved error page.
- On macOS, `timeout` is Homebrew coreutils' `gtimeout`; detect it or use the
  fallback in [bash-versions-and-portability.md](bash-versions-and-portability.md).

## Structured Logging

Log to stderr so stdout carries only the script's data (pipelines and `$(...)`
capture stdout):

```bash
log()       { printf '%s [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" "${*:2}" >&2; }
log_info()  { log INFO  "$@"; }
log_warn()  { log WARN  "$@"; }
log_error() { log ERROR "$@"; }
log_debug() { [[ "${DEBUG:-0}" == 1 ]] && log DEBUG "$@" || true; }
```

- Gate verbosity with an env var (`DEBUG=1 ./script`).
- `logger -t "$SCRIPT_NAME" "$msg"` writes to syslog.
- For machine-readable logs, build JSON with `jq -nc`, not string concatenation
  (quoting hazard):

```bash
log_json() { jq -nc --arg level "$1" --arg msg "$2" '{ts: now|todate, level: $level, msg: $msg}' >&2; }
```

## Argument Parsing with getopts

`getopts` is the built-in parser for short options:

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
    :) log_error "option -$OPTARG requires an argument"; usage 2 ;;
    \?) log_error "unknown option: -$OPTARG"; usage 2 ;;
  esac
done
shift $((OPTIND - 1))    # drop parsed options; "$@" now holds positional args
```

- The leading colon in `':vo:j:h'` enables silent errors, so the `:` (missing
  argument) and `\?` (unknown option) cases report cleanly.
- `o:` means `-o` takes an argument, in `$OPTARG`.
- `getopts` has no long options (`--output`); use the manual loop below.

## Long-Option Parsing (manual loop)

```bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) verbose=1; shift ;;
    -o|--output)  output="${2:?--output needs a value}"; shift 2 ;;
    --output=*)   output="${1#*=}"; shift ;;
    -h|--help)    usage 0 ;;
    --)           shift; break ;;     # everything after -- is positional
    -*)           log_error "unknown option: $1"; usage 2 ;;
    *)            break ;;            # first non-option → positional args
  esac
done
# remaining "$@" are positional arguments
```

Accept both `--output VALUE` and `--output=VALUE`; `--` ends option parsing so
data starting with `-` isn't read as a flag.

## Input Validation and Required Variables

```bash
: "${API_TOKEN:?API_TOKEN must be set}"          # fail immediately if unset/empty
[[ -n "$output" ]] || { log_error "-o/--output is required"; usage 2; }
[[ "$jobs" =~ ^[0-9]+$ ]] || { log_error "jobs must be numeric: $jobs"; exit 2; }
[[ -r "$input" ]] || { log_error "cannot read: $input"; exit 2; }
```

- Regex-check numerics before arithmetic, and check file preconditions up front
  so failures are clear rather than deep and cryptic.
- Keep unvalidated input out of `eval`, globs, and paths; build dynamic commands
  as arrays. Injection defense:
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

Use `command -v`, not `which` (external and non-portable). GNU/BSD divergences:
[bash-versions-and-portability.md](bash-versions-and-portability.md).

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

Preview destructive operations with `DRY_RUN=1`, and check-then-act so a re-run
is a no-op rather than a duplicate or an error.

## Bounded Parallelism

Cap concurrency for independent work items. Prefer `xargs -P` on NUL-delimited
input (the command must be an executable; xargs can't call shell functions):

```bash
find . -name '*.log' -print0 \
  | xargs -0 -P "$(getconf _NPROCESSORS_ONLN)" -I{} -- compress_log {}
```

For shell logic per item, throttle a job pool with `wait -n` (Bash 4.3+):

```bash
max_jobs=4
for item in "${items[@]}"; do
  process "$item" &
  while (( $(jobs -rp | wc -l) >= max_jobs )); do wait -n; done
done
wait    # drain the remaining jobs
```

- CPU count: `getconf _NPROCESSORS_ONLN` (portable) or `nproc` (GNU).
- A failed background job doesn't abort the parent under `set -e`; collect
  statuses explicitly if each job matters.

## Annotated Script Skeleton

Combines the patterns above: prologue, traps with exit-code capture, stderr
logging, `getopts`, validation, `flock`, `mktemp -d`, array commands, dry-run,
and publish by rename.

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
      :) log_error "-$OPTARG requires a value"; usage 2 ;;
      \?) log_error "unknown option -$OPTARG"; usage 2 ;;
    esac
  done
  shift $((OPTIND - 1))

  [[ -n "$src" && -n "$dst" ]] || usage 2
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
