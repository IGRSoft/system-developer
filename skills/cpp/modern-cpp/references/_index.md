# Reference Index

Quick navigation for the modern-cpp skill references.

## Per-Standard Feature Catalogs

| File | Use it for |
|------|------------|
| `cpp17-features.md` | the C++17 baseline: `optional`/`variant`/`string_view`, CTAD, structured bindings, `if constexpr`, fold expressions, `filesystem`, parallel algorithms |
| `cpp20-features.md` | concepts and `requires`, `std::format`, `span`, three-way comparison `<=>`, designated initializers, `consteval`/`constinit`, modules overview |
| `cpp23-features.md` | `std::expected`, `std::print`/`println`, deducing this, `std::generator`, `mdspan`, `if consteval`, `ranges::to`, monadic `optional` |

## Cross-Cutting Topics

| File | Use it for |
|------|------------|
| `ranges.md` | views and pipeline composition, lazy evaluation, dangling/borrowed-range rules, projections, materializing results, range-v3 fallback on C++17 |
| `error-handling.md` | choosing exceptions vs `std::expected` vs error codes, `noexcept` policy, exception-safety guarantees, error types at API/ABI boundaries |

## Problem Router

- "Which standard do I need for feature X?" → [../../SKILL.md](../../SKILL.md) standard-selection table
- "I'm stuck on C++17 — what's the modern baseline?" → `cpp17-features.md`
- "Replace this enable_if/SFINAE mess" → `cpp20-features.md` (concepts)
- "My constraint error is unreadable" → `cpp20-features.md` (concepts diagnostics)
- "Format or print without iostream" → C++20 `std::format` in `cpp20-features.md`; C++23 `std::print` in `cpp23-features.md`
- "Return errors without throwing" → `error-handling.md`
- "`std::expected` chaining (`and_then`, `transform`, `or_else`)" → `cpp23-features.md`, policy in `error-handling.md`
- "Rewrite raw loops as pipelines" → `ranges.md`
- "Ranges pipeline returns garbage / dangling view" → `ranges.md` (borrowed ranges)
- "Collect a view into a vector" → `ranges.md` (`ranges::to`, C++23)
- "Kill this CRTP base class" → deducing this in `cpp23-features.md`
- "Designated initializer compile error" → `cpp20-features.md` (declaration-order rule)
- "Static init order fiasco" → `constinit` in `cpp20-features.md`
- "Lazy sequences / generators" → `std::generator` in `cpp23-features.md`; machinery in [../../cpp-concurrency/references/coroutines.md](../../cpp-concurrency/references/coroutines.md)
- "Ownership, lifetimes, smart pointers" → [../SKILL.md](../SKILL.md) (not a reference topic — core skill)
