# Modern CMake Reference

Recipes for target-based CMake, presets, toolchain files, dependency integration,
C++20 modules, install/export, and CMake 4.x migration. Choosing a build system or
package manager: [build-systems SKILL.md](../SKILL.md), [package-managers.md](package-managers.md).

## Target-Based Doctrine

Attach everything to a target with a visibility keyword. Global commands
(`include_directories`, `add_definitions`, `link_libraries`) leak to every target.

```cmake
cmake_minimum_required(VERSION 3.28...4.3)
project(app LANGUAGES CXX)

add_library(core src/core.cpp)
target_include_directories(core
  PUBLIC  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
          $<INSTALL_INTERFACE:include>)         # build-tree vs install-tree paths
target_compile_features(core PUBLIC cxx_std_23) # standard propagates to consumers

add_executable(app src/main.cpp)
target_link_libraries(app PRIVATE core)
```

A dependency that appears in the target's public headers is `PUBLIC`; one used only in
`.cpp` files is `PRIVATE`; one consumers need but the target itself does not build
against (header-only) is `INTERFACE`.

Set `CMAKE_EXPORT_COMPILE_COMMANDS=ON` so clang-tidy / clangd / IDEs see real flags.

## CMakePresets Schema (v6+)

Configure, build, and test settings travel with the repo. Use `"version": 6` or higher
(CMake 3.25+). Generate the file with `../../../_shared/scripts/scaffold_cmake_preset.sh`
(`--name`, `--std`, `--build-type`, `--vcpkg`): it emits configure/build/test presets with
`CMAKE_EXPORT_COMPILE_COMMANDS=ON`, Ninja, and `binaryDir` `build/<name>`.

```bash
cmake --preset default          # configure
cmake --build --preset default  # build
ctest --preset default          # test
cmake --list-presets            # discover available presets
```

- `inherits` composes presets: one base, toolchains and sanitizers layered on top.
- `${sourceDir}`, `$env{VAR}`, `${presetName}` keep paths portable.
- Machine-private overrides go in a gitignored `CMakeUserPresets.json` that `inherits`
  the checked-in presets.

## Toolchain Files

A toolchain file sets the compiler, sysroot, and package-manager integration before the
project configures. To change it, wipe the build dir and reconfigure; CMake ignores a new
toolchain on an existing cache.

```bash
cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE=/path/to/toolchain.cmake
```

```cmake
# toolchain.cmake — minimal cross/explicit-compiler example
set(CMAKE_C_COMPILER   clang)
set(CMAKE_CXX_COMPILER clang++)
# vcpkg and Conan also ship toolchain files you point at the same way.
```

