#!/usr/bin/env bash
#
# sanitizer_flags.sh — emit canonical sanitizer build flags and runtime options.
#
# Prints the exact compile/link flags and runtime *_OPTIONS exports for a
# sanitizer set, so a build never re-derives them from prose. Output goes to
# stdout (safe to pipe into a build); warnings go to stderr.
#
# Source of truth: skills/tooling/diagnostics/SKILL.md § Copy-Paste Flag Sets,
# § Ground Rules, § Runtime options. Keep this script in sync with that prose.
#
# USAGE
#   sanitizer_flags.sh --lang {c|cpp|python} --sanitizer SET [--output MODE]
#
# OPTIONS
#   --lang {c|cpp|python}   Target language. python = flags for a native
#                           extension build (injected via CFLAGS/CXXFLAGS).
#   --sanitizer SET         One of: asan, ubsan, asan+ubsan, tsan, msan.
#                           asan+ubsan is the default crash/UB hunt. tsan and
#                           msan must run alone (mutually exclusive with asan).
#   --output {flags|env|cmake|make}   What to print; default flags.
#                           flags  compile flags (one line)
#                           env    runtime *_OPTIONS exports (+ CFLAGS/CXXFLAGS
#                                  for python)
#                           cmake  a CMakePresets.json v6 configurePresets entry
#                           make   Makefile variable assignments
#   -h, --help              Show this help and exit.
#
# EXAMPLES
#   sanitizer_flags.sh --lang cpp --sanitizer asan+ubsan
#   sanitizer_flags.sh --lang c   --sanitizer tsan --output env
#   sanitizer_flags.sh --lang cpp --sanitizer asan+ubsan --output cmake
#   eval "$(sanitizer_flags.sh --lang c --sanitizer asan+ubsan --output env)"
#
# EXIT CODES
#   0  success
#   1  usage error (unknown flag, missing/invalid value)
#
# DEPENDENCIES
#   bash (3.2+; macOS system bash is fine), printf. No external tools.
#
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Help: reprint the header comment block (the lines above), validate.sh-style.
# ---------------------------------------------------------------------------
show_help() {
	grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
}

die() {
	# die <message>
	printf 'error: %s | fix: run --help\n' "$1" >&2
	exit 1
}

# ---------------------------------------------------------------------------
# Parse arguments (bash 3.2-safe: no associative arrays).
# ---------------------------------------------------------------------------
LANG_ARG=""
SAN=""
OUTPUT="flags"

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
		--sanitizer)
			[[ $# -ge 2 ]] || die "--sanitizer needs a value"
			SAN="$2"
			shift 2
			;;
		--sanitizer=*)
			SAN="${1#*=}"
			shift
			;;
		--output)
			[[ $# -ge 2 ]] || die "--output needs a value"
			OUTPUT="$2"
			shift 2
			;;
		--output=*)
			OUTPUT="${1#*=}"
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

case "${LANG_ARG}" in
	c | cpp | python) ;;
	"") die "--lang is required (c|cpp|python)" ;;
	*) die "invalid --lang \"${LANG_ARG}\" (want c|cpp|python)" ;;
esac

case "${OUTPUT}" in
	flags | env | cmake | make) ;;
	*) die "invalid --output \"${OUTPUT}\" (want flags|env|cmake|make)" ;;
esac

# ---------------------------------------------------------------------------
# Compose flags from the sanitizer set.
#   BASE      always-on debug-info/frame flags (or reports lose symbols+frames)
#   SANCORE   the -fsanitize=... token (also needed at link time)
#   EXTRA     sanitizer-specific extras
# ---------------------------------------------------------------------------
BASE="-g -O1 -fno-omit-frame-pointer"
SANCORE=""
EXTRA=""

case "${SAN}" in
	asan)
		SANCORE="-fsanitize=address"
		;;
	ubsan)
		SANCORE="-fsanitize=undefined"
		EXTRA="-fno-sanitize-recover=all"
		;;
	asan+ubsan)
		SANCORE="-fsanitize=address,undefined"
		EXTRA="-fno-sanitize-recover=all"
		;;
	tsan)
		SANCORE="-fsanitize=thread"
		;;
	msan)
		SANCORE="-fsanitize=memory"
		EXTRA="-fsanitize-memory-track-origins"
		;;
	"")
		die "--sanitizer is required (asan|ubsan|asan+ubsan|tsan|msan)"
		;;
	*)
		die "invalid --sanitizer \"${SAN}\" (want asan|ubsan|asan+ubsan|tsan|msan)"
		;;
