# C++17 Features

The C++17 baseline: each facility with worked patterns and its traps, plus migration notes from C++11/14. On a C++20+ baseline, concepts, ranges, and `std::format` replace several patterns here ([cpp20-features.md](cpp20-features.md)).

## Compiler Support Summary

Any maintained toolchain supports the C++17 core language; the surprises are in filesystem linking and parallel algorithms.

| Feature | Standard | GCC | Clang | MSVC | Fallback if unavailable |
|---|---|---|---|---|---|
| Structured bindings | C++17 | 7+ | 4+ | 19.11+ | `std::tie`, `.first`/`.second` |
| `if constexpr` | C++17 | 7+ | 3.9+ | 19.11+ | Tag dispatch, SFINAE |
| `optional`/`variant`/`any` | C++17 | 7+ | 4+ (libc++ 4+) | 19.10+ | Boost.Optional/Variant |
| `string_view` | C++17 | 7+ | 4+ | 19.10+ | `const std::string&` + pointer/length pairs |
| `filesystem` | C++17 | 8+ (see linking note) | 7+ (libc++) | 19.14+ | Boost.Filesystem |
| Parallel algorithms | C++17 | 9+ with TBB | partial in libc++ | 19.14+ | Serial algorithms, OpenMP, manual threading |
| CTAD | C++17 | 7+ | 5+ | 19.14+ | `std::make_pair`-style factories |
| Fold expressions | C++17 | 6+ | 3.9+ | 19.12+ | Recursive variadic templates |

Versions are first-usable releases. Canonical minimums: [version-feature-matrix.md](../../../_shared/version-feature-matrix.md).

## Structured Bindings

Decompose pairs, tuples, arrays, and plain structs into named bindings.

```cpp
std::map<std::string, int> counts;

for (const auto& [word, count] : counts) {
    std::cout << word << ": " << count << '\n';
}

auto [it, inserted] = counts.try_emplace("hello", 1);
if (!inserted) {
    ++it->second;
}
```

Works with any struct whose non-static data members are all public and in one class:

```cpp
struct Point { double x; double y; };

Point p = midpoint_of(a, b);
auto [x, y] = p;  // copies p, then x/y alias the copy's members
```

### Opting your own types into binding

Types with accessors instead of public members opt in through the tuple protocol:

```cpp
class Entry {
public:
    const std::string& key() const { return key_; }
    int value() const { return value_; }
private:
    std::string key_;
    int value_;
};

template <> struct std::tuple_size<Entry> : std::integral_constant<std::size_t, 2> {};
template <> struct std::tuple_element<0, Entry> { using type = std::string; };
template <> struct std::tuple_element<1, Entry> { using type = int; };

template <std::size_t I> decltype(auto) get(const Entry& e) {
    if constexpr (I == 0) return e.key();
    else                  return e.value();
}

auto [k, v] = lookup();   // now works on Entry
```

Do this only for genuinely pair-like types; gratuitous tuple protocol hurts readability.

### Pitfalls

- Bindings are aliases, not variables. `auto [a, b] = f();` materializes a hidden object; `a` and `b` name its members. `decltype(a)` is the member type, which surprises generic code.
- Lambda capture of a binding is ill-formed in C++17 (allowed from C++20, P1091). Copy into a local first: `auto a_copy = a;`.
- No selective ignore: use a dummy name plus `[[maybe_unused]]`. C++26 adds the `_` placeholder (GCC 14+, Clang 18+).
- `for (auto [k, v] : map)` copies every pair. Default to `const auto&` or `auto&` in range-for.

## if constexpr

Compile-time branching inside one function body. The not-taken branch is not instantiated, so code in it may be invalid for the current `T`.

```cpp
template <typename T>
std::string stringify(const T& value) {
    if constexpr (std::is_same_v<T, std::string>) {
        return value;
    } else if constexpr (std::is_arithmetic_v<T>) {
        return std::to_string(value);
    } else {
        return to_string(value);  // ADL hook; only instantiated when reached
    }
}
```

This replaces tag dispatch and most simple `enable_if` SFINAE. On C++20, prefer concepts plus overloads for public APIs and keep `if constexpr` for internal branching.

It also ends the base-case-overload dance for variadic recursion:

```cpp
template <typename T, typename... Rest>
void write_csv(std::ostream& os, const T& first, const Rest&... rest) {
    os << first;
    if constexpr (sizeof...(rest) > 0) {   // no separate zero-arg overload needed
        os << ',';
        write_csv(os, rest...);
    }
}
```

### Pitfalls

