"""Passing tests for the clean module. Run with `uv run pytest`."""

import pytest

from calc.core import add, mean


def test_add() -> None:
    assert add(2, 3) == 5


def test_mean() -> None:
    assert mean([2.0, 4.0, 6.0]) == 4.0


def test_mean_empty_raises() -> None:
    with pytest.raises(ValueError):
        mean([])
