#!/usr/bin/env bash
#
# shfmt + ShellCheck project-config scaffold (shellcheck_shfmt_scaffold.sh).
#
# Generates .shellcheckrc and .editorconfig (and, with --with-precommit, a
# .pre-commit-config.yaml) using the canonical settings from
# skills/bash/bash-testing/references/shellcheck-shfmt.md — the enforced shfmt
# set is `-i 2 -ci -bn` and ShellCheck gates at severity=warning. Keep in sync
# with that reference (the source of truth).
#
# USAGE
#   bash/scripts/shellcheck_shfmt_scaffold.sh [--with-precommit] [--write] [--dir DIR]
#
# OPTIONS
#   --with-precommit   Also emit a .pre-commit-config.yaml.
#   --write            Write the files into DIR instead of printing to stdout.
#   --dir DIR          Target directory for --write (default: .).
#   -h, --help         Show this help and exit.
#
# OUTPUT
#   Without --write, prints each file to stdout preceded by a `# >>> name`
#   marker. With --write, creates the files in DIR.
#
# EXIT CODES
#   0  success
#   2  usage error
#
# DEPENDENCIES
#   bash (3.2+), printf. No external tools.
#
set -Eeuo pipefail

die() {
	printf 'error: %s | fix: run --help\n' "$1" >&2
	exit 2
}

show_help() {
	grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
}

WITH_PRECOMMIT=0
WRITE=0
DIR="."

while [[ $# -gt 0 ]]; do
	case "$1" in
		--with-precommit)
			WITH_PRECOMMIT=1
			shift
			;;
		--write)
			WRITE=1
			shift
			;;
		--dir)
			[[ $# -ge 2 ]] || die "--dir needs a value"
			DIR="$2"
			shift 2
			;;
		--dir=*)
			DIR="${1#*=}"
			shift
			;;
		-h | --help)
			show_help
			exit 0
			;;
		*)
			die "unknown argument \"$1\""
			;;
	esac
done

[[ "${WRITE}" -eq 0 || -d "${DIR}" ]] || die "--dir is not a directory: ${DIR}"

# shellcheck disable=SC2329,SC2317 # invoked indirectly via write_file "$2"
shellcheckrc() {
	cat <<'EOF'
# Dialect for extensionless / sourced files
shell=bash

# Gate at warning and above
severity=warning

# Opt into stricter optional checks
enable=quote-safe-variables
enable=require-variable-braces
enable=check-unassigned-uppercase

# Follow sourced files for cross-file checks
external-sources=true

# Project-wide, justified disables (keep short and documented)
# SC1091: helper libs live outside the lint sandbox in CI
disable=SC1091
EOF
}

# shellcheck disable=SC2329,SC2317 # invoked indirectly via write_file "$2"
editorconfig() {
	cat <<'EOF'
root = true

[*.{sh,bash,bats}]
indent_style = space
indent_size = 2
switch_case_indent = true     # = shfmt -ci
binary_next_line = true       # = shfmt -bn
EOF
}

# shellcheck disable=SC2329,SC2317 # invoked indirectly via write_file "$2"
precommit() {
	cat <<'EOF'
repos:
  - repo: https://github.com/koalaman/shellcheck-precommit
    rev: v0.10.0
    hooks:
      - id: shellcheck
        args: [--severity=warning, --external-sources]
  - repo: https://github.com/scop/pre-commit-shfmt
    rev: v3.10.0-2
    hooks:
      - id: shfmt
        args: [-i, "2", -ci, -bn, -d]
EOF
}

write_file() {
	# write_file <name> <producer-fn>
	if [[ "${WRITE}" -eq 1 ]]; then
		"$2" >"${DIR%/}/$1"
		printf 'wrote %s\n' "${DIR%/}/$1" >&2
	else
		printf '# >>> %s\n' "$1"
		"$2"
		printf '\n'
	fi
}

write_file ".shellcheckrc" shellcheckrc
write_file ".editorconfig" editorconfig
[[ "${WITH_PRECOMMIT}" -eq 1 ]] && write_file ".pre-commit-config.yaml" precommit
exit 0
