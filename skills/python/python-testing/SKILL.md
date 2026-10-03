---
name: python-testing
description: >-
  Pytest testing for Python 3.12-3.14: plain-assert tests, fixtures and
  conftest scoping, parametrization, async tests, mocking, branch coverage,
  and Hypothesis. Use when writing or structuring pytest tests, designing
  fixtures, testing async code, mocking dependencies, gating coverage, or
  triaging flaky tests.
---

# Python Testing (pytest)

Run tests via `uv run pytest`, with pytest and its plugins pinned in the lockfile.

## Core Rules

1. Plain `assert`, not `unittest` assert methods; pytest rewrites asserts to show the operands.
2. One behavior per test, so a failure names the broken behavior.
3. Test error paths: `pytest.raises(Err, match=...)` pins the exception and its message.
4. Fixtures over setup/teardown; shared ones go in `conftest.py` at the right directory level.
5. Patch where the name is used, not where it is defined (see Mocking).
6. Branch coverage with a CI floor: `--cov-branch --cov-fail-under=N`.
7. Deterministic by default: no real network, clock, or randomness without control. Fix flaky tests; don't retry them away.

## Plain-Assert Tests

```python
import pytest

def test_divide_returns_quotient():
    assert divide(6, 3) == 2

def test_divide_by_zero_raises():
    with pytest.raises(ZeroDivisionError, match="divide by zero"):
        divide(5, 0)
```

`pytest.raises` returns an `ExceptionInfo`; assert on the raised object via `exc_info.value`.

## Fixtures and Scopes

```python
import pytest

@pytest.fixture                       # scope="function": fresh per test
def db():
    conn = Database(":memory:")
    conn.connect()
    yield conn                        # code after yield is teardown
    conn.disconnect()

@pytest.fixture(scope="session")      # built once per run
def app_config() -> dict[str, str]:
    return {"env": "test"}
```

| Scope | Built once per | Use for |
|-------|----------------|---------|
| `function` (default) | test | mutable state, isolation |
| `class` | test class | shared read-only setup in a class |
| `module` | test file | a connection reused across a file |
| `package` | package dir | per-package resources |
| `session` | run | expensive immutable resources |

Wider scope is faster but shared, so a wide-scoped fixture must not hold state that tests mutate.

### conftest.py Placement

`conftest.py` exposes its fixtures to every test at or below its directory, without imports. Broad fixtures go in `tests/conftest.py`, narrow ones in the subpackage's `conftest.py`; the closer file wins on a name clash. `../scripts/scaffold_conftest.sh` emits a starting `conftest.py` (`--with-async` adds a pytest-asyncio fixture).

## Parametrization

```python
@pytest.mark.parametrize(
    ("value", "expected"),
    [
        pytest.param(1, True, id="positive"),
        pytest.param(0, False, id="zero"),
        pytest.param(-1, False, id="negative"),
    ],
)
def test_is_positive(value, expected):
    assert (value > 0) is expected
```

- IDs (`ids=` or `pytest.param(..., id=...)`) make `-k` selection and failure output readable.
- Stacked `parametrize` decorators run the Cartesian product.
- `pytest.param(..., marks=pytest.mark.xfail)` marks one case as expected-fail.
- To pass a value through a fixture first, use `indirect=True` (see the reference).

## Async Testing

Configure the runner once in `pyproject.toml`:

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"              # pytest-asyncio: no @pytest.mark.asyncio needed
```

```python
async def test_fetch_returns_payload(fake_transport):
    result = await fetch("/status", transport=fake_transport)
    assert result["ok"] is True
