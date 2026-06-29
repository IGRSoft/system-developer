# Modern CMake Reference

Use this when:

- You are writing or refactoring `CMakeLists.txt` / `CMakePresets.json` and want the
  target-based, preset-driven form.
- You are wiring a dependency (FetchContent, vcpkg, Conan 2.29) into a CMake build.
- You are turning on C++20 modules (`FILE_SET CXX_MODULES`, `import std`).
- You are packaging a library for downstream `find_package` (`install(... EXPORT ...)`).
- You are migrating a tree to CMake 4.x and hitting policy floors.

Skip if:

- You only need to pick a build system or a package manager. That is the
  [build-systems SKILL.md](../SKILL.md) and [package-managers.md](package-managers.md).
- The problem is a runtime fault, not a build/link failure. See
  [diagnostics](../../diagnostics/SKILL.md).

Jump to:

- Target-Based Doctrine
- CMakePresets Schema (v6+)
- Toolchain Files
- FetchContent
- vcpkg Integration
- Conan 2.29 (`CMakeConfigDeps`)
- C++20 Modules (`FILE_SET CXX_MODULES`)
- `import std` Status
- Install / Export (`install(TARGETS ... EXPORT ...)`)
- CMake 4.x Policy Floors
- CI Integration

---

## Target-Based Doctrine

Everything attaches to a target with a visibility keyword. Global commands
(`include_directories`, `add_definitions`, `link_libraries`) leak to every target and
break cache-correctness — do not use them.

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

| Keyword | Meaning | Propagates to consumers? |
|---------|---------|--------------------------|
| `PRIVATE` | used in this target's implementation only | No |
| `PUBLIC` | used in implementation **and** public headers | Yes |
| `INTERFACE` | not used to build this target; consumers need it (header-only) | Yes (only) |

Rule of thumb: if a dependency appears in a **public header** of the target, it is
`PUBLIC`; if it appears only in `.cpp` files, it is `PRIVATE`; a header-only library that
the target re-exports is `INTERFACE`.

Set `CMAKE_EXPORT_COMPILE_COMMANDS=ON` so clang-tidy / clangd / IDEs see real flags.

---

## CMakePresets Schema (v6+)

`CMakePresets.json` removes per-machine guesswork: configure, build, and test settings
travel with the repo. Use `"version": 6` or higher (CMake 3.25+ reads v6).

Generate a starting file with `../../../_shared/scripts/scaffold_cmake_preset.sh`
(`--name`, `--std`, `--build-type`, `--vcpkg`) rather than hand-writing the JSON — it
emits `configurePresets` / `buildPresets` / `testPresets` with `CMAKE_EXPORT_COMPILE_COMMANDS=ON`,
a Ninja generator, and an out-of-source `binaryDir`. Then:

```bash
cmake --preset default          # configure
cmake --build --preset default  # build
ctest --preset default          # test
cmake --list-presets            # discover available presets
```

Notes:

- `inherits` composes presets — keep one base, layer toolchains/sanitizers on top.
- `${sourceDir}`, `$env{VAR}`, `${presetName}` macros keep paths portable.
- Put machine-private overrides in `CMakeUserPresets.json` (gitignored); it can
  `inherits` from the checked-in presets.

---

## Toolchain Files

A toolchain file sets the compiler, sysroot, and package-manager integration *before*
the project is configured. Pass it once at configure time; never change it on an existing
build dir (wipe and reconfigure instead).

```bash
cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE=/path/to/toolchain.cmake
```

```cmake
# toolchain.cmake — minimal cross/explicit-compiler example
set(CMAKE_C_COMPILER   clang)
set(CMAKE_CXX_COMPILER clang++)
set(CMAKE_CXX_STANDARD 23)
# vcpkg and Conan also ship toolchain files you point at the same way.
```

In presets, use the `toolchainFile` field (see the `vcpkg` preset above) instead of
passing `-DCMAKE_TOOLCHAIN_FILE` by hand.

---

## FetchContent

Vendor dependencies at configure time — no external package manager, no lockfile.
Simplest option for a handful of dependencies.

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

- **Always pin `GIT_TAG`** to a tag or commit SHA; a branch makes builds irreproducible.
- `FetchContent_MakeAvailable` is the modern one-call form (replaces the old
  `Populate` + `add_subdirectory` dance).
- Trade-off: every dependency is rebuilt from source and there is no binary cache or
  lockfile. For many deps or cross-platform binary caching, prefer vcpkg or Conan
  ([package-managers.md](package-managers.md)).

---

## vcpkg Integration

Manifest mode is **GA** and the default. Declare deps in `vcpkg.json`; integrate via the
toolchain file.

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

- `builtin-baseline` pins the catalog snapshot — the lockfile equivalent for reproducible
  resolution. Use `"overrides"` to pin a specific port version.
- Manifest mode installs into the build tree automatically at configure time; no global
  `vcpkg install` needed.

---

## Conan 2.29 (`CMakeConfigDeps`)

Conan 2.x is the only supported Conan. Use the **`CMakeConfigDeps`** generator — it
replaces `CMakeDeps` from earlier Conan 2 releases and produces standard
`find_package`-consumable config files.

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

- **Profiles** (`-pr:h` host, `-pr:b` build) capture compiler/arch/build-type; check them
  into the repo for reproducible CI.
- **Lockfiles** (`conan.lock`, v2 format): `conan lock create .` pins the full graph;
  pass `--lockfile=conan.lock` to `conan install` to reproduce exactly.
- `CMakeToolchain` writes `conan_toolchain.cmake`; `CMakeConfigDeps` writes the
  `*-config.cmake` files `find_package` consumes.

