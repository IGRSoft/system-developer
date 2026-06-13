# C++23 Features

Use this when:

- You are on a C++23 toolchain and want to use the new language and library features correctly.
- You need the pre-23 fallback for a C++23 feature because part of your build is pinned to C++17/20.
- You are reviewing code that uses `std::expected`, `std::print`, deducing this, or `std::generator` and need the rules.
- A C++23 symbol fails to compile and you need the feature-test macro to check.

Skip this file if:

- You need the C++17 baseline or C++20 features (concepts, `std::format`, `span`). Use `cpp17-features.md` / `cpp20-features.md`.
- You want ranges pipelines, including the C++23 view adaptors (`zip`, `chunk`, `fold_left`, `ranges::to`). Use `ranges.md`.
- You are choosing an error-handling strategy rather than learning `expected` mechanics. Use `error-handling.md`.
- You need "which standard do I target?" policy. Use the standard-selection table in [../../SKILL.md](../../SKILL.md).

Jump to:

- Availability at a Glance
- Deducing This (Explicit Object Parameter)
- std::expected and Monadic Error Chaining
- Monadic std::optional
- std::print and std::println
- std::generator
- std::mdspan
- flat_map and flat_set
- std::move_only_function
- if consteval
- std::stacktrace
- string contains
- import std (Standard Library Modules)
- Smaller Quality-of-Life Features

## Availability at a Glance

Gate every C++23 feature on its feature-test macro, not on a compiler version number. Library support lags core-language support, and the three major standard libraries adopted these pieces at different times — verify against your toolchain.

| Feature | Kind | Feature-test macro | Pre-23 fallback |
|---------|------|--------------------|-----------------|
| Deducing this | language | `__cpp_explicit_this_parameter >= 202110L` | CRTP; hand-written const/ref overload sets |
| `std::expected` | library | `__cpp_lib_expected >= 202202L` | `tl::expected` (API-compatible) |
| `expected` monadic ops | library | `__cpp_lib_expected >= 202211L` | `tl::expected` (ships monadic ops) |
| Monadic `std::optional` | library | `__cpp_lib_optional >= 202110L` | explicit `if (opt)` chains |
| `std::print` / `println` | library | `__cpp_lib_print >= 202207L` | fmtlib `fmt::print`; C++20 `std::format` + `std::cout` |
| `std::generator` | library | `__cpp_lib_generator >= 202207L` | range-v3 generators; handwritten iterators |
| `std::mdspan` | library | `__cpp_lib_mdspan >= 202207L` | Kokkos `mdspan` reference implementation (works on C++17) |
| `std::flat_map` / `flat_set` | library | `__cpp_lib_flat_map` / `__cpp_lib_flat_set >= 202207L` | `boost::container::flat_map`; sorted `vector` + `lower_bound` |
| `std::move_only_function` | library | `__cpp_lib_move_only_function >= 202110L` | `std::function` + `shared_ptr` capture; `fu2::unique_function`; `absl::AnyInvocable` |
| `if consteval` | language | `__cpp_if_consteval >= 202106L` | `std::is_constant_evaluated()` (C++20) — see trap below |
| `std::stacktrace` | library | `__cpp_lib_stacktrace >= 202011L` | `boost::stacktrace` |
| `string::contains` | library | `__cpp_lib_string_contains >= 202011L` | `s.find(x) != std::string::npos` |
| `import std;` | language + tooling | `__cpp_lib_modules >= 202207L` (presence ≠ build support) | `#include` headers, optionally PCH |
| `std::to_underlying` | library | `__cpp_lib_to_underlying >= 202102L` | `static_cast<std::underlying_type_t<E>>(e)` |
| `std::unreachable` | library | `__cpp_lib_unreachable >= 202202L` | `__builtin_unreachable()` / `__assume(false)` |
| `std::byteswap` | library | `__cpp_lib_byteswap >= 202110L` | `__builtin_bswap32` and friends |
| `std::out_ptr` / `inout_ptr` | library | `__cpp_lib_out_ptr >= 202106L` | temporary raw pointer + manual `reset` |

