# Tooling Index

Quick navigation for build systems, diagnostics, and FFI interop.

## Skills

| Path | Description |
|------|-------------|
| `SKILL.md` | Entry router: skill selection, symptom router, tool version snapshot, decision tree |
| `build-systems/SKILL.md` | Modern CMake doctrine, presets, dependency strategy, C++ modules, Meson/Make positioning |
| `build-systems/references/cmake-modern.md` | Target-based CMake deep dive: presets schema, toolchain files, FetchContent, modules, install/export, CMake 4.x migration |
| `build-systems/references/meson-and-make.md` | Meson build setup and when plain Make is the right tool |
| `build-systems/references/package-managers.md` | FetchContent vs vcpkg manifest vs Conan 2 vs uv |
| `build-systems/references/ci-pipelines.md` | Wiring build + test + sanitize + lint into CI |
| `diagnostics/SKILL.md` | Symptom → tool routing, sanitizer combinations, debugger and profiler selection |
| `diagnostics/references/sanitizers.md` | ASan/UBSan/TSan/LSan/MSan flags, combinations, options, triage |
| `diagnostics/references/gdb-lldb.md` | Interactive debugging; gdb ↔ lldb command translation |
| `diagnostics/references/profiling-tools.md` | perf/valgrind/sample/py-spy/hyperfine/Google Benchmark |
| `ffi-interop/SKILL.md` | Python ↔ C/C++ boundary doctrine and binding choice |
| `ffi-interop/references/pybind11-nanobind.md` | pybind11 and nanobind binding patterns, packaging, GIL |
| `ffi-interop/references/c-api-boundaries.md` | `extern "C"` boundaries, ABI stability, error translation |

## Quick Links by Problem

### "I need to..."

- **Configure a CMake build** → `build-systems/SKILL.md`
- **Write CMakePresets.json** → `build-systems/references/cmake-modern.md`
- **Pick a dependency manager** → `build-systems/references/package-managers.md`
- **Use C++20 modules** → `build-systems/references/cmake-modern.md`
- **Migrate to CMake 4.x** → `build-systems/references/cmake-modern.md`
- **Bind C/C++ to Python** → `ffi-interop/SKILL.md`

### "I'm getting..."

- **`undefined reference` / `Undefined symbols`** → `build-systems/SKILL.md` (linking diagnostics)
- **`Could NOT find <Pkg>`** → `build-systems/references/package-managers.md`
- **Compatibility error on CMake 4.x (`<3.5`)** → `build-systems/references/cmake-modern.md` (CMAKE_POLICY_VERSION_MINIMUM)
- **A crash / leak / data race** → `diagnostics/SKILL.md`
- **A slow program** → `diagnostics/references/profiling-tools.md`
