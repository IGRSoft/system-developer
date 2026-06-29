#!/usr/bin/env bash
#
# scaffold_pyproject.sh — emit a modern pyproject.toml (the one source of truth).
#
# Generates a PEP 621 / PEP 735 pyproject.toml with a ruff config, matching
# skills/python/python-tooling/SKILL.md (uv + ruff, src layout, dependency
# groups). Keep this in sync with that skill (the source of truth). Output goes
# to stdout by default; customize the emitted metadata afterward.
#
# USAGE
#   scaffold_pyproject.sh (--package NAME | --app NAME) [--python-version VER]
#                         [--output FILE]
#
# OPTIONS
#   --package NAME       Library/CLI: adds a [build-system] (uv_build) and
#                        assumes a src/ layout (uv init --package).
#   --app NAME           Application: no [build-system], flat layout.
#   --python-version VER Minimum Python (default 3.14); sets requires-python
#                        and ruff target-version (3.14 -> py314).
#   --output FILE        Write to FILE instead of stdout.
#   -h, --help           Show this help and exit.
#
# EXAMPLES
#   scaffold_pyproject.sh --package my-lib
#   scaffold_pyproject.sh --app my-svc --python-version 3.12 --output pyproject.toml
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

MODE=""
NAME=""
PYVER="3.14"
OUTPUT=""

set_mode() {
	[[ -z "${MODE}" ]] || die "use exactly one of --package / --app"
	MODE="$1"
	NAME="$2"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--package)
			[[ $# -ge 2 ]] || die "--package needs a NAME"
			set_mode package "$2"
			shift 2
			;;
		--app)
			[[ $# -ge 2 ]] || die "--app needs a NAME"
			set_mode app "$2"
			shift 2
			;;
		--python-version)
			[[ $# -ge 2 ]] || die "--python-version needs a value"
			PYVER="$2"
			shift 2
			;;
		--python-version=*)
			PYVER="${1#*=}"
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

[[ -n "${MODE}" ]] || die "one of --package NAME or --app NAME is required"
case "${PYVER}" in
	[0-9]*.[0-9]*) ;;
	*) die "invalid --python-version \"${PYVER}\" (want e.g. 3.14)" ;;
esac

# ruff target-version: 3.14 -> py314.
TARGET="py${PYVER//./}"

emit() {
	printf '[project]\n'
	printf 'name = "%s"\n' "${NAME}"
	printf 'version = "0.1.0"\n'
	printf 'description = ""\n'
	printf 'requires-python = ">=%s"\n' "${PYVER}"
	printf 'dependencies = []\n'
	printf '\n'
	printf '# PEP 735 dev tooling — not published as extras.\n'
	printf '[dependency-groups]\n'
	printf 'dev = ["pytest>=8", "ruff", "pyright"]\n'
	printf '\n'

	if [[ "${MODE}" == "package" ]]; then
		printf '# Library/CLI: src/ layout + a build backend (uv init --package).\n'
		printf '[build-system]\n'
		printf 'requires = ["uv_build>=0.11,<0.12"]\n'
		printf 'build-backend = "uv_build"\n'
		printf '\n'
	fi

	printf '[tool.ruff]\n'
	printf 'target-version = "%s"\n' "${TARGET}"
	printf 'line-length = 88\n'
	printf 'src = ["src", "tests"]\n'
	printf '\n'
	printf '[tool.ruff.lint]\n'
	printf 'select = ["E", "F", "I", "UP", "B", "SIM"]\n'
	printf '# E/F pyflakes+pycodestyle · I import sort · UP pyupgrade · B bugbear · SIM simplify\n'
}

if [[ -n "${OUTPUT}" ]]; then
	emit >"${OUTPUT}"
	printf 'wrote %s (%s "%s", python >=%s)\n' "${OUTPUT}" "${MODE}" "${NAME}" "${PYVER}" >&2
else
	emit
fi
