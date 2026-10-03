---
name: build-systems
description: >-
  Configure and fix C/C++ builds: target-based CMake with presets, CMake 4.x
  migration, C++20 modules (FILE_SET CXX_MODULES, import std), FetchContent vs
  vcpkg vs Conan 2, Meson, and plain Make. Use when configuring a build,
  picking a package manager, wiring C++20 modules, or diagnosing configure and
  link errors.
---

# Build Systems

## When to Use

Problems at configure, build, or link time:

- Won't configure or build: CMake errors, generator drift, missing toolchain.
- `undefined reference` / `Undefined symbols`: a target is not linked to what it uses.
- C++20 `import` fails, or no `import std`.
- `Could NOT find <Pkg>`: the dependency never reached the build.
- Builds locally, breaks in CI: toolchain, preset, or cache drift.

If it builds and runs but misbehaves (crash, leak, race, slow), use
[diagnostics](../diagnostics/SKILL.md).

## Build System Selection

| Project shape | Use | Why |
|---------------|-----|-----|
| New C/C++ project; multi-target; needs packages, presets, IDE support | CMake | The default: widest tooling and package-manager support. |
| Clean-slate C/C++ wanting fast configure and terse syntax | Meson | Faster and stricter than CMake, Ninja by default. |
| Existing working `Makefile`, or one simple single-language target | Make | Don't migrate a working simple build. |
| Python-only (no native extension) | uv | Not a C/C++ build system; native extensions go through CMake/Meson. |

Meson, Make, and the Make migration signal: [meson-and-make.md](references/meson-and-make.md).

## CMake: the Modern Target-Based Workflow

Attach include dirs, defines, and flags to targets with a visibility keyword;
`include_directories()` / `link_libraries()` leak to every target, so don't use them.

```cmake
cmake_minimum_required(VERSION 3.28...4.3)   # floor...max-tested; 3.28 = FILE_SET CXX_MODULES
project(app LANGUAGES CXX)

add_library(core src/core.cpp)
target_include_directories(core PUBLIC include)      # consumers see include/
target_compile_features(core PUBLIC cxx_std_23)      # propagates the standard

add_executable(app src/main.cpp)
target_link_libraries(app PRIVATE core)
```

Visibility: `PRIVATE` = implementation only; `PUBLIC` = implementation and public
headers; `INTERFACE` = consumers need it, the target itself does not (header-only).

### Presets

Keep configure/build/test settings in `CMakePresets.json` (v6+) so every machine and CI
runner configures the same way, always out of source. Scaffold one with
`../../_shared/scripts/scaffold_cmake_preset.sh --name default --std 23` (`--vcpkg` adds
the toolchain); details in [cmake-modern.md](references/cmake-modern.md) > CMakePresets Schema.

```bash
cmake --preset default
cmake --build --preset default
ctest --preset default
```

## CMake 4.x Migration

CMake 4.x (about 4.3) is current. Two things break older trees:

- `cmake_minimum_required(VERSION <3.5)` is a hard error. Raise the floor; for a
  dependency you cannot edit, bridge with `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` and
  remove it once upstream is fixed.
- The bundled `FindBoost` is removed (CMP0167, CMake 3.30+). Use
  `find_package(Boost CONFIG ...)`, which loads Boost's own `BoostConfig.cmake`.

More: [cmake-modern.md](references/cmake-modern.md) > CMake 4.x Policy Floors.

## C++20 Modules

Adopt deliberately; tooling still gates them.

- `FILE_SET CXX_MODULES` needs CMake 3.28+ and the Ninja or Visual Studio generator:

  ```cmake
  add_library(math)
  target_sources(math PUBLIC FILE_SET CXX_MODULES FILES math.ixx)   # .cppm/.ixx
  target_compile_features(math PUBLIC cxx_std_20)
  ```

- `import std;` is partial and experimental (Clang 17+, GCC 15+, MSVC 2022+) and needs a
  built standard-library module. Gate on `__cpp_lib_modules` or a toolchain probe before
  using it in portable code.

Generator matrix and `import std` setup: [cmake-modern.md](references/cmake-modern.md) > C++20 Modules.

## Dependency Strategy

Pick one per project. Recipes and "Could NOT find" diagnosis: [package-managers.md](references/package-managers.md).

| Option | When | Lockfile | Note |
|--------|------|----------|------|
| FetchContent | A few deps, vendor at configure | none (pin `GIT_TAG`) | Simplest; rebuilds deps from source. |
| vcpkg (manifest mode) | Cross-platform binary caching, broad catalog | `vcpkg.json` + `builtin-baseline` | Integrates via toolchain file. |
| Conan 2.29 | Versioned binary packages, profiles, enterprise | `conan.lock` (v2) | Use the `CMakeConfigDeps` generator (replaces `CMakeDeps`). |
| uv | Python-only dependencies | `uv.lock` / `pylock.toml` | Not a C/C++ dependency manager. |

## Meson 1.11

```bash
meson setup build          # configure (Ninja backend)
meson compile -C build
meson test -C build
```

Dependencies come from `dependency()` with `subprojects/*.wrap` fallbacks; see
[meson-and-make.md](references/meson-and-make.md).

## Linking Diagnostics

| Symptom | Cause | Fix |
|---------|-------|-----|
| `undefined reference to ...` / `Undefined symbols for architecture ...` | A target uses a symbol it never linked | Add the provider to `target_link_libraries(<tgt> PRIVATE ...)`; check link order for static libs. |
| `Could NOT find <Pkg>` | `find_package` missing, or vcpkg/Conan toolchain not passed | Add `find_package(<Pkg> ...)`; pass the vcpkg/Conan toolchain file. |
| `multiple definition of ...` | A symbol defined in a header included by many TUs | Mark it `inline`, or move the definition to one `.cpp`. |
| `import` of a module fails | Module support gap | CMake 3.28+, Ninja/VS generator, supporting toolchain. |

## Related

- [ci-pipelines.md](references/ci-pipelines.md): build, test, sanitize, lint, and wheel jobs in CI
- [ffi-interop](../ffi-interop/SKILL.md): building native Python extensions
- [version-feature-matrix](../../_shared/version-feature-matrix.md): CMake, Conan, and compiler floors per standard
- [secure-coding](../../_shared/secure-coding/SKILL.md): hardening flags belong in the build
