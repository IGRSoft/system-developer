"""PLANTED-DEFECTS module — do not "fix" by hand; lint-fix is meant to.

This file intentionally contains:
  1. A ruff violation: an unused import (`os`) -> rule F401.
  2. A pre-3.14 typing idiom: `Optional[int]` / `List[int]` from `typing`
     instead of `int | None` / `list[int]`. ruff's pyupgrade (UP) rules flag
     these (e.g. UP006, UP007/UP045) and `ruff check --fix` rewrites them.

Keep these defects intact so `lint-fix --check` reports them and `--fix`
clears them in the smoke test.
"""

import os  # noqa-free on purpose: this unused import is the F401 violation

from typing import List, Optional


def first_or_none(items: List[int]) -> Optional[int]:
    """Return the first item, or None when the list is empty."""
    if items:
        return items[0]
    return None
