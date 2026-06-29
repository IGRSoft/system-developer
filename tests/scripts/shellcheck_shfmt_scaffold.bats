#!/usr/bin/env bats
# Tests for skills/bash/scripts/shellcheck_shfmt_scaffold.sh.

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	ROOT="$(cd "${DIR}/../.." && pwd)"
	SCRIPT="${ROOT}/skills/bash/scripts/shellcheck_shfmt_scaffold.sh"
}

@test "--help exits 0" {
	run "${SCRIPT}" --help
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"USAGE"* ]]
}

@test "default prints both config files with markers" {
	run "${SCRIPT}"
	[ "${status}" -eq 0 ]
	[[ "${output}" == *">>> .shellcheckrc"* ]]
	[[ "${output}" == *"severity=warning"* ]]
	[[ "${output}" == *">>> .editorconfig"* ]]
	[[ "${output}" == *"binary_next_line"* ]]
}

@test "--with-precommit adds the pre-commit config" {
	run "${SCRIPT}" --with-precommit
	[[ "${output}" == *">>> .pre-commit-config.yaml"* ]]
	[[ "${output}" == *"shellcheck-precommit"* ]]
}

@test "--write creates the files in the target dir" {
	run "${SCRIPT}" --write --dir "${BATS_TEST_TMPDIR}"
	[ "${status}" -eq 0 ]
	[ -f "${BATS_TEST_TMPDIR}/.shellcheckrc" ]
	[ -f "${BATS_TEST_TMPDIR}/.editorconfig" ]
}

@test "unknown argument exits 2" {
	run "${SCRIPT}" --bogus
	[ "${status}" -eq 2 ]
}
