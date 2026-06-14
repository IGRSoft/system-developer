# Packaging and Project Structure

Use this when:

- You are filling in `pyproject.toml` metadata for a library, CLI, or application.
- You are deciding between `[dependency-groups]` (PEP 735) and `[project.optional-dependencies]`.
- You are choosing the `src/` layout and want the full rationale, not the summary.
- You are picking a build backend — `uv_build` for pure Python, hatchling for hooks, scikit-build-core for C/C++ extensions.
- You are building and publishing distributions with `uv build` / `uv publish`.
- You are choosing a versioning scheme (static, dynamic, VCS-derived).

Skip this file if:

- You only need the cheat sheet and the two-tool rule. Use [../SKILL.md](../SKILL.md).
- You need the uv command loop, workspaces, Docker, or CI. Use [uv-workflows.md](uv-workflows.md).
- You are writing the *extension code itself* (pybind11/nanobind, the C-API boundary). Use the ffi-interop skill; this file only covers how to *package* it.

Jump to:

- The One File: pyproject.toml
- Required and Common Metadata
- Dependencies, Groups, and Extras
- Entry Points and Scripts
- The src/ Layout
- Build Backends
- uv_build (pure Python)
- hatchling (hooks, flexible layout)
- scikit-build-core (native extensions)
- Building Distributions
- Publishing with uv
- Versioning
- Project Structure Patterns
- Diagnostics

This file is uv-first and modern-standards-first. setup.py / setup.cfg and
poetry-specific tables are legacy — convert them to `[project]` (PEP 621). Poetry
is not recommended for new work in this plugin; uv covers its ground.

## The One File: pyproject.toml

`pyproject.toml` is the single source of truth: project metadata (PEP 621),
dependencies, dependency groups (PEP 735), the build system (PEP 517/518), and
every tool's configuration (`[tool.ruff]`, `[tool.pyright]`, `[tool.pytest.ini_options]`,
`[tool.uv]`). No `setup.py`, no `setup.cfg`, no `requirements.txt` as the source
of intent.

```toml
[project]
name = "acme-widgets"
version = "1.2.0"
description = "Widget toolkit"
readme = "README.md"
requires-python = ">=3.14"
license = "MIT"                          # SPDX expression (PEP 639)
license-files = ["LICENSE"]
authors = [{ name = "IGRSoft", email = "support@igrsoft.com" }]
keywords = ["widgets", "cli"]
classifiers = [
    "Programming Language :: Python :: 3.14",
    "Operating System :: POSIX",
    "Operating System :: MacOS",
]
dependencies = ["httpx>=0.27", "click>=8.1"]

[project.urls]
Homepage = "https://github.com/IGRSoft/acme-widgets"
Issues = "https://github.com/IGRSoft/acme-widgets/issues"

[project.scripts]
acme = "acme_widgets.cli:main"

[dependency-groups]
dev = ["pytest>=8", "ruff", "pyright"]

[build-system]
requires = ["uv_build>=0.11,<0.12"]      # uv_build is Production/Stable (uv 0.11.x)
build-backend = "uv_build"
```

## Required and Common Metadata

| Field | Required | Notes |
|-------|----------|-------|
| `name` | Yes | Normalized per PEP 503 (case-insensitive, `-`/`_`/`.` equivalent) |
| `version` | Yes (or `dynamic`) | Static string, or list it in `dynamic = ["version"]` |
| `requires-python` | Strongly recommended | e.g. `">=3.14"` — bounds resolution; keep it in sync with `.python-version` |
| `dependencies` | As needed | PEP 508 strings; runtime only |
| `description` / `readme` | Recommended | `readme` points at a file (rendered on PyPI) |
| `license` / `license-files` | Recommended | SPDX expression + file globs (PEP 639) |
| `authors` / `maintainers` | Recommended | `[{ name, email }]` |
| `classifiers` | Recommended | Trove classifiers; do **not** set a license classifier when using SPDX `license` |
| `keywords`, `[project.urls]` | Optional | Discoverability and project links |

Applications (not published) need far less: `name`, `requires-python`,
`dependencies`, and groups — no `version` semantics, classifiers, or even a
`[build-system]` unless something installs the app itself.

## Dependencies, Groups, and Extras

Three buckets, three audiences:

| Bucket | Table | Installed by consumers? | Published in metadata? | Use for |
|--------|-------|--------------------------|------------------------|---------|
| Runtime deps | `[project.dependencies]` | Yes (always) | Yes | What the package needs to run |
| Optional extras | `[project.optional-dependencies]` | Only via `pip install pkg[extra]` | Yes (as extras) | User-facing optional features |
| Dependency groups | `[dependency-groups]` (PEP 735) | No | No | Dev/test/docs tooling, internal only |

```toml
[project.dependencies]
# (listed under [project] as `dependencies = [...]`)

[project.optional-dependencies]
redis = ["redis>=5"]          # consumers opt in: pip install acme-widgets[redis]
postgres = ["psycopg[binary]>=3"]

[dependency-groups]
dev = ["pytest>=8", "ruff", "pyright"]
docs = ["mkdocs-material"]
typecheck = ["pyright", "types-requests"]   # groups can include other groups:
all-checks = [{ include-group = "dev" }, { include-group = "typecheck" }]
```

Decision rule:
- A dependency a *user* might want → `optional-dependencies` (it becomes an
  extra they can install).
- A dependency only *you/CI* need (linters, test runners, docs builders) →
  `[dependency-groups]`. PEP 735 groups are the modern home for what poetry
  called dev groups and what people used to misfile as a `dev` extra.

`uv sync` installs the default group (`dev`) automatically; scope with
`--no-dev`, `--group docs`, `--only-group typecheck` (see
[uv-workflows.md](uv-workflows.md)).

## Entry Points and Scripts

```toml
[project.scripts]                 # console entry points (CLI commands)
acme = "acme_widgets.cli:main"    # creates an `acme` executable -> calls main()

[project.gui-scripts]             # GUI launchers (no console window on Windows)
acme-gui = "acme_widgets.gui:run"

[project.entry-points."acme.plugins"]   # plugin discovery groups
csv = "acme_widgets.plugins.csv:Plugin"
```

`project.scripts` is the modern, backend-agnostic way to ship a CLI — no
`console_scripts` in setup.py. The value is `module.path:callable`.

## The src/ Layout

```text
acme-widgets/
├── pyproject.toml
├── README.md
├── LICENSE
├── uv.lock
├── src/
│   └── acme_widgets/
│       ├── __init__.py
│       ├── py.typed          # ship this for a typed library (PEP 561)
│       ├── cli.py
│       └── core.py
└── tests/
    └── test_core.py
```

Why `src/` for anything you build or publish:

1. **Tests exercise the installed package.** With `src/`, the package is not on
   `sys.path` from the repo root, so `import acme_widgets` resolves to the wheel
   uv installed into `.venv` — the exact artifact users get. A file missing from
   the wheel fails *your* tests, not a user's runtime.
2. **No accidental shadowing.** A flat `acme_widgets/` at the root can be imported
   without installation, masking packaging mistakes and letting a same-named dir
   or stray module shadow the package.
3. **Clean boundaries.** Package code, `tests/`, `docs/`, and project files stay
   visibly separate.
4. **Editable installs still work.** `uv sync` installs the project editable into
   `.venv`; `src/` does not cost you live-edit ergonomics.

`uv init --package` scaffolds this automatically. Applications that are never
built into a distribution may stay flat, but libraries, CLIs, and extension
packages should use `src/`. Ship `py.typed` in the package dir for typed
libraries so downstream type checkers trust your inline annotations (PEP 561) —
see the python-typing skill.

## Build Backends

The build backend (PEP 517) turns the source tree into an sdist/wheel. Choose by
what you ship:

| Backend | Use when | Native code? |
|---------|----------|--------------|
| `uv_build` | Pure-Python package; want zero-config and uv-native speed | No |
| `hatchling` | Need build hooks, version-from-VCS plugins, or a non-default layout | No (via plugins, limited) |
| `scikit-build-core` | C/C++/Fortran extension modules built with CMake | Yes |
| `meson-python` | Native extensions built with Meson | Yes |
| `setuptools` | Legacy projects only; avoid for new work | Yes (clunky) |

### uv_build (pure Python)

Native uv backend: zero-config defaults, fast, validates structure, integrates
with uv's messaging. **Production/Stable** as of the uv 0.11.x line (current
**0.11.21**) — the default pure-Python backend, no longer experimental.
**Pure Python only** — it cannot compile extension modules.

