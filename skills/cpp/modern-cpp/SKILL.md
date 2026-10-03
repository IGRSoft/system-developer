---
name: modern-cpp
description: >-
  Modern C++ core idioms: RAII, Rule of Zero, smart-pointer ownership,
  vocabulary types, the constexpr family, deducing this, and std::print.
  Use when writing or reviewing C++ code, choosing between unique_ptr and
  shared_ptr, picking parameter types like string_view and span, replacing
  CRTP or iostream, or deciding which C++17/20/23 feature to reach for.
---

# Modern C++

Which standard has feature X: [cpp entry skill](../SKILL.md) standard-selection table. Deep dives: [references/](references/_index.md).

## Ownership: RAII and the Rule of Zero

Every resource (memory, file, socket, lock) is owned by exactly one object whose destructor releases it. Default to the Rule of Zero: declare no destructor and no copy/move members — let members manage themselves.

```cpp
class Parser {
    std::string buffer_;            // owns its memory
    std::unique_ptr<Lexer> lexer_;  // owns the lexer
    std::vector<Token> tokens_;     // owns the tokens
    // No ~Parser, no copy/move declarations: Rule of Zero.
};
```

If you declare any of destructor/copy/move, declare, `=default`, or `=delete` all five (Rule of Five), and take it as a sign the raw resource belongs in its own small RAII wrapper.

### Smart-pointer policy

| Pointer | Meaning | Use |
|---------|---------|-----|
| `std::unique_ptr<T>` | sole ownership | default for any heap allocation |
| `std::shared_ptr<T>` | genuinely shared lifetime | rare: only when "last owner cleans up" is the real design |
| `T*` / `T&` | non-owning observer | parameters and back-references; don't `delete` through it |
| `std::weak_ptr<T>` | break `shared_ptr` cycles | caches, observers of shared objects |

- `std::make_unique` / `std::make_shared`; no naked `new`/`delete` in application code.
- Pass `unique_ptr` by value only to transfer ownership; if the callee just uses the object, pass `T&` or `T*`.
- A `shared_ptr` parameter means "I participate in ownership". For mere access, take `const T&`.

## Vocabulary Types

| You have | Take parameter as | Min standard | Trap |
|----------|-------------------|--------------|------|
| read-only string data | `std::string_view` | C++17 | non-owning: see lifetime trap below |
| read-only contiguous sequence | `std::span<const T>` | C++20 (C++17: pointer + size) | same lifetime trap |
| mutable contiguous sequence | `std::span<T>` | C++20 | same lifetime trap |
| maybe-a-value | `std::optional<T>` | C++17 | `*opt` on empty is UB; `.value()` throws instead |
| one of N alternatives | `std::variant<...>` | C++17 | prefer `std::visit` over blind `std::get` |
| success or domain error | `std::expected<T, E>` | C++23 (C++17: `tl::expected`) | see [error-handling](references/error-handling.md) |
| callable to *store* | `std::function` / `std::move_only_function` (C++23) | C++17 | for invocation-only, take a template parameter |

### The string_view/span lifetime trap

`string_view` and `span` are borrowed references; they don't extend the owner's lifetime:

```cpp
std::string_view sv = std::string{"temp"};     // dangles: temporary destroyed at ';'
std::string_view broken() {
    std::string local = compute();
    return local;                              // dangles: view of a dead local
}
std::span<const int> sp = std::vector{1, 2, 3}; // dangles: temporary vector
```

Use them as parameters (the caller guarantees lifetime), almost never as return types or data members; a member that keeps text stores `std::string`. Lifetime warnings (`-Wdangling-gsl` and friends) catch some cases; ASan is the verifier.

## Compile-Time Spectrum: constexpr → consteval → constinit → if consteval

| Keyword | Min standard | Meaning | Use for |
|---------|--------------|---------|---------|
| `constexpr` function | C++17 | *may* run at compile time | default for pure computations |
| `consteval` | C++20 | *must* run at compile time | compile-time-only APIs |
| `constinit` | C++20 | static initialized at compile time, mutable at runtime | globals; ends the static-init-order fiasco |
| `if consteval` | C++23 | branch on evaluation context | split compile-time and runtime impls (C++20: `std::is_constant_evaluated()`) |

```cpp
constinit std::atomic<int> counter{0};          // no runtime static init

constexpr double smart_sqrt(double x) {
    if consteval { return constexpr_sqrt(x); }  // C++23
    else { return std::sqrt(x); }               // runtime: libm
}
```

`constinit` is not `const`; write `constinit const` for a constant that must not be dynamically initialized.

## Deducing This (C++23): the CRTP Killer

The explicit object parameter deduplicates const/ref overloads and replaces CRTP for static polymorphism:

