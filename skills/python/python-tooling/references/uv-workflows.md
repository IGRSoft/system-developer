# uv Workflows

Use this when:

- You are running the day-to-day project loop (`add`/`sync`/`run`/`lock`) and want the precise semantics and gotchas.
- You are setting up a workspace or monorepo with multiple interdependent packages.
- You are installing or pinning Python interpreters, including the free-threaded `3.14t` build.
- You are managing standalone tools (`uvx`, `uv tool install`) and keeping them out of the project.
- You are writing a Dockerfile and want correct layer caching for uv.
- You are wiring uv into CI for reproducible, lock-frozen installs.

Skip this file if:

- You only need the command cheat sheet and the two-tool rule. Use [../SKILL.md](../SKILL.md).
- You are deciding `pyproject.toml` fields, the `src/` layout, build backends, or publishing. Use [packaging-and-project-structure.md](packaging-and-project-structure.md).
- You need to choose between the standard and free-threaded interpreter at the *language* level. Use the python-concurrency skill; this file only installs them.

Jump to:

- Mental Model: What uv Manages
- Projects: the sync/lock/run loop
- The `uv pip` Escape Hatch
- Lockfiles in Depth
- Python Version Management
- Free-Threaded Builds (3.14t)
- Tools: uvx and uv tool
- Workspaces and Monorepos
- Docker Layer Caching
- CI Pipelines
- Caching and Offline
- Migration
- Command Reference

Toolchain note: this reference tracks the uv **0.11.x** line (current **0.11.21**),
where the project workflow and the `uv_build` backend are stable. Flag names below
are current; confirm anything you script with `uv <cmd> --help` and `uv self version`.

## Mental Model: What uv Manages

uv owns four things that used to need four tools:

| Concern | Old stack | uv |
|---------|-----------|----|
| Virtual environment | virtualenv / venv | `.venv` created and managed automatically |
| Dependencies | pip + pip-tools / poetry | `uv add` / `uv lock` / `uv sync` |
| Python interpreter | pyenv / system packages | `uv python install` / `pin` |
| Standalone tools | pipx | `uvx` / `uv tool install` |

The project state is three files: `pyproject.toml` (intent), `uv.lock`
(resolution), `.python-version` (interpreter pin). The `.venv` is derived and
disposable — never commit it; `uv sync` rebuilds it from the lock.

## Projects: the sync/lock/run loop

### The loop

```bash
uv init my-pkg --package        # scaffold (src/ + build-system) — or `uv init` for an app
uv add httpx                    # 1. edit pyproject  2. re-resolve lock  3. sync .venv
uv run python -m my_pkg         # auto-syncs if stale, then runs inside .venv
uv run pytest -q                # same: no activation needed
```

`uv add` does the full cycle atomically. `uv run` checks whether the environment
matches the lock and syncs first if not, so you never run against a stale env.

### Adding dependencies precisely

```bash
uv add "httpx>=0.27,<0.28"          # constraint
uv add --group dev pytest pytest-cov  # PEP 735 dependency group
uv add --optional redis redis         # user-facing extra: pip install pkg[redis]
uv add "ruff ; python_version >= '3.12'"   # environment marker
uv add git+https://github.com/psf/requests@main   # VCS source
uv add ../sibling-lib                 # local path; recorded under [tool.uv.sources]
uv add --editable ../sibling-lib      # editable local path
```

Prefer `--group` for dev/test/docs tooling (not published) and `--optional` only
for genuine consumer-facing extras. See
[packaging-and-project-structure.md](packaging-and-project-structure.md) § groups.

### Running

```bash
uv run pytest                   # project env
uv run --group docs mkdocs build   # include a non-default group for this run
uv run --no-sync python x.py    # skip the sync check (env known good; faster)
uv run --with rich python x.py  # ad-hoc extra dep for one run, not persisted
uv run --python 3.13 python x.py   # one-off alternate interpreter
```

### Inline-script dependencies (PEP 723)

For single-file scripts, declare deps in the file and let uv build an ephemeral env:

```bash
uv add --script analyze.py httpx     # writes a PEP 723 metadata block
uv run analyze.py                    # resolves + runs in a throwaway env
```

```python
# /// script
# requires-python = ">=3.14"
# dependencies = ["httpx"]
# ///
import httpx
```

No project, no manual venv — ideal for ops scripts and reproducible gists.

## The `uv pip` Escape Hatch

