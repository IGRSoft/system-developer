# Advanced pytest

Commands assume `uv run pytest`, with `pytest`, `pytest-asyncio`/`anyio`, `pytest-mock`, `pytest-cov`, `pytest-xdist`, and `hypothesis` pinned in the lockfile.

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

The factory closes over a list so teardown reaches every object the test created.

## Parametrized Fixtures

A fixture with `params=` runs every dependent test once per param, sweeping a backend or config across a module without touching each test:

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

Add IDs with `ids=[...]` or `pytest.param(value, id="...")`.

## Finalization and Teardown Order

Two teardown styles:

```python
@pytest.fixture
def resource():
    r = acquire()
    yield r
    release(r)                         # preferred

@pytest.fixture
def resource_alt(request):
    r = acquire()
    request.addfinalizer(lambda: release(r))   # for conditional cleanup
    return r
```

Order guarantees:

- Fixtures tear down in reverse order of setup.
- A higher-scoped fixture (session) tears down after all lower-scoped (function) fixtures that depend on it.
- If setup raises before `yield`, that fixture's teardown does not run; guard partial setup yourself.
- Multiple `addfinalizer` calls run in reverse registration order.

Use `addfinalizer` only when cleanup must be registered conditionally, e.g. only after a resource actually opened.

## autouse Fixtures

`autouse=True` applies a fixture to every test in its scope without being named. Keep it for cross-cutting setup (reset a global, freeze a clock), not for state a test should request explicitly:

```python
@pytest.fixture(autouse=True)
def reset_singleton():
    Registry.clear()
    yield
    Registry.clear()
```

Scope it narrowly; an autouse `session` fixture that mutates state leaks between tests.

## Indirect Parametrization

`indirect=True` routes parametrize values through a fixture, so the test gets the fixture's output instead of the raw value:

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

For plain value tables, direct parametrize is simpler.

## Async Testing in Depth

### Choosing a runner

| Concern | pytest-asyncio | anyio (`@pytest.mark.anyio`) |
|---------|----------------|------------------------------|
| Backends | asyncio only | asyncio by default; trio via `anyio_backend` |
| Marking | `@pytest.mark.asyncio` or `asyncio_mode="auto"` | `@pytest.mark.anyio` |
| Fixtures | `@pytest_asyncio.fixture` | plain `@pytest.fixture` with `async def` |
| Best for | asyncio-only apps | libraries that must support trio too |

Configure once:

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"          # pytest-asyncio: every async def test runs without a marker
```

```python
import pytest

@pytest.fixture(params=["asyncio", "trio"])
def anyio_backend(request):    # anyio: default is asyncio only; this adds trio
    return request.param

@pytest.mark.anyio
async def test_with_anyio():
    await something()
```

### The loop-scope trap

An async fixture and its test must share one event loop; mismatched scopes raise `Event loop is closed` or `... attached to a different loop`.

```python
import pytest_asyncio

@pytest_asyncio.fixture(loop_scope="session", scope="session")
async def client():
    c = await AsyncClient.connect()
    yield c
    await c.aclose()
```

Function-scoped loop and fixture is the safe default; widen both together, and only for expensive resources. `loop_scope` needs pytest-asyncio 0.24 or later.

### Testing concurrency and timeouts

```python
import asyncio, pytest

async def test_fetches_run_concurrently():
    async with asyncio.TaskGroup() as tg:
        a = tg.create_task(fetch("a"))
        b = tg.create_task(fetch("b"))
    assert a.result() and b.result()

async def test_times_out():
    with pytest.raises(TimeoutError):
        async with asyncio.timeout(0.05):
            await never_returns()
```

## monkeypatch vs mocker

Both undo their changes at test end. Pick by what you change:

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

Don't patch with a bare `setattr`; it is never restored.

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
    mocker.patch("myapp.service.fetch", return_value={"ok": True})  # not myapp.client.fetch
    assert run() == {"ok": True}
```

