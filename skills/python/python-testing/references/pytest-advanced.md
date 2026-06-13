# Advanced pytest

Use this when:

- You need fixture factories, parametrized fixtures, or precise finalization/teardown order.
- You are parametrizing through a fixture with `indirect=True`.
- You are configuring async tests (`pytest-asyncio` vs `anyio`) and hitting loop-scope errors.
- You need to choose between `monkeypatch` and the `mocker` fixture, or patch environment/attributes/imports.
- You are writing Hypothesis strategies beyond the built-ins (composite, `st.builds`, stateful).
- You are configuring coverage (branch, exclusions, combine) or parallelizing with `pytest-xdist`.

Skip this file if:

- You need the core rules, plain-assert basics, or the diagnostic table. Use [../SKILL.md](../SKILL.md).
- You are testing concurrency-specific behavior (free-threading, subinterpreters). Use the python-concurrency skill.
- You need the cross-language test pyramid, framework matrix, or coverage targets. Use [testing-principles](${CLAUDE_SKILL_DIR}/_shared/testing-principles.md).

Jump to:

- Fixture Factories
- Parametrized Fixtures
- Finalization and Teardown Order
- autouse Fixtures
- Indirect Parametrization
- Async Testing in Depth
- monkeypatch vs mocker
- Mocking Patterns
- Hypothesis Strategies
- Coverage Configuration
- Parallelization with xdist
- pyproject Configuration

All commands assume `uv run pytest`. Pin `pytest`, `pytest-asyncio`/`anyio`, `pytest-mock`, `pytest-cov`, `pytest-xdist`, and `hypothesis` in your lockfile; their behavior moves between releases — verify against your toolchain.

## Fixture Factories

When a test needs several customized instances, return a *factory* from the fixture instead of one object:

```python
import pytest

@pytest.fixture
def make_user():
    created: list[User] = []

    def _make(name: str = "alice", *, admin: bool = False) -> User:
        user = User(name=name, admin=admin)
        created.append(user)
        return user

    yield _make
    for user in created:               # teardown: clean up everything built
        user.delete()

def test_admin_can_ban(make_user):
    admin = make_user(admin=True)
    target = make_user(name="bob")
    assert admin.ban(target) is True
```

The factory closes over a list so teardown reaches every object the test created, no matter how many. This is the standard pattern for "give me N of these, each slightly different".

## Parametrized Fixtures

A fixture with `params=` runs every dependent test once per param. Use it to sweep a backend/config across an entire test module without touching each test:

```python
@pytest.fixture(params=["sqlite", "postgres"])
def db_backend(request) -> str:
    backend = request.param
    conn = connect(backend)
    yield conn
    conn.close()

def test_roundtrip(db_backend):        # runs twice: sqlite, postgres
    db_backend.put("k", "v")
    assert db_backend.get("k") == "v"
```

Add readable IDs with `params=[...]` plus `ids=[...]`, or wrap values in `pytest.param(value, id="...")`. `request.param` is only available inside parametrized fixtures.

## Finalization and Teardown Order

Two equivalent teardown styles:

```python
@pytest.fixture
def resource():
    r = acquire()
    yield r
    release(r)                         # yield style — preferred, reads top-to-bottom

@pytest.fixture
def resource_alt(request):
    r = acquire()
    request.addfinalizer(lambda: release(r))   # finalizer style — for conditional cleanup
    return r
```

Order guarantees:

- Within a test, fixtures tear down in **reverse** order of setup (LIFO).
- A higher-scoped fixture (session) tears down after all lower-scoped (function) fixtures that depend on it.
- If setup raises *before* `yield`, teardown does not run for that fixture — guard partial setup yourself.
- Multiple `addfinalizer` calls run in reverse registration order.

Prefer `yield`; reach for `addfinalizer` only when cleanup must be registered conditionally (e.g., only after a resource was actually opened).

## autouse Fixtures

