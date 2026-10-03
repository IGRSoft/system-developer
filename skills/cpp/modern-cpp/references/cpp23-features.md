# C++23 Features

C++23 language and library features with their rules and pre-23 fallbacks. The new view adaptors, `fold_left`, and `ranges::to` live in [ranges.md](ranges.md); when to pick `expected` over exceptions, in [error-handling.md](error-handling.md).

## Availability at a Glance

Gate every C++23 feature on its feature-test macro, not a compiler version: library support lags the core language, and the three standard libraries adopted these pieces at different times.

The slowest adopters were `flat_map`/`flat_set`, `std::generator` on libc++, and `import std` tooling; keep the fallback wired in for any target you can't pin. C++26 fills some gaps below (e.g. `submdspan`); see the C++26 section of [../../SKILL.md](../../SKILL.md).

### Language and tooling features

| Feature | Kind | Feature-test macro | Pre-23 fallback |
|---------|------|--------------------|-----------------|
| Deducing this | language | `__cpp_explicit_this_parameter >= 202110L` | CRTP; hand-written const/ref overload sets |
| `if consteval` | language | `__cpp_if_consteval >= 202106L` | `std::is_constant_evaluated()` (C++20) — see trap below |
| `import std;` | language + tooling | `__cpp_lib_modules >= 202207L` (presence ≠ build support) | `#include` headers, optionally PCH |

### Vocabulary and callable types

| Feature | Kind | Feature-test macro | Pre-23 fallback |
|---------|------|--------------------|-----------------|
| `std::expected` | library | `__cpp_lib_expected >= 202202L` | `tl::expected` (API-compatible) |
| `expected` monadic ops | library | `__cpp_lib_expected >= 202211L` | `tl::expected` (ships monadic ops) |
| Monadic `std::optional` | library | `__cpp_lib_optional >= 202110L` | explicit `if (opt)` chains |
| `std::move_only_function` | library | `__cpp_lib_move_only_function >= 202110L` | `std::function` + `shared_ptr` capture; `fu2::unique_function`; `absl::AnyInvocable` |

### Output, views, containers, and diagnostics

| Feature | Kind | Feature-test macro | Pre-23 fallback |
|---------|------|--------------------|-----------------|
| `std::print` / `println` | library | `__cpp_lib_print >= 202207L` | fmtlib `fmt::print`; C++20 `std::format` + `std::cout` |
| `std::generator` | library | `__cpp_lib_generator >= 202207L` | range-v3 generators; handwritten iterators |
| `std::mdspan` | library | `__cpp_lib_mdspan >= 202207L` | Kokkos `mdspan` reference implementation (works on C++17) |
| `std::flat_map` / `flat_set` | library | `__cpp_lib_flat_map` / `__cpp_lib_flat_set >= 202207L` | `boost::container::flat_map`; sorted `vector` + `lower_bound` |
| `std::stacktrace` | library | `__cpp_lib_stacktrace >= 202011L` | `boost::stacktrace` |

### Small utilities

| Feature | Kind | Feature-test macro | Pre-23 fallback |
|---------|------|--------------------|-----------------|
| `string::contains` | library | `__cpp_lib_string_contains >= 202011L` | `s.find(x) != std::string::npos` |
| `std::to_underlying` | library | `__cpp_lib_to_underlying >= 202102L` | `static_cast<std::underlying_type_t<E>>(e)` |
| `std::unreachable` | library | `__cpp_lib_unreachable >= 202202L` | `__builtin_unreachable()` / `__assume(false)` |
| `std::byteswap` | library | `__cpp_lib_byteswap >= 202110L` | `__builtin_bswap32` and friends |
| `std::out_ptr` / `inout_ptr` | library | `__cpp_lib_out_ptr >= 202106L` | temporary raw pointer + manual `reset` |

### Gating on the macro

