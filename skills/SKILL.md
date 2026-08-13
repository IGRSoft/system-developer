---
name: skills
description: >-
  Comprehensive C, C++, Python, and Bash systems development skills. Use when
  writing C17/C23 or C++17/20/23 code, developing Python 3.12-3.14 applications,
  authoring Bash scripts, configuring CMake or Meson builds, running sanitizers,
  debugging with gdb/lldb, profiling native or Python code, or binding Python
  to native libraries.
---

# Skills Index

## Overview

This collection provides guidance for systems-level development across four
languages — C, C++, Python, and Bash — plus the shared tooling that builds,
tests, sanitizes, profiles, and links them. The emphasis is on **version
specificity**: every feature carries a standard/version marker and a fallback
path, so guidance stays correct whether you target C17 or C23, C++17 or C++23,
Python 3.12 or the free-threaded 3.14, Bash 5.2 or 5.3. When a toolchain claim
matters, verify it against your toolchain and the canonical
[`_shared/version-feature-matrix.md`](_shared/version-feature-matrix.md) rather
than trusting memory.

## Quick Navigation

| Domain | Entry | Skills | Focus |
|--------|-------|--------|-------|
| [C](#c) | [`c/SKILL.md`](c/SKILL.md) | 1 + 2 leaves | C17/C23 selection, C23 features, memory ownership, UB, atomics |
| [C++](#c-1) | [`cpp/SKILL.md`](cpp/SKILL.md) | 1 + 2 leaves | C++17/20/23 standard selection, RAII, ranges, concepts, coroutines, concurrency |
| [Python](#python) | [`python/SKILL.md`](python/SKILL.md) | 1 + 5 leaves | 3.12-3.14 features, typing, concurrency, uv/ruff tooling, pytest |
| [Bash](#bash) | [`bash/SKILL.md`](bash/SKILL.md) | 1 + 2 leaves | Defensive scripting, POSIX portability, bats/shellcheck/shfmt |
| [Embedded](#embedded) | [`embedded/SKILL.md`](embedded/SKILL.md) | 1 + 2 leaves | Bare-metal/freestanding C & C++: MMIO, volatile, ISRs/startup, no-heap, fixed-point, linker scripts, embedded C++ subset |
| [Tooling](#tooling) | [`tooling/SKILL.md`](tooling/SKILL.md) | 1 + 3 leaves | CMake/Meson/Make, sanitizers, gdb/lldb, profilers, FFI/interop |
| [Shared](#shared) | [`_shared/_index.md`](_shared/_index.md) | 2 + references | Workflow integration, secure coding, versions, routing, severity |

**Total: 25 SKILL.md across 7 domains, plus shared references.**

## I need help with...

| Task | Go to |
|------|-------|
| Choosing `-std` (C17 vs C23) or adopting a C23 feature | [c/modern-c/SKILL.md](c/modern-c/SKILL.md) |
| Fixing a leak, double-free, or use-after-free in C | [c/c-memory-ownership/SKILL.md](c/c-memory-ownership/SKILL.md) |
| Deciding which C++ standard a feature needs | [cpp/SKILL.md](cpp/SKILL.md) (standard-selection table) |
| RAII, smart pointers, ranges, `std::expected`, `std::print` | [cpp/modern-cpp/SKILL.md](cpp/modern-cpp/SKILL.md) |
| Threads, atomics, coroutines, or a C++ data race | [cpp/cpp-concurrency/SKILL.md](cpp/cpp-concurrency/SKILL.md) |
| Adopting a Python 3.14 feature or finding a fallback | [python/modern-python/SKILL.md](python/modern-python/SKILL.md) |
| Picking asyncio vs threads vs free-threading vs subinterpreters | [python/python-concurrency/SKILL.md](python/python-concurrency/SKILL.md) |
| Type annotations, PEP 695 generics, strict pyright/mypy | [python/python-typing/SKILL.md](python/python-typing/SKILL.md) |
| uv/ruff setup, dependencies, lockfiles, project layout | [python/python-tooling/SKILL.md](python/python-tooling/SKILL.md) |
| Writing or triaging pytest tests | [python/python-testing/SKILL.md](python/python-testing/SKILL.md) |
| Hardening a Bash script or fixing a quoting bug | [bash/bash-scripting/SKILL.md](bash/bash-scripting/SKILL.md) |
| Writing bats tests, wiring shellcheck/shfmt | [bash/bash-testing/SKILL.md](bash/bash-testing/SKILL.md) |
| MMIO register access, ISRs, startup, linker scripts, or cross-compilation | [embedded/embedded-systems/SKILL.md](embedded/embedded-systems/SKILL.md) |
| C++ subset for embedded (`-fno-exceptions -fno-rtti`, freestanding stdlib) | [embedded/embedded-cpp/SKILL.md](embedded/embedded-cpp/SKILL.md) |
| Writing CMakeLists, fixing a build, choosing a package manager | [tooling/build-systems/SKILL.md](tooling/build-systems/SKILL.md) |
| Picking a sanitizer/debugger/profiler for a symptom | [tooling/diagnostics/SKILL.md](tooling/diagnostics/SKILL.md) |
| Binding C/C++ to Python or designing an ABI boundary | [tooling/ffi-interop/SKILL.md](tooling/ffi-interop/SKILL.md) |
| Reviewing untrusted input, subprocess calls, or secrets | [_shared/secure-coding/SKILL.md](_shared/secure-coding/SKILL.md) |
| Confirming a feature is available on a toolchain | [_shared/version-feature-matrix.md](_shared/version-feature-matrix.md) |
| Routing a file or repo to the right agent | [_shared/language-detection.md](_shared/language-detection.md) |

---

## C

C17/C23 standard selection, C23 feature adoption, memory ownership, undefined
behavior, and C11/C17 concurrency.

**Start here:** [c/SKILL.md](c/SKILL.md)

| Skill | Path | Description |
|-------|------|-------------|
| **modern-c** | [c/modern-c/SKILL.md](c/modern-c/SKILL.md) | C17/C23 standard selection, C23 quick wins, checked integer arithmetic, hygiene flags |
| **c-memory-ownership** | [c/c-memory-ownership/SKILL.md](c/c-memory-ownership/SKILL.md) | Ownership conventions, cleanup patterns, allocators, sanitizer-first debugging |

---

## C++

C++17/20/23 standard selection, modern idioms, and concurrency.

**Start here:** [cpp/SKILL.md](cpp/SKILL.md) — holds the canonical standard-selection table.

| Skill | Path | Description |
|-------|------|-------------|
| **modern-cpp** | [cpp/modern-cpp/SKILL.md](cpp/modern-cpp/SKILL.md) | RAII, Rule of Zero, smart pointers, vocabulary types, constexpr family, deducing this, std::print |
| **cpp-concurrency** | [cpp/cpp-concurrency/SKILL.md](cpp/cpp-concurrency/SKILL.md) | jthread/stop_token, atomics and memory ordering, coroutines, std::generator, TSan-first verification |

---

## Python

Python 3.12-3.14 language features, typing, concurrency, tooling, and testing.

**Start here:** [python/SKILL.md](python/SKILL.md)

| Skill | Path | Description |
|-------|------|-------------|
| **modern-python** | [python/modern-python/SKILL.md](python/modern-python/SKILL.md) | 3.12-3.14 features with version gates: t-strings, deferred annotations, except*, PEP 695, zstd |
| **python-typing** | [python/python-typing/SKILL.md](python/python-typing/SKILL.md) | PEP 695 generics, protocols, TypedDict/Literal/overload, strict pyright/mypy |
| **python-concurrency** | [python/python-concurrency/SKILL.md](python/python-concurrency/SKILL.md) | asyncio vs threads vs free-threading vs subinterpreters vs multiprocessing |
| **python-tooling** | [python/python-tooling/SKILL.md](python/python-tooling/SKILL.md) | uv as the single tool, ruff linter/formatter, pyproject.toml, lockfiles, CI |
| **python-testing** | [python/python-testing/SKILL.md](python/python-testing/SKILL.md) | pytest: plain-assert tests, fixtures, parametrization, async, mocking, coverage, Hypothesis |

---

## Bash

Defensive Bash scripting, POSIX portability, and shell testing.

**Start here:** [bash/SKILL.md](bash/SKILL.md)

| Skill | Path | Description |
|-------|------|-------------|
| **bash-scripting** | [bash/bash-scripting/SKILL.md](bash/bash-scripting/SKILL.md) | Strict-mode prologue, quoting, arrays, traps, safe resource handling |
| **bash-testing** | [bash/bash-testing/SKILL.md](bash/bash-testing/SKILL.md) | bats-core tests, sourceable scripts, PATH stubs, shellcheck/shfmt in CI |

---

## Embedded

Bare-metal and freestanding C & C++ development.

**Start here:** [embedded/SKILL.md](embedded/SKILL.md)

| Skill | Path | Description |
|-------|------|-------------|
| **embedded-systems** | [embedded/embedded-systems/SKILL.md](embedded/embedded-systems/SKILL.md) | Language-agnostic core: freestanding, MMIO/register access, `volatile` (not atomicity, not ordering), ISRs/startup, no-heap, fixed-point, linker scripts, cross-compilation |
| **embedded-cpp** | [embedded/embedded-cpp/SKILL.md](embedded/embedded-cpp/SKILL.md) | C++ subset: RAII without exceptions/RTTI, freestanding stdlib subset, static/placement-new, `constexpr`/`constinit` ROM-able data |

---

## Tooling

Build systems, diagnostics, and FFI/interop for all four languages.

**Start here:** [tooling/SKILL.md](tooling/SKILL.md)

| Skill | Path | Description |
|-------|------|-------------|
| **build-systems** | [tooling/build-systems/SKILL.md](tooling/build-systems/SKILL.md) | Modern CMake, CMakePresets, FetchContent vs vcpkg vs Conan, CMake 4.x, C++ modules, Meson/Make |
| **diagnostics** | [tooling/diagnostics/SKILL.md](tooling/diagnostics/SKILL.md) | Symptom → sanitizer/debugger/profiler routing with exact flags |
| **ffi-interop** | [tooling/ffi-interop/SKILL.md](tooling/ffi-interop/SKILL.md) | nanobind/pybind11/cffi/ctypes, extern "C" boundaries, GIL release, scikit-build-core |

---

## Shared

Cross-cutting patterns used by every agent, command, and skill.

**Start here:** [_shared/_index.md](_shared/_index.md)

| Skill | Path | Description |
|-------|------|-------------|
| **secure-coding** | [_shared/secure-coding/SKILL.md](_shared/secure-coding/SKILL.md) | Non-negotiable security rules and bug-class defenses for C, C++, Python, Bash |
| version-feature-matrix | [_shared/version-feature-matrix.md](_shared/version-feature-matrix.md) | Standards/versions → minimum toolchains + headline features (canonical) |
| language-detection | [_shared/language-detection.md](_shared/language-detection.md) | Marker → language → agent routing table |
| model-selection | [_shared/model-selection.md](_shared/model-selection.md) | Per-agent model/effort/maxTurns assignments |
| severity-matrix | [_shared/severity-matrix.md](_shared/severity-matrix.md) | Severity levels, P0-P3 priorities, coverage requirements |
| testing-principles | [_shared/testing-principles.md](_shared/testing-principles.md) | Test pyramid, per-language framework matrix, quality gates |

---

## Cross-Language Version Snapshot

A summary only — the canonical lookup with minimum toolchains and fallback rows
is [`_shared/version-feature-matrix.md`](_shared/version-feature-matrix.md).
Compiler-support tables shift between minor releases; verify against your
toolchain before relying on a feature.

| Language | Baseline | Newest | Headline of the newest |
|----------|----------|--------|------------------------|
| C | C17 (portability baseline) | C23 | `nullptr`, `constexpr` objects, `typeof`, `<stdckdint.h>`, `_BitInt(N)`, `()` means `(void)` |
| C++ | C++17 | C++23 (+ C++26 emerging) | C++23: `std::expected`, `std::print`/`println`, deducing this, `if consteval`, `std::mdspan`, `std::generator`. C++26 (DIS 2026 — emerging, not shipping): static reflection (P2996), contracts, `std::execution` (P2300), `std::inplace_vector`, `std::optional<T&>` — gate on `-std=c++2c` + feature-test macros |
| Python | 3.12 | 3.14 | Free-threading supported (PEP 779), t-strings (PEP 750), deferred annotations (PEP 649/749), subinterpreters (PEP 734), `compression.zstd` |
| Bash | 5.2 | 5.3 (current stable) | `${ cmd; }` / `${ |cmd; }` no-fork command substitution, `GLOBSORT`, `compat` updates |

> **macOS caveat:** the system `/bin/bash` is 5.x-incompatible 3.2 — install a
> current Bash via your package manager and verify with `bash --version`. See
> [bash/bash-scripting/SKILL.md](bash/bash-scripting/SKILL.md).

## Conventions

- **Version markers everywhere.** Every version-specific claim names a standard
  or version and links to the matrix; volatile minutiae are hedged with "verify
  against your toolchain" instead of asserting an uncertain minor version.
- **Warnings as errors.** Native code is expected to build `-Wall -Wextra
  -Werror` clean; Python ruff-clean; Bash shellcheck-clean.
- **Sanitizer-first.** Memory and concurrency bugs are reproduced under
  ASan/UBSan/TSan before they are "fixed" — see
  [tooling/diagnostics/SKILL.md](tooling/diagnostics/SKILL.md).

## Related Documentation

- [`_shared/version-feature-matrix.md`](_shared/version-feature-matrix.md) — canonical version/toolchain lookup
- [`_shared/language-detection.md`](_shared/language-detection.md) — file/repo → agent routing
- [`_index.md`](_index.md) — full navigation index of every skill directory
