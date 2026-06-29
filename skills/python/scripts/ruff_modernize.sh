#!/usr/bin/env bash
#
# ruff_modernize.sh — run ruff's modernization rule set with this plugin's flags.
#
# Wraps the exact `ruff check` invocation the skills prescribe for modernizing
# Python (pyupgrade + bugbear + simplify + comprehension/idiom rules), gated to a
# target version. Mirrors skills/python/python-tooling/SKILL.md (ruff config) and
# the modern-python anti-pattern guidance. Keep the rule set in sync with those.
#
# USAGE
#   ruff_modernize.sh [--target-version VER] [--fix] [PATH ...]
#
# OPTIONS
#   --target-version VER   Python target, e.g. 3.14 (default) -> ruff py314.
#   --fix                  Apply safe autofixes (default: report only).
#   PATH ...               Files/dirs to check (default: .).
#   -h, --help             Show this help and exit.
#
# RULE SET
#   UP (pyupgrade) drives modernization; B (bugbear), SIM (simplify),
#   C4 (comprehensions), PIE, RUF round out safe idiom fixes.
#
# EXIT CODES
#   0  clean (or all issues fixed)
#   1  ruff reported remaining issues
#   2  usage error, or ruff is not installed
#
# DEPENDENCIES
#   bash (3.2+), ruff on PATH (or `uvx ruff`).
#
set -Eeuo pipefail

die() {
	printf 'error: %s | fix: run --help\n' "$1" >&2
	exit 2
}

show_help() {
	grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
}

TARGET="3.14"
FIX=0
PATHS=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		--target-version)
			[[ $# -ge 2 ]] || die "--target-version needs a value"
			TARGET="$2"
			shift 2
			;;
		--target-version=*)
			TARGET="${1#*=}"
			shift
			;;
		--fix)
			FIX=1
			shift
			;;
		-h | --help)
			show_help
			exit 0
			;;
		--)
			shift
			while [[ $# -gt 0 ]]; do
				PATHS+=("$1")
				shift
			done
			;;
		*)
			PATHS+=("$1")
			shift
			;;
	esac
done

case "${TARGET}" in
	[0-9]*.[0-9]*) ;;
	*) die "invalid --target-version \"${TARGET}\" (want e.g. 3.14)" ;;
esac
[[ "${#PATHS[@]}" -gt 0 ]] || PATHS=(".")

command -v ruff >/dev/null 2>&1 || die "ruff not found on PATH (try: uvx ruff ...)"

cmd=(ruff check "--target-version=py${TARGET//./}" "--select=UP,B,SIM,C4,PIE,RUF")
[[ "${FIX}" -eq 1 ]] && cmd+=(--fix)

printf 'running: %s %s\n' "${cmd[*]}" "${PATHS[*]}" >&2
"${cmd[@]}" "${PATHS[@]}"