`autouse=True` applies a fixture to every test in its scope without being named. Use sparingly — for cross-cutting setup (reset a global, freeze a clock), never for state a test should explicitly request:

```python
@pytest.fixture(autouse=True)
def reset_singleton():
    Registry.clear()
    yield
    Registry.clear()
```

Scope it as narrowly as correctness allows; an autouse `session` fixture that mutates state is a classic source of cross-test contamination.

## Indirect Parametrization

`indirect=True` routes parametrize values *through a fixture* before the test sees them — use it when the test needs the fixture's processed output, not the raw value:

```python
@pytest.fixture
def user(request) -> User:
    return User.from_role(request.param)   # raw param is a role string

@pytest.mark.parametrize("user", ["admin", "guest"], indirect=True)
def test_permissions(user):                # `user` is a built User, not a string
    assert user.can_read() is True
```

Partial indirection parametrizes some args through fixtures and others directly:

```python
@pytest.mark.parametrize(
    ("user", "expected"),
    [("admin", True), ("guest", False)],
    indirect=["user"],                     # only `user` goes through the fixture
)
def test_can_delete(user, expected):
    assert user.can_delete() is expected
```

Reach for indirect parametrization when setup depends on the parameter; for plain value tables, direct parametrize is simpler and clearer.

## Async Testing in Depth

### Choosing a runner

| Concern | pytest-asyncio | anyio (`@pytest.mark.anyio`) |
|---------|----------------|------------------------------|
| Backends | asyncio only | asyncio and trio (per `anyio_backend`) |
| Marking | `@pytest.mark.asyncio` or `asyncio_mode="auto"` | `@pytest.mark.anyio` |
| Fixtures | `@pytest_asyncio.fixture` | plain `@pytest.fixture` with `async def` |
| Best for | asyncio-only apps | libraries that must support trio too |

Configure once:

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"          # pytest-asyncio: treat every async def test as a coroutine test
```

```python
import pytest

@pytest.fixture
def anyio_backend():           # anyio: restrict to asyncio if you do not need trio
    return "asyncio"

@pytest.mark.anyio
async def test_with_anyio():
    await something()
```

### The loop-scope trap

An async fixture and its test must share one event loop. Mismatched scopes produce `RuntimeError: Event loop is closed` or `... attached to a different loop`.

```python
import pytest_asyncio

@pytest_asyncio.fixture(loop_scope="session", scope="session")
async def client():
    c = await AsyncClient.connect()
    yield c
    await c.aclose()
```

Rules of thumb:

- Default (function-scoped loop and fixture) is safest; widen only for genuinely expensive resources.
- When you set `scope="session"` on an async fixture, set a matching `loop_scope="session"`.
- The exact attribute name and defaults have changed across `pytest-asyncio` releases — verify against your installed version before relying on a wide loop scope.

### Testing concurrency and timeouts

```python
import asyncio, pytest

@pytest.mark.asyncio
async def test_gather_runs_concurrently():
    async with asyncio.TaskGroup() as tg:       # 3.11+: structured, propagates errors
        a = tg.create_task(fetch("a"))
        b = tg.create_task(fetch("b"))
    assert a.result() and b.result()

@pytest.mark.asyncio
async def test_times_out():
    with pytest.raises(TimeoutError):
        async with asyncio.timeout(0.05):
            await never_returns()
```

## monkeypatch vs mocker

Both undo their changes at test end. Pick by *what* you are changing:

| Task | Tool | Call |
|------|------|------|
| Set/unset env var | `monkeypatch` | `monkeypatch.setenv("K", "v")` / `delenv("K", raising=False)` |
| Replace an attribute/function | either | `monkeypatch.setattr("mod.fn", fake)` / `mocker.patch("mod.fn")` |
| Need a spy/assertion API on the replacement | `mocker` | `m = mocker.patch(...); m.assert_called_once()` |
| `chdir`, `syspath_prepend`, dict items | `monkeypatch` | `monkeypatch.chdir(tmp_path)` |
| Patch with autospec | `mocker` | `mocker.patch("mod.Client", autospec=True)` |

```python
def test_reads_env(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "sqlite://:memory:")
    assert get_db_url() == "sqlite://:memory:"