- Discarded branches must still parse. Only template-dependent invalid code is tolerated; non-dependent errors (typos, wrong arity on a known function) are diagnosed even in the dead branch.
- `static_assert(false)` in the final else is ill-formed before P2593. Use the dependent-false idiom:

```cpp
template <typename> inline constexpr bool always_false_v = false;

// ...
} else {
    static_assert(always_false_v<T>, "unsupported type");
}
```

  P2593 (C++23, applied as a DR by GCC 13+ and Clang 17+) makes plain `static_assert(false)` valid in uninstantiated branches.
- Branches may `return` different types only because the others are discarded; if two returning branches are instantiated for some `T` with different types, deduction fails.
- The condition must be a constant expression; runtime conditions still need ordinary `if`.

## Init-Statements in if and switch

Scope a variable to exactly the statement that uses it.

```cpp
if (auto it = cache.find(key); it != cache.end()) {
    return it->second;
}

switch (auto status = poll(fd); status.kind) {
    case Kind::ready:   handle(status); break;
    case Kind::timeout: retry();        break;
    default:            fail(status);   break;
}

if (std::lock_guard lock(mutex_); !queue_.empty()) {
    return queue_.front();  // lock held for the whole if/else
}
```

### Pitfalls

- Lifetime ends with the `if`/`else` chain. Returning a reference or `string_view` into the init-statement variable dangles.
- The init variable is visible in `else` too, so a `lock_guard` stays locked through `else`.
- `if (std::string_view sv = make_string(); ...)` dangles immediately: the temporary `std::string` dies at the end of the initializer. Bind the `std::string` itself.

## std::optional

A value that may be absent, without sentinel values or heap allocation.

```cpp
std::optional<Config> load_config(const fs::path& p) {
    std::ifstream in(p);
    if (!in) return std::nullopt;
    return parse_config(in);
}

if (auto cfg = load_config(path)) {
    apply(*cfg);
} else {
    apply(Config::defaults());
}

int port = load_config(path)
    .transform([](const Config& c) { return c.port; })   // C++23 monadic ops
    .value_or(8080);
```

`transform`/`and_then`/`or_else` are C++23; on C++17 use `value_or` and explicit checks.

Lazy single-init caching:

```cpp
class Report {
    std::optional<Summary> summary_;  // computed at most once
public:
    const Summary& summary() {
        if (!summary_) summary_.emplace(compute_summary());
        return *summary_;
    }
};
```

When the caller needs to know why it failed, use `std::expected<T, E>` (C++23) or an error code: [error-handling.md](error-handling.md).

### Pitfalls

- `*opt` and `opt->` on an empty optional are undefined behavior; only `.value()` throws (`std::bad_optional_access`). Sanitizers don't reliably catch the UB form.
- No `std::optional<T&>` before C++26: use `T*` or `std::reference_wrapper`.
- `optional<bool>` has three states, and `if (opt)` tests presence, not the value. Test `has_value()` and `*opt` separately when both matter.
- `opt == 5` compiles (empty compares unequal) and hides the presence check in review. Be explicit in non-trivial code.
- The value is stored inline: `optional<BigObject>` is `sizeof(BigObject)` plus a flag plus padding.

## std::variant

A type-safe tagged union. The closed-set alternative to inheritance.

```cpp
using Shape = std::variant<Circle, Rect, Triangle>;

template <typename... Ts> struct overloaded : Ts... { using Ts::operator()...; };
template <typename... Ts> overloaded(Ts...) -> overloaded<Ts...>;  // not needed in C++20

double area(const Shape& s) {
    return std::visit(overloaded{
        [](const Circle& c)   { return std::numbers::pi * c.r * c.r; }, // <numbers> is C++20
        [](const Rect& r)     { return r.w * r.h; },
        [](const Triangle& t) { return 0.5 * t.base * t.height; },
    }, s);
}
```

`std::visit` with `overloaded` is the canonical pattern; C++20 aggregate CTAD makes the deduction guide unnecessary.

### Variant as a state machine

States become types, so per-state data is impossible to misuse from the wrong state:

```cpp
struct Disconnected {};
struct Connecting   { std::chrono::steady_clock::time_point started; };
struct Connected    { int fd; };
struct Failed       { std::error_code reason; };

using ConnState = std::variant<Disconnected, Connecting, Connected, Failed>;

ConnState on_tick(Connecting c) {
    if (timed_out(c.started)) return Failed{make_error_code(std::errc::timed_out)};
    if (auto fd = try_finish()) return Connected{*fd};
    return c;  // stay
}
```