Compiler reality (2026): current GCC and Clang releases ship the bulk of this table; MSVC tracks closely. The slowest adopters historically were `flat_map`/`flat_set`, `std::generator` on libc++, and `import std` tooling — check the macro before assuming, and keep the fallback row wired into your build for any target you cannot pin.

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

**C++23 language feature (P0847).** A member function may take its object as an explicit first parameter named with `this`. The object's type and value category are then deduced like any other template parameter.

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

`std::forward<Self>(self).member` forwards the value category onto the member access — a moved-from `Box` yields an rvalue `string`, so callers can steal it.

### CRTP replacement

Static polymorphism without a templated base class or `static_cast<Derived*>(this)`:

```cpp
// C++23
struct Animal {
    void speak(this auto&& self) { self.make_sound(); }  // self deduces Cat, Dog…
};
struct Cat : Animal { void make_sound() const { std::println("meow"); } };
struct Dog : Animal { void make_sound() const { std::println("woof"); } };

Cat{}.speak();  // "meow" — no virtual, no CRTP boilerplate
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

Pre-23, a lambda cannot name itself; you needed `std::function` (allocation, indirection) or a Y-combinator. Now:

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
- Inside the body there is no implicit `this`; you must access members through `self`.
- Taking a pointer to one yields a *plain function pointer* type (`auto (*)(Box&)`), not a pointer-to-member — this changes how callback registries store them.
- A by-value `this Self self` slices if called on a derived object — deduce with `Self&&` unless you specifically want a copy of a known concrete type.

Verify `__cpp_explicit_this_parameter` before using it in headers shared with older-toolchain consumers; the CRTP fallback above is mechanical to swap in.

## std::expected and Monadic Error Chaining

**C++23 library feature (P0323; monadic operations P2505), header `<expected>`.** `std::expected<T, E>` holds either a value `T` or an error `E` — a return type that makes fallibility part of the signature. Pre-23 fallback: `tl::expected`, which is deliberately API-compatible.

When to choose `expected` over exceptions or raw codes is a policy question — see the decision framework in `error-handling.md`. This section covers mechanics.

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
    use(*r);                 // operator*: UNCHECKED — UB if r holds an error
} else {
    log(r.error());          // error(): UNCHECKED — UB if r holds a value
}
int port = r.value_or(8080); // checked, with default
```

- `r.value()` is the *checked* accessor: it throws `std::bad_expected_access<E>` when `r` holds an error. `operator*` and `error()` are unchecked.
- `std::expected<void, E>` models "action that can fail with no result"; `has_value()` and the monadic ops still work.
- Keep `E` small and cheap to copy (an enum, or a small struct with an enum + context). `expected` stores `T` and `E` in a union — a fat `E` taxes every return.

### Monadic operations (require `__cpp_lib_expected >= 202211L`)

| Operation | Callable takes | Callable returns | Runs when |
|-----------|----------------|------------------|-----------|
| `and_then(f)` | `T` | `std::expected<U, E>` | value present |
| `transform(f)` | `T` | plain `U` (wrapped for you) | value present |
| `or_else(f)` | `E` | `std::expected<T, F>` | error present |
| `transform_error(f)` | `E` | plain `F` (wrapped for you) | error present |
| `error_or(e)` | — | `E` | either (default on success) |

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

The pipeline short-circuits: after the first error, subsequent `and_then`/`transform` calls are skipped and the error propagates untouched. Use `transform_error` at module boundaries to convert a low-level error enum into the layer's own error type (see boundary translation in `error-handling.md`).

### What expected does NOT do

- No early-return sugar: C++ has no `?` operator. Deep call stacks either chain monadically or check-and-return at each level. A common bridge macro exists in many codebases (`TRY(expr)` expanding to a check + return) — if your project has one, follow it; do not invent a second.
- No implicit conversion from `E` to `expected<T, E>` when `T` and `E` are the same type — wrap errors in `std::unexpected` always; it reads better even when not required.

## Monadic std::optional

**C++23 library addition (P0798) to the C++17 type.** `std::optional` gains the same chaining vocabulary: `and_then`, `transform`, `or_else`. Gate on `__cpp_lib_optional >= 202110L`.

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

`or_else` takes a nullary callable returning `optional<T>` (note the difference from `expected::or_else`, whose callable receives the error — `optional` has no error to pass).

