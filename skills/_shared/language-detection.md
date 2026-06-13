---
name: language-detection
description: Shared marker-to-language-to-agent routing table for system-developer commands and the router agent. Reference when deciding which language agent owns a file, directory, or repository.
---

# Language Detection & Agent Routing

Single source of truth for the marker → language → agent mapping used by `system-developer` (router), `igrsoft:developer`, and every command that scopes work per language. Keep command-local detection logic in sync with this file — do not fork the table.

## Detection Priority Order

Evaluate top-down; the first matching tier wins. Within a tier, apply the tie-breaking rules below.

| Priority | Signal | Why it ranks here |
|----------|--------|-------------------|
| 1 | Explicit user statement ("this is a C project", `--language` flag) | User intent overrides inference |
| 2 | Build-system manifests (`CMakeLists.txt`, `meson.build`, `pyproject.toml`, `configure.ac`, …) | Declares the toolchain authoritatively |
| 3 | Lockfiles / package manifests (`uv.lock`, `vcpkg.json`, `conanfile.*`) | Pins the ecosystem |
| 4 | Extension census of tracked source files | Reflects actual code volume |
| 5 | Shebangs (`#!/usr/bin/env bash`, `#!/usr/bin/env python3`) | Last resort for extensionless scripts |

## Marker → Language → Agent Table

| Marker(s) | Language | Agent |
|-----------|----------|-------|
| `CMakeLists.txt`, `CMakePresets.json`, `meson.build`, `vcpkg.json`, `conanfile.txt` / `conanfile.py` | C++ (default; see tie-break 1 for C-only trees) | `system-developer:cpp-developer` |
| Pure `.c`/`.h` tree + `Makefile` / `configure.ac` / `Makefile.am` (no C++ sources) | C | `system-developer:c-developer` |
| `pyproject.toml`, `uv.lock`, `setup.py`, `requirements*.txt`, `*.py` | Python | `system-developer:python-developer` |
| `*.sh`, `*.bash`, `*.bats`, `.shellcheckrc` | Bash / POSIX shell | `system-developer:bash-developer` |
| Mixed markers across tiers (e.g. `CMakeLists.txt` + `pyproject.toml`) | Cross-language | `system-developer:system-developer` (router; handles FFI, C extensions, mixed repos directly) |

File-level extension map (for per-file routing inside a mixed repo):

| Extension | Agent |
|-----------|-------|
| `.c` | `c-developer` |
| `.cpp`, `.cc`, `.cxx`, `.hpp`, `.hh`, `.ixx` | `cpp-developer` |
| `.h` | Ambiguous — see tie-break 2 |
| `.py`, `.pyi` | `python-developer` |
| `.sh`, `.bash`, `.bats` | `bash-developer` |

## Tie-Breaking Rules

1. **CMake/Meson with C-only sources → c-developer.** A `CMakeLists.txt` whose targets contain only `.c`/`.h` files (e.g. `project(x C)`) is a C project. Any `.cpp`/`.cc`/`.cxx`/`.hpp` source, `project(x CXX)`, or `CMAKE_CXX_STANDARD` flips it to `cpp-developer`.
2. **Bare `.h` headers count as C** unless the tree has C++ markers (C++ sources, `extern "C"` guards wrapping a C++ build, `CMAKE_CXX_STANDARD`). When a `.h` is included from both languages, route the change to the agent owning the consuming target; cross-boundary API changes go to the router.
3. **Auxiliary scripts do not flip the project.** `scripts/*.sh` or a `Makefile` wrapper in a C++/Python repo does not make it a Bash project — route by the dominant build manifest; route edits *to those scripts* to `bash-developer`.
4. **Python with native extensions → router.** `pyproject.toml` plus C/C++ extension sources (`CMakeLists.txt`, `setup.py` with `ext_modules`, scikit-build-core/pybind11/nanobind config) is FFI territory: `system-developer:system-developer` coordinates, delegating per-file work to the language agents.
5. **`Makefile` is not a language marker by itself.** Classify by what it builds: C sources → `c-developer`; C++ → `cpp-developer`; only shell/phony targets → treat as repo tooling (rule 3).
6. **Lockfile beats stray files.** One `tools/helper.py` in a `vcpkg.json` repo does not make it a Python project; `uv.lock` outranks a vendored `*.c` file.
7. **Still ambiguous → router.** When two tiers conflict irreconcilably (e.g. equal C++ and Python volume, no dominant manifest), dispatch `system-developer:system-developer` and let it split the work.

## Census Snippet

When manifests are absent, count tracked sources (never `node_modules`, `build/`, `.venv/`, vendored dirs):

```bash
git ls-files | grep -E '\.(c|cc|cpp|cxx|h|hpp|py|sh|bash|bats)$' \
  | sed 's/.*\.//' | sort | uniq -c | sort -rn
```

Route to the dominant language's agent if it holds >70% of source files; otherwise use the router.

## Related Skills

- `workflow-integration/SKILL.md` — how the routed agent participates in DV
- `model-selection.md` — model/effort to pass with the routed `Task()` call
- `version-feature-matrix.md` — standard/version floors once the language is known
