---
name: python-tooling
description: >-
  Python project tooling with uv as the single tool (init/add/run/sync/lock,
  Python version management, uvx) plus ruff as linter and formatter, with
  pyproject.toml as the one source of truth. Use when starting a Python
  project, choosing or configuring uv/ruff, managing dependencies and
  lockfiles, installing Python interpreters (including free-threaded 3.14t),
  wiring CI with uv sync --frozen, or laying out a src/ project.
---

# Python Tooling (uv + ruff)

**One tool for environments, dependencies, and Python itself; one linter that also formats**

## When to Use

Use this skill when:
- Bootstrapping a new Python project or adopting tooling for an existing one
- Adding, removing, locking, or syncing dependencies
- Installing or pinning a Python interpreter (standard or free-threaded 3.14t)
- Choosing and configuring ruff (lint + format) and wiring it into CI
- Deciding `src/` vs flat layout, or where `[dependency-groups]` belong
- Running a tool once without installing it (`uvx`)

Routing: deep CLI workflows (workspaces, Docker, CI matrices) →
[references/uv-workflows.md](references/uv-workflows.md); packaging, build
backends, and publishing → [references/packaging-and-project-structure.md](references/packaging-and-project-structure.md).

## The Two-Tool Rule

| Job | Tool | Do not use |
|-----|------|------------|
| Env + deps + Python install + run | **uv** | pip, pip-tools, virtualenv, pyenv, poetry, pipx |
| Lint + import-sort + format | **ruff** | flake8, isort, black, pyupgrade, autoflake |
| Type checking (CI gate) | pyright or mypy (see python-typing) | — |
| Type checking (emerging, fast) | `ty` (Astral, beta) / `pyrefly` (Meta, stable v1.0) — report-only alongside the gate | — |

uv replaces the whole pip/pyenv/pipx/poetry stack; ruff replaces the
flake8/isort/black/pyupgrade stack. Two binaries, no plugin zoo. Pin both in
the project — version-independent of CPython within 3.12–3.14 (verify against
your toolchain) — and let `uv.lock` carry their exact versions.

For type checking, **pyright or mypy remains the gate** (see python-typing); the
Rust newcomers `ty` (Astral, beta — v0.0.49, no stable API) and `pyrefly` (Meta,
stable v1.0) are fast report-only additions you run from the editor or
pre-commit, not yet the gate. `uvx ty check` / `uvx pyrefly check` run either
ephemerally without polluting the project.

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

`uv run` and `uv sync` resolve and install transparently — you rarely activate
`.venv` or call `uv pip` by hand. The `uv pip` interface exists for migration
and scripts; the project interface (`add`/`sync`/`run`) is the default.

## Python Version Management

uv installs and selects interpreters — no system Python, no pyenv.

```bash
uv python install 3.14          # standard build
uv python install 3.14t         # free-threaded build (PEP 779; separate binary)
uv python list                  # show installed + discoverable versions
uv python pin 3.14              # write .python-version for this project
```

`3.14t` is the **free-threaded** interpreter (no GIL); it is a distinct binary
from `3.14`, not a flag. Pin it explicitly when you need it
(`requires-python` plus `uv python pin 3.14t`). For when to choose it, see the
python-concurrency skill. Standard/version minimums:
[version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md).

## uvx: Run a Tool Without Installing

```bash
uvx ruff check .                # ephemeral, cached env — no project pollution
uvx --from "ruff==0.14.*" ruff check .   # pin the tool version
uv tool install ruff            # persistent user-level install (PATH shim)
```

Use `uvx` for one-off or CI tool runs; use `uv tool install` for tools you want
on `PATH` across projects. Tools never touch the project's dependency tree.

## Lockfiles: Commit and Freeze

- **Commit `uv.lock`** for applications and end products. (Libraries publish
  loose constraints and may still commit the lock for reproducible dev — see
  [references/packaging-and-project-structure.md](references/packaging-and-project-structure.md).)
- **CI uses `uv sync --frozen`** — it installs exactly the lock and errors if
  `pyproject.toml` drifted from `uv.lock` instead of silently re-resolving.
- Regenerate deliberately: `uv lock --upgrade` (all) or `--upgrade-package NAME`
  (one), then review the diff.

```bash
uv sync --frozen                # CI: reproducible, fails on lock drift
uv lock --check                 # CI guard: assert lock is current, no writes
```

**`uv.lock` is uv's own format; `pylock.toml` is the standard.** PEP 751 (final)
defines `pylock.toml` — a standardized, tool-interoperable lockfile. Keep
`uv.lock` as the authoritative project lock, and **export** `pylock.toml` when
another tool or a scanner needs the standard format:

```bash
uv export --format pylock.toml -o pylock.toml   # PEP 751 standard, for interop
uv export --format requirements-txt -o requirements.txt   # legacy interop
```

Commit `uv.lock`; generate `pylock.toml` on demand (or in CI) for cross-tool
consumers and supply-chain scanners — see the `/system-developer:deps` command.

## ruff: Lint + Format

ruff is both the linter and the formatter. Run `ruff check` (lint, `--fix` to
autofix) and `ruff format` (black-compatible formatting). Starter config in the
single `pyproject.toml`:

```toml
[tool.ruff]
target-version = "py314"
line-length = 88
src = ["src", "tests"]

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B", "SIM"]
# E/F pyflakes+pycodestyle · I import sort (replaces isort)
# UP pyupgrade (modernize syntax) · B bugbear · SIM simplify
```