```

- `pytest-asyncio` is asyncio-only. `anyio` (`@pytest.mark.anyio`) runs on asyncio by default and can add trio by parametrizing the `anyio_backend` fixture.
- An async fixture and its test must share an event loop. A `session`/`module`-scoped `pytest-asyncio` fixture needs a matching `loop_scope` (`@pytest_asyncio.fixture(scope="session", loop_scope="session")`), otherwise you get "attached to a different loop" or "Event loop is closed". Function scope is the safe default.

## Mocking

Prefer the `pytest-mock` `mocker` fixture; it undoes patches at test end.

```python
def test_get_user_calls_api(mocker):
    fake_get = mocker.patch("myapp.client.requests.get")
    fake_get.return_value.json.return_value = {"id": 1}

    user = get_user(1)

    assert user["id"] == 1
    fake_get.assert_called_once_with("https://api/users/1")
```

### Patch where used

If `myapp.service` does `from myapp.client import get_user`, patch `myapp.service.get_user`, the name bound in the consuming module. Patching `myapp.client.get_user` leaves the already-imported reference untouched.

```python
fake.side_effect = [ConnError(), ConnError(), {"ok": True}]   # fail twice, then succeed
fake.side_effect = ValueError("boom")                         # raise on call
```

For environment variables, cwd, and `sys.path`, use the builtin `monkeypatch` fixture.

## Coverage

```sh
uv run pytest --cov=myapp --cov-branch --cov-report=term-missing --cov-fail-under=85
```

- `--cov-branch` catches half-tested conditionals that line coverage reports as 100%.
- `term-missing` lists uncovered lines and branches.
- Set source and exclusions in `[tool.coverage.run]` / `[tool.coverage.report]` (see the reference).
- Aim at branches and error paths, not a percentage for its own sake.

## Hypothesis (Property-Based)

State an invariant; Hypothesis searches for counterexamples and shrinks them to a minimal one.

```python
from collections import Counter
from hypothesis import given, strategies as st

@given(st.lists(st.integers()))
def test_sorted_is_ordered_and_preserves_elements(xs):
    out = sorted(xs)
    assert Counter(out) == Counter(xs)
    assert all(a <= b for a, b in zip(out, out[1:]))
```

Good fits: parsers, encode/decode round-trips, functions with an algebraic property. Add a reported falsifying example as `@example(...)` to keep it as a regression.

## Flaky-Test Triage

### Isolation and order

| Symptom | Cause | Fix |
|---------|-------|-----|
| Passes alone, fails in suite | Shared mutable state | Narrow fixture scope; reset state in teardown |
| Result depends on run order | One test relies on another | Make tests independent; replay the order with pytest-randomly's `--randomly-seed=N` |
| `Event loop is closed` / "different loop" | Async fixture loop scope differs from the test's | Match `loop_scope`; default to function scope |
| `fixture 'x' not found` | Fixture's `conftest.py` is below or beside the test | Move it to a `conftest.py` at or above the test |
| Fails only under `pytest -n` | Order dependence or a shared resource per worker | See xdist in the reference |

### Mocks, time, coverage

| Symptom | Cause | Fix |
|---------|-------|-----|
| Mock never hit | Patched the definition site | Patch the name in the consuming module |
| Time-dependent assertion intermittently off | Real clock | Inject a clock or freeze time (see the reference) |
| Rare failure from random data | Uncontrolled randomness | Seed the RNG, or treat it as a real bug |
| 100% coverage but bug shipped | Untested branches | `--cov-branch`; cover both arms |

## References

| File | Read it for |
|---|---|
| [references/pytest-advanced.md](references/pytest-advanced.md) | Fixture factories and teardown order, indirect parametrize, async runners, `monkeypatch` vs `mocker`, autospec, time, Hypothesis strategies, coverage config, xdist, pyproject config |

## Related Skills

| Skill | For |
|---|---|
| [python-typing](../python-typing/SKILL.md) | Typing test code, typed fixtures and fakes |
| [python-concurrency](../python-concurrency/SKILL.md) | Async, free-threaded, and subinterpreter code |
| [python-tooling](../python-tooling/SKILL.md) | Wiring pytest into uv projects and CI |
| [modern-python](../modern-python/SKILL.md) | 3.14 language features and anti-patterns |
| [testing-principles](../../_shared/testing-principles.md) | Test pyramid, framework matrix, coverage targets |
