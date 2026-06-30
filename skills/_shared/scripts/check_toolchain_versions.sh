#!/usr/bin/env bash
#
# check_toolchain_versions.sh — probe installed toolchain versions against the
# floors this plugin assumes.
#
# Turns the "verify against your toolchain" hedge into a fact: probes each tool
# on PATH, parses its version, and compares it to the floor in
# skills/_shared/version-feature-matrix.md § Build / Toolchain Floor (the source
# of truth — keep the floors below in sync with it). Prints an aligned table.
#
# USAGE
#   check_toolchain_versions.sh [--strict]
#
# OPTIONS
#   --strict       Exit non-zero if any tool is below its floor or missing
#                  (use as a CI-image gate). Without it, the command only
#                  reports and always exits 0.
#   -h, --help     Show this help and exit.
#
# OUTPUT
#   A table: TOOL  INSTALLED  FLOOR  STATUS (ok | below | missing). Floor "*"
#   means "any present version is fine" (current-stable tools like uv/ruff).
#
# EXIT CODES
#   0  no findings (or findings without --strict)
#   1  a tool below its floor or missing, under --strict
#   2  usage error
#
# DEPENDENCIES
#   bash (3.2+), awk, grep. Probes whatever compilers/tools are installed.
#
set -Eeuo pipefail

die() {
	printf 'error: %s | fix: run --help\n' "$1" >&2
	exit 2
}

show_help() {
	grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
}

STRICT=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--strict)
			STRICT=1
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

# Floors assumed by this plugin (see version-feature-matrix.md). "*" = present
# is enough. Newline-delimited "name floor" keeps this bash 3.2-safe.
FLOORS="cmake 3.28
meson 1.11
conan 2.29
uv *
ruff *
shellcheck 0.11
shfmt 3.13
bats 1.13
cppcheck 2.18
gcc 13
clang 16
python3 3.12
bash 5.0"

# version_ge <installed> <floor> -> prints "ge" or "lt" (dotted numeric compare).
version_ge() {
	awk -v a="$1" -v b="$2" 'BEGIN {
		na = split(a, A, "."); nb = split(b, B, ".")
		n = (na > nb) ? na : nb
		for (i = 1; i <= n; i++) {
			x = (i <= na) ? A[i] + 0 : 0
			y = (i <= nb) ? B[i] + 0 : 0
			if (x > y) { print "ge"; exit }
			if (x < y) { print "lt"; exit }
		}
		print "ge"
	}'
}

# probe_version <tool> -> first dotted version on its --version output, or "".
probe_version() {
	"$1" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true
}

OK_COUNT=0
BELOW_COUNT=0
MISSING_COUNT=0

printf '%-12s %-12s %-8s %s\n' "TOOL" "INSTALLED" "FLOOR" "STATUS"
printf '%-12s %-12s %-8s %s\n' "----" "---------" "-----" "------"

while IFS=' ' read -r tool floor; do
	[[ -z "${tool}" ]] && continue
	if ! command -v "${tool}" >/dev/null 2>&1; then
		printf '%-12s %-12s %-8s %s\n' "${tool}" "-" "${floor}" "missing"
		MISSING_COUNT=$((MISSING_COUNT + 1))
		continue
	fi
	ver="$(probe_version "${tool}")"
	if [[ -z "${ver}" ]]; then
		printf '%-12s %-12s %-8s %s\n' "${tool}" "?" "${floor}" "unknown"
		continue
	fi
	if [[ "${floor}" == "*" ]]; then
		printf '%-12s %-12s %-8s %s\n' "${tool}" "${ver}" "${floor}" "ok"
		OK_COUNT=$((OK_COUNT + 1))
		continue
	fi
	if [[ "$(version_ge "${ver}" "${floor}")" == "ge" ]]; then
		printf '%-12s %-12s %-8s %s\n' "${tool}" "${ver}" "${floor}" "ok"
		OK_COUNT=$((OK_COUNT + 1))
	else
		printf '%-12s %-12s %-8s %s\n' "${tool}" "${ver}" "${floor}" "below"
		BELOW_COUNT=$((BELOW_COUNT + 1))
	fi
done <<EOF
${FLOORS}
EOF

printf '\nSummary: %d ok, %d below, %d missing%s\n' \
	"${OK_COUNT}" "${BELOW_COUNT}" "${MISSING_COUNT}" \
	"$(if [[ "${STRICT}" -eq 1 ]]; then printf ' (strict)'; fi)" >&2

if [[ "${STRICT}" -eq 1 && $((BELOW_COUNT + MISSING_COUNT)) -gt 0 ]]; then
	exit 1
fi
exit 0