```cpp
#include <version>   // pulls in all feature-test macros without other headers

#if defined(__cpp_lib_expected) && __cpp_lib_expected >= 202211L
    #include <expected>
    template <class T, class E> using Expected = std::expected<T, E>;
#else
    #include <tl/expected.hpp>
    template <class T, class E> using Expected = tl::expected<T, E>;
#endif
```

Toolchain minimums per feature: [version-feature-matrix](../../../_shared/version-feature-matrix.md).

## Deducing This (Explicit Object Parameter)

C++23 language feature (P0847). A member function may take its object as an explicit first parameter named with `this`. The object's type and value category are then deduced like any other template parameter.

### Killing the const/ref overload quartet

Pre-23, exposing a member through all value categories needs four overloads. With deducing this, one template covers all of them:

```cpp
class Box {
    std::string name_;
public:
    // C++23: one function replaces &, const&, &&, const&& overloads
    template <typename Self>
    auto&& name(this Self&& self) {
        return std::forward<Self>(self).name_;
    }
};

Box b;
b.name();              // Self = Box&         → std::string&
std::move(b).name();   // Self = Box          → std::string&&
const Box cb;
cb.name();             // Self = const Box&   → const std::string&
```

`std::forward<Self>(self).member` forwards the value category onto the member, so an rvalue `Box` yields an rvalue `string` callers can steal.

### CRTP replacement

Static polymorphism without a templated base class or `static_cast<Derived*>(this)`:

```cpp
// C++23
struct Animal {
    void speak(this auto&& self) { self.make_sound(); }  // self deduces Cat, Dog…
};
struct Cat : Animal { void make_sound() const { std::println("meow"); } };
struct Dog : Animal { void make_sound() const { std::println("woof"); } };

Cat{}.speak();  // "meow": no virtual, no CRTP boilerplate
```

```cpp
// Pre-23 fallback: classic CRTP
template <class Derived>
struct Animal {
    void speak() { static_cast<Derived&>(*this).make_sound(); }
};
struct Cat : Animal<Cat> { void make_sound() const { /* … */ } };
```

### Recursive lambdas

Pre-23, a lambda can't name itself without `std::function` or a Y-combinator. Now:

```cpp
auto fib = [](this auto self, int n) -> long {
    return n < 2 ? n : self(n - 1) + self(n - 2);
};
```

### By-value this for small types

For small, cheap-to-copy types (iterators, views, `string_view` wrappers), taking the object by value can beat the implicit `const&`:

```cpp
struct SmallIter {
    int* p;
    auto deref(this SmallIter self) { return *self.p; }  // passed in a register
};
```

### Rules and limitations

- An explicit-object member function cannot be `static`, `virtual`, or cv/ref-qualified (the qualification lives on the `Self` parameter instead).
- Inside the body there is no implicit `this`; access members through `self`.
- Taking its address yields a plain function pointer (`auto (*)(Box&)`), not a pointer-to-member, which changes how callback registries store them.
- A by-value parameter of a concrete type (`this Base self`) slices derived objects; `this auto self` copies the derived type. Deduce with `Self&&` unless you want a copy.

Guard headers shared with older toolchains with `__cpp_explicit_this_parameter`; the CRTP fallback swaps in mechanically.

## std::expected and Monadic Error Chaining

C++23 library feature (P0323; monadic operations P2505), header `<expected>`. `std::expected<T, E>` holds a value `T` or an error `E`, making fallibility part of the signature. Pre-23 fallback: `tl::expected` (API-compatible). This section covers mechanics; policy is in `error-handling.md`.

### Construction and observation

