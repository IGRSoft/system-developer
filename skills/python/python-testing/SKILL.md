---
name: python-testing
description: >-
  Pytest testing for Python 3.12-3.14: plain-assert tests, fixtures and
  conftest scoping, parametrization, async testing, mocking, coverage, and
  property-based testing with Hypothesis. Use when writing or structuring
  pytest tests, designing fixtures, parametrizing cases, testing async or
  concurrent code, mocking dependencies, measuring branch coverage, or
  triaging flaky tests.
---

# Python Testing (pytest)

**Idiomatic pytest for Python 3.12–3.14 — plain asserts, scoped fixtures, parametrization, async, coverage, and Hypothesis.**

Pin tool versions in your lockfile and run via `uv run pytest`. Plugin behavior (especially async loop scoping) shifts between releases — verify against your toolchain.

## When to Use

- Writing unit, integration, or end-to-end tests with pytest.
- Designing fixtures and deciding `conftest.py` placement and scope.
- Parametrizing repetitive cases, including stacked parametrize and custom IDs.
- Testing async code (`pytest-asyncio` or `anyio`) and concurrent operations.
- Mocking dependencies and patching at the right import site.
- Measuring branch coverage and gating CI on it.
- Triaging a flaky or order-dependent test.

## Core Rules

1. **Plain `assert` — never `unittest` assert methods.** pytest rewrites asserts to show the operands; `assert result == 5` beats `self.assertEqual`.
2. **One behavior per test.** A focused failure names the broken behavior; a test with five asserts hides four of them.
3. **Test error paths, not just happy paths.** Use `pytest.raises(Err, match=...)` to pin the exception *and* its message.
4. **Fixtures over setup/teardown.** Compose state with fixtures; place shared ones in `conftest.py` at the right directory level.
5. **Patch where the name is used, not where it is defined** (the single biggest mock mistake — see below).
6. **Branch coverage, not line coverage**, and gate CI on a floor — `--cov-branch --cov-fail-under=N`.
7. **Deterministic by default.** No real network, clock, or random without control; flakiness is a bug to fix, not retry away.

## Plain-Assert Tests

```python
import pytest

def test_divide_returns_quotient():
    assert divide(6, 3) == 2

def test_divide_by_zero_raises():
    with pytest.raises(ZeroDivisionError, match="divide by zero"):
        divide(5, 0)
```

`pytest.raises` returns an `ExceptionInfo`; inspect it via `exc_info.value` for typed assertions on the raised object.

## Fixtures and Scopes

```python
import pytest

@pytest.fixture                       # default scope="function" — fresh per test
def db():
    conn = Database(":memory:")
    conn.connect()
    yield conn                        # everything after yield is teardown
    conn.disconnect()

@pytest.fixture(scope="session")      # built once for the whole run
def app_config() -> dict[str, str]:
    return {"env": "test"}
```

| Scope | Built once per | Use for |
|-------|----------------|---------|
| `function` (default) | each test | mutable state, isolation |
| `class` | test class | shared read-only setup in a class |
| `module` | test file | a connection reused across a file |
| `package` | package dir | per-package resources |
| `session` | whole run | expensive immutable resources |

Wider scope = faster but shared; never let a wider-scoped fixture hold mutable state that tests mutate. Teardown after `yield` runs in reverse order; use `request.addfinalizer` only when you need finalizers registered conditionally.

### conftest.py Placement

`conftest.py` makes fixtures available to every test **at or below** its directory — no import needed. Put broad fixtures (`tmp config`, fakes) in the top `tests/conftest.py`; put narrow ones in the subpackage's `conftest.py`. Closer files override farther ones by name. Scaffold a starting `conftest.py` (scoped fixtures; `--with-async` for a pytest-asyncio fixture) with `../scripts/scaffold_conftest.sh`.

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

- **`ids=`** (or per-case `pytest.param(..., id=...)`) makes `-k` selection and failure output readable. Without IDs, pytest auto-generates noisy ones.
- **Stacking** two `parametrize` decorators yields the Cartesian product:

```python
@pytest.mark.parametrize("x", [1, 2])
@pytest.mark.parametrize("y", [10, 20])
def test_grid(x, y): ...     # runs 4 combinations
```

- **`pytest.param(..., marks=pytest.mark.xfail)`** marks a single case as expected-fail without splitting the test.
- For parametrizing *through a fixture*, use `indirect=True` — see `references/pytest-advanced.md`.

## Async Testing

Pick one runner and configure it once in `pyproject.toml`:

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"              # pytest-asyncio: no @pytest.mark.asyncio needed
```

```python
async def test_fetch_returns_payload():
    result = await fetch("https://example.invalid")
    assert result["ok"] is True