def test_spies_on_call(mocker):
    spy = mocker.patch("myapp.metrics.emit")
    do_work()
    spy.assert_called_once_with("work.done")
```

Rule: `monkeypatch` for environment, filesystem cwd, `sys.path`, and dict/attr tweaks; `mocker` when you want a `Mock`'s recording/assertion surface. Both auto-restore, so never patch with a bare `setattr`.

## Mocking Patterns

### Patch where used

```python
# myapp/service.py
from myapp.client import fetch          # name 'fetch' now lives in myapp.service

def run():
    return fetch("/data")
```

```python
def test_run(mocker):
    mocker.patch("myapp.service.fetch", return_value={"ok": True})  # NOT myapp.client.fetch
    assert run() == {"ok": True}
```

Patching `myapp.client.fetch` would miss the already-imported binding in `myapp.service`. If the consumer does `import myapp.client` and calls `myapp.client.fetch(...)`, then patch `myapp.client.fetch` — patch the attribute on the object that the code actually looks up at call time.

### side_effect: sequences, exceptions, callables

```python
fake.side_effect = [1, 2, 3]                  # successive return values
fake.side_effect = ConnectionError("down")    # raise on call
fake.side_effect = lambda x: x * 2            # compute from args
```

Sequence side effects are the idiom for testing retry logic (fail twice, then succeed) — assert `fake.call_count == 3`.

### autospec to catch signature drift

```python
client = mocker.patch("myapp.client.Client", autospec=True)
client.return_value.get.assert_not_called()   # wrong arg counts now raise in the test
```

`autospec=True` makes the mock reject calls that don't match the real signature, so a refactor that changes arguments fails the test instead of silently passing.

### Mocking time

```python
from freezegun import freeze_time
from datetime import datetime

@freeze_time("2026-01-15 10:00:00")
def test_token_expiry():
    token = create_token(ttl_seconds=3600)
    assert token.expires_at == datetime(2026, 1, 15, 11, 0, 0)
```

Better still, inject a clock (a `Callable[[], datetime]` parameter) so production code never reads the wall clock directly — then tests pass a fixed lambda and need no patching library.

## Hypothesis Strategies

### Built-in strategies

```python
from hypothesis import given, strategies as st

@given(st.integers(min_value=0), st.text(max_size=20), st.lists(st.floats(allow_nan=False)))
def test_signature(n, s, xs): ...
```

Common strategies: `st.integers`, `st.floats(allow_nan=, allow_infinity=)`, `st.text`, `st.binary`, `st.lists(elems, min_size=, max_size=, unique=)`, `st.dictionaries(keys, values)`, `st.sampled_from(seq)`, `st.one_of(a, b)`, `st.none()`.

### Building objects with st.builds

```python
users = st.builds(User, name=st.text(min_size=1), age=st.integers(0, 120))

@given(users)
def test_user_serialization_roundtrips(user):
    assert User.from_json(user.to_json()) == user
```

### Composite strategies (dependent data)

```python
from hypothesis import strategies as st

@st.composite
def sorted_pair(draw):
    lo = draw(st.integers())
    hi = draw(st.integers(min_value=lo))      # hi depends on lo
    return lo, hi

@given(sorted_pair())
def test_range_contains_lo(pair):
    lo, hi = pair
    assert lo <= hi
```

### map / filter / assume

```python
even = st.integers().map(lambda x: x * 2)
nonempty = st.text().filter(lambda s: s.strip())   # prefer map/builds; filter can be slow

