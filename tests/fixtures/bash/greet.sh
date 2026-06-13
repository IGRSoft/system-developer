#!/usr/bin/env bash
#
# greet.sh — emit a greeting. Intentionally NOT fully hardened: it carries one
# planted ShellCheck finding (SC2086) so `lint-fix --check` has something to
# report. The behavior is still correct for single-word, unquoted-safe input,
# which is what the bats test exercises.
#
set -euo pipefail

greet() {
	local name="${1:-world}"
	# PLANTED DEFECT (SC2086): unquoted $name word-splits/globs. ShellCheck
	# reports SC2086 ("Double quote to prevent globbing and word splitting").
	# Left undisabled on purpose so `lint-fix --check` flags it. The fix is:
	#   printf 'Hello, %s!\n' "$name"
	echo Hello, $name
}

# Only run greet when executed directly (so the bats test can source us).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	greet "$@"
fi
