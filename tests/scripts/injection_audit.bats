#!/usr/bin/env bats
#
# Tests for skills/_shared/scripts/injection_audit.sh.
# Run with: bats tests/scripts/injection_audit.bats

setup() {
	DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
	ROOT="$(cd "${DIR}/../.." && pwd)"
	SCRIPT="${ROOT}/skills/_shared/scripts/injection_audit.sh"
	WORK="$(mktemp -d)"
	printf 'import subprocess\nsubprocess.run(f"grep {a}", shell=True)\neval(x)\n' >"${WORK}/bad.py"
	printf 'int main(void){ system("ls"); return 0; }\n' >"${WORK}/bad.c"
	printf '#!/usr/bin/env bash\neval "rm $f"\n' >"${WORK}/bad.sh"
	mkdir -p "${WORK}/clean"
	printf 'x = 1\n' >"${WORK}/clean/ok.py"
}

teardown() {
	rm -rf "${WORK}"
}

@test "flags python shell=True and exits 1" {
	run "${SCRIPT}" --lang python --path "${WORK}"
	[ "${status}" -eq 1 ]
	[[ "${output}" == *"shell=True"* ]]
}

@test "flags C system() and exits 1" {
	run "${SCRIPT}" --lang c --path "${WORK}"
	[ "${status}" -eq 1 ]
	[[ "${output}" == *"system"* ]]
}

@test "flags bash eval and exits 1" {
	run "${SCRIPT}" --lang bash --path "${WORK}"
	[ "${status}" -eq 1 ]
	[[ "${output}" == *"eval"* ]]
}

@test "clean tree exits 0" {
	run "${SCRIPT}" --lang python --path "${WORK}/clean"
	[ "${status}" -eq 0 ]
}

@test "--help exits 0" {
	run "${SCRIPT}" --help
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"USAGE"* ]]
}

@test "missing --lang exits 2" {
	run "${SCRIPT}" --path "${WORK}"
	[ "${status}" -eq 2 ]
}

@test "invalid --lang exits 2" {
	run "${SCRIPT}" --lang go --path "${WORK}"
	[ "${status}" -eq 2 ]
}