`uv pip` is a fast, pip-compatible interface for cases the project workflow does
not cover (legacy `requirements.txt`, container scripts, ad-hoc envs). It does
**not** read or update `pyproject.toml`/`uv.lock`.

```bash
uv venv                              # explicit venv when you want one
uv pip install -r requirements.txt   # legacy install
uv pip compile requirements.in -o requirements.txt   # pip-tools replacement
uv pip sync requirements.txt         # exact-match install
uv pip freeze                        # list installed
```

Rule of thumb: for an owned project use `add`/`sync`/`lock`; reach for `uv pip`
only when you do not have (or do not want) project files.

## Lockfiles in Depth

### What the lock is

`uv.lock` is a cross-platform, fully-resolved, hashed snapshot of the entire
dependency graph for every group and supported platform/marker. It is a uv
format (TOML) — not `requirements.txt`. One lock covers Linux/macOS/Windows.

### Policy

| Project kind | Commit `uv.lock`? | Rationale |
|--------------|-------------------|-----------|
| Application / service / CLI end product | **Yes** | Reproducible deploys; `--frozen` in CI |
| Library (published to an index) | Optional but recommended | Publish loose constraints; commit the lock for reproducible *dev/CI* only |
| Workspace root | Yes (single root lock) | One lock governs all members |

### Commands

```bash
uv lock                          # resolve, write uv.lock (no install)
uv lock --upgrade                # re-resolve everything to newest allowed
uv lock --upgrade-package httpx  # bump exactly one dependency
uv lock --check                  # assert the lock is current; non-zero if not (CI guard)
uv sync --frozen                 # install exactly the lock; error on any drift
uv sync --locked                 # like --frozen; verify lock is up to date first
uv export --format pylock.toml -o pylock.toml          # PEP 751 standard lockfile
uv export --format requirements-txt > requirements.txt   # legacy interop export
```

`--frozen` is the CI default: it refuses to silently re-resolve, so a forgotten
`uv lock` after a `pyproject.toml` edit fails the build instead of shipping
different versions than were reviewed.

### Standard interop: pylock.toml (PEP 751)

`uv.lock` is uv's own format. **PEP 751 `pylock.toml` is the standardized,
tool-interoperable lockfile** (final) — export it when a non-uv tool or a
supply-chain scanner needs a standard lock:

```bash
uv export --format pylock.toml -o pylock.toml   # write the PEP 751 lock
uv export --format pylock.toml --group dev -o pylock.dev.toml   # scope a group
```

Keep `uv.lock` as the committed source of truth; treat `pylock.toml` as a
generated export (on demand or in CI) for interop and scanning, not as the lock
you resolve from. See the `/system-developer:deps` command for feeding it to scanners.

## Python Version Management

uv downloads standalone interpreters (python-build-standalone) — independent of
the system Python and of pyenv.

```bash
uv python install 3.14           # install one
uv python install 3.12 3.13 3.14 # several at once
uv python list                   # installed + downloadable
uv python find 3.14              # path to a specific interpreter
uv python pin 3.14               # write .python-version for this project
uv python uninstall 3.12         # remove
```

`requires-python` in `pyproject.toml` bounds what uv will *resolve* against;
`.python-version` (via `uv python pin`) selects the interpreter uv *uses* for the
project. Keep them consistent: `requires-python = ">=3.14"` with a pinned `3.14`.

When you run `uv run` / `uv sync` and the pinned interpreter is absent, uv can
fetch it automatically (subject to `python-downloads` settings *(verify against
your uv)*) — so a fresh clone bootstraps without a manual install step.

## Free-Threaded Builds (3.14t)

The free-threaded ("no-GIL") interpreter is officially supported as of Python
3.14 (PEP 779) and ships as a **separate binary**, `3.14t` — it is not a runtime
flag on `3.14`.

```bash
uv python install 3.14t          # install the free-threaded build
uv python pin 3.14t              # pin the project to it
uv run python -c "import sys; print(sys._is_gil_enabled())"   # False on 3.14t
```

Notes:
- `3.14` and `3.14t` are different interpreters; installing one does not install
  the other. Errors like `No interpreter found for Python 3.14t` mean the
  free-threaded build is missing — install it explicitly.
- Pure-Python wheels work on both. C-extension wheels must be built for the
  free-threaded ABI (tagged `cp314t`); if a dependency lacks a `t` wheel, uv may
  build from sdist or fail to resolve. Verify your dependency tree before pinning
  `3.14t` for production.
