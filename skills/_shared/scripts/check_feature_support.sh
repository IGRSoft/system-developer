#!/usr/bin/env bash
#
# check_feature_support.sh — does this toolchain support a given language feature?
#
# Turns "verify against your toolchain" into a fact. Consolidates the per-feature
# availability tables in skills/_shared/version-feature-matrix.md and the C23 /
# C++20-23 feature lists: probes the actual compiler (feature-test macro or a
# compile probe) for C/C++, and compares the interpreter version for Python and
# Bash. Keep the feature map below in sync with that matrix (the source of truth).
#
# USAGE
#   check_feature_support.sh --feature NAME [--lang L] [--format text|json|silent]
#   check_feature_support.sh --list
#
# OPTIONS
#   --feature NAME   Feature to probe (see --list). The language is implied by
#                    its prefix (cpp-/c-/py-/bash-).
#   --lang L         Optional cross-check; must match the feature's language.
#   --format FMT     text (default), json, or silent (exit code only).
#   --list           Print all known feature names, grouped by language.
#   -h, --help       Show this help and exit.
#
# EXAMPLES
#   check_feature_support.sh --feature cpp-expected
#   check_feature_support.sh --feature py-tstrings --format json
#   check_feature_support.sh --feature c23 --format silent && echo "C23 ok"
#
# EXIT CODES
#   0  feature is supported
#   1  feature is not supported
#   2  usage error, unknown feature, or no suitable compiler found
#
# DEPENDENCIES
#   bash (3.2+), awk. C/C++ probes need a compiler (clang/gcc) on PATH; Python
#   probes need python3; Bash probes read the running bash version.
#
set -Eeuo pipefail

die() {
	printf 'error: %s | fix: run --help / --list\n' "$1" >&2
	exit 2
}

show_help() {
	grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
}

# version_ge <a> <b> -> "ge" | "lt" (dotted numeric compare).
version_ge() {
	awk -v a="$1" -v b="$2" 'BEGIN {
		na = split(a, A, "."); nb = split(b, B, ".")
		n = (na > nb) ? na : nb
		for (i = 1; i <= n; i++) {
			x = (i <= na) ? A[i] + 0 : 0
			y = (i <= nb) ? B[i] + 0 : 0
			if (x > y) { print "ge"; exit }
			if (x < y) { print "lt"; exit }
		}
		print "ge"
	}'
}

# Known features, one per line (grouped by language prefix for --list).
FEATURES="cpp-concepts
cpp-ranges
cpp-format
cpp-coroutines
cpp-modules
cpp-expected
cpp-print
c23
c-bitint
c-stdckdint
c-nullptr
c-typeof
py-tstrings
py-deferred-annotations
py-freethreading
py-subinterpreters
py-zstd
bash-nofork-cmdsub
bash-globsort
bash-patsub"

# resolve_feature <name>: sets FLANG, KIND, and kind-specific vars. Returns 1 if
# the name is unknown.
resolve_feature() {
	MACRO=""; STD=""; THRESH=""; SNIPPET=""; PYMIN=""; BASHMIN=""
	case "$1" in
		cpp-concepts) FLANG=cpp KIND=macro MACRO=__cpp_concepts STD=c++20 THRESH=201907 ;;
		cpp-ranges) FLANG=cpp KIND=macro MACRO=__cpp_lib_ranges STD=c++20 THRESH=201911 ;;
		cpp-format) FLANG=cpp KIND=macro MACRO=__cpp_lib_format STD=c++20 THRESH=201907 ;;
		cpp-coroutines) FLANG=cpp KIND=macro MACRO=__cpp_impl_coroutine STD=c++20 THRESH=201902 ;;
		cpp-modules) FLANG=cpp KIND=macro MACRO=__cpp_modules STD=c++20 THRESH=201907 ;;
		cpp-expected) FLANG=cpp KIND=macro MACRO=__cpp_lib_expected STD=c++23 THRESH=202202 ;;
		cpp-print) FLANG=cpp KIND=macro MACRO=__cpp_lib_print STD=c++23 THRESH=202207 ;;
		c23) FLANG=c KIND=macro MACRO=__STDC_VERSION__ STD=c23 THRESH=202311 ;;
		c-bitint) FLANG=c KIND=compile STD=c23 SNIPPET='int main(void){ _BitInt(8) x = 0; return (int)x; }' ;;
		c-stdckdint) FLANG=c KIND=compile STD=c23 SNIPPET='#include <stdckdint.h>
int main(void){ return 0; }' ;;
		c-nullptr) FLANG=c KIND=compile STD=c23 SNIPPET='int main(void){ void *p = nullptr; return p != 0; }' ;;
		c-typeof) FLANG=c KIND=compile STD=c23 SNIPPET='int main(void){ int a = 0; typeof(a) b = a; return b; }' ;;
		py-tstrings) FLANG=python KIND=pyver PYMIN=3.14 ;;
		py-deferred-annotations) FLANG=python KIND=pyver PYMIN=3.14 ;;
		py-freethreading) FLANG=python KIND=pyver PYMIN=3.14 ;;
		py-subinterpreters) FLANG=python KIND=pyver PYMIN=3.14 ;;
		py-zstd) FLANG=python KIND=pyver PYMIN=3.14 ;;
		bash-nofork-cmdsub) FLANG=bash KIND=bashver BASHMIN=5.3 ;;
		bash-globsort) FLANG=bash KIND=bashver BASHMIN=5.3 ;;
		bash-patsub) FLANG=bash KIND=bashver BASHMIN=5.2 ;;
		*) return 1 ;;
	esac
	return 0
}