```cpp
struct Widget {
    // One template instead of four &/const&/&&/const&& overloads:
    template <typename Self>
    auto&& name(this Self&& self) { return std::forward<Self>(self).name_; }
};

// CRTP replacement: no template base, no static_cast<Derived*>(this)
struct Animal {
    void speak(this auto&& self) { self.make_sound(); }  // deduces Cat, Dog...
};
struct Cat : Animal { void make_sound() { std::println("meow"); } };
```

C++17/20 fallback: classic CRTP (`template <class Derived> struct Base`). Guard shared headers with `__cpp_explicit_this_parameter`.

## Output: std::print over iostream

```cpp
std::println("processed {} items in {:.2f}s", count, secs);  // C++23 <print>
// C++20: std::cout << std::format("...{}...", x);
// C++17: fmt::print("...{}...", x);                          // fmtlib
```

Prefer `std::print`/`std::println` (C++23) or `std::format` (C++20) over `operator<<` chains: type-safe, locale-independent by default, one call per line, and `std::print` writes UTF-8 correctly. Keep iostream for incremental streaming of large output or existing `operator<<` ecosystems.

## Sugar: CTAD, Structured Bindings, Designated Initializers

```cpp
std::pair p{1, "one"sv};                  // CTAD (C++17): no make_pair
std::lock_guard lock{mutex_};             // CTAD: no <std::mutex>

for (const auto& [key, value] : map) { /* ... */ }   // structured bindings (C++17)
auto [iter, inserted] = set.insert(x);

struct Config { int port; bool verbose; std::string host; };
Config cfg{.port = 8080, .verbose = true, .host = "::1"};   // C++20
```

C++ designated initializers are stricter than C99: they follow declaration order and can't mix with positional initializers. Out of order (`.host` before `.port`) is ill-formed; GCC rejects it, Clang only warns (`-Wreorder-init-list`).

## Feature Routing

| Topic | Min standard | Reference |
|-------|--------------|-----------|
| `optional`, `variant`, `string_view`, CTAD, `if constexpr`, folds, filesystem | C++17 | [references/cpp17-features.md](references/cpp17-features.md) |
| Concepts, `std::format`, `span`, `<=>`, designated initializers, `consteval`/`constinit`, modules | C++20 | [references/cpp20-features.md](references/cpp20-features.md) |
| `std::expected`, `std::print`, deducing this, `std::generator`, `mdspan`, `if consteval`, `ranges::to` | C++23 | [references/cpp23-features.md](references/cpp23-features.md) |
| Views, pipelines, dangling rules, projections, range-v3 fallback | C++20 (C++17: range-v3) | [references/ranges.md](references/ranges.md) |
| Exceptions vs `expected`, `noexcept` policy, safety guarantees | C++17+ | [references/error-handling.md](references/error-handling.md) |
| `jthread`, atomics, coroutine machinery | C++20 | [cpp-concurrency](../cpp-concurrency/SKILL.md) |

## Diagnostics: Compile Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `call to deleted constructor of 'std::unique_ptr<T>'` | copying a `unique_ptr` | `std::move` to transfer, or pass `T&`/`T*` to observe |
| `constraints not satisfied` wall of notes | concept rejected the type | `static_assert(TheConcept<T>);` near the call shows the failed atom ([cpp20-features](references/cpp20-features.md)) |
| `call to consteval function ... is not a constant expression` | runtime argument to `consteval` | make inputs `constexpr`, or downgrade to `constexpr` |
| `designator order ... does not match declaration order` | out-of-order designated initializers | reorder to match member declaration order |
| `no member named 'expected'/'print' in namespace 'std'` | `-std=c++23` missing or stdlib lacks it | set the standard, check `__cpp_lib_expected`/`__cpp_lib_print`; fall back to `tl::expected`/fmtlib |

## Diagnostics: Runtime Symptoms

| Symptom | Cause | Fix |
|---------|-------|-----|
| ASan `heap-use-after-free` with `string_view::data` / `span` in the stack | view outlived its owner | store `std::string`/container; keep views to parameters |
| crash before `main()` / value depends on TU link order | static initialization order fiasco | `constinit` globals or function-local `static` accessors |
| `bad_optional_access` in production | unchecked `.value()` on empty optional | branch on `has_value()`, or `value_or`/monadic ops (C++23) |
| garbled multithreaded log output via `<<` | interleaving between chained `<<` calls | one `std::print`/`fmt::print` call per line |

## Related Skills

- [cpp-concurrency](../cpp-concurrency/SKILL.md) — jthread, atomics, memory ordering, coroutines
- [modern-c](../../c/modern-c/SKILL.md) — C17/C23 idioms for C translation units and `extern "C"` boundaries
- [build-systems](../../tooling/build-systems/SKILL.md) — setting the standard per target, CMake presets, package managers
- [diagnostics](../../tooling/diagnostics/SKILL.md) — sanitizers that verify the ownership and lifetime rules above
- [secure-coding](../../_shared/secure-coding/SKILL.md) — input validation and injection-safe patterns
