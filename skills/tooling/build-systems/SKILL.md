---
name: build-systems
description: >-
  Modern CMake doctrine, CMakePresets, FetchContent vs vcpkg vs Conan 2,
  CMake 4.x migration, C++20 modules (FILE_SET CXX_MODULES / import std),
  Meson 1.11, and plain Make positioning. Use when configuring a build,
  picking a package manager, wiring C++20 modules, or diagnosing link errors.
---

# Build Systems

**Pick a build system, then wire targets, dependencies, and CI the modern way.**

## When to Use

Use this skill when the problem is at *configure/build/link* time, not runtime:

- "Won't build" / "won't configure" — CMake errors, generator drift, missing toolchain.
- `undefined reference` / `Undefined symbols` — a target is not linked to what it uses.
- C++20 `import` fails / no `import std` — module support gap in CMake or the toolchain.
- `Could NOT find <Pkg>` — a dependency was never provided to the build.
- Builds locally, breaks in CI — toolchain, preset, or cache drift across machines.

Skip if the program *builds and runs* but misbehaves (crash, leak, race, slow) — that is
[diagnostics](../diagnostics/SKILL.md).

## Build System Selection

| Project shape | Use | Why |
|---------------|-----|-----|
| Any new C/C++ project; multi-target; needs packages, presets, IDE integration | **CMake** | The default. Widest tooling/IDE/package-manager support; presets standardize configure/build/test. |
| Clean-slate C/C++, want fast configure and terse syntax | **Meson** | Faster, stricter, less boilerplate than CMake; Ninja backend by default. See [meson-and-make.md](references/meson-and-make.md). |
| Existing `Makefile`s, or one simple single-language target | **Make** | Don't migrate a working simple build. See [meson-and-make.md](references/meson-and-make.md) for the migration signal. |
| Python-only project (no native extension) | **uv** | Project + dependency + build-backend tool; not a C/C++ build system. See [package-managers.md](references/package-managers.md). |

CMake is the default for C/C++ in this plugin. Reach for Meson on clean projects that
want a faster, stricter configure; keep Make only for legacy or trivially simple builds;
use uv for pure-Python work (a native extension routes back through CMake/Meson).

## CMake: the Modern Target-Based Workflow

Targets carry their own usage requirements. Stop setting global state; attach
include dirs, defines, and flags to targets with the right visibility.

```cmake
cmake_minimum_required(VERSION 3.28...4.3)   # floor...max-tested; 3.28 = FILE_SET CXX_MODULES
project(app LANGUAGES CXX)

add_library(core src/core.cpp)
target_include_directories(core PUBLIC include)      # consumers see include/
target_compile_features(core PUBLIC cxx_std_23)      # propagates the standard

add_executable(app src/main.cpp)
target_link_libraries(app PRIVATE core)              # app uses core; nobody links app
```

- **`target_link_libraries(<tgt> PRIVATE|PUBLIC|INTERFACE ...)`** — visibility is the
  whole game. `PRIVATE` = used in the implementation only; `PUBLIC` = used in the
  implementation *and* the public headers; `INTERFACE` = header-only, consumers need it
  but the target itself does not.
- **Never `include_directories()` / `link_libraries()` globally.** They leak to every
  target and defeat incremental, cache-correct builds. Use the `target_*` forms.
- **CMakePresets v6+** — put configure/build/test settings in `CMakePresets.json` so
  every machine and CI runner configures identically. See
  [cmake-modern.md](references/cmake-modern.md) > Presets.
- **Out-of-source builds always.** Configure into `build/`, never the source tree.

```bash
cmake --preset default          # configure (reads CMakePresets.json)
cmake --build --preset default  # build
ctest --preset default          # test
```

## CMake 4.x Migration

CMake 4.x (≈4.3.x) is current. Two things bite when you upgrade an older tree:

- **`cmake_minimum_required(VERSION <3.5)` is now a hard error.** Old projects that
  declared `2.8`/`3.0` will not configure. Raise the floor, or — for a dependency you
  cannot edit — set `CMAKE_POLICY_VERSION_MINIMUM` to unblock the configure during
  migration:

  ```bash
  cmake -S . -B build -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  ```

  Treat this as a temporary bridge, not a fix — patch the floor upstream when you can.
- **`CMP0167` (FindBoost) is deprecated.** CMake's bundled `FindBoost` is gone in favor
  of Boost's own `BoostConfig.cmake`; prefer `find_package(Boost CONFIG ...)`.