find_compiler() {
	# find_compiler <c|cpp> -> prints a compiler path or empty.
	if [[ "$1" == "cpp" ]]; then
		printf '%s' "${CXX:-$(command -v clang++ 2>/dev/null || command -v g++ 2>/dev/null || true)}"
	else
		printf '%s' "${CC:-$(command -v clang 2>/dev/null || command -v gcc 2>/dev/null || true)}"
	fi
}

FEATURE=""
WANT_LANG=""
FORMAT="text"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--feature)
			[[ $# -ge 2 ]] || die "--feature needs a value"
			FEATURE="$2"
			shift 2
			;;
		--feature=*)
			FEATURE="${1#*=}"
			shift
			;;
		--lang)
			[[ $# -ge 2 ]] || die "--lang needs a value"
			WANT_LANG="$2"
			shift 2
			;;
		--lang=*)
			WANT_LANG="${1#*=}"
			shift
			;;
		--format)
			[[ $# -ge 2 ]] || die "--format needs a value"
			FORMAT="$2"
			shift 2
			;;
		--format=*)
			FORMAT="${1#*=}"
			shift
			;;
		--list)
			printf 'C++:    '
			printf '%s\n' "${FEATURES}" | grep '^cpp-' | tr '\n' ' '
			printf '\nC:      '
			printf '%s\n' "${FEATURES}" | grep -E '^(c-|c23)' | tr '\n' ' '
			printf '\nPython: '
			printf '%s\n' "${FEATURES}" | grep '^py-' | tr '\n' ' '
			printf '\nBash:   '
			printf '%s\n' "${FEATURES}" | grep '^bash-' | tr '\n' ' '
			printf '\n'
			exit 0
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

[[ -n "${FEATURE}" ]] || die "--feature is required (see --list)"
resolve_feature "${FEATURE}" || die "unknown feature \"${FEATURE}\" (see --list)"
if [[ -n "${WANT_LANG}" && "${WANT_LANG}" != "${FLANG}" ]]; then
	die "--lang ${WANT_LANG} does not match feature language ${FLANG}"
fi

SUPPORTED=0
DETAIL=""

case "${KIND}" in
	macro)
		compiler="$(find_compiler "${FLANG}")"
		[[ -n "${compiler}" ]] || die "no ${FLANG} compiler found (clang/gcc) — cannot probe"
		xlang="c"
		header=""
		[[ "${FLANG}" == "cpp" ]] && xlang="c++" && header="#include <version>"
		val="$(printf '%s\n' "${header}" |
			"${compiler}" "-std=${STD}" -x "${xlang}" -dM -E - 2>/dev/null |
			awk -v m="${MACRO}" '$2 == m { v = $3; gsub(/[Ll]+$/, "", v); print v; exit }')"
		if [[ -n "${val}" && "${val}" -ge "${THRESH}" ]] 2>/dev/null; then
			SUPPORTED=1
			DETAIL="${compiler##*/} -std=${STD}, ${MACRO}=${val} >= ${THRESH}"
		else
			DETAIL="${compiler##*/} -std=${STD}, ${MACRO}=${val:-undefined} < ${THRESH}"
		fi
		;;
	compile)
		compiler="$(find_compiler "${FLANG}")"
		[[ -n "${compiler}" ]] || die "no ${FLANG} compiler found (clang/gcc) — cannot probe"
		tmp="$(mktemp -t feat.XXXXXX)"
		trap 'rm -f "${tmp}" "${tmp}.c"' EXIT
		mv "${tmp}" "${tmp}.c"
		printf '%s\n' "${SNIPPET}" >"${tmp}.c"
		if "${compiler}" "-std=${STD}" -fsyntax-only "${tmp}.c" >/dev/null 2>&1; then
			SUPPORTED=1
			DETAIL="${compiler##*/} -std=${STD} compiles the probe"
		else
			DETAIL="${compiler##*/} -std=${STD} fails to compile the probe"
		fi
		;;
	pyver)
		py="$(command -v python3 2>/dev/null || true)"
		[[ -n "${py}" ]] || die "python3 not found — cannot probe"
		pv="$("${py}" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])')"
		if [[ "$(version_ge "${pv}" "${PYMIN}")" == "ge" ]]; then
			SUPPORTED=1
			DETAIL="python3 ${pv} >= ${PYMIN}"
		else
			DETAIL="python3 ${pv} < ${PYMIN}"
		fi
		;;
	bashver)
		bv="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
		if [[ "$(version_ge "${bv}" "${BASHMIN}")" == "ge" ]]; then
			SUPPORTED=1
			DETAIL="bash ${bv} >= ${BASHMIN}"
		else
			DETAIL="bash ${bv} < ${BASHMIN} (macOS /bin/bash is 3.2 — use #!/usr/bin/env bash)"
		fi
		;;
esac

case "${FORMAT}" in
	text)
		if [[ "${SUPPORTED}" -eq 1 ]]; then
			printf '%s: supported (%s)\n' "${FEATURE}" "${DETAIL}"
		else
			printf '%s: NOT supported (%s)\n' "${FEATURE}" "${DETAIL}"
		fi
		;;
	json)
		printf '{"feature":"%s","lang":"%s","supported":%s,"detail":"%s"}\n' \
			"${FEATURE}" "${FLANG}" "$([[ "${SUPPORTED}" -eq 1 ]] && printf true || printf false)" "${DETAIL}"
		;;
	silent) ;;
	*)
		die "invalid --format \"${FORMAT}\" (want text|json|silent)"
		;;
esac

[[ "${SUPPORTED}" -eq 1 ]] && exit 0 || exit 1
