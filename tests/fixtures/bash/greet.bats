#!/usr/bin/env bats
#
# Passing bats test for greet.sh. Run with: bats greet.bats
#
# Note: greet.sh carries a planted SC2086 finding, but its observable behavior
# is correct for the single-word inputs exercised here, so these tests pass.

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	# shellcheck source=/dev/null
	source "${DIR}/greet.sh"
}

@test "greet defaults to world" {
	run greet
	[ "${status}" -eq 0 ]
	[ "${output}" = "Hello, world" ]
}

@test "greet uses the supplied name" {
	run greet Vitalii
	[ "${status}" -eq 0 ]
	[ "${output}" = "Hello, Vitalii" ]
}