```cpp
#include <expected>

enum class ParseError { empty, not_a_number, out_of_range };

std::expected<int, ParseError> parse_port(std::string_view s) {
    if (s.empty()) return std::unexpected(ParseError::empty);
    int value{};
    auto [ptr, ec] = std::from_chars(s.data(), s.data() + s.size(), value);
    if (ec != std::errc{}) return std::unexpected(ParseError::not_a_number);
    if (value < 1 || value > 65535) return std::unexpected(ParseError::out_of_range);
    return value;   // implicit success construction
}

auto r = parse_port(input);
if (r) {
    use(*r);                 // operator*: unchecked, UB if r holds an error
} else {
    log(r.error());          // error(): unchecked, UB if r holds a value
}
int port = r.value_or(8080); // checked, with default
```

### Checked access, void results, and error size

- `r.value()` is the checked accessor: it throws `std::bad_expected_access<E>` when `r` holds an error.
- `std::expected<void, E>` models "action that can fail with no result"; `has_value()` and the monadic ops still work.
- Keep `E` small (an enum, or a small struct with an enum + context). `expected` stores `T` and `E` in a union, so a fat `E` taxes every return.

### Monadic operations (require `__cpp_lib_expected >= 202211L`)

| Operation | Callable takes | Callable returns | Runs when |
|-----------|----------------|------------------|-----------|
| `and_then(f)` | `T` | `std::expected<U, E>` | value present |
| `transform(f)` | `T` | plain `U` (wrapped for you) | value present |
| `or_else(f)` | `E` | `std::expected<T, F>` | error present |
| `transform_error(f)` | `E` | plain `F` (wrapped for you) | error present |
| `error_or(e)` | — | `E` | either (default on success) |

### Chaining example

```cpp
std::expected<Config, ParseError> load(std::string_view path);

auto port = load(path)
    .and_then([](Config c) { return parse_port(c.port_string); }) // may fail again
    .transform([](int p) { return p + offset; })                  // cannot fail
    .or_else([](ParseError e) -> std::expected<int, ParseError> {
        log_warning(e);
        return 8080;                                              // recover
    });
```

After the first error, later `and_then`/`transform` calls are skipped and the error propagates untouched. Use `transform_error` at module boundaries to convert a low-level error into the layer's own type (boundary translation in `error-handling.md`).

### What expected doesn't do

- No early-return sugar (C++ has no `?` operator): chain monadically or check-and-return at each level. If the project already has a `TRY(expr)` macro, use it rather than inventing a second.
- `return err;` never constructs an error: it fails to compile or, when `E` converts to `T`, silently becomes a value. Wrap errors in `std::unexpected`.

## Monadic std::optional

C++23 library addition (P0798). `std::optional` gains the same chaining vocabulary: `and_then`, `transform`, `or_else`. Gate on `__cpp_lib_optional >= 202110L`.

```cpp
std::optional<User> find_user(int id);

// C++23: declarative chain
auto city = find_user(id)
    .and_then([](const User& u) { return u.address; })   // optional<Address>
    .transform([](const Address& a) { return a.city; })  // optional<std::string>
    .value_or("unknown");

// Pre-23 fallback: explicit chain
std::string city2 = "unknown";
if (auto u = find_user(id); u && u->address) city2 = u->address->city;
```

`or_else` takes a nullary callable returning `optional<T>` (unlike `expected::or_else`, there is no error to pass).

Use `optional` when absence isn't an error, `expected` when the caller needs to know why (`error-handling.md`).

## std::print and std::println

C++23 library feature (P2093), headers `<print>` and (for `ostream` overloads) `<ostream>`. Output built on the C++20 `std::format` machinery.

```cpp
#include <print>

std::println("processed {} items in {:.2f}s", count, seconds);
std::print("no trailing newline; ");
std::println(stderr, "warning: {} retries", retries);   // FILE* overload
std::println(log_stream, "to any ostream");             // <ostream> overload
```

### Advantages over `operator<<`

Over `operator<<` chains it gives:

- Compile-time checked format strings: a `{}`/argument mismatch is a compile error.
- One call per line, so threads don't interleave mid-line as they can between `<<` segments.
- Locale independence by default (`{:L}` opts in).
- Correct UTF-8 to a terminal, including Windows consoles, when the literal encoding is UTF-8.

