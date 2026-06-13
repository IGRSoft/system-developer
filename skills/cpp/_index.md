# C++ Skills Index

Quick navigation for C++17/20/23 language skills.

## Core Skills

| File | Description |
|------|-------------|
| `SKILL.md` | Entry point: canonical standard-selection table (need → minimum standard → C++17 fallback), decision tree |
| `modern-cpp/SKILL.md` | RAII, Rule of Zero, smart-pointer policy, vocabulary types, constexpr family, deducing this, std::print |
| `cpp-concurrency/SKILL.md` | jthread, atomics, memory ordering defaults, coroutines, TSan-first workflow |

## Subdirectories

| Directory | Contents | Description |
|-----------|----------|-------------|
| `modern-cpp/` | 1 skill + 5 refs | Core idioms and per-standard feature catalogs (C++17/20/23, ranges, error handling) |
| `cpp-concurrency/` | 1 skill + 2 refs | Threads, atomics and memory model, coroutines |

## Reference Files

| File | Use it for |
|------|------------|
| `modern-cpp/references/cpp17-features.md` | C++17 baseline: optional/variant/string_view, CTAD, structured bindings, if constexpr |
| `modern-cpp/references/cpp20-features.md` | Concepts, std::format, span, `<=>`, designated initializers, consteval/constinit |
| `modern-cpp/references/cpp23-features.md` | std::expected, std::print, deducing this, std::generator, mdspan, if consteval |
| `modern-cpp/references/ranges.md` | Views, pipelines, dangling rules, ranges::to, range-v3 fallback |
| `modern-cpp/references/error-handling.md` | Exceptions vs std::expected, noexcept policy, exception-safety guarantees |
| `cpp-concurrency/references/coroutines.md` | Coroutine machinery, std::generator, awaitable design |
| `cpp-concurrency/references/atomics-and-memory-model.md` | Memory orderings, happens-before, lock-free patterns |

## Quick Links by Problem

### "I need to..."

- **Know which standard has feature X** → `SKILL.md` > Standard Selection Table
- **Pick unique_ptr vs shared_ptr vs raw pointer** → `modern-cpp/SKILL.md` > Ownership
- **Avoid string_view/span dangling** → `modern-cpp/SKILL.md` > Vocabulary Types
- **Choose constexpr vs consteval vs constinit** → `modern-cpp/SKILL.md` > Compile-Time Spectrum
- **Replace CRTP with deducing this** → `modern-cpp/SKILL.md` > Deducing This
- **Return errors without exceptions** → `modern-cpp/references/error-handling.md`
- **Write a ranges pipeline on C++17** → `modern-cpp/references/ranges.md` (range-v3 fallback)
- **Stop a data race** → `cpp-concurrency/SKILL.md`
- **Understand memory_order_acquire** → `cpp-concurrency/references/atomics-and-memory-model.md`
- **Write a generator coroutine** → `cpp-concurrency/references/coroutines.md`
- **Set up CMake or vcpkg** → `../tooling/build-systems/SKILL.md`
- **Run ASan/UBSan/TSan** → `../tooling/diagnostics/SKILL.md`
