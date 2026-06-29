#!/usr/bin/env bats
# Tests for skills/c/scripts/gen_checked_arithmetic.sh.

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	ROOT="$(cd "${DIR}/../.." && pwd)"
	SCRIPT="${ROOT}/skills/c/scripts/gen_checked_arithmetic.sh"
}

@test "--help exits 0" {
	run "${SCRIPT}" --help
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"USAGE"* ]]
}

@test "emits CK_* macros and both backends" {
	run "${SCRIPT}"
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"CK_ADD"* ]]
	[[ "${output}" == *"CK_MUL"* ]]
	[[ "${output}" == *"stdckdint.h"* ]]
	[[ "${output}" == *"__builtin_add_overflow"* ]]
}

@test "--guard sets the include guard" {
	run "${SCRIPT}" --guard MYPROJ_CK_H
	[[ "${output}" == *"#ifndef MYPROJ_CK_H"* ]]
}

@test "generated header compiles and runs (clang, c23 + c17)" {
	command -v clang >/dev/null 2>&1 || skip "clang not installed"
	"${SCRIPT}" --output "${BATS_TEST_TMPDIR}/ck.h"
	cat >"${BATS_TEST_TMPDIR}/use.c" <<'C'
#include <stddef.h>
#include "ck.h"
int main(void){ size_t t; if (CK_MUL(&t,(size_t)4,(size_t)8)||CK_ADD(&t,t,(size_t)16)) return 1; return (int)(t!=48); }
C
	run clang -std=c23 -I"${BATS_TEST_TMPDIR}" -Wall -Wextra -Werror "${BATS_TEST_TMPDIR}/use.c" -o "${BATS_TEST_TMPDIR}/use"
	[ "${status}" -eq 0 ]
	run "${BATS_TEST_TMPDIR}/use"
	[ "${status}" -eq 0 ]
}

@test "invalid --guard exits 2" {
	run "${SCRIPT}" --guard "9bad"
	[ "${status}" -eq 2 ]
}

@test "unknown argument exits 2" {
	run "${SCRIPT}" --bogus
	[ "${status}" -eq 2 ]
}