If the consumer instead does `import myapp.client` and calls `myapp.client.fetch(...)`, patch `myapp.client.fetch`: patch whatever the code looks up at call time.

### side_effect: sequences, exceptions, callables

```python
fake.side_effect = [1, 2, 3]                  # successive return values
fake.side_effect = ConnectionError("down")    # raise on call
fake.side_effect = lambda x: x * 2            # compute from args
```

For retry logic, a sequence like `[Err(), Err(), value]` plus `fake.call_count == 3` covers fail-twice-then-succeed.

### autospec to catch signature drift

```python
client_cls = mocker.patch("myapp.service.Client", autospec=True)
run()                                          # a call with the wrong signature raises TypeError
client_cls.return_value.get.assert_called_once_with("/data")
```

`autospec=True` makes the mock reject calls that don't match the real signature, so a changed signature fails the test instead of passing silently.

### Mocking time

```python
from freezegun import freeze_time
from datetime import datetime

@freeze_time("2026-01-15 10:00:00")
def test_token_expiry():
    token = create_token(ttl_seconds=3600)
    assert token.expires_at == datetime(2026, 1, 15, 11, 0, 0)
```

Better, inject a clock (a `Callable[[], datetime]` parameter) so tests pass a fixed lambda and need no patching library.

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
def test_divmod_identity(n):
    assume(n != 0)                                  # discard the invalid case
    assert (10 // n) * n + 10 % n == 10
```

Prefer `map`/`st.builds` over `filter`/`assume`: discarded examples count against Hypothesis's budget.

### settings, examples, and reproducing failures

```python
from hypothesis import given, settings, example, strategies as st

@settings(max_examples=500, deadline=None)         # deadline=None for inherently slow tests
@given(st.text())
@example("")                                        # always test this specific case
def test_normalize_idempotent(s):
    assert normalize(normalize(s)) == normalize(s)
```

A failure prints the shrunk falsifying example; add it as `@example(...)` to keep it as a regression. The local example database also replays the last failure on the next run.

### Stateful testing (brief)

For operation sequences checked against a model, `RuleBasedStateMachine` generates and shrinks action sequences. Reserve it for stateful systems (caches, parsers with modes).

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
exclude_also = [                       # adds to the default "pragma: no cover"
    "if TYPE_CHECKING:",
    "raise NotImplementedError",
    "if __name__ == .__main__.:",
    '^\s*\.\.\.$',                         # Protocol/overload bodies
]

[tool.coverage.paths]
source = ["src/", "*/site-packages/"]  # map installed paths back to source for combine
```

`uv run pytest --cov=myapp --cov-report=html` writes a browsable `htmlcov/`. pytest-cov combines xdist workers' data itself; separate runs need `uv run coverage combine` then `coverage report`, and `[tool.coverage.paths]` maps installed-wheel paths back to `src/` for that.

## Parallelization with xdist

```sh
uv run pytest -n auto          # one worker per CPU
uv run pytest -n 4             # fixed worker count
uv run pytest -n auto --dist loadgroup   # keep @pytest.mark.xdist_group tests on one worker
```

- Tests must be independent; xdist runs them across processes in nondeterministic order.
- `session` fixtures are built once per worker, not once globally. A single global resource (a port, a shared file) needs per-worker names via `tmp_path_factory` and the `worker_id` fixture.

```python
def test_uses_unique_db(tmp_path_factory, worker_id):
    db_path = tmp_path_factory.mktemp("db") / f"{worker_id}.sqlite"   # avoid cross-worker clash
    ...
```

## pyproject Configuration

A conventional `[tool.pytest.ini_options]` block:

```toml
[tool.pytest.ini_options]
minversion = "8.0"
testpaths = ["tests"]
addopts = [
    "-ra",                      # show summary of all non-passing outcomes
    "--strict-markers",         # a mistyped marker is an error, not a silent no-op
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