```toml
[build-system]
requires = ["uv_build>=0.11,<0.12"]   # pin a bound; uv_build is stable in uv 0.11.x
build-backend = "uv_build"
```

Defaults: a single root module at `src/<package_name>/__init__.py`, with the
package name normalized (lowercased, `-`/`.` → `_`). Override layout only if you
must:

```toml
[tool.uv.build-backend]
module-name = "acme_widgets"     # explicit module name
module-root = "src"              # default; set "" for a root-level module
```

The `uv` executable bundles a copy of the backend, so `uv build` is fast; other
frontends (`python -m build`, pip) pull the published `uv_build` package. Keep
the upper bound (`<0.12`) so a future backend release cannot silently change how
your package builds.

### hatchling (hooks, flexible layout)

Reach for hatchling when you need build-time hooks, VCS-derived versions, or a
layout `uv_build` will not express. Still pure Python (extension support is
limited).

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/acme_widgets"]

[tool.hatch.version]
source = "vcs"                   # version from git tags (needs hatch-vcs)
```

### scikit-build-core (native extensions)

For C/C++ extension modules built with **CMake**, use scikit-build-core. This is
the recommended path for packaging C-API/pybind11/nanobind extensions — it drives
your `CMakeLists.txt`, produces wheels per platform, and works with `uv build`.

```toml
[build-system]
requires = ["scikit-build-core>=0.10"]
build-backend = "scikit_build_core.build"

[tool.scikit-build]
minimum-version = "build-system.requires"
cmake.version = ">=3.23"
wheel.packages = ["src/acme_ext"]
```

```text
acme-ext/
├── pyproject.toml
├── CMakeLists.txt          # builds the extension; installs into the package
└── src/
    └── acme_ext/
        ├── __init__.py
        └── _core.cpp       # the C/C++ extension source
