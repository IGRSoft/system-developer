#!/usr/bin/env bash
#
# scaffold_conftest.sh — emit a pytest conftest.py skeleton.
#
# Generates a conftest.py with correctly-scoped fixtures (and, with --with-async,
# a pytest-asyncio fixture + the asyncio_mode note), following the patterns in
# skills/python/python-testing/SKILL.md (fixtures/scopes, conftest placement,
# async testing). Keep in sync with that skill (the source of truth).
#
# USAGE
#   scaffold_conftest.sh [--with-async] [--async-mode auto|strict] [--output FILE]
#
# OPTIONS
#   --with-async         Add a pytest-asyncio fixture and the asyncio_mode note.
#   --async-mode MODE    auto (default) or strict — for the emitted pyproject note.
#   --output FILE        Write to FILE instead of stdout.
#   -h, --help           Show this help and exit.
#
# EXAMPLES
#   scaffold_conftest.sh > tests/conftest.py
#   scaffold_conftest.sh --with-async --async-mode strict --output tests/conftest.py
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

WITH_ASYNC=0
ASYNC_MODE="auto"
OUTPUT=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--with-async)
			WITH_ASYNC=1
			shift
			;;
		--async-mode)
			[[ $# -ge 2 ]] || die "--async-mode needs a value"
			ASYNC_MODE="$2"
			shift 2
			;;
		--async-mode=*)
			ASYNC_MODE="${1#*=}"
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

case "${ASYNC_MODE}" in
	auto | strict) ;;
	*) die "invalid --async-mode \"${ASYNC_MODE}\" (want auto|strict)" ;;
esac

emit() {
	# Quoted heredoc: emitted verbatim (no shell expansion in Python source).
	cat <<'EOF'
"""Shared pytest fixtures — auto-discovered for every test at or below this dir.

Put broad fixtures (config, fakes) in the top tests/conftest.py; narrow ones in a
subpackage's conftest.py. Closer files override farther ones by name.
"""

from __future__ import annotations

from collections.abc import Iterator

import pytest


@pytest.fixture(scope="session")
def app_config() -> dict[str, str]:
    """Immutable, session-wide config — built once for the whole run."""
    return {"env": "test"}


@pytest.fixture
def tmp_db(tmp_path) -> Iterator[str]:
    """Function-scoped resource; everything after yield is teardown."""
    db_path = str(tmp_path / "test.db")
    # open / migrate here
    yield db_path
    # close / clean up here
EOF

	if [[ "${WITH_ASYNC}" -eq 1 ]]; then
		# Unquoted heredoc: only ${ASYNC_MODE} interpolates.
		cat <<EOF


# Requires pytest-asyncio (add to [dependency-groups] dev). Set the loop mode in
# pyproject.toml, not here:
#   [tool.pytest.ini_options]
#   asyncio_mode = "${ASYNC_MODE}"
import pytest_asyncio


@pytest_asyncio.fixture
async def async_client():
    """Async fixture; teardown runs after yield, awaited."""
    client = await make_client()  # replace with your client factory
    yield client
    await client.aclose()
EOF
	fi
}

if [[ -n "${OUTPUT}" ]]; then
	emit >"${OUTPUT}"
	printf 'wrote %s\n' "${OUTPUT}" >&2
else
	emit
fi
