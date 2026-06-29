#!/usr/bin/env bats
# Tests for skills/bash/scripts/probe_toolchain.sh.

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	ROOT="$(cd "${DIR}/../.." && pwd)"
	SCRIPT="${ROOT}/skills/bash/scripts/probe_toolchain.sh"
}

@test "--help exits 0" {
	run "${SCRIPT}" --help
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"USAGE"* ]]
}

@test "default report names os and coreutils flavor" {
	run "${SCRIPT}"
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"os:"* ]]
	[[ "${output}" == *"coreutils:"* ]]
}

@test "--wrappers emits syntactically valid, sourceable shims" {
	"${SCRIPT}" --wrappers >"${BATS_TEST_TMPDIR}/w.sh"
	run bash -n "${BATS_TEST_TMPDIR}/w.sh"
	[ "${status}" -eq 0 ]
	run grep -q 'sed_i' "${BATS_TEST_TMPDIR}/w.sh"
	[ "${status}" -eq 0 ]
}

@test "unknown argument exits 2" {
	run "${SCRIPT}" --bogus
	[ "${status}" -eq 2 ]
}
