#!/usr/bin/env bats
#
# Tests for skills/_shared/scripts/check_toolchain_versions.sh.
# Run with: bats tests/scripts/check_toolchain_versions.bats
#
# These assert structure and exit-code policy, not specific versions (which vary
# by machine). --strict's pass/fail depends on what is installed, so it is not
# asserted to a fixed code here.

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	ROOT="$(cd "${DIR}/../.." && pwd)"
	SCRIPT="${ROOT}/skills/_shared/scripts/check_toolchain_versions.sh"
}

@test "--help exits 0 and documents FLOOR" {
	run "${SCRIPT}" --help
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"FLOOR"* ]]
}

@test "default run exits 0 and prints the table header + summary" {
	run "${SCRIPT}"
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"TOOL"* ]]
	[[ "${output}" == *"FLOOR"* ]]
	[[ "${output}" == *"Summary:"* ]]
}

@test "lists known tools (python3, cmake, bash)" {
	run "${SCRIPT}"
	[[ "${output}" == *"python3"* ]]
	[[ "${output}" == *"cmake"* ]]
	[[ "${output}" == *"bash"* ]]
}

@test "unknown argument exits 2" {
	run "${SCRIPT}" --bogus
	[ "${status}" -eq 2 ]
}
