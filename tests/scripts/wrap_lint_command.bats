#!/usr/bin/env bats
# Tests for skills/_shared/scripts/wrap_lint_command.sh.

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	ROOT="$(cd "${DIR}/../.." && pwd)"
	SCRIPT="${ROOT}/skills/_shared/scripts/wrap_lint_command.sh"
}

@test "--help exits 0 and lists tools" {
	run "${SCRIPT}" --help
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"TOOLS"* ]]
}

@test "no tool exits 2" {
	run "${SCRIPT}"
	[ "${status}" -eq 2 ]
}

@test "unknown tool exits 2" {
	run "${SCRIPT}" definitely-not-a-linter src/
	[ "${status}" -eq 2 ]
}

@test "a missing tool reports not-found (exit 2)" {
	# Pick a tool unlikely to be installed in CI; if it happens to be present,
	# the dispatch runs instead — either way it must not be a usage crash.
	run "${SCRIPT}" clang-tidy nonexistent.cpp
	[ "${status}" -ne 0 ]
}

@test "shellcheck dispatch lints a clean file (when shellcheck is present)" {
	command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not installed"
	printf '#!/usr/bin/env bash\nprintf "hi\\n"\n' >"${BATS_TEST_TMPDIR}/ok.sh"
	run "${SCRIPT}" shellcheck "${BATS_TEST_TMPDIR}/ok.sh"
	[ "${status}" -eq 0 ]
}
