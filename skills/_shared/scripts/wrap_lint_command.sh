#!/usr/bin/env bash
#
# wrap_lint_command.sh — run a linter/formatter with this plugin's canonical flags.
#
# One entry point for the per-tool invocations scattered across the skills
# (python-tooling ruff, bash-testing shellcheck/shfmt, build-systems clang-tidy),
# so CI jobs and skill examples don't re-derive the exact flags. Check-only by
# default; --fix applies changes where the tool supports it.
#
# USAGE
#   wrap_lint_command.sh TOOL [--fix] [--strict] [PATH ...]
#
# TOOLS (canonical flags):
#   * ruff          -> ruff check  (lint; --fix autofixes)
#   * ruff-format   -> ruff format (--check by default; --fix writes)
#   * mypy          -> mypy        (type check; no --fix)
#   * shellcheck    -> shellcheck --severity=warning --external-sources
#   * shfmt         -> shfmt -i 2 -ci -bn (-d check / -w with --fix)
#   * clang-format  -> clang-format (--dry-run --Werror / -i with --fix)
#   * clang-tidy    -> clang-tidy (--warnings-as-errors='*' under --strict)
#
# OPTIONS
#   --fix       Apply fixes instead of only checking (where supported).
#   --strict    Treat warnings as errors (clang-tidy/clang-format).
#   PATH ...    Files/dirs to act on (default: .). clang-* expect file lists.
#   -h, --help  Show this help and exit.
#
# EXIT CODES
#   0  the tool reported clean
#   1  the tool reported findings (or failed)
#   2  usage error, or the tool is not installed
#
# DEPENDENCIES
#   bash (3.2+), plus whichever TOOL you invoke on PATH.
#
set -Eeuo pipefail

die() {
	printf 'error: %s | fix: run --help\n' "$1" >&2
	exit 2
}

show_help() {
	grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
}

[[ $# -ge 1 ]] || die "a TOOL is required (see --help)"
case "$1" in
	-h | --help)
		show_help
		exit 0
		;;
esac

TOOL="$1"
shift
FIX=0
STRICT=0
PATHS=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		--fix)
			FIX=1
			shift
			;;
		--strict)
			STRICT=1
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

[[ "${#PATHS[@]}" -gt 0 ]] || PATHS=(".")

# Base binary name (before any subcommand) for the existence check.
case "${TOOL}" in
	ruff | ruff-format) bin="ruff" ;;
	mypy) bin="mypy" ;;
	shellcheck) bin="shellcheck" ;;
	shfmt) bin="shfmt" ;;
	clang-format) bin="clang-format" ;;
	clang-tidy) bin="clang-tidy" ;;
	*) die "unknown TOOL \"${TOOL}\" (see --help)" ;;
esac
command -v "${bin}" >/dev/null 2>&1 || die "${bin} not found on PATH"

cmd=()
case "${TOOL}" in
	ruff)
		cmd=(ruff check)
		[[ "${FIX}" -eq 1 ]] && cmd+=(--fix)
		;;
	ruff-format)
		cmd=(ruff format)
		[[ "${FIX}" -eq 1 ]] || cmd+=(--check)
		;;
	mypy)
		cmd=(mypy)
		;;
	shellcheck)
		cmd=(shellcheck --severity=warning --external-sources)
		;;
	shfmt)
		if [[ "${FIX}" -eq 1 ]]; then
			cmd=(shfmt -w -i 2 -ci -bn)
		else
			cmd=(shfmt -d -i 2 -ci -bn)
		fi
		;;
	clang-format)
		if [[ "${FIX}" -eq 1 ]]; then
			cmd=(clang-format -i)
		else
			cmd=(clang-format --dry-run --Werror)
		fi
		;;
	clang-tidy)
		cmd=(clang-tidy)
		[[ "${STRICT}" -eq 1 ]] && cmd+=("--warnings-as-errors=*")
		;;
esac

printf 'running: %s %s\n' "${cmd[*]}" "${PATHS[*]}" >&2
"${cmd[@]}" "${PATHS[@]}"
