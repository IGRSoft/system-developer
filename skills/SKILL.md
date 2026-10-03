---
name: skills
description: >-
  Index of the C, C++, Python, and Bash systems skills; routes a task to the
  right leaf skill. Use when writing C17/C23 or C++17/20/23 code, Python
  3.12-3.14 applications, or Bash scripts, configuring CMake or Meson builds,
  running sanitizers, debugging with gdb/lldb, profiling native or Python code,
  or binding Python to native libraries.
---

# Systems Skills Index

Routes C, C++, Python, Bash, and embedded work to the skill that covers it. Paths are relative to this file.

## Domains

| Domain | Entry skill | Focus |
|--------|-------------|-------|
| C | [`c-skills`](c/SKILL.md) | C17/C23 selection, C23 features, memory ownership, UB, atomics |
| C++ | [`cpp-skills`](cpp/SKILL.md) | C++17/20/23 standard-selection table, RAII, ranges, concepts, coroutines, concurrency |
| Python | [`python-skills`](python/SKILL.md) | 3.12-3.14 features, typing, concurrency, uv/ruff, pytest |
| Bash | [`bash-skills`](bash/SKILL.md) | Defensive scripting, POSIX portability, bats/shellcheck/shfmt |
| Embedded | [`embedded-skills`](embedded/SKILL.md) | Freestanding C/C++: MMIO, ISRs/startup, no-heap, fixed-point, linker scripts |
| Tooling | [`tooling-skills`](tooling/SKILL.md) | CMake/Meson/Make, sanitizers, gdb/lldb, profilers, FFI |
| Shared | [`_shared/_index.md`](_shared/_index.md) | Secure coding, version matrix, routing, severity, testing |

## I need help with...

### C and C++

| Task | Skill |
|------|-------|
| Choosing `-std` (C17 vs C23) or adopting a C23 feature | [`modern-c`](c/modern-c/SKILL.md) |
| A leak, double-free, or use-after-free in C | [`c-memory-ownership`](c/c-memory-ownership/SKILL.md) |
| Which C++ standard a feature needs | [`cpp-skills`](cpp/SKILL.md) |
| RAII, smart pointers, ranges, `std::expected`, `std::print` | [`modern-cpp`](cpp/modern-cpp/SKILL.md) |
| Threads, atomics, coroutines, or a C++ data race | [`cpp-concurrency`](cpp/cpp-concurrency/SKILL.md) |

### Python

| Task | Skill |
|------|-------|
| A Python 3.14 feature or its fallback | [`modern-python`](python/modern-python/SKILL.md) |
| asyncio vs threads vs free-threading vs subinterpreters | [`python-concurrency`](python/python-concurrency/SKILL.md) |
| Type annotations, PEP 695 generics, strict pyright/mypy | [`python-typing`](python/python-typing/SKILL.md) |
| uv/ruff setup, dependencies, lockfiles, project layout | [`python-tooling`](python/python-tooling/SKILL.md) |
| Writing or triaging pytest tests | [`python-testing`](python/python-testing/SKILL.md) |

### Bash and embedded

| Task | Skill |
|------|-------|
| Hardening a Bash script or fixing a quoting bug | [`bash-scripting`](bash/bash-scripting/SKILL.md) |
| bats tests, shellcheck/shfmt wiring | [`bash-testing`](bash/bash-testing/SKILL.md) |
| MMIO, ISRs, startup, linker scripts, cross-compilation | [`embedded-systems`](embedded/embedded-systems/SKILL.md) |
| Embedded C++ subset (`-fno-exceptions -fno-rtti`, freestanding stdlib) | [`embedded-cpp`](embedded/embedded-cpp/SKILL.md) |

### Builds, diagnostics, and cross-cutting

| Task | Skill |
|------|-------|
| CMakeLists, a broken build, choosing a package manager | [`build-systems`](tooling/build-systems/SKILL.md) |
| Picking a sanitizer, debugger, or profiler for a symptom | [`diagnostics`](tooling/diagnostics/SKILL.md) |
| Binding C/C++ to Python or designing an ABI boundary | [`ffi-interop`](tooling/ffi-interop/SKILL.md) |
| Untrusted input, subprocess calls, or secrets | [`secure-coding`](_shared/secure-coding/SKILL.md) |
| Whether a feature is available on a toolchain | [`version-feature-matrix.md`](_shared/version-feature-matrix.md) |
| Routing a file or repo to the right agent | [`language-detection.md`](_shared/language-detection.md) |

## Version Snapshot

Summary only; minimum toolchains and fallbacks are in [`_shared/version-feature-matrix.md`](_shared/version-feature-matrix.md).

| Language | Baseline | Newest | Headline of the newest |
|----------|----------|--------|------------------------|
| C | C17 | C23 | `nullptr`, `constexpr` objects, `typeof`, `<stdckdint.h>`, `_BitInt(N)`, `()` means `(void)` |
| C++ | C++17 | C++23 | `std::expected`, `std::print`, deducing this, `if consteval`, `std::mdspan`, `std::generator`. C++26 (DIS 2026) is emerging, not shipping: gate on `-std=c++2c` + feature-test macros |
| Python | 3.12 | 3.14 | Supported free-threading (PEP 779), t-strings (PEP 750), deferred annotations (PEP 649/749), subinterpreters (PEP 734), `compression.zstd` |
| Bash | 5.2 | 5.3 | `${ cmd; }` no-fork command substitution, `GLOBSORT` |

macOS `/bin/bash` is 3.2; install a current Bash and check `bash --version` (see [`bash-scripting`](bash/bash-scripting/SKILL.md)).

## Conventions

- Name the standard or version behind every version-specific claim, and hedge volatile minutiae with "verify against your toolchain".
- Native code builds clean under `-Wall -Wextra -Werror`; Python is ruff-clean; Bash is shellcheck-clean.
- Reproduce memory and concurrency bugs under ASan/UBSan/TSan before fixing them ([`diagnostics`](tooling/diagnostics/SKILL.md)).
