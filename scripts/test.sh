#!/usr/bin/env bash
#
# test.sh — run the system-developer bundled-script test suite.
#
# Exercises the scripts under skills/<domain>/scripts/ and _shared/scripts/
# (plus this repo's scripts/), and their tests:
#   1. shellcheck   — lint every bundled script + scripts/validate.sh + scripts/test.sh
#   2. bats         — tests/scripts/*.bats
#   3. pytest       — tests/scripts/*_test.py (via uv if present, else python3)
#
# Note on formatting: the plugin's own scripts are tab-indented and are NOT
# shfmt-gated (validate.sh predates and does not pass `shfmt -i 2`). The
# `-i 2 -ci -bn` set in the bash-testing skill is guidance for *user* projects;
# this runner enforces shellcheck (which the plugin does gate on), not shfmt.
# hooks/ are pre-existing infra outside this suite — lint them separately.
#
# Mirrors the plugin's "degrade gracefully" philosophy: a missing tool is a
# SKIP, not a failure — unless --strict, which turns SKIPs into failures so a
# CI image that should have the tool fails loudly. Actual failures always fail.
#
# Usage:
#   scripts/test.sh [--strict]
#
# Exit codes:
#   0  every suite that ran passed (SKIPs allowed without --strict)
#   1  a lint or test suite failed (or a SKIP under --strict)
#   2  usage error
#
set -Eeuo pipefail

STRICT=0
for arg in "$@"; do
	case "${arg}" in
		--strict) STRICT=1 ;;
		-h | --help)
			grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
			exit 0
			;;
		*)
			printf 'ERROR unknown argument "%s" | fix: run with --strict or no args\n' "${arg}" >&2
			exit 2
			;;
	esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

FAIL_COUNT=0
SKIP_COUNT=0
RAN_COUNT=0

pass() { printf 'PASS  %s\n' "$1"; RAN_COUNT=$((RAN_COUNT + 1)); }
fail() {
	printf 'FAIL  %s\n' "$1" >&2
	FAIL_COUNT=$((FAIL_COUNT + 1))
	RAN_COUNT=$((RAN_COUNT + 1))
}
skip() {
	# skip <suite> <install-hint>
	if [[ "${STRICT}" -eq 1 ]]; then
		printf 'FAIL  %s (required under --strict; %s)\n' "$1" "$2" >&2
		FAIL_COUNT=$((FAIL_COUNT + 1))
	else
		printf 'SKIP  %s (%s)\n' "$1" "$2"
		SKIP_COUNT=$((SKIP_COUNT + 1))
	fi
}

# Scripts this suite owns: bundled skill scripts + this repo's scripts/.
# Newline-delimited; bash 3.2-safe (no mapfile).
SCRIPTS="$(
	find skills -type f -path '*/scripts/*.sh'
	find scripts -type f -name '*.sh'
)"

# --- 1. shellcheck ----------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
	if printf '%s\n' "${SCRIPTS}" | tr '\n' '\0' | xargs -0 shellcheck; then
		pass "shellcheck ($(printf '%s\n' "${SCRIPTS}" | grep -c .) scripts)"
	else
		fail "shellcheck"
	fi
else
	skip "shellcheck" "brew install shellcheck"
fi

# --- 2. bats ----------------------------------------------------------------
if command -v bats >/dev/null 2>&1; then
	if bats tests/scripts/*.bats; then
		pass "bats (tests/scripts)"
	else
		fail "bats"
	fi
else
	skip "bats" "brew install bats-core"
fi

# --- 3. pytest --------------------------------------------------------------
PYTEST_RUNNER=""
if command -v uv >/dev/null 2>&1; then
	PYTEST_RUNNER="uvx pytest" # ephemeral; no project/pyproject needed at repo root
elif python3 -c 'import pytest' >/dev/null 2>&1; then
	PYTEST_RUNNER="python3 -m pytest"
fi
if [[ -n "${PYTEST_RUNNER}" ]]; then
	if ${PYTEST_RUNNER} tests/scripts/ -q; then
		pass "pytest (tests/scripts)"
	else
		fail "pytest"
	fi
else
	skip "pytest" "uv tool install pytest, or pip install pytest"
fi

# --- Summary ----------------------------------------------------------------
printf '\nSummary: %d ran, %d failed, %d skipped%s\n' \
	"${RAN_COUNT}" "${FAIL_COUNT}" "${SKIP_COUNT}" \
	"$([[ "${STRICT}" -eq 1 ]] && printf ' (strict)' || true)"

[[ "${FAIL_COUNT}" -eq 0 ]] || exit 1
exit 0
