#!/usr/bin/env bats
#
# Tests for skills/_shared/scripts/scaffold_cmake_preset.sh.
# Run with: bats tests/scripts/scaffold_cmake_preset.bats

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	ROOT="$(cd "${DIR}/../.." && pwd)"
	SCRIPT="${ROOT}/skills/_shared/scripts/scaffold_cmake_preset.sh"
}

@test "--help exits 0" {
	run "${SCRIPT}" --help
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"USAGE"* ]]
}

@test "default output is valid JSON with configure/build/test presets" {
	run bash -c "'${SCRIPT}' --name default --std 23 2>/dev/null | jq -e '.configurePresets[0].cacheVariables.CMAKE_CXX_STANDARD == \"23\" and (.buildPresets | length == 1) and (.testPresets | length == 1)'"
	[ "${status}" -eq 0 ]
}

@test "export compile commands is on" {
	run bash -c "'${SCRIPT}' 2>/dev/null | jq -e '.configurePresets[0].cacheVariables.CMAKE_EXPORT_COMPILE_COMMANDS == \"ON\"'"
	[ "${status}" -eq 0 ]
}

@test "--vcpkg adds the toolchain file" {
	run bash -c "'${SCRIPT}' --vcpkg 2>/dev/null | jq -e '.configurePresets[0].cacheVariables.CMAKE_TOOLCHAIN_FILE | test(\"vcpkg.cmake\")'"
	[ "${status}" -eq 0 ]
}

@test "invalid --std exits 2" {
	run "${SCRIPT}" --std abc
	[ "${status}" -eq 2 ]
}

@test "unknown argument exits 2" {
	run "${SCRIPT}" --bogus
	[ "${status}" -eq 2 ]
}