- Choosing the free-threaded build is a *concurrency* decision (CPU-bound
  parallelism in-process) — see the python-concurrency skill. This file only
  installs and pins it. Version anchors:
  [version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md).

## Tools: uvx and uv tool

Standalone CLI tools live in their own cached environments, never in the project.

```bash
uvx ruff check .                     # ephemeral run (alias: uv tool run)
uvx --from "ruff==0.14.*" ruff .     # pin the tool version for this run
uvx --with mkdocs-material mkdocs build   # tool plus an extra plugin
uv tool install ruff                 # persistent install with a PATH shim
uv tool install --python 3.14 mypy   # tool on a chosen interpreter
uv tool list                         # what is installed
uv tool upgrade --all                # upgrade all installed tools
uv tool uninstall ruff
```

Decision: `uvx` for one-off or CI invocations (zero install, cached);
`uv tool install` for tools you invoke across many projects from the shell.
Either way the tool's dependencies stay out of `pyproject.toml` and `uv.lock`.

In CI, prefer `uv run ruff` (project-pinned ruff from a dependency group) so the
linter version is locked with everything else, or `uvx --from "ruff==X" ruff`
for an explicitly pinned ephemeral run.

## Workspaces and Monorepos

A uv **workspace** is multiple packages sharing one lockfile and one resolution —
the Cargo-style monorepo model. One `uv.lock` at the root governs every member.

### Layout

```text
repo/
├── pyproject.toml          # workspace root (may also be a package)
├── uv.lock                 # single lock for the whole workspace
├── packages/
│   ├── core/pyproject.toml
│   └── api/pyproject.toml  # depends on core
└── apps/
    └── worker/pyproject.toml
```

### Root configuration

```toml
# repo/pyproject.toml
[tool.uv.workspace]
members = ["packages/*", "apps/*"]
exclude = ["packages/_scratch"]

[tool.uv.sources]
core = { workspace = true }     # resolve `core` from the workspace, not an index
```

Member `api` declares `dependencies = ["core"]`; `tool.uv.sources` (root or
member) maps it to the in-tree package. Run commands against a member with
`--package`:

```bash
uv sync                          # sync the whole workspace
uv run --package api pytest      # run within member `api`'s context
uv add --package api httpx       # add a dep to member `api`
uv lock                          # one resolution for all members
```

When to use a workspace vs separate repos: use a workspace when packages release
and version together and you want one consistent dependency set. If a package
needs an independent release cadence or conflicting dependency versions, keep it
in its own project. (Conflicting constraints across members fail the single
resolution — that is the signal to split.)

## Docker Layer Caching

Goal: cache the dependency install separately from your source so code edits do
not bust the dependency layer. Install deps from the lock *before* copying source.

```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.14-slim AS build

# Copy the uv binary from the official distroless image (pinned tag)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# 1. Dependency layer: only manifest + lock — cached until they change
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project --no-dev

# 2. Source layer: changes here do NOT re-run the dependency install above
COPY . .
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

ENV PATH="/app/.venv/bin:$PATH"
CMD ["python", "-m", "my_pkg"]
```

Key points:
- `--no-install-project` on the first sync installs only third-party deps, so the
  expensive layer is cached independently of your code.
- `--frozen` guarantees the image uses the committed lock — no surprise resolves.
- `--mount=type=cache,target=/root/.cache/uv` (BuildKit) reuses uv's download
  cache across builds.
- `UV_LINK_MODE=copy` avoids hardlink warnings across the cache mount boundary.
- `UV_COMPILE_BYTECODE=1` precompiles `.pyc` for faster container startup.
- Pin the `astral-sh/uv` image to a version tag in production rather than
  `:latest`.

For a smaller final image, build the `.venv` in a builder stage and `COPY` it
into a fresh runtime stage (multi-stage); pure-Python projects can run the
runtime stage without uv present.

## CI Pipelines

Generic shape (any CI). Install uv, restore its cache, sync frozen, run gates.

```yaml
# GitHub Actions
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python: ["3.13", "3.14", "3.14t"]   # include the free-threaded build
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v6
        with:
          enable-cache: true
          cache-dependency-glob: "uv.lock"
      - run: uv python install ${{ matrix.python }}
      - run: uv sync --frozen
      - run: uv run ruff check . --diff      # lint, no edits
      - run: uv run ruff format . --check     # format check, no edits
      - run: uv run pytest -q
```

