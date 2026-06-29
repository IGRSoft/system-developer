#!/usr/bin/env bash
#
# scaffold_cmake_preset.sh — emit a CMakePresets.json v6 with configure, build,
# and test presets.
#
# Generates the modern, machine-identical preset workflow from
# skills/tooling/build-systems/SKILL.md (out-of-source build, Ninja,
# CMAKE_EXPORT_COMPILE_COMMANDS, a pinned C++ standard, optional vcpkg
# toolchain). Keep in sync with that skill (the source of truth). Sanitizer
# presets are a separate concern — use sanitizer_flags.sh --output cmake.
#
# USAGE
#   scaffold_cmake_preset.sh [--name NAME] [--std N] [--build-type TYPE]
#                            [--generator GEN] [--vcpkg] [--output FILE]
#
# OPTIONS
#   --name NAME          Preset name (default: default). Used for the build dir
#                        build/<name> and the build/test presets.
#   --std N              C++ standard, e.g. 17/20/23 (default: 23).
#   --build-type TYPE    CMAKE_BUILD_TYPE (default: Debug).
#   --generator GEN      Generator (default: Ninja).
#   --vcpkg              Add the vcpkg toolchain file via $env{VCPKG_ROOT}.
#   --output FILE        Write to FILE instead of stdout.
#   -h, --help           Show this help and exit.
#
# EXAMPLES
#   scaffold_cmake_preset.sh --name default --std 23
#   scaffold_cmake_preset.sh --name rel --build-type Release --vcpkg --output CMakePresets.json
#
# After writing CMakePresets.json:
#   cmake --preset NAME && cmake --build --preset NAME && ctest --preset NAME
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

NAME="default"
STD="23"
BUILD_TYPE="Debug"
GENERATOR="Ninja"
VCPKG=0
OUTPUT=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--name)
			[[ $# -ge 2 ]] || die "--name needs a value"
			NAME="$2"
			shift 2
			;;
		--name=*)
			NAME="${1#*=}"
			shift
			;;
		--std)
			[[ $# -ge 2 ]] || die "--std needs a value"
			STD="$2"
			shift 2
			;;
		--std=*)
			STD="${1#*=}"
			shift
			;;
		--build-type)
			[[ $# -ge 2 ]] || die "--build-type needs a value"
			BUILD_TYPE="$2"
			shift 2
			;;
		--build-type=*)
			BUILD_TYPE="${1#*=}"
			shift
			;;
		--generator)
			[[ $# -ge 2 ]] || die "--generator needs a value"
			GENERATOR="$2"
			shift 2
			;;
		--generator=*)
			GENERATOR="${1#*=}"
			shift
			;;
		--vcpkg)
			VCPKG=1
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

case "${STD}" in
	[0-9][0-9]) ;;
	*) die "invalid --std \"${STD}\" (want a CMake CXX standard like 17/20/23)" ;;
esac

emit() {
	printf '{\n'
	printf '  "version": 6,\n'
	printf '  "configurePresets": [\n'
	printf '    {\n'
	printf '      "name": "%s",\n' "${NAME}"
	printf '      "generator": "%s",\n' "${GENERATOR}"
	# shellcheck disable=SC2016 # ${sourceDir} is a literal CMake macro, not a shell var
	printf '      "binaryDir": "${sourceDir}/build/%s",\n' "${NAME}"
	printf '      "cacheVariables": {\n'
	printf '        "CMAKE_BUILD_TYPE": "%s",\n' "${BUILD_TYPE}"
	printf '        "CMAKE_EXPORT_COMPILE_COMMANDS": "ON",\n'
	printf '        "CMAKE_CXX_STANDARD": "%s",\n' "${STD}"
	if [[ "${VCPKG}" -eq 1 ]]; then
		printf '        "CMAKE_CXX_STANDARD_REQUIRED": "ON",\n'
		# shellcheck disable=SC2016 # $env{...} is a literal CMake preset macro
		printf '        "CMAKE_TOOLCHAIN_FILE": "$env{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake"\n'
	else
		printf '        "CMAKE_CXX_STANDARD_REQUIRED": "ON"\n'
	fi
	printf '      }\n'
	printf '    }\n'
	printf '  ],\n'
	printf '  "buildPresets": [\n'
	printf '    { "name": "%s", "configurePreset": "%s" }\n' "${NAME}" "${NAME}"
	printf '  ],\n'
	printf '  "testPresets": [\n'
	printf '    {\n'
	printf '      "name": "%s",\n' "${NAME}"
	printf '      "configurePreset": "%s",\n' "${NAME}"
	printf '      "output": { "outputOnFailure": true }\n'
	printf '    }\n'
	printf '  ]\n'
	printf '}\n'
}

if [[ -n "${OUTPUT}" ]]; then
	emit >"${OUTPUT}"
	printf 'wrote %s (preset "%s", C++%s, %s)\n' "${OUTPUT}" "${NAME}" "${STD}" "${BUILD_TYPE}" >&2
else
	emit
fi
