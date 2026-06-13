"""Clean module: ruff-clean, modern idioms, fully covered by the test."""

from collections.abc import Sequence


def add(a: int, b: int) -> int:
    """Return the sum of two integers."""
    return a + b


def mean(values: Sequence[float]) -> float:
    """Return the arithmetic mean of a non-empty sequence."""
    if not values:
        raise ValueError("mean() requires at least one value")
    return sum(values) / len(values)