Principles for any CI system:
- **`uv sync --frozen`** — reproducible, fails on lock drift. Add a separate
  `uv lock --check` step if you want an explicit "lock is current" gate.
- **Cache uv's download dir** keyed on `uv.lock` (`~/.cache/uv` on Linux/macOS).
  `astral-sh/setup-uv` does this with `enable-cache`; on other systems cache the
  path from `uv cache dir`.
- **Pin tool versions** via dependency groups + `uv run`, or `uvx --from "tool==X"`,
  so CI and local agree.
- **Matrix free-threaded** by adding `3.14t` — it surfaces C-extension and
  thread-safety issues the standard build hides.
- Mixed C/C++/Python repos: combine this with the build-systems CI guidance —
  [build-systems](${CLAUDE_SKILL_DIR}/tooling/build-systems/SKILL.md).

## Caching and Offline

```bash
uv cache dir                     # location of the global cache
uv cache clean                   # wipe it
uv cache prune                   # remove unused entries (CI housekeeping)
uv sync --offline                # resolve/install from cache only, no network
```

uv hardlinks from a global cache into each `.venv`, so repeated installs across
projects are near-instant and disk-cheap. Across filesystem boundaries (Docker
cache mounts, some CI volumes) set `UV_LINK_MODE=copy` to silence hardlink
warnings.

## Migration

| From | Path |
|------|------|
| `requirements.txt` | `uv add -r requirements.txt` (into pyproject), or keep using `uv pip install -r` during transition |
| pip-tools (`*.in`) | `uv pip compile in -o txt` short-term; long-term move deps into `pyproject.toml` + `uv.lock` |
| poetry | Keep `[project]` metadata; replace `[tool.poetry]` deps with `[project.dependencies]` + `[dependency-groups]`; `uv lock`; swap backend to `uv_build` or `hatchling` |
| pyenv | `uv python install` the versions; delete `.python-version` shims you no longer need and `uv python pin` instead |
| pipx | `uv tool install` the same tools; `uvx` for one-offs |

After migrating poetry, the biggest change is groups: poetry's
`[tool.poetry.group.*]` map to PEP 735 `[dependency-groups]` (dev tooling) or
`[project.optional-dependencies]` (consumer extras) — see
[packaging-and-project-structure.md](packaging-and-project-structure.md).

## Command Reference

| Command | Purpose |
|---------|---------|
| `uv init [--package] [name]` | Scaffold a project (`--package` = src/ + build-system) |
| `uv add PKG [--group G] [--optional E] [--editable] [--script F]` | Add a dependency |
| `uv remove PKG [--group G]` | Remove a dependency |
| `uv sync [--frozen] [--locked] [--no-dev] [--only-group G] [--no-install-project]` | Make `.venv` match the lock |
| `uv lock [--upgrade] [--upgrade-package P] [--check]` | Resolve / refresh / verify the lock |
| `uv run [--group G] [--with PKG] [--python V] [--no-sync] CMD` | Run inside the project env |
| `uv export --format pylock.toml -o pylock.toml` | Export the PEP 751 standard lockfile (interop/scanners) |
| `uv export --format requirements-txt` | Export the lock for legacy interop |
| `uv python install\|list\|find\|pin\|uninstall [V]` | Manage interpreters |
| `uvx [--from SPEC] [--with PKG] TOOL` | Run a tool in an ephemeral env |
| `uv tool install\|list\|upgrade\|uninstall TOOL` | Manage persistent tools |
| `uv pip install\|compile\|sync\|freeze` | pip-compatible escape hatch |
| `uv cache dir\|clean\|prune` | Manage the global cache |
| `uv build` / `uv publish` | Build / upload distributions (see packaging reference) |
| `uv self version` / `uv self update` | uv's own version / update |

Always confirm flags with `uv <cmd> --help` — uv adds and renames options between
releases; treat the table above as a map, not a spec.

## Related Skills

- [../SKILL.md](../SKILL.md) — the entry skill (two-tool rule, ruff, diagnostics)
- [packaging-and-project-structure.md](packaging-and-project-structure.md) — pyproject fields, groups, src layout, build backends, publishing
- [python-concurrency](${CLAUDE_SKILL_DIR}/python/python-concurrency/SKILL.md) — choosing the `3.14t` free-threaded build
- [build-systems](${CLAUDE_SKILL_DIR}/tooling/build-systems/SKILL.md) — uv inside mixed-language CI and monorepos
- [version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md) — Python and tool version minimums
