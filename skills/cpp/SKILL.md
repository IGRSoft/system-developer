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

Picks the C++ standard a feature needs and routes C++ work to the right leaf skill or reference.

## Standard Selection Table

Pick the lowest standard that provides the feature; if the toolchain is pinned lower, use the C++17 fallback. Library support lags compiler-core support, so gate on feature-test macros (`__cpp_lib_expected`, `__cpp_lib_print`, `__cpp_explicit_this_parameter`), not compiler versions. Per-feature toolchain minimums: [version-feature-matrix](../_shared/version-feature-matrix.md).

### C++17 (baseline)

`std::optional`, `std::variant`, `std::string_view`, CTAD, structured bindings, `if constexpr`.

### C++20

| Need | C++17 fallback |
|------|----------------|
| Concepts (`requires` clauses) | `std::enable_if` + `static_assert` |
| Ranges pipelines (`views::filter`, `views::transform`) | range-v3 |
| `std::format` | fmtlib (`fmt::format`) |
| `std::span` | pointer + size pair, or `gsl::span` |
| Three-way comparison `<=>` | hand-written comparison operators |
| Designated initializers | constructors or member-by-member init |
| `std::jthread` / `std::stop_token` | `std::thread` + RAII join wrapper + atomic flag |
| Coroutines (`co_await`, `co_yield`) | callbacks or explicit state machines |
| `consteval` / `constinit` | `constexpr` + discipline |
| Modules (`import std;` is C++23) | headers + PCH (still the safe default) |

### C++23

| Need | Fallback |
|------|----------|
| `std::expected` | `tl::expected` |
| `std::print` / `std::println` | fmtlib (`fmt::print`) |
| Deducing this (explicit object parameter) | CRTP |
| `std::generator` | range-v3 generators or handwritten iterators |
| `std::mdspan` | Kokkos `mdspan` reference implementation |
| `if consteval` | `std::is_constant_evaluated()` (C++20) |

### C++26 (not yet shipping)

Static reflection (P2996), contracts, `std::execution` (P2300), `std::inplace_vector`, `std::hive`, `std::optional<T&>`, `span::at`, `submdspan`, pack indexing, hardened standard library. Keep C++23 as the baseline and adopt features one at a time behind their `__cpp_*` macros under `-std=c++2c`, confirmed by a CI compile probe.

## Skill Selection

| I need to... | Go to |
|--------------|-------|
| Modern idioms, vocabulary types, constexpr family | [modern-cpp](modern-cpp/SKILL.md) |
| `unique_ptr` vs `shared_ptr` vs raw | [modern-cpp](modern-cpp/SKILL.md) > Ownership |
| A feature's details per standard | [cpp17](modern-cpp/references/cpp17-features.md), [cpp20](modern-cpp/references/cpp20-features.md), [cpp23](modern-cpp/references/cpp23-features.md) features |
| Exceptions vs `std::expected` | [error-handling.md](modern-cpp/references/error-handling.md) |
| Ranges pipelines | [ranges.md](modern-cpp/references/ranges.md) |
| Threads, atomics, memory ordering | [cpp-concurrency](cpp-concurrency/SKILL.md), [atomics-and-memory-model.md](cpp-concurrency/references/atomics-and-memory-model.md) |
| Coroutines, `std::generator` | [coroutines.md](cpp-concurrency/references/coroutines.md) |
| Migrate standards (17→20→23) | `/system-developer:fix-modernize` |

## Related Skills

| I need to... | Go to |
|--------------|-------|
| C++ on a microcontroller: `-fno-exceptions -fno-rtti`, no heap, ROM-able data | [embedded-cpp](../embedded/embedded-cpp/SKILL.md), [freestanding-stdlib-subset.md](../embedded/embedded-cpp/references/freestanding-stdlib-subset.md) |
| CMake, vcpkg, Conan | [build-systems](../tooling/build-systems/SKILL.md) |
| Sanitizers, debuggers | [diagnostics](../tooling/diagnostics/SKILL.md) |
| Python bindings | [ffi-interop](../tooling/ffi-interop/SKILL.md) |
| C-only translation units, `extern "C"` boundaries | [modern-c](../c/modern-c/SKILL.md) |
| Input validation, injection-safe process execution | [secure-coding](../_shared/secure-coding/SKILL.md) |