```

- **`pytest-asyncio`** vs **`anyio`** (`@pytest.mark.anyio`): anyio runs each test on both asyncio and trio backends; asyncio-only projects can use either.
- **Loop-scope caveat:** an async fixture and the test that uses it must share an event loop. With `pytest-asyncio`, a `session`/`module`-scoped async fixture needs a matching `loop_scope` (`@pytest_asyncio.fixture(loop_scope="session")`) or you get "attached to a different loop" / "Event loop is closed". The default function loop scope is safest; widen deliberately. Verify the exact knob against your installed `pytest-asyncio` version.

## Mocking

Prefer the `pytest-mock` `mocker` fixture — it auto-undoes patches at test end, so no `with` nesting or decorator stacks:

```python
def test_get_user_calls_api(mocker):
    fake_get = mocker.patch("myapp.client.requests.get")
    fake_get.return_value.json.return_value = {"id": 1}

    user = get_user(1)

    assert user["id"] == 1
    fake_get.assert_called_once_with("https://api/users/1")
```

**Patch where used.** If `myapp.service` does `from myapp.client import get_user`, patch `myapp.service.get_user` — the name *bound in the consuming module* — not `myapp.client.get_user`. Patching the definition site leaves the already-imported reference untouched.

```python
fake.side_effect = [ConnError(), ConnError(), {"ok": True}]   # fail twice, then succeed
fake.side_effect = ValueError("boom")                         # raise on call
```

For environment, attributes, and `sys.path`, use the builtin `monkeypatch` fixture instead of `mocker` (see `references/pytest-advanced.md` for `monkeypatch` vs `mocker`).

## Coverage

```sh
uv run pytest --cov=myapp --cov-branch --cov-report=term-missing --cov-fail-under=85
```

- **`--cov-branch`** catches half-tested conditionals that line coverage reports as 100%.
- **`--cov-report=term-missing`** prints uncovered line *and branch* numbers.
- Configure source and exclusions in `[tool.coverage.run]` / `[tool.coverage.report]` (e.g. `exclude_lines = ["pragma: no cover", "if TYPE_CHECKING:"]`). Full config in `references/pytest-advanced.md`.
- Chase meaningful coverage of branches and error paths, not a percentage for its own sake.

## Hypothesis (Property-Based)

State an invariant; Hypothesis finds counterexamples and shrinks them to a minimal failing case.

```python
from hypothesis import given, strategies as st

@given(st.lists(st.integers()))
def test_sorted_is_ordered_and_preserves_elements(xs):
    out = sorted(xs)
    assert len(out) == len(xs)              # same elements
    assert all(a <= b for a, b in zip(out, out[1:]))   # ordered
```

Use for parsers, encoders/decoders (round-trips), and any function with an algebraic property. A failing example is reported as a concrete `@example` you can paste back as a regression test. Strategy composition lives in `references/pytest-advanced.md`.

## Flaky-Test Triage

| Symptom | Cause | Fix | Reference |
|---------|-------|-----|-----------|
| Passes alone, fails in suite | Shared mutable state across tests | Narrow fixture scope; reset state in teardown | Fixtures and Scopes |
| Passes/fails by run order | Order dependence (one test relies on another) | Make tests independent; run `-p no:randomly` to confirm | this file |
| `Event loop is closed` / "different loop" | Async fixture loop scope ≠ test loop scope | Match `loop_scope`; default to function scope | Async Testing |
| `assert_called_once_with` fails, mock never hit | Patched the definition site, not the use site | Patch the name in the consuming module | Mocking |
| Time-dependent assertion intermittently off | Real clock used | Freeze time (`freezegun`) or inject a clock | `references/pytest-advanced.md` |
| Random fixture data triggers rare failure | Uncontrolled randomness | Seed RNG; or treat as a real bug Hypothesis found | Hypothesis |
| Coverage 100% but bug shipped | Line coverage, untested branches | Add `--cov-branch`; cover both arms | Coverage |
| `fixture 'x' not found` | `conftest.py` too deep / wrong dir | Move fixture to a `conftest.py` at/above the test | conftest.py Placement |
| Slow suite, parallel needed | Serial execution | `pytest -n auto` (xdist); ensure tests are isolated | `references/pytest-advanced.md` |

## References

| File | Read it for |
|---|---|
| [references/pytest-advanced.md](references/pytest-advanced.md) | Fixture factories and finalization, indirect parametrize, async backends, `monkeypatch` vs `mocker`, Hypothesis strategies, coverage config, xdist parallelization |

## Related Skills

- [python-typing](../python-typing/SKILL.md) — typing test code, typed fixtures and fakes
- [python-concurrency](../python-concurrency/SKILL.md) — testing async, free-threaded, and subinterpreter code
- [python-tooling](../python-tooling/SKILL.md) — wiring pytest into uv projects and CI
- [modern-python](../modern-python/SKILL.md) — 3.14 language features and anti-patterns
- [testing-principles](${CLAUDE_SKILL_DIR}/_shared/testing-principles.md) — test pyramid, framework matrix, coverage targets
