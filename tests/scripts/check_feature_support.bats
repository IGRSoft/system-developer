#!/usr/bin/env bats
#
# Tests for skills/_shared/scripts/check_feature_support.sh.
# Run with: bats tests/scripts/check_feature_support.bats
#
# Uses bash-* features for the verdict tests because they need no external
# compiler/interpreter — they read the running bash version, so the assertions
# hold on any CI image.

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	ROOT="$(cd "${DIR}/../.." && pwd)"
	SCRIPT="${ROOT}/skills/_shared/scripts/check_feature_support.sh"
}

@test "--help exits 0" {
	run "${SCRIPT}" --help
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"USAGE"* ]]
}

@test "--list shows features for every language" {
	run "${SCRIPT}" --list
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"cpp-expected"* ]]
	[[ "${output}" == *"py-tstrings"* ]]
	[[ "${output}" == *"bash-patsub"* ]]
}

@test "a bash feature yields a 0/1 verdict (not a usage error)" {
	run "${SCRIPT}" --feature bash-patsub
	[ "${status}" -ne 2 ]
}

@test "json format is parseable and names the feature" {
	run bash -c "'${SCRIPT}' --feature bash-patsub --format json | jq -e '.feature == \"bash-patsub\" and (.supported | type == \"boolean\")'"
	[ "${status}" -eq 0 ]
}

@test "unknown feature exits 2" {
	run "${SCRIPT}" --feature totally-made-up
	[ "${status}" -eq 2 ]
}

@test "missing --feature exits 2" {
	run "${SCRIPT}"
	[ "${status}" -eq 2 ]
}

@test "unknown argument exits 2" {
	run "${SCRIPT}" --list-nope
	[ "${status}" -eq 2 ]
}

@test "lang/feature mismatch exits 2" {
	run "${SCRIPT}" --feature cpp-print --lang c
	[ "${status}" -eq 2 ]
}

@test "invalid --format exits 2" {
	run "${SCRIPT}" --feature bash-patsub --format yaml
	[ "${status}" -eq 2 ]
}
