#!/usr/bin/env bash
#
# injection_audit.sh — heuristic scan for command-injection and dynamic
# code-execution patterns in C, C++, Python, and Bash sources.
#
# A fast grep gate for the banned constructs in
# skills/_shared/secure-coding/references/command-execution-and-injection.md
# (the "Why Dynamic Code Execution Is Banned" table and the per-language
# rules). It flags lines for human review — it does not parse syntax, so it
# can over-match inside comments/strings; treat hits as "look here", not proof.
# Keep the pattern set in sync with that reference (the source of truth).
#
# USAGE
#   injection_audit.sh --lang {c|cpp|python|bash} [--path DIR]
#
# OPTIONS
#   --lang {c|cpp|python|bash}   Which source set to scan.
#   --path DIR                   Directory to scan (default: .). Files come
#                                from `git ls-files`, or a walk outside git.
#   -h, --help                   Show this help and exit.
#
# OUTPUT
#   One finding per line: path:line: [pattern] message. A trailing summary
#   prints the count to stderr.
#
# EXIT CODES
#   0  no findings
#   1  one or more findings (use as a CI/DR gate)
#   2  usage error
#
# DEPENDENCIES
#   bash (3.2+), grep, git (optional; falls back to find).
#
set -Eeuo pipefail

die() {
	printf 'error: %s | fix: run --help\n' "$1" >&2
	exit 2
}

show_help() {
	grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
}

LANG_ARG=""
ROOT="."

while [[ $# -gt 0 ]]; do
	case "$1" in
		--lang)
			[[ $# -ge 2 ]] || die "--lang needs a value"
			LANG_ARG="$2"
			shift 2
			;;
		--lang=*)
			LANG_ARG="${1#*=}"
			shift
			;;
		--path)
			[[ $# -ge 2 ]] || die "--path needs a value"
			ROOT="$2"
			shift 2
			;;
		--path=*)
			ROOT="${1#*=}"
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

[[ -d "${ROOT}" ]] || die "path is not a directory: ${ROOT}"

# Extension globs per language (space-separated, used for filtering).
case "${LANG_ARG}" in
	c) EXT_RE='\.(c|h)$' ;;
	cpp) EXT_RE='\.(cpp|cc|cxx|hpp|hh|hxx|ixx|h)$' ;;
	python) EXT_RE='\.(py|pyi)$' ;;
	bash) EXT_RE='\.(sh|bash|bats)$' ;;
	"") die "--lang is required (c|cpp|python|bash)" ;;
	*) die "invalid --lang \"${LANG_ARG}\" (want c|cpp|python|bash)" ;;
esac

# ---------------------------------------------------------------------------
# Collect candidate files: tracked sources via git, else a pruned find.
# ---------------------------------------------------------------------------
list_files() {
	if git -C "${ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		(cd "${ROOT}" && git ls-files) | grep -E "${EXT_RE}" | sed "s#^#${ROOT%/}/#"
	else
		find "${ROOT}" \
			-type d \( -name '.git' -o -name 'build*' -o -name '.venv' -o -name 'node_modules' \) -prune \
			-o -type f -print | grep -E "${EXT_RE}"
	fi
}

FILES="$(list_files || true)"
if [[ -z "${FILES}" ]]; then
	printf 'note: no %s source files under %s\n' "${LANG_ARG}" "${ROOT}" >&2
	exit 0
fi

FINDINGS=0

# scan <regex> <message>: print path:line: [regex] message for each match.
scan() {
	local re="$1" msg="$2" line
	while IFS= read -r line; do
		[[ -z "${line}" ]] && continue
		printf '%s [%s] %s\n' "${line}" "${re}" "${msg}"
		FINDINGS=$((FINDINGS + 1))
	done < <(printf '%s\n' "${FILES}" | tr '\n' '\0' | xargs -0 grep -HnE "${re}" 2>/dev/null || true)
}

case "${LANG_ARG}" in
	c | cpp)
		scan 'std::system[[:space:]]*\(' 'std::system invokes the shell — build an argv vector and posix_spawn'
		scan '(^|[^_[:alnum:]])system[[:space:]]*\(' 'system() invokes /bin/sh -c — injection risk; use posix_spawn/execvp'
		scan '(^|[^_[:alnum:]])popen[[:space:]]*\(' 'popen() invokes the shell — use a pipe + posix_spawn instead'
		scan '(^|[^_[:alnum:]])(strcpy|strcat|sprintf|gets)[[:space:]]*\(' 'unsafe unbounded copy — use bounded variants / snprintf'
		scan 'dlopen[[:space:]]*\(' 'dlopen on a computed path runs attacker-chosen code — review the path source'
		;;
	python)
		scan 'shell[[:space:]]*=[[:space:]]*True' 'subprocess shell=True parses a shell string — pass a list with shell=False'
		scan 'os\.(system|popen)[[:space:]]*\(' 'os.system/os.popen are shell-based — use subprocess([...], shell=False)'
		scan '(^|[^_.[:alnum:]])(eval|exec)[[:space:]]*\(' 'eval/exec run attacker-controlled Python — use a dispatch table / parser'
		scan '(pickle|marshal)\.loads?[[:space:]]*\(' 'pickle/marshal on untrusted data is RCE — use json / a safe schema'
		scan 'yaml\.load[[:space:]]*\(' 'yaml.load without SafeLoader executes tags — use yaml.safe_load'
		scan '__import__[[:space:]]*\(' '__import__ on a computed name runs arbitrary modules — review'
		;;
	bash)
		# shellcheck disable=SC2016 # the message literally shows the "${cmd[@]}" idiom; must not expand
		scan '(^|[^[:alnum:]_])eval[[:space:]]' 'eval re-parses data as shell code — use an array: cmd=(...); "${cmd[@]}"'
		scan 'sh[[:space:]]+-c[[:space:]]+"[^"]*\$' 'sh -c on a string with an expansion can inject — exec the helper directly'
		scan '(^|[^[:alnum:]_])(source|\.)[[:space:]]+"?\$' 'sourcing a variable path runs arbitrary code — pin the path'
		;;
esac

if [[ "${FINDINGS}" -gt 0 ]]; then
	printf 'injection_audit: %d finding(s) in %s sources under %s\n' "${FINDINGS}" "${LANG_ARG}" "${ROOT}" >&2
	exit 1
fi
printf 'injection_audit: clean (%s under %s)\n' "${LANG_ARG}" "${ROOT}" >&2
exit 0