---

## C++20 Modules (`FILE_SET CXX_MODULES`)

Modules require **CMake 3.28+** and a generator that supports scanning.

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
| **Ninja** / **Ninja Multi-Config** | Yes | The recommended path; full collated module dependency scanning. |
| **Visual Studio** (2022+) | Yes | Supported with MSVC. |
| **Makefiles** (Unix/MinGW) | **No** | No module dependency scanning — do not use for modules. |
| Xcode | Limited / verify | Treat as unsupported for portable module builds; *verify against your toolchain*. |

Gate module use on CMake ≥ 3.28 **and** Ninja/VS — Makefile generators silently
fail to scan. Module interface units conventionally use `.cppm` (Clang/CMake) or `.ixx`
(MSVC); list whatever your compiler accepts in the `FILE_SET`.

---

## `import std` Status

`import std;` (and `import std.compat;`) replaces `#include`-ing standard headers, but it
is **partial and tooling-gated**. Do not assume it in portable code — **gate on
`__cpp_lib_modules`** or a configure-time probe.

| Toolchain | `import std` status | Note |
|-----------|---------------------|------|
| **Clang 17+** | Partial / experimental | Needs libc++ built as a module + recent CMake; verify. |
| **GCC 15+** | Partial / experimental | libstdc++ module support maturing; verify. |
| **MSVC 2022+** | Partial | Best-supported of the three, still version-sensitive. |

```cmake
# Opt in explicitly; CMake exposes the std module behind an experimental flag.
set(CMAKE_EXPERIMENTAL_CXX_IMPORT_STD
    "0e5b6991-d74f-4b3d-a41c-cf096e0b2508")   # value tracks the CMake release — verify
set(CMAKE_CXX_MODULE_STD ON)
```

The UUID gate value changes between CMake releases — *verify against your CMake version's
docs* before pinning. Until this stabilizes, prefer classic `#include` for portability and
adopt `import std` only where you control the full toolchain.

---

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

- `EXPORT` + `NAMESPACE` give consumers a namespaced imported target (`core::core`).
- Use `$<BUILD_INTERFACE:>` / `$<INSTALL_INTERFACE:>` on `target_include_directories`
  (see Target-Based Doctrine) so include paths are correct in *both* the build tree and
  after install.
- `configure_package_config_file` generates the `Config.cmake` that
  `find_package(core CONFIG)` loads.

---

## CMake 4.x Policy Floors

CMake 4.x (≈4.3.x) is current. Migration friction concentrates in policy floors.

| Trigger | Behavior in 4.x | Action |
|---------|-----------------|--------|
| `cmake_minimum_required(VERSION <3.5)` | **Hard error** — configure aborts | Raise the floor in your code; for un-editable deps, bridge with `CMAKE_POLICY_VERSION_MINIMUM`. |
| Legacy policy warnings (`CMP00xx`) during migration | Noise | Set `CMAKE_POLICY_VERSION_MINIMUM` to silence the batch while you migrate incrementally. |
| `CMP0167` (FindBoost) | **Deprecated** — bundled `FindBoost` removed | Use `find_package(Boost CONFIG REQUIRED ...)` (Boost's own `BoostConfig.cmake`). |

```bash
# Bridge a dependency that still declares an ancient minimum (temporary, not a fix)
cmake -S . -B build -DCMAKE_POLICY_VERSION_MINIMUM=3.5

# Or scope it inside your own CMakeLists for a vendored subdir
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
add_subdirectory(third_party/legacy_dep)
```

`CMAKE_POLICY_VERSION_MINIMUM` is a **migration bridge**: it lets a tree with a too-old
`cmake_minimum_required` configure on CMake 4.x without you editing upstream. Patch the
real floor upstream and remove the bridge as soon as the dependency is updated.

Legacy floors that still matter: **3.28+** for `FILE_SET CXX_MODULES`; **3.23+** for the
`FILE_SET HEADERS` install form; **3.25+** for presets v6.

---

## CI Integration

Configure/build/test through presets so CI matches local exactly. Full matrix, caching,
and sanitizer/lint gates: [ci-pipelines.md](ci-pipelines.md).

```yaml
# GitHub Actions sketch — presets keep this short and machine-agnostic
jobs:
  build:
    strategy:
      matrix: { os: [ubuntu-latest, macos-latest], preset: [default] }
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - name: Configure
        run: cmake --preset ${{ matrix.preset }}
      - name: Build
        run: cmake --build --preset ${{ matrix.preset }}
      - name: Test
        run: ctest --preset ${{ matrix.preset }} --output-on-failure
```

- Use **single-command** invocations (`cmake --build build`, `ctest --test-dir build`),
  never `cd`-chains — scoped Bash allowlists do not match compound commands.
- Cache the dependency layer (vcpkg binary cache, Conan cache, or FetchContent
  `_deps/`) keyed on the manifest/lockfile hash. See [ci-pipelines.md](ci-pipelines.md).

## Related References

- [build-systems SKILL.md](../SKILL.md) — build-system selection and the modern-CMake summary
- [package-managers.md](package-managers.md) — FetchContent vs vcpkg vs Conan vs uv selection + "Could NOT find" diagnosis
- [meson-and-make.md](meson-and-make.md) — the Meson alternative and Make positioning
- [ci-pipelines.md](ci-pipelines.md) — matrix builds, caching, sanitize/lint gates, reproducible builds
- [diagnostics references](../../diagnostics/references/sanitizers.md) — wiring a sanitized preset into the build
- [version-feature-matrix](../../../_shared/version-feature-matrix.md) — CMake/Conan/compiler floors per standard
