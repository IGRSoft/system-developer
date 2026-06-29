#!/usr/bin/env bats
#
# Tests for skills/_shared/scripts/sanitizer_flags.sh.
# Run with: bats tests/scripts/sanitizer_flags.bats
#
# bats is not always installed locally; these run in CI. The same assertions
# can be reproduced by hand with the script and `jq`.

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	ROOT="$(cd "${DIR}/../.." && pwd)"
	SCRIPT="${ROOT}/skills/_shared/scripts/sanitizer_flags.sh"
}

@test "--help exits 0 and prints USAGE" {
	run "${SCRIPT}" --help
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"USAGE"* ]]
	[[ "${output}" == *"--sanitizer"* ]]
}

@test "flags: cpp asan+ubsan stdout is the canonical line" {
	run bash -c "'${SCRIPT}' --lang cpp --sanitizer asan+ubsan 2>/dev/null"
	[ "${status}" -eq 0 ]
	[ "${output}" = "-g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined -fno-sanitize-recover=all" ]
}

@test "flags: ubsan adds -fno-sanitize-recover=all" {
	run bash -c "'${SCRIPT}' --lang c --sanitizer ubsan 2>/dev/null"
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"-fsanitize=undefined"* ]]
	[[ "${output}" == *"-fno-sanitize-recover=all"* ]]
}

@test "tsan warns it must run alone and still succeeds" {
	run "${SCRIPT}" --lang c --sanitizer tsan
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"mutually exclusive"* ]]
	[[ "${output}" == *"-fsanitize=thread"* ]]
}

@test "msan warns it is Clang-only" {
	run "${SCRIPT}" --lang cpp --sanitizer msan
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"Clang-only"* ]]
	[[ "${output}" == *"-fsanitize=memory"* ]]
}

@test "env: c asan+ubsan emits both runtime option exports" {
	run bash -c "'${SCRIPT}' --lang c --sanitizer asan+ubsan --output env 2>/dev/null"
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"export ASAN_OPTIONS="* ]]
	[[ "${output}" == *"export UBSAN_OPTIONS="* ]]
}

@test "env: python injects CFLAGS/CXXFLAGS for the extension build" {
	run bash -c "'${SCRIPT}' --lang python --sanitizer asan --output env 2>/dev/null"
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"export CFLAGS="* ]]
	[[ "${output}" == *"export CXXFLAGS="* ]]
}

@test "cmake output is valid JSON with a configurePresets entry" {
	run bash -c "'${SCRIPT}' --lang cpp --sanitizer asan+ubsan --output cmake 2>/dev/null | jq -e '.configurePresets[0].name'"
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"san-asan-ubsan"* ]]
}

@test "make output assigns SANFLAGS and appends to CFLAGS" {
	run bash -c "'${SCRIPT}' --lang c --sanitizer asan --output make 2>/dev/null"
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"SANFLAGS = "* ]]
	[[ "${output}" == *"CFLAGS += "* ]]
}

@test "invalid --lang exits 1" {
	run "${SCRIPT}" --lang rust --sanitizer asan
	[ "${status}" -eq 1 ]
}

@test "invalid --sanitizer exits 1" {
	run "${SCRIPT}" --lang c --sanitizer foo
	[ "${status}" -eq 1 ]
}

@test "missing --lang exits 1" {
	run "${SCRIPT}" --sanitizer asan
	[ "${status}" -eq 1 ]
}

@test "missing --sanitizer exits 1" {
	run "${SCRIPT}" --lang c
	[ "${status}" -eq 1 ]
}

@test "unknown flag exits 1" {
	run "${SCRIPT}" --lang c --sanitizer asan --bogus
	[ "${status}" -eq 1 ]
}