Behavior notes:

- `std::print` doesn't flush; call `std::fflush(stdout)` where latency matters.
- One `std::formatter<T>` specialization serves both `std::format` and `std::print`.
- Printing a range (`std::println("{}", vec)`) is a separate feature (`__cpp_lib_format_ranges`); check it independently.

### Fallbacks

```cpp
// C++20: same format machinery, manual stream write
std::cout << std::format("processed {} items\n", count);

// C++17: fmtlib — std::print is standardized fmt; migration is s/fmt::/std::/
fmt::print("processed {} items\n", count);
```

If the codebase already uses fmtlib, stay on `fmt::` rather than mixing; it also ships formatting features ahead of standard libraries.

## std::generator

C++23 library feature (P2502), header `<generator>`. The first standard coroutine return type: a lazy, synchronous, move-only view that produces elements on demand via `co_yield`.

```cpp
#include <generator>

std::generator<int> collatz(int n) {
    while (n != 1) {
        co_yield n;
        n = (n % 2 == 0) ? n / 2 : 3 * n + 1;
    }
    co_yield 1;
}

for (int x : collatz(27)) std::print("{} ", x);   // computed one at a time
```

Key properties:

- Lazy: the body doesn't run until iteration begins; each `co_yield` suspends until the consumer asks for the next element.
- Single-pass input range: `begin()` once. Pipe into `ranges::to` if you need a container.
- A view: composes with adaptors, `collatz(27) | std::views::take(5)`.
- `std::generator<T>` yields `T&&`. Yield cheap values or references to stable storage, not to frame locals that mutate after the yield.
- Exceptions in the body surface at the iteration site, not where the generator was created.

### Nested generators without O(n²)

Recursive yielding through `std::ranges::elements_of` forwards elements directly to the outermost consumer instead of re-yielding through every stack level:

```cpp
std::generator<const Node&> walk(const Node& n) {
    co_yield n;
    for (const Node* child : n.children)
        co_yield std::ranges::elements_of(walk(*child));
}
```

### Fallbacks and caveats

- Pre-23, or without `__cpp_lib_generator` (libc++ lags here): range-v3's generators, or a handwritten iterator class (tedious but allocation-free, works on C++17).
- Each generator usually heap-allocates its frame unless the compiler elides it (HALO); measure in hot loops. The third template parameter takes an allocator.
- Coroutine machinery (`promise_type`, awaiters, task types): [coroutines.md](../../cpp-concurrency/references/coroutines.md).

## std::mdspan

C++23 library feature (P0009), header `<mdspan>`. A non-owning multidimensional view over contiguous (or strided) memory, replacing hand-rolled `data[i * cols + j]` indexing.

```cpp
#include <mdspan>

std::vector<double> storage(rows * cols);

// Dynamic extents: sizes known at runtime
std::mdspan m{storage.data(), rows, cols};   // CTAD → mdspan<double, dextents<size_t, 2>>

for (std::size_t i = 0; i < m.extent(0); ++i)
    for (std::size_t j = 0; j < m.extent(1); ++j)
        m[i, j] = compute(i, j);             // C++23 multidimensional operator[]
```

### Extents, layouts, and accessors

The pieces, each independently customizable:

| Component | Default | Alternatives |
|-----------|---------|--------------|
| `ElementType` | — | any object type; `const T` for read-only views |
| `Extents` | — | `std::extents<size_t, 3, std::dynamic_extent>` mixes static and dynamic; static extents cost zero storage |
| `LayoutPolicy` | `layout_right` (row-major, C order) | `layout_left` (column-major, Fortran/BLAS order), `layout_stride` (subviews, interleaved data) |
| `AccessorPolicy` | `default_accessor` | atomic access, aligned-load hints, address-space wrappers |