In presets, set `toolchainFile` or `CMAKE_TOOLCHAIN_FILE` in `cacheVariables` (the
scaffold's `--vcpkg` does the latter) instead of passing it by hand. Keep the language standard on targets
(`target_compile_features`), not in the toolchain.

## FetchContent

Vendors dependencies at configure time; no package manager, no lockfile.

```cmake
include(FetchContent)

FetchContent_Declare(
  fmt
  GIT_REPOSITORY https://github.com/fmtlib/fmt.git
  GIT_TAG        11.0.2          # pin a tag/commit — never a moving branch
)
FetchContent_MakeAvailable(fmt)  # configures + adds the subproject's targets

target_link_libraries(app PRIVATE fmt::fmt)
```

- Pin `GIT_TAG` to a tag or commit SHA; a branch makes builds irreproducible.
- `FetchContent_MakeAvailable` replaces the old `Populate` + `add_subdirectory` form.
- Every dependency rebuilds from source with no binary cache; for many deps prefer vcpkg
  or Conan.

## vcpkg Integration

Manifest mode is the default: declare deps in `vcpkg.json`, integrate via the toolchain file.

```json
{
  "name": "app",
  "version": "0.1.0",
  "dependencies": [ "fmt", "spdlog", { "name": "boost-asio" } ],
  "builtin-baseline": "<commit-sha-of-vcpkg-repo>"
}
```

```bash
cmake -S . -B build \
  -DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake
cmake --build build
```

```cmake
find_package(fmt CONFIG REQUIRED)
target_link_libraries(app PRIVATE fmt::fmt)
```

- `builtin-baseline` pins the catalog snapshot (the lockfile equivalent); `"overrides"`
  pins a specific port version.
- Dependencies install into the build tree at configure time; no global `vcpkg install`.

## Conan 2.29 (`CMakeConfigDeps`)

Conan 2.x only. Use the `CMakeConfigDeps` generator; it replaces `CMakeDeps` from earlier
Conan 2 releases.

```ini
# conanfile.txt
[requires]
fmt/11.0.2
spdlog/1.14.1

[generators]
CMakeConfigDeps
CMakeToolchain
```

```bash
conan install . --output-folder=build --build=missing \
  -pr:h=default -pr:b=default          # host/build profiles
cmake -S . -B build \
  -DCMAKE_TOOLCHAIN_FILE=build/conan_toolchain.cmake
cmake --build build
```

```cmake
find_package(fmt REQUIRED)
target_link_libraries(app PRIVATE fmt::fmt)
```

### Profiles and lockfiles

- Profiles (`-pr:h` host, `-pr:b` build) capture compiler, arch, and build type; check
  them in for reproducible CI.
- `conan lock create .` writes `conan.lock` (v2); `conan install --lockfile=conan.lock`
  reproduces the graph.
- `--build=missing` builds from source only packages with no matching cached binary.
- `CMakeToolchain` writes `conan_toolchain.cmake`; `CMakeConfigDeps` writes the
  `*-config.cmake` files `find_package` consumes.

## C++20 Modules (`FILE_SET CXX_MODULES`)

Modules need CMake 3.28+ and a generator that scans module dependencies.

```cmake
cmake_minimum_required(VERSION 3.28)
project(mathlib LANGUAGES CXX)

add_library(math)
target_sources(math
  PUBLIC
    FILE_SET CXX_MODULES FILES        # module interface units (.cppm / .ixx)
      src/math.cppm
      src/math.linalg.cppm)
target_compile_features(math PUBLIC cxx_std_20)

add_executable(app src/main.cpp)      # main.cpp does: import math;
target_link_libraries(app PRIVATE math)
```

```bash
cmake -S . -B build -G Ninja        # use Ninja or Visual Studio
cmake --build build
```

### Generator support matrix

| Generator | Module scanning | Note |
|-----------|-----------------|------|
| Ninja / Ninja Multi-Config | Yes | Recommended. |
| Visual Studio 2022+ | Yes | With MSVC. |
| Makefiles (Unix/MinGW) | No | Do not use for modules. |
| Xcode | Limited | Treat as unsupported for portable module builds. |

Interface units use `.cppm` (Clang) or `.ixx` (MSVC); list whatever your compiler accepts.

## `import std` Status

`import std;` (and `import std.compat;`) replaces standard `#include`s but is partial and
tooling-gated. In portable code, gate on `__cpp_lib_modules` or a configure-time probe.

| Toolchain | `import std` status | Note |
|-----------|---------------------|------|
| Clang 17+ | Partial / experimental | Needs libc++ built as a module and recent CMake. |
| GCC 15+ | Partial / experimental | libstdc++ module support still maturing. |
| MSVC 2022+ | Partial | Best-supported of the three, still version-sensitive. |

```cmake
# Opt in explicitly; CMake exposes the std module behind an experimental flag.
set(CMAKE_EXPERIMENTAL_CXX_IMPORT_STD
    "0e5b6991-d74f-4b3d-a41c-cf096e0b2508")   # value tracks the CMake release — verify
set(CMAKE_CXX_MODULE_STD ON)
```

The UUID changes between CMake releases; check your CMake version's docs before pinning
it. Prefer `#include` for portability; adopt `import std` only where you control the
whole toolchain.

## Install / Export (`install(TARGETS ... EXPORT ...)`)

Make a library consumable by downstream `find_package(<Pkg> CONFIG)`.

```cmake
include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

install(TARGETS core
  EXPORT  coreTargets
  ARCHIVE  DESTINATION ${CMAKE_INSTALL_LIBDIR}
  LIBRARY  DESTINATION ${CMAKE_INSTALL_LIBDIR}
  RUNTIME  DESTINATION ${CMAKE_INSTALL_BINDIR}
  FILE_SET HEADERS                       # installs the target's public headers
)

install(EXPORT coreTargets
  FILE        coreTargets.cmake
  NAMESPACE   core::                     # consumers link core::core
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/core)

configure_package_config_file(
  cmake/coreConfig.cmake.in
  ${CMAKE_CURRENT_BINARY_DIR}/coreConfig.cmake
  INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/core)

install(FILES ${CMAKE_CURRENT_BINARY_DIR}/coreConfig.cmake
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/core)
```

### Include paths and package config

- Use `$<BUILD_INTERFACE:>` / `$<INSTALL_INTERFACE:>` on `target_include_directories`
  (see Target-Based Doctrine) so include paths work in the build tree and after install.
- `configure_package_config_file` generates the `Config.cmake` that
  `find_package(core CONFIG)` loads.

## CMake 4.x Policy Floors

| Trigger | Behavior in 4.x | Action |
|---------|-----------------|--------|
| `cmake_minimum_required(VERSION <3.5)` | Hard error; configure aborts | Raise the floor in your code; bridge un-editable deps with `CMAKE_POLICY_VERSION_MINIMUM`. |
| `find_package(Boost)` | Bundled `FindBoost` removed (CMP0167, 3.30+) | `find_package(Boost CONFIG REQUIRED ...)` (Boost's own `BoostConfig.cmake`). |

```bash
# Bridge a dependency that still declares an ancient minimum (temporary, not a fix)
cmake -S . -B build -DCMAKE_POLICY_VERSION_MINIMUM=3.5

# Or scope it inside your own CMakeLists for a vendored subdir
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
add_subdirectory(third_party/legacy_dep)
```

Remove the bridge once upstream raises its floor. Other floors: 3.28+ for
`FILE_SET CXX_MODULES`, 3.23+ for `FILE_SET HEADERS`, 3.25+ for presets v6.

## CI Integration

Run CI through the same presets (`cmake --preset`, `cmake --build --preset`,
`ctest --preset ... --output-on-failure`) so it matches local builds. Use single commands
(`cmake --build build`, `ctest --test-dir build`), not `cd`-chains: scoped Bash allowlists
do not match compound commands. Matrix, caching, and gates: [ci-pipelines.md](ci-pipelines.md).

## Related References

- [diagnostics sanitizers.md](../../diagnostics/references/sanitizers.md): sanitizer flags for a sanitized preset
- [version-feature-matrix](../../../_shared/version-feature-matrix.md): CMake, Conan, and compiler floors per standard
