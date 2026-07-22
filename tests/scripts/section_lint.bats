#!/usr/bin/env bats
#
# Tests for scripts/section-lint.sh.
# Run with: bats tests/scripts/section_lint.bats

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	ROOT="$(cd "${DIR}/../.." && pwd)"
	SCRIPT="${ROOT}/scripts/section-lint.sh"
}

@test "--self-test passes" {
	run "${SCRIPT}" --self-test
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"section-lint self-test: ALL PASS"* ]]
}

@test "a within-cap file passes and reports its section count" {
	printf -- '## small heading\nshort body line\n' >"${BATS_TEST_TMPDIR}/ok.md"
	run "${SCRIPT}" "${BATS_TEST_TMPDIR}/ok.md"
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"all ≤ cap ok"* ]]
}

@test "an over-cap section is flagged and exits nonzero" {
	{ printf -- '## big heading\n'; printf 'x%.0s' $(seq 1 1100); printf '\n'; } >"${BATS_TEST_TMPDIR}/over.md"
	run "${SCRIPT}" "${BATS_TEST_TMPDIR}/over.md"
	[ "${status}" -ne 0 ]
	[[ "${output}" == *"OVER"* ]]
}

@test "real run reports the repo baseline in a stable summary line" {
	# Asserts the summary FORMAT, not the exact count — the count is a moving
	# prose-debt baseline (warn-only in scripts/test.sh, see CHANGELOG).
	run "${SCRIPT}"
	[ "${status}" -ne 0 ]
	[[ "${output}" =~ section-lint:\ [0-9]+\ files,\ [0-9]+\ sections\ over\ cap ]]
}

@test "an unreadable path exits 2" {
	run "${SCRIPT}" "${BATS_TEST_TMPDIR}/does-not-exist.md"
	[ "${status}" -eq 2 ]
}