```cpp
// Static extents where dimensions are compile-time constants: indexing math folds away
std::mdspan<float, std::extents<std::size_t, 4, 4>> mat{buf.data()};

// Column-major view over the same memory for a BLAS call boundary
std::mdspan<double, std::dextents<std::size_t, 2>, std::layout_left> fortran{p, n, m};
```

### Limits and fallback

- Non-owning, with the same lifetime discipline as `span`/`string_view` ([../SKILL.md](../SKILL.md)): fine as a parameter, not as a member or return value referencing locals.
- Slicing (`submdspan`) is C++26. Until then, build strided sub-views with `layout_stride`, or use the Kokkos implementation, which ships `submdspan`.
- `m[i, j]` is a C++23 language change (P2128). On C++20, the Kokkos mdspan provides `m(i, j)`.

Pre-23 fallback: the Kokkos `mdspan` reference implementation (single-header, works on C++17, same API modulo `operator[]`). That makes migration to `std::mdspan` a namespace swap later.

## flat_map and flat_set

C++23 library feature (P0429, P1222), headers `<flat_map>`, `<flat_set>`. Container adaptors that keep keys sorted in a contiguous sequence (default `std::vector`) instead of a node-based red-black tree.

| | `std::map` / `set` | `std::flat_map` / `flat_set` |
|---|---|---|
| Layout | one heap node per element | contiguous vectors (flat_map: separate key and value vectors) |
| Lookup | `O(log n)`, pointer-chasing | `O(log n)`, cache-friendly binary search; typically much faster |
| Insert/erase (middle) | `O(log n)` | `O(n)`: shifts elements |
| Iterator/reference stability | stable across inserts | invalidated by insert/erase |
| Memory | high per-node overhead | minimal; bulk-load friendly |

### When to use and bulk loading

Use them for build-once-query-many data: configuration tables, symbol tables, lookup maps populated at startup. Avoid them when the workload interleaves many single-element inserts with lookups.

```cpp
#include <flat_map>

std::flat_map<std::string, int, std::less<>> limits = /* bulk init */;

// Bulk insertion: sort once (O(n log n)) instead of n middle inserts (O(n²))
std::vector<std::pair<std::string, int>> rows = load_rows();
std::ranges::sort(rows, {}, &std::pair<std::string, int>::first);  // keys must be unique
std::flat_map<std::string, int> m{std::sorted_unique, rows.begin(), rows.end()};
// or adopt separate sorted containers: m{std::sorted_unique, std::move(keys), std::move(values)}
```

### Sharp edges

- Every insert/erase invalidates iterators. Code migrated from `std::map` that holds iterators across mutation breaks silently; this is the top migration bug.
- `flat_map`'s `reference` is the proxy `std::pair<const Key&, T&>`, so generic code expecting a real `pair<const K, T>&` may need adjustment.
- Exception safety is weaker than `std::map`: a throwing comparator or copy during insert can leave the adaptor empty. Keep comparators `noexcept`.
- Library support came last among C++23 containers (libstdc++ in GCC 15, libc++ from LLVM 20); gate on `__cpp_lib_flat_map`/`__cpp_lib_flat_set`.

Pre-23 fallback: `boost::container::flat_map`, or a sorted `std::vector<std::pair<K, V>>` with `std::ranges::lower_bound` when you need only a few operations.

## std::move_only_function

C++23 library feature (P0288), header `<functional>`. Like `std::function` without the copyable-target requirement, so it holds lambdas capturing `unique_ptr`, sockets, or other move-only state.

```cpp
#include <functional>

std::move_only_function<void()> task =
    [conn = std::make_unique<Connection>(addr)]() { conn->send_heartbeat(); };
// std::function<void()> rejects it: the lambda isn't copyable

queue.push(std::move(task));
```

### Differences from std::function

The ones that matter:

| Aspect | `std::function` | `std::move_only_function` |
|--------|-----------------|---------------------------|
| Copyable target required | yes | no |
| Calling an empty one | throws `std::bad_function_call` | undefined behavior |
| `target()` / `target_type()` introspection | yes | no |
| cv/ref/`noexcept` in signature | no | yes: `move_only_function<R(Args) const noexcept>` etc. |

Signature qualifiers are enforced: `move_only_function<void() const>` accepts only targets callable as const, closing `std::function`'s const-correctness hole.

```cpp
// Empty-call discipline: UB, not an exception
if (callback) callback();          // guard, or design so empties can't exist
```

### Pre-23 fallbacks

In order of preference:

1. `fu2::unique_function` or `absl::AnyInvocable` — purpose-built equivalents.
2. Wrap move-only state in `std::shared_ptr` so the lambda is copyable and fits `std::function`. Works, but misstates ownership and adds an allocation.
3. A small hand-rolled type-erased wrapper (one virtual call, ~30 lines) if you cannot take dependencies.

## if consteval

C++23 language feature (P1938). Branch on whether the current evaluation is at compile time, without the C++20 predecessor's trap.

```cpp
constexpr double smart_sqrt(double x) {
    if consteval {
        return constexpr_newton_sqrt(x);   // compile-time path; may call consteval fns
    } else {
        return std::sqrt(x);               // runtime path: use libm
    }
}
```

Rules:

- Braces are mandatory on both branches; `if !consteval { … }` is also legal for the inverted test.
- The `if consteval` block is an immediate function context, so it can call `consteval` functions with non-constant arguments; the C++20 fallback can't.

### The C++20 fallback and its trap

```cpp
// C++20 fallback
constexpr double smart_sqrt(double x) {
    if (std::is_constant_evaluated()) { /* compile-time */ }
    else                              { /* runtime */ }
}

// The trap: inside if constexpr it is always true
if constexpr (std::is_constant_evaluated()) { /* always taken */ }
```

`if constexpr` evaluates its condition as a constant, so the runtime branch is dead. GCC and Clang warn; `if consteval` makes the mistake unwritable. Gate on `__cpp_if_consteval`. The full `constexpr`/`consteval`/`constinit` spectrum is in [../SKILL.md](../SKILL.md).

## std::stacktrace

C++23 library feature (P0881), header `<stacktrace>`. Portable call-stack capture for error context, assertions, and logging.

```cpp
#include <stacktrace>

void on_invariant_violation(std::string_view what) {
    auto trace = std::stacktrace::current();      // capture here
    std::println(stderr, "invariant violated: {}\n{}", what, std::to_string(trace));
}

// Inspect individual frames
for (const auto& entry : std::stacktrace::current()) {
    std::println("{} ({}:{})", entry.description(),
                 entry.source_file(), entry.source_line());
}
```

### Practical patterns

- Capture when the error is constructed, not at the catch/log site, where the interesting frames are gone. A member default-initializer does this: `struct Error { Code code; std::stacktrace where = std::stacktrace::current(); };`.
- `std::stacktrace::current(skip, max_depth)` trims wrapper frames and bounds the cost.
- Hashing and comparison are supported, so traces can deduplicate repeated error reports.

### Caveats and fallback

- Link requirements vary: libstdc++ needs `-lstdc++exp` (GCC 14+; `-lstdc++_libbacktrace` on 12-13), MSVC works out of the box, libc++ lags. Check `__cpp_lib_stacktrace` and link-test in CI.
- Without debug info (`-g`, not fully stripped), `description()` degrades to addresses.
- Capture costs tens of microseconds and up, plus symbolization when printed. Capture on error paths, not per request on hot paths.

Pre-23 fallback: `boost::stacktrace`, near-identical API.

## string contains

C++23 library feature (P1679). `basic_string` and `basic_string_view` gain `contains`, next to C++20's `starts_with`/`ends_with`.