Full policy-floor table and `CMAKE_POLICY_VERSION_MINIMUM` mechanics:
[cmake-modern.md](references/cmake-modern.md) > CMake 4.x Policy Floors.

## C++20 Modules

Modules are real but still tooling-gated — adopt deliberately, not by default.

- **`FILE_SET CXX_MODULES`** is the CMake mechanism, and it **requires CMake 3.28+**
  with the Ninja or Visual Studio generator:

  ```cmake
  add_library(math)
  target_sources(math
    PUBLIC FILE_SET CXX_MODULES FILES math.ixx)   # .cppm/.ixx module interface units
  target_compile_features(math PUBLIC cxx_std_20)
  ```

- **`import std;`** is **partial in Clang 17+ / GCC 15+ / MSVC 2022+** and still
  **experimental / tooling-gated** (it needs a built standard-library module and recent
  CMake support). Do not assume it; **gate on `__cpp_lib_modules`** or a toolchain probe
  before relying on it in portable code.

Module syntax, the generator support matrix, and the `import std` status table live in
[cmake-modern.md](references/cmake-modern.md) > C++20 Modules.

## Dependency Strategy

Pick one strategy per project and stay consistent. Full recipes and a "Could NOT find"
diagnosis live in [package-managers.md](references/package-managers.md).

| Option | When | Lockfile | Note |
|--------|------|----------|------|
| **FetchContent** | Small projects, a few deps, vendor-at-configure | none | In-tree, simplest; rebuilds deps from source. |
| **vcpkg** (manifest mode, **GA**) | Cross-platform binary caching, broad catalog | `vcpkg.json` + `builtin-baseline` | Manifest mode is the default; integrates via toolchain file. |
| **Conan 2.29** | Versioned binary packages, profiles, enterprise | `conan.lock` (v2) | Use the **`CMakeConfigDeps`** generator (replaces `CMakeDeps` in Conan 2.x). |
| **uv** | Python-only dependencies | `uv.lock` / `pylock.toml` | Not a C/C++ dependency manager; for Python projects. |

## Meson 1.11

A faster, stricter alternative for clean projects:

```bash
meson setup build          # configure (Ninja backend by default)
meson compile -C build     # build
meson test -C build        # run the test suite
```

Subprojects (`subprojects/*.wrap`) handle dependencies. Fastest configure of the three
for greenfield work. Details and the Make positioning: [meson-and-make.md](references/meson-and-make.md).

## Linking Diagnostics

| Symptom | Cause | Fix |
|---------|-------|-----|
| `undefined reference to ...` / `Undefined symbols for architecture ...` | A target uses a symbol it never linked | Add the provider to `target_link_libraries(<tgt> PRIVATE ...)`; check link **order** for static libs. |
| `Could NOT find <Pkg>` | `find_package` missing, or vcpkg/Conan not initialized | Add `find_package(<Pkg> ...)`; pass the vcpkg/Conan toolchain file. See [package-managers.md](references/package-managers.md). |
| `multiple definition of ...` | A symbol defined in a header pulled into many TUs | `inline`, or move the definition to one `.cpp`. |
| `import` of a module fails | Module support gap | Need CMake 3.28+, Ninja/VS, and a supporting toolchain. See [cmake-modern.md](references/cmake-modern.md) > C++20 Modules. |

## Related Skills

- [cmake-modern.md](references/cmake-modern.md) — presets schema, toolchain files, FetchContent, vcpkg/Conan recipes, `FILE_SET CXX_MODULES`, `import std` table, install/export, CMake 4.x policy floors
- [meson-and-make.md](references/meson-and-make.md) — Meson 1.11 verbs, subprojects/wrap, when plain Make is right, the Make→CMake/Meson migration signal
- [package-managers.md](references/package-managers.md) — FetchContent vs vcpkg vs Conan 2.29 vs uv selection table + "Could NOT find" diagnosis
- [ci-pipelines.md](references/ci-pipelines.md) — wiring build + test + sanitize + lint into CI: matrix builds, caching, ASan/UBSan gates
- [diagnostics](../diagnostics/SKILL.md) — once it builds, route runtime symptoms (crash/leak/race/slow) here
- [ffi-interop](../ffi-interop/SKILL.md) — building native extensions for Python (the Python↔C/C++ boundary)
- [version-feature-matrix](../../_shared/version-feature-matrix.md) — toolchain floors per standard (CMake/Conan/compiler versions)
- [secure-coding](../../_shared/secure-coding/SKILL.md) — hardening flags belong in the build, not as an afterthought
