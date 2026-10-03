---
name: python-tooling
description: >-
  Python project tooling: uv for environments, dependencies, lockfiles, Python
  installs, and uvx, plus ruff as linter and formatter, with pyproject.toml as
  the one source of truth. Use when starting a Python project, configuring
  uv or ruff, managing dependencies and lockfiles, installing interpreters
  (including free-threaded 3.14t), wiring CI with uv sync --locked, or laying
  out a src/ project.
---

# Python Tooling (uv + ruff)

## The Two-Tool Rule

| Job | Tool | Replaces |
|-----|------|----------|
| Env + deps + Python install + run | uv | pip, pip-tools, virtualenv, pyenv, poetry, pipx |
| Lint + import-sort + format | ruff | flake8, isort, black, pyupgrade, autoflake |
| Type checking (CI gate) | pyright or mypy (see python-typing) | — |
| Type checking (fast, report-only) | `ty` (Astral) / `pyrefly` (Meta), via `uvx ty check` / `uvx pyrefly check` | — |

Pin ruff (and the type checker) in a dependency group so `uv.lock` carries their exact versions. pyright or mypy stays the gate; ty and pyrefly run alongside it from the editor or pre-commit.

## uv: Core Commands

```bash
uv init my-pkg --package        # src/ layout + build-system (library/CLI)
uv init my-app                  # application layout (no build-system needed)
uv add httpx "pydantic>=2"      # add runtime deps, update pyproject + lock + venv
uv add --group dev pytest ruff  # add to a PEP 735 dependency group
uv remove httpx                 # drop a dep, re-resolve
uv run pytest                   # run in the project env (auto-syncs first)
uv sync                         # make .venv match the lockfile exactly
uv lock                         # resolve and write uv.lock (no install)
uv lock --upgrade-package httpx # bump one dependency
```

`uv run` and `uv sync` resolve and install as needed, so you rarely activate `.venv`. `uv pip` exists for migration and scripts without project files; the project interface (`add`/`sync`/`run`) is the default.

## Python Version Management

```bash
uv python install 3.14          # standard build
uv python install 3.14t         # free-threaded build (PEP 779; separate binary)
uv python list                  # installed + discoverable versions
uv python pin 3.14              # write .python-version for this project
```

`3.14t` is the free-threaded (no-GIL) interpreter, a distinct binary from `3.14`, not a flag. Pin it explicitly when needed (`requires-python` plus `uv python pin 3.14t`); python-concurrency covers when to choose it. Version minimums: [version-feature-matrix](../../_shared/version-feature-matrix.md).

## uvx: Run a Tool Without Installing

```bash
uvx ruff check .                         # ephemeral, cached env
uvx --from "ruff==0.14.*" ruff check .   # pin the tool version
uv tool install ruff                     # persistent user-level install (PATH shim)
```

`uvx` for one-off or CI runs, `uv tool install` for tools you want on `PATH` across projects. Neither touches the project's dependency tree.

## Lockfiles

- Commit `uv.lock` for applications. Libraries publish loose constraints and may still commit the lock for reproducible dev (see the packaging reference).
- CI runs `uv sync --locked`: it fails if `pyproject.toml` drifted from `uv.lock`. `--frozen` installs the lock without checking it, so drift passes silently; use it only where the lock is known current (e.g. Docker layers).
- Upgrade deliberately with `uv lock --upgrade` or `--upgrade-package NAME`, then review the diff.

```bash
uv sync --locked                # CI: reproducible, fails on lock drift
uv lock --check                 # CI guard: assert lock is current, no writes
```

`uv.lock` is uv's own format; PEP 751 `pylock.toml` is the interoperable standard. Keep `uv.lock` authoritative and export the others for non-uv tools and scanners (see `/system-developer:deps`):

```bash
uv export --format pylock.toml -o pylock.toml
uv export --format requirements-txt -o requirements.txt   # legacy interop
```

## ruff: Lint + Format

`ruff check` lints (`--fix` to autofix); `ruff format` formats (black-compatible). Starter config:

```toml
[tool.ruff]
target-version = "py314"
line-length = 88
src = ["src", "tests"]

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B", "SIM"]
# E pycodestyle · F pyflakes · I import sort · UP pyupgrade · B bugbear · SIM simplify
```

### Commands and CI

