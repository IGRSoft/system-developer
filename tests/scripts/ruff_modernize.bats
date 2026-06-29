#!/usr/bin/env bats
# Tests for skills/python/scripts/ruff_modernize.sh.

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	ROOT="$(cd "${DIR}/../.." && pwd)"
	SCRIPT="${ROOT}/skills/python/scripts/ruff_modernize.sh"
}

@test "--help exits 0 and documents the rule set" {
	run "${SCRIPT}" --help
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"RULE SET"* ]]
}

@test "invalid --target-version exits 2 (before any ruff call)" {
	run "${SCRIPT}" --target-version abc
	[ "${status}" -eq 2 ]
}

@test "missing ruff reports not-found (when ruff absent)" {
	command -v ruff >/dev/null 2>&1 && skip "ruff is installed"
	run "${SCRIPT}"
	[ "${status}" -eq 2 ]
}