Choose `optional` when absence is not an error ("no such user" needs no diagnosis); choose `expected` when the caller needs to know *why* — full decision table in `error-handling.md`.

## std::print and std::println

**C++23 library feature (P2093), headers `<print>` and (for `ostream` overloads) `<ostream>`.** Format-string-based output built on the C++20 `std::format` machinery.

```cpp
#include <print>

std::println("processed {} items in {:.2f}s", count, seconds);
std::print("no trailing newline; ");
std::println(stderr, "warning: {} retries", retries);   // FILE* overload
std::println(log_stream, "to any ostream");             // <ostream> overload
```

Why prefer it over `operator<<` chains:

- **Type-safe**: format string checked at compile time; a `{}`/argument mismatch is a compile error, not garbage output.
- **Atomic lines**: one call per line means no interleaving between threads, unlike a chain of `<<` calls where another thread can write between segments.
- **Locale-independent by default**: `1234.5` prints the same on every machine unless you opt into locale with `{:L}`.
- **Correct Unicode**: when the literal encoding is UTF-8, `std::print` writes UTF-8 correctly to a terminal (including on Windows consoles) — iostreams do not guarantee this.

Behavior notes:

- `std::print` does **not** flush. There is no `std::endl` equivalent; call `std::fflush(stdout)` or use unbuffered streams where latency matters.
- Custom types print by specializing `std::formatter<T>` — the same specialization serves `std::format`, `std::print`, and (C++23) `std::format`-based logging wrappers. Write it once.
- Printing a range directly (`std::println("{}", vec)`) is formatting-of-ranges, a separate C++23 library feature (`__cpp_lib_format_ranges`) — check it independently.

Fallbacks:

```cpp
// C++20: same format machinery, manual stream write
std::cout << std::format("processed {} items\n", count);

// C++17: fmtlib — std::print is standardized fmt; migration is s/fmt::/std::/
fmt::print("processed {} items\n", count);
```

If the codebase already uses fmtlib, staying on `fmt::` uniformly is better than mixing — fmtlib also tends to ship new formatting features ahead of standard libraries.

## std::generator

**C++23 library feature (P2502), header `<generator>`.** The first standard coroutine return type you can actually use: a lazy, synchronous, move-only *view* that produces elements on demand via `co_yield`.

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

- **Lazy**: the body does not run until iteration begins; each `co_yield` suspends until the consumer asks for the next element.
- **Input range, single pass**: you get one traversal. Calling `begin()` twice is not supported; pipe into `ranges::to` (see `ranges.md`) if you need a container.
- **It is a view**: composes with range adaptors — `collatz(27) | std::views::take(5)`.
- **Reference semantics by default**: `std::generator<T>` yields `T&&`. Yield cheap values or yield references to stable storage; do not yield references to coroutine-frame locals that mutate after the yield.
- **Exceptions** thrown in the body propagate to the consumer at the point of iteration — the `for` loop site, not the call site that created the generator.

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

- Pre-23 (or where the macro is absent — libc++ adopted `<generator>` late; verify `__cpp_lib_generator` against your toolchain): range-v3's generator facilities, or a handwritten iterator class. The handwritten version is tedious but allocation-free and works on C++17.
- Each generator instance typically heap-allocates its coroutine frame unless the compiler elides it (HALO); do not assume elision in hot loops — measure. Allocator customization is possible via the third template parameter.
- For the underlying coroutine machinery (`promise_type`, awaiters, writing your own task types), see [../../cpp-concurrency/references/coroutines.md](../../cpp-concurrency/references/coroutines.md).

## std::mdspan

**C++23 library feature (P0009), header `<mdspan>`.** A non-owning multidimensional view over contiguous (or strided) memory — the vocabulary type that ends hand-rolled `data[i * cols + j]` indexing.

```cpp
#include <mdspan>

std::vector<double> storage(rows * cols);

// Dynamic extents: sizes known at runtime
std::mdspan m{storage.data(), rows, cols};   // CTAD → mdspan<double, dextents<size_t, 2>>

for (std::size_t i = 0; i < m.extent(0); ++i)
    for (std::size_t j = 0; j < m.extent(1); ++j)
        m[i, j] = compute(i, j);             // C++23 multidimensional operator[]
```

