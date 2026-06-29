#!/usr/bin/env bash
#
# prologue_generator.sh — emit a defensive Bash strict-mode prologue.
#
# Prints the canonical prologue from skills/bash/bash-scripting/SKILL.md (strict
# mode, IFS, ERR/EXIT traps) plus the version guard from
# references/bash-versions-and-portability.md. Keep in sync with those (the
# source of truth). The prose explains *why* each line matters; this script just
# emits a correct copy so it never has to be retyped.
#
# USAGE
#   prologue_generator.sh [--min-version N] [--with-version-guard]
#                         [--with-int-term-traps] [--with-comments] [--output FILE]
#
# OPTIONS
#   --min-version N        Minimum Bash major for the guard (default 5).
#   --with-version-guard   Emit a BASH_VERSINFO check that fails on old Bash
#                          (e.g. macOS /bin/bash 3.2).
#   --with-int-term-traps  Trap INT and TERM in addition to EXIT (cleanup on ^C).
#   --with-comments        Annotate each line with why it is there (teaching).
#   --output FILE          Write to FILE instead of stdout.
#   -h, --help             Show this help and exit.
#
# EXAMPLES
#   prologue_generator.sh                                  # minimal prologue
#   prologue_generator.sh --with-version-guard --with-comments
#   prologue_generator.sh --with-int-term-traps --output head.sh
#
# EXIT CODES
#   0  success
#   2  usage error
#
# DEPENDENCIES
#   bash (3.2+), printf. No external tools.
#
set -Eeuo pipefail

die() {
	printf 'error: %s | fix: run --help\n' "$1" >&2
	exit 2
}

show_help() {
	grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
}

MIN_VERSION="5"
GUARD=0
INT_TERM=0
COMMENTS=0
OUTPUT=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--min-version)
			[[ $# -ge 2 ]] || die "--min-version needs a value"
			MIN_VERSION="$2"
			shift 2
			;;
		--min-version=*)
			MIN_VERSION="${1#*=}"
			shift
			;;
		--with-version-guard)
			GUARD=1
			shift
			;;
		--with-int-term-traps)
			INT_TERM=1
			shift
			;;
		--with-comments)
			COMMENTS=1
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

case "${MIN_VERSION}" in
	[0-9]*) ;;
	*) die "invalid --min-version \"${MIN_VERSION}\" (want an integer like 5)" ;;
esac

TRAP_SIGNALS="EXIT"
[[ "${INT_TERM}" -eq 1 ]] && TRAP_SIGNALS="EXIT INT TERM"

emit() {
	printf '#!/usr/bin/env bash\n'

	if [[ "${GUARD}" -eq 1 ]]; then
		[[ "${COMMENTS}" -eq 1 ]] &&
			printf '# Fail loudly on macOS /bin/bash 3.2 and other pre-%s shells.\n' "${MIN_VERSION}"
		# Unquoted heredoc: ${MIN_VERSION} expands; \$ and %s stay literal.
		cat <<EOF
if ((BASH_VERSINFO[0] < ${MIN_VERSION})); then
	printf 'error: bash >= ${MIN_VERSION} required, found %s\n' "\${BASH_VERSION:-unknown}" >&2
	exit 1
fi
EOF
	fi

	# Quoted heredoc: emitted verbatim (\$LINENO etc. must NOT expand here).
	if [[ "${COMMENTS}" -eq 1 ]]; then
		cat <<'EOF'
set -Eeuo pipefail                              # -E: ERR trap inherited; -e: exit on error; -u: unset is error; pipefail
shopt -s inherit_errexit 2>/dev/null || true    # propagate errexit into subshells (bash 4.4+)
IFS=$'\n\t'                                     # split on newline/tab only, never space

trap 'printf "error: line %d: exit %d\n" "$LINENO" "$?" >&2' ERR
cleanup() { :; }                                # fill in: rm temp files, kill children
EOF
	else
		cat <<'EOF'
set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true
IFS=$'\n\t'

trap 'printf "error: line %d: exit %d\n" "$LINENO" "$?" >&2' ERR
cleanup() { :; }
EOF
	fi

	printf 'trap cleanup %s\n' "${TRAP_SIGNALS}"
}

if [[ -n "${OUTPUT}" ]]; then
	emit >"${OUTPUT}"
	printf 'wrote %s\n' "${OUTPUT}" >&2
else
	emit
fi