```bash
ruff check . --fix              # lint and autofix
ruff format .                   # format (replaces black)
ruff check . --diff             # CI: show would-be fixes, no writes
ruff format . --check           # CI: fail if unformatted
```

Add rule families incrementally (`RUF`, `C4`, `PTH`, `A`, `PT`) once the starter
set is clean. `UP` with `target-version = "py314"` drives modernization (see the
`/system-developer:fix-modernize` command and the modern-python skill). For a modernization-only
pass, `../scripts/ruff_modernize.sh [--fix]` runs the `UP,B,SIM,C4,PIE,RUF` set at
a target version without touching the project config.

## pyproject.toml: Single Source of Truth

One file holds metadata, dependencies, groups, and every tool's config. Scaffold a
correct starting point with `../scripts/scaffold_pyproject.sh` rather than hand-writing
it:

```bash
../scripts/scaffold_pyproject.sh --package my-pkg                  # library/CLI: src layout + uv_build backend
../scripts/scaffold_pyproject.sh --app my-svc --python-version 3.12  # application, no [build-system]
```

It emits `[project]`, PEP 735 `[dependency-groups]` (dev-only, never published), the
`[tool.ruff]` config, and — for `--package` — the `uv_build` `[build-system]`; then edit
metadata and add deps.

The `uv_build` backend is **Production/Stable** as of the uv 0.11.x line (current
**0.11.21**) — it is the default pure-Python backend, no longer experimental.

**`[dependency-groups]` (PEP 735) over `[project.optional-dependencies]`** for
dev/test/docs tooling: groups are not published as extras and not installable by
downstream consumers. Keep optional-dependencies for genuine user-facing extras
(`pip install my-pkg[redis]`). `uv add --group dev X` manages groups; `uv sync`
installs the default groups, `--no-dev` / `--only-group docs` scope them.

## src/ Layout: Why

`uv init --package` scaffolds `src/<pkg>/`. The `src/` layout puts an import
barrier between your checkout root and the installed package:

- Tests import the **installed** package, not loose files on `sys.path` — the
  same code CI and users get; catches missing-from-wheel files early.
- No accidental shadowing by a same-named top-level dir or stray module.
- Clean separation of package, `tests/`, and project files.

Applications (`uv init`, no `--package`) can stay flat; libraries and anything
you build/publish should use `src/`. Full rationale and the build-backend choice
(`uv_build` pure-Python vs hatchling vs native): [references/packaging-and-project-structure.md](references/packaging-and-project-structure.md).

## Diagnostics

| Error | Cause | Fix | Reference |
|-------|-------|-----|-----------|
| `error: The lockfile ... is not up to date` (under `--frozen`) | `pyproject.toml` changed without re-locking | Run `uv lock`, commit `uv.lock`; CI must not edit | [uv-workflows.md](references/uv-workflows.md) § ci |
| `error: No interpreter found for Python 3.14t` | Free-threaded build not installed | `uv python install 3.14t` (distinct from `3.14`) | this file, Python Version Management |
| `uv run` reinstalls every invocation | No lockfile, or `--no-sync` misuse | `uv lock` once; let `uv run` reuse the synced env | [uv-workflows.md](references/uv-workflows.md) § projects |
| ruff and black disagree on formatting | Both formatters configured | Remove black; `ruff format` is the formatter | this file, ruff |
| `ruff check` passes locally, fails in CI | CI pinned a different ruff | Pin ruff in `[dependency-groups]`; CI runs `uvx --from ...` or `uv run ruff` | this file, uvx |
| `Failed to build editable ...` on `uv sync` | Library missing `[build-system]` | Add `uv_build` (pure Python) or a native backend | [packaging-and-project-structure.md](references/packaging-and-project-structure.md) § backends |
| Tool deps leak into project lock | Installed a tool via `uv add` | Use `uvx`/`uv tool install`; keep tools out of deps | this file, uvx |
| `optional-dependencies` dev extra published to PyPI | Dev tooling in the wrong table | Move to `[dependency-groups]` (PEP 735) | this file, pyproject |
| Tests pass locally, fail after install (missing data file) | Flat layout hid a packaging gap | Move to `src/`; verify the wheel contents | [packaging-and-project-structure.md](references/packaging-and-project-structure.md) § src |

## Deep-Dive References

- [references/uv-workflows.md](references/uv-workflows.md) — projects and the
  sync/lock/run loop, lockfile policy, workspaces/monorepos, tool management,
  Python version management (incl. free-threaded builds), Docker layer caching,
  CI pipelines
- [references/packaging-and-project-structure.md](references/packaging-and-project-structure.md)
  — `pyproject.toml` fields, dependency groups vs extras, the `src/` layout,
  build backends (`uv_build`, hatchling, scikit-build-core for native),
  `uv build` / `uv publish`, versioning

## Related Skills

- [modern-python](../modern-python/SKILL.md) — language features `UP` targets modernize toward
- [python-typing](../python-typing/SKILL.md) — wiring pyright/mypy into the same pyproject and CI
- [python-testing](../python-testing/SKILL.md) — `uv run pytest`, test dependency groups
- [python-concurrency](../python-concurrency/SKILL.md) — when to choose the `3.14t` free-threaded build
- [build-systems](${CLAUDE_SKILL_DIR}/tooling/build-systems/SKILL.md) — uv in mixed C/C++/Python repos and CI
- [ffi-interop](${CLAUDE_SKILL_DIR}/tooling/ffi-interop/SKILL.md) — scikit-build-core packaging for C extensions
- [version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md) — Python/tool version minimums