The pieces, each independently customizable:

| Component | Default | Alternatives |
|-----------|---------|--------------|
| `ElementType` | — | any object type; `const T` for read-only views |
| `Extents` | — | `std::extents<size_t, 3, std::dynamic_extent>` mixes static and dynamic; static extents cost zero storage |
| `LayoutPolicy` | `layout_right` (row-major, C order) | `layout_left` (column-major, Fortran/BLAS order), `layout_stride` (arbitrary strides — subviews, interleaved data) |
| `AccessorPolicy` | `default_accessor` | atomic access, aligned-load hints, address-space wrappers |

```cpp
// Static extents where dimensions are compile-time constants: indexing math folds away
std::mdspan<float, std::extents<std::size_t, 4, 4>> mat{buf.data()};

// Column-major view over the same memory for a BLAS call boundary
std::mdspan<double, std::dextents<std::size_t, 2>, std::layout_left> fortran{p, n, m};
```

Notes and limits:

- `mdspan` is **non-owning** — the same lifetime discipline as `span`/`string_view` (see the lifetime trap in [../SKILL.md](../SKILL.md)). Parameters: yes. Data members or return values referencing locals: no.
- Slicing (`submdspan`) did not make C++23; it is a C++26 feature. Until then, build strided sub-views manually with `layout_stride`, or use the Kokkos implementation which ships `submdspan` today.
- The multidimensional subscript `m[i, j]` is a C++23 *language* change (P2128). On a C++20 compiler use `m(i, j)`-style via the Kokkos mdspan, which provides `operator()` for older standards.

Pre-23 fallback: the Kokkos `mdspan` reference implementation (single-header, works on C++17, same API modulo `operator[]`). That makes migration to `std::mdspan` a namespace swap later.

## flat_map and flat_set

**C++23 library feature (P0429, P1222), headers `<flat_map>`, `<flat_set>`.** Container *adaptors* that keep keys sorted in a contiguous sequence (default `std::vector`) instead of a node-based red-black tree.

| | `std::map` / `set` | `std::flat_map` / `flat_set` |
|---|---|---|
| Layout | one heap node per element | contiguous vectors (flat_map: separate key and value vectors) |
| Lookup | `O(log n)`, pointer-chasing | `O(log n)`, cache-friendly binary search — typically much faster |
| Insert/erase (middle) | `O(log n)` | `O(n)` — shifts elements |
| Iterator/reference stability | stable across inserts | **invalidated** by insert/erase |
| Memory | high per-node overhead | minimal; bulk-load friendly |

Use them for build-once-query-many data: configuration tables, symbol tables, lookup maps populated at startup. Avoid them when the workload interleaves many single-element inserts with lookups.

```cpp
#include <flat_map>

std::flat_map<std::string, int, std::less<>> limits = /* bulk init */;

// Bulk insertion: sort first, then adopt — O(n log n) once instead of O(n²)
std::vector<std::pair<std::string, int>> rows = load_rows();
std::ranges::sort(rows, {}, &std::pair<std::string, int>::first);
std::flat_map<std::string, int> m{std::sorted_unique, std::move(rows)};
```

Sharp edges:

- **Iterator invalidation on every insert/erase.** Code migrated from `std::map` that holds iterators across mutation is broken silently. This is the number-one migration bug.
- Element access yields `std::pair<const Key&, T&>`-like proxies via zipped iteration over the two underlying containers — generic code that assumes `value_type` is a real `pair<const K, T>&` may need adjustment.
- Exception safety is weaker than `std::map`: a throwing comparator or copy during insert can leave the adaptor empty (it restores invariants by clearing). Keep comparators `noexcept`.
- Standard-library adoption of `<flat_map>`/`<flat_set>` lagged the rest of C++23 noticeably — gate on `__cpp_lib_flat_map`/`__cpp_lib_flat_set` and verify against your toolchain before depending on them.

Pre-23 fallback: `boost::container::flat_map` (same design, mature), or a sorted `std::vector<std::pair<K, V>>` with `std::ranges::lower_bound` — which is also the honest choice when you only need 3 operations.

## std::move_only_function

