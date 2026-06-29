#!/usr/bin/env bats
#
# Tests for skills/python/scripts/scaffold_pyproject.sh.
# Run with: bats tests/scripts/scaffold_pyproject.bats

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	ROOT="$(cd "${DIR}/../.." && pwd)"
	SCRIPT="${ROOT}/skills/python/scripts/scaffold_pyproject.sh"
}

@test "--help exits 0" {
	run "${SCRIPT}" --help
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"USAGE"* ]]
}

@test "package mode includes a uv_build build-system" {
	run bash -c "'${SCRIPT}' --package my-lib 2>/dev/null"
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"[build-system]"* ]]
	[[ "${output}" == *"uv_build"* ]]
}

@test "app mode omits the build-system" {
	run bash -c "'${SCRIPT}' --app my-svc 2>/dev/null"
	[ "${status}" -eq 0 ]
	[[ "${output}" != *"[build-system]"* ]]
}

@test "python-version drives requires-python and ruff target" {
	run bash -c "'${SCRIPT}' --app my-svc --python-version 3.12 2>/dev/null"
	[[ "${output}" == *'requires-python = ">=3.12"'* ]]
	[[ "${output}" == *'target-version = "py312"'* ]]
}

@test "no mode exits 2" {
	run "${SCRIPT}"
	[ "${status}" -eq 2 ]
}

@test "both --package and --app exits 2" {
	run "${SCRIPT}" --package a --app b
	[ "${status}" -eq 2 ]
}