from hypothesis import assume
@given(st.integers())
def test_nonzero(n):
    assume(n != 0)                                  # discard uninteresting examples
    assert (10 // n) * n <= 10
```

Prefer `map`/`st.builds` over `filter`/`assume` — filtering discards examples and can exhaust Hypothesis's budget.

### settings, examples, and reproducing failures

```python
from hypothesis import given, settings, example, strategies as st

@settings(max_examples=500, deadline=None)         # deadline=None for inherently slow tests
@given(st.text())
@example("")                                        # always test this specific case
def test_normalize_idempotent(s):
    assert normalize(normalize(s)) == normalize(s)
```

When Hypothesis finds a failure it prints a `@reproduce_failure`/`@example` block — paste it in as a permanent regression. The `hypothesis` database also replays the last failing example automatically on the next run.

### Stateful testing (brief)

For sequences of operations against a model, use `RuleBasedStateMachine` to generate and shrink action sequences. Reserve it for stateful systems (caches, parsers with modes); most code is covered by `@given`.

## Coverage Configuration

```toml
[tool.coverage.run]
source = ["myapp"]
branch = true                          # measure branch coverage, not just lines
omit = ["*/tests/*", "*/__main__.py"]

[tool.coverage.report]
show_missing = true
skip_covered = true
fail_under = 85
exclude_lines = [
    "pragma: no cover",
    "if TYPE_CHECKING:",
    "raise NotImplementedError",
    "if __name__ == .__main__.:",
    "\\.\\.\\.",                       # Protocol/overload bodies
]

[tool.coverage.paths]
source = ["src/", "*/site-packages/"]  # map installed paths back to source for combine
```

Run and gate:

```sh
uv run pytest --cov=myapp --cov-branch --cov-report=term-missing --cov-fail-under=85
uv run pytest --cov=myapp --cov-report=html        # browsable htmlcov/ report
```

Combining across processes (needed with xdist or multiple test runs):

```sh
uv run coverage combine        # merge .coverage.* data files
uv run coverage report
```

`[tool.coverage.paths]` is what makes combine work when tests run from an installed wheel and you report against `src/`.

## Parallelization with xdist

```sh
uv run pytest -n auto          # one worker per CPU
uv run pytest -n 4             # fixed worker count
uv run pytest -n auto --dist loadgroup   # keep @pytest.mark.xdist_group tests on one worker
```

Requirements and caveats:

- Tests must be **independent** — xdist distributes them across processes in nondeterministic order. Order-dependent tests fail under `-n`.
- `session`-scoped fixtures are built **once per worker**, not once globally. A fixture that assumed a single global instance (a port, a shared file) needs per-worker uniqueness (`tmp_path_factory`, `worker_id` from the `worker_id` fixture).
- Coverage requires `combine` (see above); `pytest-cov` handles this when its `pytest-xdist` integration is active.
- Use `--dist loadgroup` with `@pytest.mark.xdist_group("name")` to pin a set of tests that share an expensive resource to the same worker.

```python
def test_uses_unique_db(tmp_path_factory, worker_id):
    db_path = tmp_path_factory.mktemp("db") / f"{worker_id}.sqlite"   # avoid cross-worker clash
    ...
```

## pyproject Configuration

A complete, conventional `[tool.pytest.ini_options]` block:

```toml
[tool.pytest.ini_options]
minversion = "8.0"
testpaths = ["tests"]
addopts = [
    "-ra",                      # show summary of all non-passing outcomes
    "--strict-markers",         # unknown @pytest.mark.* is an error, not a warning
    "--strict-config",          # config typos fail fast
    "--import-mode=importlib",  # modern import mode; no sys.path hacks
]
markers = [
    "slow: long-running tests (deselect with -m 'not slow')",
    "integration: touches external services",
]
asyncio_mode = "auto"
```

Select and deselect with markers and keywords:

```sh
uv run pytest -m "not slow"            # skip slow tests
uv run pytest -m integration           # only integration tests
uv run pytest -k "user and not delete" # by test-name substring expression
uv run pytest tests/test_api.py::test_create_user   # a single test by node id
```

`--strict-markers` plus a declared `markers` list turns a mistyped marker into an immediate failure — keep it on so dead `@pytest.mark.slwo` markers never silently skip nothing.