```cpp
std::string_view header = get_header();

if (header.contains("charset"))   { /* C++23 */ }
if (header.contains('='))         { /* char overload */ }

// Pre-23 equivalent:
if (header.find("charset") != std::string_view::npos) { /* C++17/20 */ }
```

Gate on `__cpp_lib_string_contains`. The range algorithm `std::ranges::contains(vec, 42)` is separate, with its own macro (`__cpp_lib_ranges_contains`).

## import std (Standard Library Modules)

C++23 standardizes two named modules (P2465): `import std;` (everything in namespace `std`) and `import std.compat;` (additionally the global-namespace C library names like `::printf`).

```cpp
import std;   // replaces every standard #include — one line

int main() {
    std::println("modular hello");
    std::vector<int> v{1, 2, 3};
}
```

Much faster compiles than headers (parsed once per build, not per TU), no macro leakage, no include-order sensitivity.

### Toolchain requirements

Availability is a tooling question; treat it as opt-in experimental. Three things must align:

1. Compiler and standard library ship the `std` module sources.
2. The build system scans module dependencies. CMake gates `import std` behind an experimental flag (`CMAKE_EXPERIMENTAL_CXX_IMPORT_STD` plus `CXX_MODULE_STD`; the knob's value changes between releases), with Ninja 1.11+ or MSBuild.
3. `import std;` and standard `#include`s aren't mixed in one TU on toolchains that can't interleave them (some diagnose, some miscompile). Pick one style per TU.

### Adoption

Use named modules for your own code where the team controls the toolchain end to end (`FILE_SET CXX_MODULES` in [build-systems](../../../tooling/build-systems/SKILL.md)); keep `import std` behind a build option with `#include` as the default. Fallback: plain headers, optionally precompiled.

## Smaller Quality-of-Life Features

All C++23 unless noted; macros in the availability table above.

### Enums, unreachable paths, and size literals

```cpp
// std::to_underlying: no verbose static_cast for enum classes
enum class Level : std::uint8_t { info = 0, warn = 1, error = 2 };
auto raw = std::to_underlying(Level::warn);          // uint8_t{1}
// Pre-23: static_cast<std::underlying_type_t<Level>>(Level::warn)

// std::unreachable: documented impossible path; reaching it is UB
switch (kind) {
    case Kind::a: return handle_a();
    case Kind::b: return handle_b();
}
std::unreachable();   // Pre-23: __builtin_unreachable() / __assume(false)

// size_t literal suffix: no signed/unsigned loop mismatch
for (auto i = 0uz; i < vec.size(); ++i) { /* i is std::size_t */ }
```

### Byte order, C out-parameters, and string buffers

```cpp
// std::byteswap: endianness conversion without intrinsics
std::uint32_t be = std::byteswap(le_value);
// Combine with C++20 std::endian for conditional swapping.

// std::out_ptr / std::inout_ptr: smart pointers across C out-parameter APIs
std::unique_ptr<FILE, decltype(&fclose)> f{nullptr, &fclose};
// C API: int open_log(FILE** out);
if (open_log(std::out_ptr(f)) != 0) { /* handle error */ }
// Pre-23: raw temp pointer, call, then .reset(temp); easy to leak on early return.

// std::string::resize_and_overwrite: fill via a C API without zero-init
std::string buf;
buf.resize_and_overwrite(256, [&](char* p, std::size_t n) {
    return c_api_read(p, n);   // return actual length written
});
```

### Covered elsewhere

Also in C++23:

- The full set of new view adaptors (`zip`, `enumerate`, `chunk`, `slide`, `stride`, `cartesian_product`, `join_with`), the `fold_left` family, and `ranges::to` → `ranges.md`.
- `std::expected` policy (vs exceptions vs error codes), `noexcept` rules → `error-handling.md`.
- `[[assume(expr)]]` (GCC 13+, Clang 19+): optimizers exploit it unevenly; measure before relying on it for performance. A false assumption is UB.