esac

# Compile flags = base + sanitize + extras; link flags need the -fsanitize core.
if [[ -n "${EXTRA}" ]]; then
	COMPILE_FLAGS="${BASE} ${SANCORE} ${EXTRA}"
else
	COMPILE_FLAGS="${BASE} ${SANCORE}"
fi
LINK_FLAGS="${SANCORE}"

# ---------------------------------------------------------------------------
# Incompatibility / footgun warnings -> stderr, so stdout stays pipeable.
# ---------------------------------------------------------------------------
case "${SAN}" in
	tsan)
		printf 'warning: TSan is mutually exclusive with ASan/MSan — build and run it alone.\n' >&2
		;;
	msan)
		printf 'warning: MSan is Clang-only and needs every dependency (incl. libc++) instrumented; for real projects prefer valgrind --tool=memcheck.\n' >&2
		;;
esac
printf 'note: keep llvm-symbolizer on PATH (or set ASAN_SYMBOLIZER_PATH) or frames show as "??".\n' >&2

# ---------------------------------------------------------------------------
# Runtime *_OPTIONS exports for the selected sanitizers.
# ---------------------------------------------------------------------------
emit_runtime_env() {
	case "${SAN}" in
		asan | asan+ubsan)
			printf 'export ASAN_OPTIONS=detect_leaks=1:abort_on_error=1:symbolize=1:strict_string_checks=1\n'
			;;
	esac
	case "${SAN}" in
		ubsan | asan+ubsan)
			printf 'export UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1\n'
			;;
	esac
	case "${SAN}" in
		tsan)
			printf 'export TSAN_OPTIONS=halt_on_error=1\n'
			;;
		msan)
			printf 'export MSAN_OPTIONS=halt_on_error=1\n'
			;;
	esac
}

# ---------------------------------------------------------------------------
# Render the requested output mode to stdout.
# ---------------------------------------------------------------------------
case "${OUTPUT}" in
	flags)
		printf '%s\n' "${COMPILE_FLAGS}"
		;;
	env)
		if [[ "${LANG_ARG}" == "python" ]]; then
			# Native extensions pick up sanitizer flags via CFLAGS/CXXFLAGS at
			# build time (e.g. `pip install --no-binary :all:` / scikit-build).
			printf 'export CFLAGS="%s"\n' "${COMPILE_FLAGS}"
			printf 'export CXXFLAGS="%s"\n' "${COMPILE_FLAGS}"
			printf 'export LDFLAGS="%s"\n' "${LINK_FLAGS}"
		fi
		emit_runtime_env
		;;
	cmake)
		# A CMakePresets.json v6 configurePresets entry, ready to paste.
		preset_name="san-${SAN//+/-}"
		printf '{\n'
		printf '  "version": 6,\n'
		printf '  "configurePresets": [\n'
		printf '    {\n'
		printf '      "name": "%s",\n' "${preset_name}"
		printf '      "displayName": "Debug + %s",\n' "${SAN}"
		# shellcheck disable=SC2016 # ${sourceDir} is a literal CMake macro, not a shell var
		printf '      "binaryDir": "${sourceDir}/build/%s",\n' "${preset_name}"
		printf '      "generator": "Ninja",\n'
		printf '      "cacheVariables": {\n'
		printf '        "CMAKE_BUILD_TYPE": "Debug",\n'
		printf '        "CMAKE_EXPORT_COMPILE_COMMANDS": "ON",\n'
		printf '        "CMAKE_C_FLAGS": "%s",\n' "${COMPILE_FLAGS}"
		printf '        "CMAKE_CXX_FLAGS": "%s",\n' "${COMPILE_FLAGS}"
		printf '        "CMAKE_EXE_LINKER_FLAGS": "%s"\n' "${LINK_FLAGS}"
		printf '      }\n'
		printf '    }\n'
		printf '  ]\n'
		printf '}\n'
		;;
	make)
		printf 'SANFLAGS = %s\n' "${COMPILE_FLAGS}"
		printf 'SANLDFLAGS = %s\n' "${LINK_FLAGS}"
		# shellcheck disable=SC2016 # $(...) are literal Make variable refs, not shell subshells
		printf 'CFLAGS += $(SANFLAGS)\n'
		# shellcheck disable=SC2016 # literal Make variable ref
		printf 'CXXFLAGS += $(SANFLAGS)\n'
		# shellcheck disable=SC2016 # literal Make variable ref
		printf 'LDFLAGS += $(SANLDFLAGS)\n'
		;;
esac
