---
name: tooling-skills
description: >-
  Build, diagnostics, and interop tooling for C, C++, Python, and Bash.
  Use when configuring CMake/Meson/Make or package managers, running
  sanitizers, debuggers, or profilers, binding native code to Python,
  or routing a "won't build", "crashes", "too slow", or "can't link"
  symptom to the right tooling guide.
---

# Tooling Skills

**Build systems, diagnostics, and FFI interop for systems development**

Thin router. Pick a sub-skill from the tables below; the leaf skills teach.

## Skill Selection

| I need to... | Use this skill |
|--------------|----------------|
| Configure a build (CMake/Meson/Make), pick a package manager | [build-systems/SKILL.md](build-systems/SKILL.md) |
| Find/fix a crash, leak, race, or UB; run a debugger | [diagnostics/SKILL.md](diagnostics/SKILL.md) |
| Profile a slow program or set a performance baseline | [diagnostics/SKILL.md](diagnostics/SKILL.md) > Profiling |
| Call C/C++ from Python (or expose a native library) | [ffi-interop/SKILL.md](ffi-interop/SKILL.md) |

## Symptom Router

Start here when you have a behavior, not a tool name.

| Symptom | Likely cause | Go to |
|---------|--------------|-------|
| Crash / `SIGSEGV` / `SIGABRT` | memory bug (UAF, overflow), UB | [diagnostics](diagnostics/SKILL.md) > Sanitizers (ASan/UBSan) |
| Intermittent wrong results, hangs under load | data race | [diagnostics](diagnostics/SKILL.md) > Sanitizers (TSan) |
| Slow / high CPU / high memory | hot path, allocation churn | [diagnostics](diagnostics/SKILL.md) > Profiling |
| `undefined reference` / `Undefined symbols` | link order, missing target link, ABI mismatch | [build-systems](build-systems/SKILL.md) > linking diagnostics |
| `Could NOT find <Pkg>` / missing headers | dependency not provided to the build | [build-systems](build-systems/SKILL.md) > dependency strategy |
| C++20 `import` fails / no `import std` | module support / standard / toolchain gap | [build-systems](build-systems/SKILL.md) > C++ modules |
| "Python can't call my C/C++ library" | no binding layer, or ABI/GIL boundary wrong | [ffi-interop](ffi-interop/SKILL.md) |
| Build works locally, breaks in CI / on the other OS | toolchain or generator drift; GNU/BSD divergence | [build-systems](build-systems/SKILL.md) > presets & toolchain files |

## Tool Version Snapshot (verify against your toolchain)

Floors this plugin assumes. Compiler and tool support shift between minor releases — confirm with `--version` and the [version-feature-matrix](../_shared/version-feature-matrix.md) before pinning in CI.

| Tool | Assumed floor | Why |
|------|---------------|-----|
| CMake | 4.x (≈4.3.x) baseline; legacy 3.28+ for `FILE_SET CXX_MODULES`, 3.23+ for presets-only | preset configure/build/test flow; `cmake_minimum_required` below 3.5 is a hard error on 4.x — silence legacy policy warnings with `CMAKE_POLICY_VERSION_MINIMUM` |
| Ninja | current stable | generator for fast incremental + `compile_commands.json` |
| Meson | 1.11 | stable `setup`/`compile`/`test` verbs |
| Conan | 2.29 (`CMakeConfigDeps` generator) | the only supported Conan; `CMakeConfigDeps` replaces `CMakeDeps` in Conan 2.x |
| GCC / Clang | see version-feature-matrix per standard | C23 / C++23 library bits land across minor releases *(verify)* |
| sanitizers | ship with GCC/Clang | ASan/UBSan/TSan/LSan; MSan clang-only *(verify)* |
| gdb / lldb | current stable | gdb Linux-first, lldb macOS-first |
| valgrind | current stable, **Linux-first** | memcheck/cachegrind/callgrind; limited/absent on recent macOS |
| perf | Linux only | hardware-counter profiling |
| hyperfine | current stable | reproducible wall-clock benchmarking |
| nanobind / pybind11 | current stable | C++ ↔ Python bindings (nanobind preferred for new) |

## Decision Tree

```
Tooling task?
├── "How do I build / link / depend / install?" → build-systems/SKILL.md
│   ├── CMake targets, presets, modules → build-systems/references/cmake-modern.md
│   ├── Meson or plain Make → build-systems/references/meson-and-make.md
│   ├── vcpkg / Conan / FetchContent / uv → build-systems/references/package-managers.md
│   └── CI wiring → build-systems/references/ci-pipelines.md
├── "It crashes / leaks / races / is slow" → diagnostics/SKILL.md
│   ├── Sanitizer flags & combinations → diagnostics/references/sanitizers.md
│   ├── Interactive debugging → diagnostics/references/gdb-lldb.md
│   └── Profiling & benchmarking → diagnostics/references/profiling-tools.md
└── "Python ↔ native boundary" → ffi-interop/SKILL.md
    ├── pybind11 / nanobind → ffi-interop/references/pybind11-nanobind.md
    └── extern "C" / C-API boundary → ffi-interop/references/c-api-boundaries.md
```

## Conventions Across Build & Diagnostics

- **Out-of-source builds always.** Build into `build/`, never in the source tree.
- **`CMAKE_EXPORT_COMPILE_COMMANDS=ON`** (or Meson's automatic `compile_commands.json`) so clang-tidy, clangd, and IDEs see real flags.
- **Single-command Bash invocations.** Use `cmake --build build`, `ctest --test-dir build`, `make -C build` — never `cd`-chains. Scoped Bash allowlists do not match compound commands.
- **RelWithDebInfo for profiling**, debug-info-bearing builds for sanitizers and debuggers; never profile or sanitize a stripped `Release` binary.

## Related Skills

- [build-systems](build-systems/SKILL.md) — modern CMake, presets, dependency strategy, C++ modules
- [diagnostics](diagnostics/SKILL.md) — sanitizers, gdb/lldb, profilers
- [ffi-interop](ffi-interop/SKILL.md) — Python ↔ C/C++ bindings
- [version-feature-matrix](../_shared/version-feature-matrix.md) — toolchain floors per standard
- [secure-coding](../_shared/secure-coding/SKILL.md) — hardening flags belong in the build, not as an afterthought
- [workflow-integration](../_shared/workflow-integration/SKILL.md) — Build Evidence and the cli-fallback screenshot norm
