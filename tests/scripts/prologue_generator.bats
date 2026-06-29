#!/usr/bin/env bats
# Tests for skills/bash/scripts/prologue_generator.sh.

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	ROOT="$(cd "${DIR}/../.." && pwd)"
	SCRIPT="${ROOT}/skills/bash/scripts/prologue_generator.sh"
}

@test "--help exits 0" {
	run "${SCRIPT}" --help
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"USAGE"* ]]
}

@test "minimal prologue has shebang and strict mode" {
	run "${SCRIPT}"
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"#!/usr/bin/env bash"* ]]
	[[ "${output}" == *"set -Eeuo pipefail"* ]]
}

@test "version guard emits a BASH_VERSINFO check" {
	run "${SCRIPT}" --with-version-guard
	[[ "${output}" == *"BASH_VERSINFO"* ]]
}

@test "int/term traps extend the cleanup trap" {
	run "${SCRIPT}" --with-int-term-traps
	[[ "${output}" == *"trap cleanup EXIT INT TERM"* ]]
}

@test "generated prologue is syntactically valid bash" {
	"${SCRIPT}" --with-version-guard --with-comments --with-int-term-traps >"${BATS_TEST_TMPDIR}/p.sh"
	run bash -n "${BATS_TEST_TMPDIR}/p.sh"
	[ "${status}" -eq 0 ]
}

@test "unknown argument exits 2" {
	run "${SCRIPT}" --bogus
	[ "${status}" -eq 2 ]
}
