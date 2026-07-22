#!/usr/bin/env bats
#
# Tests for scripts/desc-lint.sh.
# Run with: bats tests/scripts/desc_lint.bats

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	ROOT="$(cd "${DIR}/../.." && pwd)"
	SCRIPT="${ROOT}/scripts/desc-lint.sh"
}

@test "--self-test passes both tiers" {
	run "${SCRIPT}" --self-test
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"desc-lint self-test: ALL PASS"* ]]
}

@test "real run is green today (no description over its tier cap)" {
	run "${SCRIPT}"
	[ "${status}" -eq 0 ]
}

@test "an over-250 agent/command description is flagged (250 tier)" {
	desc="$(printf 'd%.0s' $(seq 1 260))"
	printf -- '---\nname: x\ndescription: %s\n---\nbody\n' "${desc}" >"${BATS_TEST_TMPDIR}/agent.md"
	run "${SCRIPT}" "${BATS_TEST_TMPDIR}/agent.md"
	[ "${status}" -eq 1 ]
	[[ "${output}" == *"(cap 250) — OVER"* ]]
}

@test "a skills description between 250 and 600 passes on the 600 tier" {
	mkdir -p "${BATS_TEST_TMPDIR}/skills"
	desc="$(printf 's%.0s' $(seq 1 400))"
	printf -- '---\nname: s\ndescription: %s\n---\nbody\n' "${desc}" >"${BATS_TEST_TMPDIR}/skills/SKILL.md"
	run "${SCRIPT}" "${BATS_TEST_TMPDIR}/skills/SKILL.md"
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"(cap 600) ok"* ]]
}

@test "a skills description over 600 is flagged (600 tier)" {
	mkdir -p "${BATS_TEST_TMPDIR}/skills"
	desc="$(printf 'h%.0s' $(seq 1 700))"
	printf -- '---\nname: s\ndescription: %s\n---\nbody\n' "${desc}" >"${BATS_TEST_TMPDIR}/skills/SKILL.md"
	run "${SCRIPT}" "${BATS_TEST_TMPDIR}/skills/SKILL.md"
	[ "${status}" -eq 1 ]
	[[ "${output}" == *"(cap 600) — OVER"* ]]
}