**C++23 library feature (P0288), header `<functional>`.** A type-erased callable wrapper like `std::function`, minus the requirement that the target be copyable — so it can hold lambdas capturing `unique_ptr`, sockets, or any move-only state.

```cpp
#include <functional>

std::move_only_function<void()> task =
    [conn = std::make_unique<Connection>(addr)]() { conn->send_heartbeat(); };
// std::function<void()> f = same lambda;   // ERROR pre-23 workarounds needed

queue.push(std::move(task));
```

Differences from `std::function` that matter:

| Aspect | `std::function` | `std::move_only_function` |
|--------|-----------------|---------------------------|
| Copyable target required | yes | no |
| Calling an empty one | throws `std::bad_function_call` | **undefined behavior** — check before calling |
| `target()` / `target_type()` introspection | yes | no |
| cv/ref/`noexcept` in signature | no | yes: `move_only_function<R(Args) const noexcept>` etc. |

The signature qualifiers are enforced: `move_only_function<void() const>` only accepts targets callable as const, and only exposes a const `operator()`. This closes a long-standing `std::function` const-correctness hole.

```cpp
// Empty-call discipline: UB, not an exception
if (callback) callback();          // always guard, or design so empties cannot exist
```

Pre-23 fallbacks, in order of preference:

1. `fu2::unique_function` or `absl::AnyInvocable` — purpose-built equivalents.
2. The `shared_ptr` smuggle: wrap move-only state in `std::shared_ptr` so the lambda becomes copyable and fits `std::function`. Works, but lies about ownership and adds an allocation + control block.
3. A small hand-rolled type-erased wrapper (one virtual call, ~30 lines) if you cannot take dependencies.

## if consteval

**C++23 language feature (P1938).** Branch on whether the current evaluation is at compile time, fixing the trap in the C++20 predecessor.

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
- Inside the `if consteval` block you may call `consteval` (immediate) functions with non-constant arguments — the block is an *immediate function context*. This is the capability the C++20 fallback lacks entirely.

### The C++20 fallback and its trap

```cpp
// C++20 fallback
constexpr double smart_sqrt(double x) {
    if (std::is_constant_evaluated()) { /* compile-time */ }
    else                              { /* runtime */ }
}

// THE TRAP — never combine with if constexpr:
if constexpr (std::is_constant_evaluated()) { /* ALWAYS taken */ }
```

`if constexpr` forces constant evaluation of its condition, so `is_constant_evaluated()` answers "yes" unconditionally — the runtime branch is silently dead. Compilers warn about this now, but only sometimes; `if consteval` makes the mistake unwritable. Gate on `__cpp_if_consteval`.

Where this sits in the `constexpr`/`consteval`/`constinit` spectrum: see the table in [../SKILL.md](../SKILL.md).

## std::stacktrace

**C++23 library feature (P0881), header `<stacktrace>`.** Portable capture of the current call stack — for error context, assertion messages, and logging, without platform-specific backtrace code.

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

Practical patterns:

- **Attach to error types at construction**, not at the catch/log site — by the time an error surfaces, the interesting frames are gone. A `struct Error { Code code; std::stacktrace where = std::stacktrace::current(); };` member default-initializer captures at the throw/return point.
- `std::stacktrace::current(skip, max_depth)` trims wrapper frames and bounds the cost.
- Hashing and comparison are supported, so traces can deduplicate repeated error reports.

Caveats — verify against your toolchain:

- **Link requirements vary.** GCC's libstdc++ has required an extra library for the stacktrace implementation (`-lstdc++exp` in recent releases; earlier spellings differed). MSVC works out of the box. libc++ support arrived late. Check `__cpp_lib_stacktrace` *and* do a link test in CI.
- Symbol quality depends on debug info: build with `-g` (and avoid full stripping) or `description()` degrades to addresses.
- Capture is not free (tens of microseconds and up, plus symbolization cost when printed). Capture eagerly only on error paths, never per-request on hot paths.

Pre-23 fallback: `boost::stacktrace` — near-identical API, and the practical choice wherever the standard one is missing or unsymbolized.

## string contains

**C++23 library feature (P1679).** `std::string`, `std::string_view`, and `std::wstring` gain `contains`, completing the C++20 `starts_with`/`ends_with` trio.

