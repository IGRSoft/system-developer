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

Routes build, diagnostics, and FFI work to the leaf skill that teaches it. Toolchain floors (CMake, Meson, Conan): [version-feature-matrix](../_shared/version-feature-matrix.md) > Build / Toolchain Floor Quick Reference.

## Skill Selection

### Build

| I need to... | Go to | Deep dive |
|--------------|-------|-----------|
| Configure a CMake build: targets, presets, toolchain files, modules | [build-systems](build-systems/SKILL.md) | [cmake-modern.md](build-systems/references/cmake-modern.md) |
| Use Meson or plain Make | [build-systems](build-systems/SKILL.md) | [meson-and-make.md](build-systems/references/meson-and-make.md) |
| Pick vcpkg / Conan / FetchContent / uv | [build-systems](build-systems/SKILL.md) > Dependency Strategy | [package-managers.md](build-systems/references/package-managers.md) |
| Wire build, test, sanitize, lint into CI | [build-systems](build-systems/SKILL.md) | [ci-pipelines.md](build-systems/references/ci-pipelines.md) |

### Diagnostics

| I need to... | Go to | Deep dive |
|--------------|-------|-----------|
| Find/fix a crash, leak, race, or UB | [diagnostics](diagnostics/SKILL.md) | [sanitizers.md](diagnostics/references/sanitizers.md) |
| Run a debugger | [diagnostics](diagnostics/SKILL.md) > gdb / lldb Quickstart | [gdb-lldb.md](diagnostics/references/gdb-lldb.md) |
| Profile or benchmark | [diagnostics](diagnostics/SKILL.md) > Profiling Quickstart | [profiling-tools.md](diagnostics/references/profiling-tools.md) |

### Interop

| I need to... | Go to | Deep dive |
|--------------|-------|-----------|
| Call C/C++ from Python with pybind11 / nanobind | [ffi-interop](ffi-interop/SKILL.md) | [pybind11-nanobind.md](ffi-interop/references/pybind11-nanobind.md) |
| Design an `extern "C"` / C-API boundary | [ffi-interop](ffi-interop/SKILL.md) | [c-api-boundaries.md](ffi-interop/references/c-api-boundaries.md) |

## Symptom Router

Start here when you have a behavior, not a tool name.

### Runtime

| Symptom | Likely cause | Go to |
|---------|--------------|-------|
| Crash / `SIGSEGV` / `SIGABRT` | memory bug (UAF, overflow), UB | [diagnostics](diagnostics/SKILL.md) > Sanitizer Flag Sets (ASan/UBSan) |
| Intermittent wrong results, hangs under load | data race | [diagnostics](diagnostics/SKILL.md) > Sanitizer Flag Sets (TSan) |
| Slow / high CPU / high memory | hot path, allocation churn | [diagnostics](diagnostics/SKILL.md) > Profiling Quickstart |
| "Python can't call my C/C++ library" | no binding layer, or ABI/GIL boundary wrong | [ffi-interop](ffi-interop/SKILL.md) |

### Build

| Symptom | Likely cause | Go to |
|---------|--------------|-------|
| `undefined reference` / `Undefined symbols` | link order, missing target link, ABI mismatch | [build-systems](build-systems/SKILL.md) > Linking Diagnostics |
| `Could NOT find <Pkg>` / missing headers | dependency not provided to the build | [build-systems](build-systems/SKILL.md) > Dependency Strategy |
| C++20 `import` fails / no `import std` | module support, standard, or toolchain gap | [build-systems](build-systems/SKILL.md) > C++20 Modules |
| Builds locally, breaks in CI or on another OS | toolchain or generator drift | [cmake-modern.md](build-systems/references/cmake-modern.md) > CMakePresets Schema, Toolchain Files |

## Conventions

- Export `compile_commands.json` (`CMAKE_EXPORT_COMPILE_COMMANDS=ON`; Meson writes it automatically) so clang-tidy, clangd, and IDEs see the real flags.
- Run one command per Bash call with the tool's directory flag (`cmake --build build`, `ctest --test-dir build`, `make -C build`), not `cd` chains, so each command matches its scoped Bash allowlist entry.

## Related Skills

| I need to... | Go to |
|--------------|-------|
| Toolchain floors per language standard | [version-feature-matrix](../_shared/version-feature-matrix.md) |
| Hardening flags in the build | [secure-coding](../_shared/secure-coding/SKILL.md) |
