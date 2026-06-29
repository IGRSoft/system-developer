#!/usr/bin/env bash
#
# probe_toolchain.sh — detect GNU vs BSD coreutils and emit portable shims.
#
# Replaces the "verify which coreutils you have" guesswork in
# skills/bash/bash-scripting/references/bash-versions-and-portability.md
# (GNU vs BSD Coreutils Divergence). It reports the platform/flavor, and with
# --wrappers prints sourceable functions (sed_i, canonical, epoch helpers) that
# work on both. Keep in sync with that reference (the source of truth).
#
# USAGE
#   probe_toolchain.sh                 # report OS + coreutils flavor + key divergences
#   probe_toolchain.sh --wrappers      # print sourceable portable shim functions
#
# OPTIONS
#   --wrappers       Emit portable wrapper functions to stdout (source them).
#   --output FILE    With --wrappers, write to FILE instead of stdout.
#   -h, --help       Show this help and exit.
#
# EXAMPLES
#   probe_toolchain.sh
#   eval "$(probe_toolchain.sh --wrappers)" && sed_i 's/a/b/' file
#
# EXIT CODES
#   0  success
#   2  usage error
#
# DEPENDENCIES
#   bash (3.2+), uname. Probes sed for the GNU/BSD flavor.
#
set -Eeuo pipefail

die() {
	printf 'error: %s | fix: run --help\n' "$1" >&2
	exit 2
}

show_help() {
	grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
}

WRAPPERS=0
OUTPUT=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--wrappers)
			WRAPPERS=1
			shift
			;;
		--output)
			[[ $# -ge 2 ]] || die "--output needs a value"
			OUTPUT="$2"
			shift 2
			;;
		--output=*)
			OUTPUT="${1#*=}"
			shift
			;;
		-h | --help)
			show_help
			exit 0
			;;
		*)
			die "unknown argument \"$1\""
			;;
	esac
done

os="$(uname -s 2>/dev/null || printf 'unknown')"
if sed --version >/dev/null 2>&1; then
	flavor="GNU"
else
	flavor="BSD"
fi

emit_wrappers() {
	cat <<'EOF'
# Portable shims for GNU/BSD coreutils divergence. Source this, then call the
# functions instead of the raw commands.

case "$(uname -s)" in
  Darwin*) sed_i() { sed -i '' "$@"; } ;;   # BSD: empty backup suffix
  *)       sed_i() { sed -i "$@"; } ;;       # GNU
esac

canonical() {                                # canonical <path> -> absolute, symlink-resolved
  if command -v realpath >/dev/null 2>&1; then
    realpath -- "$1"
  else
    (cd -- "$(dirname -- "$1")" && printf '%s/%s\n' "$(pwd -P)" "${1##*/}")
  fi
}

epoch_now() { date +%s; }                    # seconds since epoch (no GNU/BSD date flags)
epoch_add() { printf '%d\n' "$(($(date +%s) + ${1:-0}))"; }   # epoch_add <seconds>
EOF
}

if [[ "${WRAPPERS}" -eq 1 ]]; then
	if [[ -n "${OUTPUT}" ]]; then
		emit_wrappers >"${OUTPUT}"
		printf 'wrote %s\n' "${OUTPUT}" >&2
	else
		emit_wrappers
	fi
	exit 0
fi

# Default: a short report (to stdout) of what this host has.
printf 'os: %s\n' "${os}"
printf 'coreutils: %s\n' "${flavor}"
printf '\n'
printf 'key divergences to abstract (use --wrappers for shims):\n'
if [[ "${flavor}" == "BSD" ]]; then
	printf '  sed -i      needs an explicit suffix: sed -i '\'''\'' (BSD) vs sed -i (GNU)\n'
	printf '  readlink -f absent — use realpath / the canonical() shim\n'
	printf '  date -d     absent — use date -v or epoch math\n'
	printf '  stat -c     absent — use stat -f or wc -c < file\n'
else
	printf '  sed -i      no suffix needed (GNU); BSD needs sed -i '\'''\''\n'
	printf '  readlink -f available (GNU); BSD lacks it — prefer realpath for portability\n'
	printf '  date -d     available (GNU); BSD uses date -v — prefer epoch math\n'
fi
exit 0