Transitions are total by construction: `std::visit` over the state plus an event forces you to handle every combination, and there is no `fd` to read while disconnected.

### Pitfalls

- Converting construction: `std::variant<std::string, bool> v = "abc";` selects `bool` under C++17 rules (pointer-to-bool). P0608 (C++20) picks `std::string`. If you straddle standards, construct explicitly: `v.emplace<std::string>("abc");`.
- `std::get<T>` throws `bad_variant_access` on the wrong alternative; `std::get_if<T>` takes a pointer to the variant and returns `nullptr`.
- `valueless_by_exception()` is reached when a throwing move interrupts assignment; `std::visit` on it throws. Design it out with nothrow-movable alternatives.
- The variant is default-constructible only if its first alternative is; otherwise lead with `std::monostate`.
- A generic `[](const auto&)` arm silently swallows newly added alternatives. Omit it to get a compile error when the variant grows.

## std::any

Type-erased single value for genuinely open sets (plugin payloads, heterogeneous property bags).

```cpp
std::any payload = std::string("hello");

if (const auto* s = std::any_cast<std::string>(&payload)) {
    consume(*s);
}

payload = 42;  // rebinds to int; previous value destroyed
```

### Pitfalls

- Prefer `variant` when the set of types is closed. `any` trades compile-time checking for runtime `any_cast` failures (`std::bad_any_cast` for the reference form).
- Exact-type matching: `any_cast<int>` fails on a stored `long`; no conversions, no base-class casts.
- May heap-allocate (small-object optimization is implementation-defined); not cheap in hot paths.

## std::string_view

A non-owning `(pointer, length)` view of character data. Pass by value; it is two words.

```cpp
// One signature accepts std::string, literals, and char*/length data, no copies:
bool has_prefix(std::string_view text, std::string_view prefix) {
    return text.substr(0, prefix.size()) == prefix;  // substr is O(1), no allocation
}

// Heterogeneous map lookup without constructing a temporary std::string:
std::map<std::string, int, std::less<>> table;
auto it = table.find(std::string_view{"key"});  // works because of std::less<>
```

### Pitfalls

- A `string_view` is valid only while the underlying buffer lives. The classic crashes:

```cpp
std::string_view sv = get_name() + "_suffix";  // dangles: temporary string dies here
std::string_view first_word(const std::string& s);  // fine
std::string_view bad() { std::string s = make(); return s; }  // dangles
```

  Don't return a `string_view` into a local or store one past the owner's lifetime (especially a member fed from a constructor parameter).
- Not null-terminated: don't pass `sv.data()` to C APIs expecting a NUL (`open`, `printf("%s")`). Materialize: `std::string(sv).c_str()`.
- `std::string` → `string_view` is implicit; the reverse needs explicit construction, so the expensive direction is visible.
- `remove_prefix`/`remove_suffix` mutate the view, not the data.
- Containers of views are a smell unless the backing storage is provably stable (views into one long-lived file buffer).

## std::filesystem

Portable path manipulation and directory operations.

```cpp
namespace fs = std::filesystem;

fs::path config_dir = fs::path(home) / ".config" / "myapp";

std::error_code ec;
fs::create_directories(config_dir, ec);          // non-throwing overload
if (ec) {
    log_error("mkdir {}: {}", config_dir.string(), ec.message());
}

for (const auto& entry : fs::recursive_directory_iterator(root)) {
    if (entry.is_regular_file() && entry.path().extension() == ".log") {
        total += entry.file_size();
    }
}
```

Atomic replace, so no half-written config is left behind:

```cpp
bool save_atomically(const fs::path& target, std::string_view contents) {
    fs::path tmp = target;
    tmp += ".tmp";
    {
        std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
        if (!out.write(contents.data(),
                       static_cast<std::streamsize>(contents.size()))) {
            return false;
        }
    }   // close (and flush) before rename
    std::error_code ec;
    fs::rename(tmp, target, ec);   // atomic on POSIX within one filesystem
    return !ec;
}
```

### Pitfalls

- Every operation has throwing and `error_code` overloads. Filesystem races make errors normal, so prefer `error_code` in long-running and library code.
- TOCTOU: `if (fs::exists(p)) open(p)` lets the file change between calls. In security-sensitive code, open and handle the failure ([secure-coding](../../../_shared/secure-coding/SKILL.md)).
- `path::native()` is `wchar_t` on Windows, `char` on POSIX. Use `path::u8string()`/`fs::u8path` (C++17; `char8_t`-based in C++20) at serialization boundaries; `.string()` isn't guaranteed UTF-8.
- GCC 8 needs `-lstdc++fs` and pre-LLVM-9 libc++ needs `-lc++fs`; GCC 9+ and LLVM 9+ need nothing.
- `fs::remove_all` deletes recursively; double-check the path construction above it.
- `operator/` replaces on an absolute right-hand side: `fs::path("/a") / "/etc"` yields `/etc`. Validate untrusted components before joining.