```bash
ruff check . --fix              # lint and autofix
ruff format .                   # format
ruff check .                    # CI: fail on any violation
ruff format . --check           # CI: fail if unformatted
```

Don't gate CI on `ruff check --diff`: it implies `--fix-only`, so unfixable violations pass.

Add rule families (`RUF`, `C4`, `PTH`, `A`, `PT`) once the starter set is clean. `UP` with `target-version` drives modernization (see `/system-developer:fix-modernize` and modern-python). For a modernization-only pass, `../scripts/ruff_modernize.sh [--fix]` runs `UP,B,SIM,C4,PIE,RUF` at a target version without touching the project config.

## pyproject.toml: Single Source of Truth

One file holds metadata, dependencies, groups, and every tool's config. Scaffold it rather than hand-writing:

```bash
../scripts/scaffold_pyproject.sh --package my-pkg                    # library/CLI: src layout + uv_build backend
../scripts/scaffold_pyproject.sh --app my-svc --python-version 3.12  # application, no [build-system]
```

It emits `[project]`, PEP 735 `[dependency-groups]`, the `[tool.ruff]` config, and for `--package` the `uv_build` `[build-system]` (the stable default pure-Python backend).

Use `[dependency-groups]` for dev/test/docs tooling: groups are not published and downstream consumers can't install them. Keep `[project.optional-dependencies]` for real user-facing extras (`pip install my-pkg[redis]`). `uv sync` installs the default groups; `--no-dev` / `--only-group docs` scope them.

## src/ Layout

`uv init --package` scaffolds `src/<pkg>/`, which keeps the checkout root off `sys.path`:

- Tests import the installed package, not loose files; testing the built wheel in CI then catches files missing from it.
- A same-named top-level dir or stray module can't shadow the package.

Applications (`uv init`) can stay flat; anything you build or publish should use `src/`.

## Diagnostics

### Lockfile and interpreter

| Error | Cause | Fix |
|-------|-------|-----|
| `The lockfile at uv.lock needs to be updated, but --locked was provided` | `pyproject.toml` changed without re-locking | Run `uv lock`, commit `uv.lock`; CI must not edit it |
| `No interpreter found for Python 3.14t` | Free-threaded build not installed | `uv python install 3.14t` (distinct from `3.14`) |
| Tool deps leak into project lock | Tool installed via `uv add` | Use `uvx` / `uv tool install` |

### Lint and packaging

| Error | Cause | Fix |
|-------|-------|-----|
| ruff and black disagree on formatting | Both formatters configured | Remove black; `ruff format` is the formatter |
| `ruff check` passes locally, fails in CI | Different ruff versions | Pin ruff in `[dependency-groups]`; CI runs `uv run ruff` or `uvx --from "ruff==X"` |
| `Failed to build editable ...` on `uv sync` | Library missing `[build-system]` | Add `uv_build` (pure Python) or a native backend |
| Dev extra published to PyPI | Dev tooling in `optional-dependencies` | Move to `[dependency-groups]` |
| Tests pass locally, fail after install (missing data file) | Flat layout hid a packaging gap | Move to `src/`; check the wheel contents |

## References

| File | Read it for |
|---|---|
| [references/uv-workflows.md](references/uv-workflows.md) | sync/lock/run semantics, lockfile policy, workspaces, tools, interpreters and free-threaded builds, Docker caching, CI, migration |
| [references/packaging-and-project-structure.md](references/packaging-and-project-structure.md) | `pyproject.toml` fields, groups vs extras, `src/` layout, build backends (`uv_build`, hatchling, scikit-build-core), `uv build` / `uv publish`, versioning |

## Related Skills

| Skill | For |
|---|---|
| [modern-python](../modern-python/SKILL.md) | Language features `UP` modernizes toward |
| [python-typing](../python-typing/SKILL.md) | pyright/mypy config in the same pyproject and CI |
| [python-testing](../python-testing/SKILL.md) | `uv run pytest`, test dependency groups |
| [python-concurrency](../python-concurrency/SKILL.md) | When to choose the `3.14t` build |
| [build-systems](../../tooling/build-systems/SKILL.md) | uv in mixed C/C++/Python repos and CI |
| [ffi-interop](../../tooling/ffi-interop/SKILL.md) | scikit-build-core packaging for C extensions |