```

For the extension *code* (binding API choice, GIL release, the `extern "C"`
boundary, free-threaded `cp314t` builds): the ffi-interop skill. For CMake
itself: [build-systems](${CLAUDE_SKILL_DIR}/tooling/build-systems/SKILL.md).
Pure-Python projects never need a native backend — stay on `uv_build`.

## Building Distributions

```bash
uv build                         # build sdist (.tar.gz) + wheel (.whl) into dist/
uv build --sdist                 # source distribution only
uv build --wheel                 # wheel only
uv build --package api           # build a specific workspace member
```

Always ship both an sdist and a wheel: the wheel for fast installs, the sdist so
consumers (and platforms without a matching wheel) can build from source. uv
uses the bundled backend when compatible, otherwise installs the backend from
`[build-system].requires`.

Inspect before publishing:

```bash
python -m tarfile -l dist/acme_widgets-1.2.0.tar.gz   # what's in the sdist
unzip -l dist/acme_widgets-1.2.0-py3-none-any.whl     # what's in the wheel
uvx twine check dist/*                                  # metadata sanity check
```

The wheel-content check catches the classic flat-layout bug: a data file or
submodule that exists in the repo but never made it into the wheel.

## Publishing with uv

```bash
uv publish                       # upload dist/* to PyPI
uv publish --index testpypi      # to an alternate index (configured below)
```

Authentication (in order of preference):
- **Trusted Publishing (OIDC)** in CI — no long-lived token. GitHub Actions can
  mint a short-lived credential; configure the publisher on PyPI and uv detects
  it. Preferred for releases.
- **API token** for local/manual: `UV_PUBLISH_TOKEN` env var, or
  `uv publish --token "$PYPI_TOKEN"`. Never commit tokens.

Configure alternate indexes in `pyproject.toml`:

```toml
[[tool.uv.index]]
name = "testpypi"
url = "https://test.pypi.org/simple/"
publish-url = "https://test.pypi.org/legacy/"
```

Release flow: bump `version` → `uv build` → `uvx twine check dist/*` → publish to
TestPyPI → verify install → `uv publish` to PyPI → tag. Do release uploads from
CI with Trusted Publishing where possible.

## Versioning

| Scheme | How | Use when |
|--------|-----|----------|
| Static | `version = "1.2.0"` in `[project]` | Default; simplest, explicit, reviewable in diffs |
| Dynamic from file/attr | `dynamic = ["version"]` + backend config | Single source already exists in code |
| VCS-derived | hatch-vcs / scikit-build-core SCM | Version = git tag; no manual bumps |

```toml
# Static (recommended default):
[project]
version = "1.2.0"

# Dynamic, read from the package (hatchling example):
[project]
dynamic = ["version"]
[tool.hatch.version]
path = "src/acme_widgets/__init__.py"   # reads __version__ = "1.2.0"
```

Follow semantic versioning for libraries (MAJOR.MINOR.PATCH; breaking → MAJOR).
Keep `requires-python` honest — raising the floor is a MINOR/MAJOR-worthy change
for consumers. Static versioning is the default in this plugin: it shows up in
diffs and review, and pairs with a tag-on-merge release step. Reach for VCS
versioning only when you have automation that tags reliably.

## Project Structure Patterns

### Library / CLI (publishable)

```text
pkg/
├── pyproject.toml      # [project] + [dependency-groups] + [build-system]
├── uv.lock
├── README.md  LICENSE
├── src/<pkg>/{__init__.py, py.typed, ...}
└── tests/
```

### Application / service (not published)

```text
app/
├── pyproject.toml      # [project] (name, requires-python, deps) + [dependency-groups]
├── uv.lock             # committed for reproducible deploys
├── src/<app>/ or app/  # src/ recommended; flat acceptable
└── tests/
```

### Multi-package monorepo

Use a uv **workspace** (one root `uv.lock`, members under `packages/*`) — see
[uv-workflows.md](uv-workflows.md) § Workspaces. Each member is a normal package
with its own `pyproject.toml`; `[tool.uv.sources]` wires in-tree dependencies.

### Module organization (inside the package)

- One concept per file; split when a file mixes unrelated responsibilities or
  grows past a few hundred lines.
- Declare the public surface with `__all__` in `__init__.py`; everything
  unlisted is internal.
- Prefer absolute imports (`from acme_widgets.core import Widget`) over
  deep relative chains.
- Add depth only for genuine sub-domains; flat beats nested for navigation.

## Diagnostics

| Symptom | Cause | Fix |
|---------|-------|-----|
| `error: Project ... does not have a build system` on `uv build`/editable install | Library missing `[build-system]` | Add `uv_build` (pure Python) or the right native backend |
| Import works locally, `ModuleNotFoundError` after `pip install` | Flat layout; tested against repo, not wheel | Move to `src/`; check wheel contents with `unzip -l` |
| Data file missing at runtime in the installed package | Not included by the backend | `uv_build`: keep data under the module root; or use backend `data`/include config |
| `dev` extra installed by a downstream consumer | Dev tooling in `optional-dependencies` | Move it to `[dependency-groups]` (PEP 735) |
| `uv build` cannot compile a `.c`/`.cpp` file | `uv_build` is pure-Python only | Switch to `scikit-build-core` (CMake) or `meson-python` |
| `twine check` warns about long_description / metadata | `readme` misconfigured or unsupported markup | Point `readme` at a real file; use a supported content type |
| Two packages disagree on a transitive version in a monorepo | Conflicting constraints in one workspace resolution | Reconcile constraints, or split the package into its own project |
| License classifier vs SPDX warning | Both a `License ::` classifier and SPDX `license` set | Drop the classifier; keep SPDX `license` + `license-files` (PEP 639) |
| Type checker ignores your library's annotations downstream | No `py.typed` shipped | Add `src/<pkg>/py.typed` and ensure the backend packages it (PEP 561) |
| Editable install does not pick up new submodule | Backend not re-scanning | Re-run `uv sync`; for `src/` ensure the module is under `module-root` |

## Related Skills

- [../SKILL.md](../SKILL.md) — entry skill (two-tool rule, ruff, pyproject summary)
- [uv-workflows.md](uv-workflows.md) — commands, workspaces, lockfile policy, Docker, CI, publishing flow context
- [python-typing](${CLAUDE_SKILL_DIR}/python/python-typing/SKILL.md) — `py.typed`, `.pyi` stubs, checker config in pyproject
- [ffi-interop](${CLAUDE_SKILL_DIR}/tooling/ffi-interop/SKILL.md) — writing the C-extension code that scikit-build-core packages
- [build-systems](${CLAUDE_SKILL_DIR}/tooling/build-systems/SKILL.md) — CMake driving native extension builds
- [version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md) — Python and tool version minimums