## Parallel Algorithms

Execution policies parallelize ~70 standard algorithms.

```cpp
#include <execution>

std::sort(std::execution::par, v.begin(), v.end());

double sum = std::reduce(std::execution::par_unseq,
                         data.begin(), data.end(), 0.0);

std::for_each(std::execution::par, items.begin(), items.end(),
              [](Item& it) { it.recompute(); });  // body must be thread-safe
```

Policies: `seq` (sequential, but allows the parallel overload's relaxed guarantees), `par` (multiple threads), `par_unseq` (threads + vectorization), `unseq` (vectorization only, C++20).

### The libstdc++ TBB caveat

| Standard library | Reality |
|---|---|
| libstdc++ (GCC 9+) | Parallel policies run on Intel oneTBB. Without TBB headers and `-ltbb`, `<execution>` use fails to compile or degrades to serial. Some GCC/oneTBB version pairings are incompatible. |
| libc++ | Absent in older releases; newer ones ship a PSTL behind `-fexperimental-library`. |
| MSVC STL | Implemented natively since VS 2017 15.7; no extra dependency. |

If TBB isn't guaranteed on every target, keep the serial call and parallelize explicitly (thread pool, OpenMP), or gate on `TBB::tbb`:

```cmake
find_package(TBB QUIET)
if(TBB_FOUND)
    target_link_libraries(app PRIVATE TBB::tbb)
    target_compile_definitions(app PRIVATE HAVE_PARALLEL_STL=1)
endif()
```

```cpp
#if HAVE_PARALLEL_STL
    std::sort(std::execution::par, v.begin(), v.end());
#else
    std::sort(v.begin(), v.end());
#endif
```

### Pitfalls

- An exception escaping the element function calls `std::terminate` under every standard policy. Catch inside the lambda.
- `par_unseq` forbids vectorization-unsafe operations in the element function: no locking, no allocation, nothing that synchronizes between iterations.
- The policy parallelizes; it does not synchronize your shared state.
- For small ranges or memory-bound loops, `par` is often slower than `seq`. Measure with `hyperfine` or Google Benchmark ([profiling-tools](../../../tooling/diagnostics/references/profiling-tools.md)).

## Class Template Argument Deduction (CTAD)

Template arguments deduced from constructor arguments.

```cpp
std::pair p{1, 2.5};                 // std::pair<int, double>
std::lock_guard lock(mutex_);        // std::lock_guard<std::mutex>
std::tuple t{1, "two"sv, 3.0};       // deduced three ways
```

Custom deduction guides steer deduction for your own templates:

```cpp
template <typename It>
Container(It first, It last) -> Container<typename std::iterator_traits<It>::value_type>;
```

### Pitfalls

- Braces vs parentheses change the meaning for containers:

```cpp
std::vector v1{3, 0};   // vector<int> with elements {3, 0}
std::vector v2(3, 0);   // vector<int> with elements {0, 0, 0}
std::vector v3{v1};     // vector<int> (copy), not vector<vector<int>>
```

  In deduced contexts, prefer parentheses for count/value constructors and be suspicious of single-brace copies.
- All-or-nothing: you can't supply some template arguments and deduce the rest. `std::pair<int>{1, 2.0}` is an error.
- Aggregates deduce only from C++20 (P1816). On C++17 they need explicit arguments or a hand-written guide.
- CTAD doesn't replace `make_shared`/`make_unique`, which allocate and own.
- `std::pair p{"a", "b"}` deduces `pair<const char*, const char*>`. Use `"a"s` / `"a"sv` when you mean `string`/`string_view`.

## Fold Expressions

Collapse a parameter pack over an operator without recursion.

```cpp
template <typename... Ts>
auto sum(Ts... args) { return (args + ...); }            // unary right fold

template <typename... Ts>
auto sum_from_zero(Ts... args) { return (0 + ... + args); }  // binary fold, empty-pack safe

template <typename... Ts>
void print_all(const Ts&... args) {
    ((std::cout << args << ' '), ...);                   // comma fold for side effects
    std::cout << '\n';
}

template <typename T, typename... Ts>
constexpr bool is_any_of_v = (std::is_same_v<T, Ts> || ...);
```

### Pitfalls

- Unary folds over an empty pack are ill-formed except `&&` (→ `true`), `||` (→ `false`), and `,` (→ `void()`). Use a binary fold with an identity (`(0 + ... + args)`) when the pack may be empty.
- `(args - ...)` is a right fold `a1 - (a2 - a3)`; `(... - args)` is a left fold `(a1 - a2) - a3`. For non-associative operators this changes the answer.
- A fold must sit inside its own parentheses.
- `&&`/`||` folds short-circuit left to right; a fold over `,` is the idiomatic loop over a pack.

## Smaller Features Worth Using

| Feature | One-liner | Watch out for |
|---|---|---|
| `inline` variables | Header-defined globals/statics without ODR violations: `inline constexpr int max_retries = 3;` | Replaces the `extern` + one-TU dance |
| `[[nodiscard]]` | Compiler warns when a return value is ignored | Put it on error-returning and factory functions; pair with `-Werror` |
| `[[maybe_unused]]`, `[[fallthrough]]` | Silence warnings honestly | `[[fallthrough]];` needs the semicolon |
| Nested namespaces | `namespace a::b::c { ... }` | Pure syntax sugar |
| Guaranteed copy elision | `T obj = make_T();` materializes in place; factory functions for immovable types work | Only for prvalues; NRVO is still optional |
| `std::byte` | Raw-memory type that refuses arithmetic | Requires explicit `to_integer`/casts; clearer than `unsigned char` for buffers |
| `__has_include` | Conditional includes for optional deps | Presence of a header ≠ usability of the library |
| `std::clamp` | `std::clamp(x, lo, hi)` | UB if `lo > hi`; returns a reference — beware dangling with temporaries |
| `std::size`/`std::data`/`std::empty` | Uniform free functions for containers and C arrays | Prefer over `sizeof(a)/sizeof(a[0])` |
| Mandatory `auto` deduction fixes | `auto x{1};` is now `int`, not `initializer_list` | Pre-17 code that relied on the old meaning |

## Migration Notes: C++11/14 to C++17

Upgrades worth doing in bulk; clang-tidy automates some, and `/system-developer:fix-modernize` or the sys-code-fixer agent runs batches:

| Old pattern | C++17 replacement | clang-tidy check |
|---|---|---|
| `std::tie(a, b) = f();` | `auto [a, b] = f();` | — (manual) |
| Tag dispatch / `enable_if` chains | `if constexpr` | — (manual) |
| `T* p` or sentinel values meaning "maybe absent" | `std::optional<T>` | — (manual, API-level) |
| `const std::string&` parameters that only read | `std::string_view` | — (manual; review lifetimes) |
| Type-code `enum` + `union` | `std::variant` | — (manual) |
| `boost::filesystem` | `std::filesystem` | mostly find-and-replace; API near-identical |
| `make_pair`/`make_tuple` noise | CTAD | — (manual) |
| Recursive variadic helpers | Fold expressions | — (manual) |
| Header-global `static`/`extern` constants | `inline constexpr` | — (manual) |
| `typedef` | `using` | `modernize-use-using` |

Behavioral changes to be aware of when flipping `-std=c++17` on old code:

- `noexcept` joined the function type: a potentially-throwing function no longer converts to a `noexcept` function pointer, and template deduction and mangling now see the difference.
- `auto x{1}` deduces `int` (was `initializer_list<int>`).
- Trigraphs, `register`, and `++` on `bool` are gone.
- Guaranteed copy elision changes behavior in code that counted copies (test mocks, instrumented types).
- Evaluation order is partly fixed: `a(b(), c())` argument order is still unspecified, but `a << b() << c()` and assignments are now ordered, so code that worked by accident may change.

One standard jump at a time: 11/14 → 17, stabilize under `-Wall -Wextra -Werror` plus a sanitizer pass, then consider 20.

## Related References

- [cpp20-features.md](cpp20-features.md) — concepts, `<=>`, `span`, `format`, modules.
- [cpp23-features.md](cpp23-features.md) — `expected`, `print`, deducing this, monadic `optional`.
- [ranges.md](ranges.md) — the C++20 replacement for iterator-pair pipelines.
- [error-handling.md](error-handling.md) — choosing between exceptions, `optional`, and `expected`.
- [../SKILL.md](../SKILL.md) — standard-selection table and modern-C++ core rules.
- [version-feature-matrix.md](../../../_shared/version-feature-matrix.md) — canonical toolchain minimums.
