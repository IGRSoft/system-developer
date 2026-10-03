# Package Managers Reference

Choosing how dependencies reach the build, and diagnosing `Could NOT find <Pkg>`. Full
CMake recipes for each manager: [cmake-modern.md](cmake-modern.md). Link errors after the
package was found: [build-systems SKILL.md](../SKILL.md) > Linking Diagnostics.

## Selection Table

| Manager | Best for | Lockfile / pin | Binary cache | Integrates via |
|---------|----------|----------------|--------------|----------------|
| FetchContent | A few deps, zero extra tooling | `GIT_TAG` pin (manual) | No (rebuilds from source) | CMake built-in |
| vcpkg (manifest) | Cross-platform, broad catalog, binary caching | `vcpkg.json` + `builtin-baseline` | Yes | CMake toolchain file |
| Conan 2.29 | Versioned packages, profiles, lockfile-pinned graphs | `conan.lock` (v2) | Yes | `CMakeConfigDeps` + toolchain |
| uv | Python-only dependencies | `uv.lock` / `pylock.toml` | Yes (wheel cache) | Not a C/C++ build dep manager |

Pick one per project. Providing the same dependency through FetchContent and a package
manager produces duplicate, conflicting targets.

## FetchContent

The pinned `GIT_TAG` (tag or commit SHA) is the only lock. A good first choice; move to
vcpkg or Conan when dependency count or CI build time grows.

## vcpkg (manifest mode)

`builtin-baseline` pins the catalog snapshot; `overrides` pins one port's version:

```json
"overrides": [ { "name": "fmt", "version": "11.0.2" } ]
```

Consume with `find_package(<Pkg> CONFIG REQUIRED)`.

## Conan 2.29

Use `CMakeConfigDeps` + `CMakeToolchain` generators, run `conan install` before
configuring, and check profiles in. Lockfile: `conan lock create .`, then
`conan install --lockfile=conan.lock`.

## uv (Python)

uv manages the Python environment and lockfiles; a native extension still builds through
CMake/Meson (see [ffi-interop](../../ffi-interop/SKILL.md)), and its C/C++ deps go through
one of the managers above.

```bash
uv add requests                    # add a dependency, update uv.lock
uv sync                            # install from the lockfile
uv export --format pylock.toml     # PEP 751 interop lockfile for scanners and other tools
```

## "Could NOT find &lt;Pkg&gt;" Diagnosis

CMake's search found no config or module file for the package. Diagnose by layer:

| Cause | Fix |
|-------|-----|
| Package manager not wired in | Pass the toolchain file (vcpkg: `vcpkg.cmake`; Conan: `conan_toolchain.cmake`). |
| `find_package` ran before `conan install` | Run `conan install . --output-folder=build` first, then configure with its toolchain. |
| `vcpkg.json` ignored | Pass the vcpkg toolchain; keep `vcpkg.json` next to the top-level `CMakeLists.txt`. |
| Wrong package or target name | Names are case-sensitive; link the namespaced target (`fmt::fmt`, not `fmt`). |
| Module-mode search, package ships a config | `find_package(<Pkg> CONFIG REQUIRED)`. |
| Installed outside the search path | `-DCMAKE_PREFIX_PATH=/install/prefix`, or `<Pkg>_DIR` to the dir holding `<Pkg>Config.cmake`. |
| FetchContent dep | No `find_package` step: call `FetchContent_MakeAvailable(<dep>)` and link its target. |

### Quick triage

```bash
# What did CMake search?
cmake -S . -B build --debug-find -DCMAKE_TOOLCHAIN_FILE=... 2>&1 | grep -A3 "<Pkg>"

# Point CMake at a config you know exists
cmake -S . -B build -D<Pkg>_DIR=/path/to/lib/cmake/<Pkg>
```

## Related References

- [meson-and-make.md](meson-and-make.md): Meson `dependency()` and wrap files
- [ci-pipelines.md](ci-pipelines.md): caching the dependency layer in CI
- [version-feature-matrix](../../../_shared/version-feature-matrix.md): Conan, vcpkg, and uv version floors
