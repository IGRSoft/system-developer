# Package Managers Reference

Use this when:

- You are choosing how to provide dependencies to a build (FetchContent / vcpkg / Conan / uv).
- You hit `Could NOT find <Pkg>` and need to diagnose which layer failed.
- You are deciding between in-tree vendoring and a versioned package manager.

Skip if:

- You need the full CMake recipes for each — those are in
  [cmake-modern.md](cmake-modern.md) (FetchContent / vcpkg / Conan sections).
- The failure is a link error after the package *was* found — see
  [build-systems SKILL.md](../SKILL.md) > Linking Diagnostics.

Jump to:

- Selection Table
- FetchContent
- vcpkg (manifest mode)
- Conan 2.29
- uv (Python)
- "Could NOT find &lt;Pkg&gt;" Diagnosis

---

## Selection Table

| Manager | Best for | Lockfile / pin | Binary cache | Integrates via |
|---------|----------|----------------|--------------|----------------|
| **FetchContent** | A few deps, in-tree vendoring, simplest setup | `GIT_TAG` pin (manual) | No (rebuilds from source) | CMake built-in |
| **vcpkg** (manifest, **GA**) | Cross-platform, broad catalog, binary caching | `vcpkg.json` + `builtin-baseline` | Yes | CMake toolchain file |
| **Conan 2.29** | Versioned packages, profiles, enterprise/multi-config | `conan.lock` (v2) | Yes | `CMakeConfigDeps` + toolchain |
| **uv** | Python-only dependencies | `uv.lock` / `pylock.toml` | Yes (wheel cache) | not a C/C++ build dep manager |

Decision flow:

```
C/C++ dependency?
├── Just a few, want zero extra tooling → FetchContent
├── Cross-platform, want a big catalog + binary cache → vcpkg (manifest)
└── Need versioned packages, profiles, lockfile-pinned graphs → Conan 2.29
Python dependency (no native build) → uv
```

Pick **one** per project and stay consistent. Mixing FetchContent and a package manager
for the same dependency leads to duplicate/conflicting targets.

---

## FetchContent

CMake-native, no external tool, no separate lockfile. Best when you have a small number of
dependencies and want the simplest possible setup.

```cmake
include(FetchContent)
FetchContent_Declare(fmt
  GIT_REPOSITORY https://github.com/fmtlib/fmt.git
  GIT_TAG        11.0.2)          # pin a tag/commit — never a branch
FetchContent_MakeAvailable(fmt)
target_link_libraries(app PRIVATE fmt::fmt)
```

- No binary cache: each clean build recompiles every dependency from source.
- The "lockfile" is your pinned `GIT_TAG`; keep it a tag or commit SHA.
- Good first choice; graduate to vcpkg/Conan when dependency count or CI build time grows.

---

## vcpkg (manifest mode)

Manifest mode is **GA** and the default. List dependencies in `vcpkg.json`; vcpkg resolves
and (binary-)caches them, integrating through the toolchain file.

```json
{
  "name": "app",
  "version": "0.1.0",
  "dependencies": [ "fmt", "spdlog" ],
  "builtin-baseline": "<vcpkg-repo-commit-sha>",
  "overrides": [ { "name": "fmt", "version": "11.0.2" } ]
}
```

```bash
cmake -S . -B build \
  -DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake
cmake --build build
```

- `builtin-baseline` pins the catalog snapshot (reproducibility); `overrides` pins exact
  versions of individual ports.
- Manifest mode installs into the build tree at configure time — no global `vcpkg install`.
- Consume with `find_package(<Pkg> CONFIG REQUIRED)`.

---

## Conan 2.29

Conan 2.x is the only supported line. Use the **`CMakeConfigDeps`** generator (it replaces
`CMakeDeps` from earlier Conan 2 releases).

```ini
# conanfile.txt
[requires]
fmt/11.0.2

[generators]
CMakeConfigDeps
CMakeToolchain
```

```bash
conan install . --output-folder=build --build=missing -pr:h=default -pr:b=default
cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE=build/conan_toolchain.cmake
cmake --build build
```

- **Profiles** (`-pr:h` host / `-pr:b` build) capture compiler/arch/build-type — check
  them in for reproducible CI.
- **Lockfiles** (v2): `conan lock create .` pins the full dependency graph; reproduce with
  `conan install --lockfile=conan.lock`.
- `--build=missing` builds from source only what has no matching binary in the cache.

---

## uv (Python)

uv is the Python project/dependency tool — not a C/C++ build dependency manager. It
manages the Python environment and lockfiles; a *native* extension still builds through
CMake/Meson (see [ffi-interop](../../ffi-interop/SKILL.md)).

```bash
uv add requests                    # add a dependency, update uv.lock
uv sync                            # install from the lockfile
uv export --format pylock.toml     # PEP 751 interop lockfile (for scanners/other tools)
```

- `uv.lock` is uv's native lockfile; `pylock.toml` (PEP 751, final) is the standardized,
  tool-interoperable export format.
- Reach here only for Python-side dependencies; C/C++ deps of a native extension go
  through one of the three managers above.

---

## "Could NOT find &lt;Pkg&gt;" Diagnosis

`find_package` failure means CMake's search did not locate a config or module for the
package. Diagnose by layer:

| Cause | Symptom detail | Fix |
|-------|----------------|-----|
| Package manager not wired in | Fails even though the dep is declared | Pass the toolchain file (vcpkg: `vcpkg.cmake`; Conan: `conan_toolchain.cmake`). |
| Conan not installed before configure | `find_package` runs before `conan install` | Run `conan install . --output-folder=build` *first*, then configure with the generated toolchain. |
| vcpkg manifest not picked up | `vcpkg.json` present but ignored | Configure with `-DCMAKE_TOOLCHAIN_FILE=.../vcpkg.cmake`; ensure `vcpkg.json` sits next to the top-level `CMakeLists.txt`. |
| Wrong package/target name | Found nothing under that name | Check the exact `find_package(<Name> ...)` and target (`fmt::fmt`, not `fmt`); names are case-sensitive. |
| CONFIG vs MODULE mismatch | Module-mode search, but the package ships a config | Use `find_package(<Pkg> CONFIG REQUIRED)`. |
| Custom install prefix | Installed but outside the search path | Set `-DCMAKE_PREFIX_PATH=/install/prefix` (or `<Pkg>_DIR` to the dir holding `<Pkg>Config.cmake`). |
| FetchContent dep not made available | `FetchContent_Declare` without `MakeAvailable` | Call `FetchContent_MakeAvailable(<dep>)`; then link the target it defines (no `find_package` needed). |

Quick triage:

```bash
# What did CMake actually search? Turn on the debug trace.
cmake -S . -B build --debug-find -DCMAKE_TOOLCHAIN_FILE=... 2>&1 | grep -A3 "<Pkg>"

# Point CMake at a config you know exists
cmake -S . -B build -D<Pkg>_DIR=/path/to/lib/cmake/<Pkg>
```

If the package is provided by FetchContent, there is **no** `find_package` step — link the
target `FetchContent_MakeAvailable` defined directly. Recipes:
[cmake-modern.md](cmake-modern.md).

## Related References

- [build-systems SKILL.md](../SKILL.md) — dependency-strategy summary + linking diagnostics
- [cmake-modern.md](cmake-modern.md) — full FetchContent / vcpkg / Conan CMake recipes
- [meson-and-make.md](meson-and-make.md) — Meson dependency() / wrap / subprojects
- [ci-pipelines.md](ci-pipelines.md) — caching the dependency layer in CI
- [version-feature-matrix](../../../_shared/version-feature-matrix.md) — Conan/vcpkg/uv version floors