```cpp
std::string_view header = get_header();

if (header.contains("charset"))   { /* C++23 */ }
if (header.contains('='))         { /* char overload */ }

// Pre-23 fallback — exactly equivalent:
if (header.find("charset") != std::string_view::npos) { /* C++17/20 */ }
```

Gate on `__cpp_lib_string_contains`. Note the difference from the C++23 *ranges* algorithm `std::ranges::contains`, which works on any range (`std::ranges::contains(vec, 42)`) — that one lives in `ranges.md` territory and has its own macro (`__cpp_lib_ranges_contains`).

## import std (Standard Library Modules)

**C++23 standardizes two named modules (P2465):** `import std;` (everything in namespace `std`) and `import std.compat;` (additionally the global-namespace C library names like `::printf`).

```cpp
import std;   // replaces every standard #include — one line

int main() {
    std::println("modular hello");
    std::vector<int> v{1, 2, 3};
}
```

Why care: dramatically faster compiles than including headers (the module is parsed once per build, not once per TU), no macro leakage, no include-order sensitivity.

**Availability is a tooling question, not a compiler-flag question — treat this as opt-in experimental and verify against your toolchain.** All three of these must align:

1. **Compiler + standard library** shipping the `std` module sources.
2. **Build system** that understands module dependency scanning. CMake gates `import std` behind an experimental flag (`CMAKE_EXPERIMENTAL_CXX_IMPORT_STD` plus `CXX_MODULE_STD`) on recent versions — the exact knob has changed between CMake releases; check your CMake documentation. Ninja (1.11+) or MSBuild as the generator.
3. **No mixing** of `import std;` and standard `#include`s in the same translation unit on toolchains that don't support interleaving — some do, some diagnose, some miscompile. Pick one style per TU.

Recommended posture (2026): use named modules for *your own* code where the team controls the toolchain end to end (see `FILE_SET CXX_MODULES` in [build-systems](../../../tooling/build-systems/SKILL.md)); keep `import std` behind a build option with the `#include` world as the default. Fallback: plain headers, optionally precompiled (PCH), which still capture much of the compile-time win with zero portability risk.

## Smaller Quality-of-Life Features

All C++23 unless noted; macros in the availability table above.

```cpp
// std::to_underlying — kills the verbose static_cast for enum classes
enum class Level : std::uint8_t { info = 0, warn = 1, error = 2 };
auto raw = std::to_underlying(Level::warn);          // uint8_t{1}
// Pre-23: static_cast<std::underlying_type_t<Level>>(Level::warn)

// std::unreachable — documented impossible path; reaching it is UB (optimizer fuel)
switch (kind) {
    case Kind::a: return handle_a();
    case Kind::b: return handle_b();
}
std::unreachable();   // Pre-23: __builtin_unreachable() / __assume(false)

// Literal suffix for size_t — fixes signed/unsigned loop mismatches
for (auto i = 0uz; i < vec.size(); ++i) { /* i is std::size_t */ }

// std::byteswap — endianness conversion without intrinsics
std::uint32_t be = std::byteswap(le_value);
// Combine with C++20 std::endian for conditional swapping.

// std::out_ptr / std::inout_ptr — smart pointers across C out-parameter APIs
std::unique_ptr<FILE, decltype(&fclose)> f{nullptr, &fclose};
// C API: int open_log(FILE** out);
if (open_log(std::out_ptr(f)) != 0) { /* handle error */ }
// Pre-23: raw temp pointer, call, then .reset(temp) — easy to leak on early return.

// std::string::resize_and_overwrite — fill a string via a C API without zero-init
std::string buf;
buf.resize_and_overwrite(256, [&](char* p, std::size_t n) {
    return c_api_read(p, n);   // return actual length written
});
```

Also in C++23 but covered elsewhere:

- The full set of new view adaptors (`zip`, `enumerate`, `chunk`, `slide`, `stride`, `cartesian_product`, `join_with`), the `fold_left` family, and `ranges::to` → `ranges.md`.
- `std::expected` policy (vs exceptions vs error codes), `noexcept` rules → `error-handling.md`.
- `[[assume(expr)]]` — standardized, but compiler exploitation varies widely; treat as documentation plus occasional optimization, and verify behavior against your toolchain before relying on it for performance.
