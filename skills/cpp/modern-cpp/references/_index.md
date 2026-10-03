# Reference Index

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

- "Which standard do I need for feature X?" → [../../SKILL.md](../../SKILL.md)
- "Replace this enable_if/SFINAE mess" or "my constraint error is unreadable" → `cpp20-features.md` (concepts)
- "Format or print without iostream" → `std::format` in `cpp20-features.md`; `std::print` in `cpp23-features.md`
- "Return errors without throwing" → `error-handling.md`; `std::expected` chaining mechanics in `cpp23-features.md`
- "Rewrite raw loops as pipelines", "pipeline returns garbage / dangling view", "collect a view into a vector" → `ranges.md`
- "Kill this CRTP base class" → deducing this in `cpp23-features.md`
- "Designated initializer compile error", "static init order fiasco" → `cpp20-features.md`
- "Lazy sequences / generators" → `std::generator` in `cpp23-features.md`; machinery in [../../cpp-concurrency/references/coroutines.md](../../cpp-concurrency/references/coroutines.md)
- "Ownership, lifetimes, smart pointers" → [../SKILL.md](../SKILL.md)
