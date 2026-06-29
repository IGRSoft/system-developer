"""Tests for skills/_shared/scripts/detect_language.py.

Run with: uv run pytest tests/scripts/detect_language_test.py
(or: python -m pytest ...). Drives the real CLI via subprocess against the
tests/fixtures sample trees, so it exercises exactly what the router runs.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "skills" / "_shared" / "scripts" / "detect_language.py"
FIXTURES = REPO / "tests" / "fixtures"


def run(path: Path, *extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--path", str(path), *extra],
        capture_output=True,
        text=True,
        check=False,
    )


@pytest.mark.parametrize(
    ("fixture", "agent"),
    [
        ("cmake-cpp", "system-developer:cpp-developer"),
        ("c-make", "system-developer:c-developer"),
        ("py-uv", "system-developer:python-developer"),
        ("bash", "system-developer:bash-developer"),
    ],
)
def test_fixture_routes_to_expected_agent(fixture: str, agent: str) -> None:
    result = run(FIXTURES / fixture)
    assert result.returncode == 0
    assert result.stdout.strip() == agent


@pytest.mark.parametrize(
    ("fixture", "language"),
    [
        ("cmake-cpp", "cpp"),
        ("c-make", "c"),
        ("py-uv", "python"),
        ("bash", "bash"),
    ],
)
def test_json_verdict_language(fixture: str, language: str) -> None:
    result = run(FIXTURES / fixture, "--json")
    assert result.returncode == 0
    verdict = json.loads(result.stdout)
    assert verdict["language"] == language
    assert verdict["agent"].startswith("system-developer:")
    assert verdict["confidence"] in {"high", "medium", "low"}


def test_missing_path_exits_2() -> None:
    result = run(Path("/definitely/not/here"))
    assert result.returncode == 2


def test_help_exits_0() -> None:
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--help"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0
    assert "--path" in result.stdout
