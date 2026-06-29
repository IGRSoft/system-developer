#!/usr/bin/env bats
# Tests for skills/python/scripts/scaffold_conftest.sh.

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	ROOT="$(cd "${DIR}/../.." && pwd)"
	SCRIPT="${ROOT}/skills/python/scripts/scaffold_conftest.sh"
}

@test "--help exits 0" {
	run "${SCRIPT}" --help
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"USAGE"* ]]
}

@test "default conftest has scoped fixtures and parses as Python" {
	run bash -c "'${SCRIPT}' | python3 -c 'import ast,sys; ast.parse(sys.stdin.read())'"
	[ "${status}" -eq 0 ]
	run "${SCRIPT}"
	[[ "${output}" == *"import pytest"* ]]
	[[ "${output}" == *"app_config"* ]]
	[[ "${output}" == *'scope="session"'* ]]
}

@test "--with-async adds a pytest-asyncio fixture and the mode note" {
	run bash -c "'${SCRIPT}' --with-async --async-mode strict | python3 -c 'import ast,sys; ast.parse(sys.stdin.read())'"
	[ "${status}" -eq 0 ]
	run "${SCRIPT}" --with-async --async-mode strict
	[[ "${output}" == *"pytest_asyncio"* ]]
	[[ "${output}" == *'asyncio_mode = "strict"'* ]]
}

@test "invalid --async-mode exits 2" {
	run "${SCRIPT}" --async-mode sometimes
	[ "${status}" -eq 2 ]
}

@test "unknown argument exits 2" {
	run "${SCRIPT}" --bogus
	[ "${status}" -eq 2 ]
}
