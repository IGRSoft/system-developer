---
name: cpp-skills
description: >-
  C++ language skills navigation and standard selection for C++17/20/23.
  Use when writing or reviewing C++ code, deciding which language standard
  a feature requires, finding a C++17 fallback for a C++20/23 feature,
  applying RAII and modern idioms, or working with ranges, concepts,
  coroutines, std::expected, or std::print.
---

# C++ Skills

**Standard selection and navigation for C++17/20/23 development**

## Standard Selection Table (canonical)

Every C++ feature decision starts here. Pick the lowest standard that provides the feature; if your toolchain is pinned lower, use the fallback column.

| Need | Minimum standard | C++17 fallback |
|------|------------------|----------------|
| `std::optional` / `std::variant` / `std::string_view` | C++17 | — (baseline) |
| CTAD, structured bindings, `if constexpr` | C++17 | — (baseline) |
| Concepts (`requires` clauses) | C++20 | `std::enable_if` + `static_assert` |
| Ranges pipelines (`views::filter`, `views::transform`) | C++20 | range-v3 |
| `std::format` | C++20 | fmtlib (`fmt::format`) |
| `std::span` | C++20 | pointer + size pair, or `gsl::span` |
| Three-way comparison `<=>` | C++20 | hand-written comparison operators |
| Designated initializers | C++20 | constructors or member-by-member init |
| `std::jthread` / `std::stop_token` | C++20 | `std::thread` + RAII join wrapper + atomic flag |
| Coroutine machinery (`co_await`, `co_yield`) | C++20 | callbacks or explicit state machines |
| `consteval` / `constinit` | C++20 | `constexpr` + discipline |
| `std::expected` | C++23 | `tl::expected` |
| `std::print` / `std::println` | C++23 | fmtlib (`fmt::print`) |
| Deducing this (explicit object parameter) | C++23 | CRTP |
| `std::generator` | C++23 | range-v3 generators or handwritten iterators |
| `std::mdspan` | C++23 | Kokkos `mdspan` reference implementation |
| `if consteval` | C++23 | `std::is_constant_evaluated()` (C++20) |
| Modules / `import std;` | C++20 core, C++23-era tooling | headers + PCH (still the safe default) |

**Compiler reality (2026):** current GCC and Clang releases ship a complete C++20 core and most of the C++23 library above (`std::expected`, `std::print`, deducing this); MSVC tracks closely. Library support lags compiler-core support, so gate on feature-test macros (`__cpp_lib_expected`, `__cpp_lib_print`, `__cpp_explicit_this_parameter`) and verify against your toolchain rather than trusting version tables from memory.

Per-feature toolchain minimums: [version-feature-matrix](../_shared/version-feature-matrix.md).

## Skill Selection Guide

| I need to... | Use this skill |
|--------------|----------------|
| Write or review modern C++ idioms | [modern-cpp/SKILL.md](modern-cpp/SKILL.md) |
| Choose ownership: `unique_ptr` vs `shared_ptr` vs raw | [modern-cpp/SKILL.md](modern-cpp/SKILL.md) > Ownership |
| Decide exceptions vs `std::expected` | [modern-cpp/references/error-handling.md](modern-cpp/references/error-handling.md) |
| Build ranges pipelines | [modern-cpp/references/ranges.md](modern-cpp/references/ranges.md) |
| Use threads, atomics, or coroutines | [cpp-concurrency/SKILL.md](cpp-concurrency/SKILL.md) |
| Configure CMake/vcpkg/Conan | [build-systems](../tooling/build-systems/SKILL.md) |
| Run sanitizers or debuggers | [diagnostics](../tooling/diagnostics/SKILL.md) |
| Bind C++ to Python | [ffi-interop](../tooling/ffi-interop/SKILL.md) |

## Decision Tree

```
C++ task?
├── Which standard has feature X? → Standard Selection Table (above)
├── Writing/reviewing code → modern-cpp/SKILL.md
│   ├── C++17 baseline features → modern-cpp/references/cpp17-features.md
│   ├── C++20 concepts/ranges/format → modern-cpp/references/cpp20-features.md
│   ├── C++23 expected/print/deducing-this → modern-cpp/references/cpp23-features.md
│   ├── Ranges pipelines → modern-cpp/references/ranges.md
│   └── Error strategy → modern-cpp/references/error-handling.md
├── Threads, atomics, memory ordering → cpp-concurrency/SKILL.md
│   ├── Coroutines / std::generator → cpp-concurrency/references/coroutines.md
│   └── Memory model deep-dive → cpp-concurrency/references/atomics-and-memory-model.md
├── Build, packaging, dependencies → ../tooling/build-systems/SKILL.md
├── Crashes, leaks, races → ../tooling/diagnostics/SKILL.md
└── Migrating standards (17→20→23) → /system-developer:code-modernize
```

## File Overview

| File | Purpose |
|------|---------|
| [_index.md](_index.md) | Full navigation for the cpp/ subtree |
| [modern-cpp/SKILL.md](modern-cpp/SKILL.md) | Core idioms: RAII, vocabulary types, constexpr family |
| [modern-cpp/references/](modern-cpp/references/_index.md) | 5 deep-dive references (17/20/23 features, ranges, errors) |
| [cpp-concurrency/SKILL.md](cpp-concurrency/SKILL.md) | jthread, atomics, coroutines, TSan workflow |

## Related Skills

- [modern-c](../c/modern-c/SKILL.md) — C17/C23 for C-only translation units and `extern "C"` boundaries
- [secure-coding](../_shared/secure-coding/SKILL.md) — input validation and injection-safe process execution
- [version-feature-matrix](../_shared/version-feature-matrix.md) — toolchain minimums per standard
