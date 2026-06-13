# C++17 Features

Use this when:

- Your project baseline is C++17 and you want to use every facility it offers correctly.
- You are modernizing C++11/14 code and need the worked patterns and the traps.
- You hit a C++17-specific pitfall (CTAD brace surprises, `string_view` lifetime, variant conversion quirks).

Skip this file if:

- Your baseline is C++20 or newer — concepts, ranges, and `std::format` replace several patterns here. Use `cpp20-features.md` and `cpp23-features.md`.
- You are choosing *which* standard to target. Use the standard-selection table in [../SKILL.md](../SKILL.md).
- You need ranges pipelines. Use `ranges.md`.

Jump to:

- Compiler Support Summary
- Structured Bindings
- if constexpr
- Init-Statements in if and switch
- std::optional
- std::variant
- std::any
- std::string_view
- std::filesystem
- Parallel Algorithms
- Class Template Argument Deduction (CTAD)
- Fold Expressions
- Smaller Features Worth Using
- Migration Notes: C++11/14 to C++17

## Compiler Support Summary

C++17 is old enough that any maintained toolchain supports the core language fully. The library corners (filesystem linking, parallel algorithms) are where deployment surprises live.

| Feature | Standard | GCC | Clang | MSVC | Fallback if unavailable |
|---|---|---|---|---|---|
| Structured bindings | C++17 | 7+ | 4+ | 19.11+ | `std::tie`, `.first`/`.second` |
| `if constexpr` | C++17 | 7+ | 3.9+ | 19.11+ | Tag dispatch, SFINAE |
| `optional`/`variant`/`any` | C++17 | 7+ | 4+ (libc++ 4+) | 19.10+ | Boost.Optional/Variant |
| `string_view` | C++17 | 7+ | 4+ | 19.10+ | `const std::string&` + pointer/length pairs |
| `filesystem` | C++17 | 8+ (see linking note) | 7+ (libc++) | 19.14+ | Boost.Filesystem |
| Parallel algorithms | C++17 | 9+ **with TBB** | partial in libc++ | 19.14+ | Serial algorithms, OpenMP, manual threading |
| CTAD | C++17 | 7+ | 5+ | 19.14+ | `std::make_pair`-style factories |
| Fold expressions | C++17 | 6+ | 3.9+ | 19.12+ | Recursive variadic templates |

Versions above are first-usable releases; verify against your toolchain before relying on edge cases. The canonical cross-language table is [version-feature-matrix.md](../../../_shared/version-feature-matrix.md).

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

Any type can support structured bindings through the tuple protocol — useful for types with accessors instead of public members:

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

- **Bindings are aliases, not variables.** `auto [a, b] = f();` materializes a hidden object; `a` and `b` name its members. `decltype(a)` is the member type, which surprises generic code.
- **Lambda capture is ill-formed in C++17.** `[a] { ... }` where `a` is a structured binding does not compile until C++20 (P1091). Copy into a local first: `auto a_copy = a;`.
- **No selective ignore.** There is no `std::ignore` for structured bindings. Use a dummy name plus `[[maybe_unused]]`. C++26 adds the `_` placeholder — verify against your toolchain before using it.
- **`auto&` vs `auto` matters.** `auto [k, v] : map` copies every pair (and fails to compile for map iteration since the key is `const`). Default to `const auto&` or `auto&` in range-for.

## if constexpr

Compile-time branching inside one function body. The not-taken branch is *not instantiated*, which is the whole point — code in it may be invalid for the current `T`.

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

This replaces tag dispatch and most enable_if-based SFINAE for simple cases. On a C++20 baseline, prefer concepts plus overloads for public APIs and keep `if constexpr` for internal branching — see `cpp20-features.md`.

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

- **Discarded branches must still parse.** Only *template-dependent* invalid code is tolerated. Non-dependent errors (typos, wrong arity on a known function) are diagnosed even in the dead branch.
- **`static_assert(false)` in the final else is ill-formed in C++17/20**, even though it often "works" on some compilers. Use the dependent-false idiom:

```cpp
template <typename> inline constexpr bool always_false_v = false;

// ...
} else {
    static_assert(always_false_v<T>, "unsupported type");
}
```

  C++23 (P2593) makes plain `static_assert(false)` valid in uninstantiated branches — mark the requirement if you rely on it.
- **No fall-through deduction surprises.** Different branches may `return` different types only because the others are discarded; if two branches are both instantiated for some `T` and return different types, deduction fails.
- **It is not a constexpr evaluator.** The condition must be a constant expression; runtime conditions still need ordinary `if`.

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

- **Lifetime ends with the `if`/`else` chain.** Returning a reference or `string_view` into the init-statement variable dangles.
- **The init variable is visible in `else` too** — that is a feature (error branches can inspect it), but it also means a `lock_guard` stays locked through `else`.
- **Don't create a `string_view` from a temporary in the initializer**: `if (std::string_view sv = make_string(); ...)` dangles immediately because the temporary `std::string` dies at the end of the initializer. Bind the `std::string` itself instead.

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

`transform`/`and_then`/`or_else` are C++23 — on a C++17 baseline use `value_or` and explicit checks; see `cpp23-features.md` for the monadic style.

Lazy single-init caching is a natural fit:

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

For error reporting where the caller needs to know *why* it failed, prefer `std::expected<T, E>` (C++23) or an error-code out-parameter — see [error-handling.md](error-handling.md).

### Pitfalls

- **`*opt` and `opt->` on an empty optional are undefined behavior**, not an exception. Only `.value()` throws (`std::bad_optional_access`). Sanitizers do not reliably catch the UB form; check first.
- **`std::optional<T&>` does not exist in C++17/20/23.** Use `T*` (idiomatic for "optional reference") or `std::reference_wrapper`. C++26 adds `optional<T&>` — verify against your toolchain.
- **`optional<bool>` has three states** and `if (opt)` tests *presence*, not the contained value. Write `if (opt.has_value())` and `*opt` separately when both matter.
- **Comparison conversions:** `opt == 5` works (empty compares unequal), which is convenient but hides presence checks in review. Be explicit in non-trivial code.
- **It stores the value inline.** `optional<BigObject>` is `sizeof(BigObject)` plus a flag plus padding; don't use it to "save memory."

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

`std::visit` with the `overloaded` idiom is the canonical pattern; the deduction guide is unnecessary on C++20 (aggregate CTAD covers it).

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

- **Converting construction is a trap in C++17:** `std::variant<std::string, bool> v = "abc";` selects **`bool`** under C++17 rules (array-to-pointer, pointer-to-bool). P0608 fixed this for C++20, where `std::string` is chosen. If you straddle standards, construct explicitly: `v.emplace<std::string>("abc");`.
- **`std::get<T>` throws `bad_variant_access`** on the wrong alternative; `std::get_if<T>` returns `nullptr` and wants a pointer to the variant.
- **`valueless_by_exception()`** is a real (rare) state reached when a throwing move corrupts assignment. `std::visit` on a valueless variant throws. If alternatives have throwing moves, handle it or design it out (nothrow-movable alternatives).
- **First alternative must be default-constructible** for the variant to be; otherwise lead with `std::monostate`.
- **Exhaustiveness is structural, not checked.** A generic `[](const auto&)` arm silently swallows newly added alternatives. Omit it to get a compile error when the variant grows — that is usually what you want.

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

- **Prefer `variant` when the set of types is closed.** `any` trades compile-time checking for runtime `any_cast` failures (`std::bad_any_cast` for the reference form).
- **Exact-type matching:** `any_cast<int>` fails on a stored `long`; there are no conversions, no base-class casts.
- **May heap-allocate.** Small-object optimization is implementation-defined; never assume `any` is cheap in hot paths.

## std::string_view

A non-owning `(pointer, length)` view of character data. Pass by value — it is two words.

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

- **Lifetime is the entire game.** A `string_view` is only valid while the underlying buffer lives. The classic crashes:

```cpp
std::string_view sv = get_name() + "_suffix";  // dangles: temporary string dies here
std::string_view first_word(const std::string& s);  // fine
std::string_view bad() { std::string s = make(); return s; }  // dangles
```

  Never return a `string_view` into a local; never store one past the owner's lifetime (especially as a class member fed from a constructor parameter).
- **Not null-terminated.** `sv.data()` must not be passed to C APIs expecting a NUL terminator (`open`, `printf("%s")`). Materialize: `std::string(sv).c_str()`.
- **Conversion is asymmetric.** `std::string` → `string_view` is implicit; `string_view` → `std::string` requires explicit construction. That is deliberate: the expensive direction is visible.
- **`remove_prefix`/`remove_suffix` mutate the view**, not the data — handy for parsers, confusing in review if you expected immutability.
- **Containers of views are a smell** unless the backing storage is provably stable (e.g., views into one long-lived file buffer).

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

The atomic-replace pattern — never leave a half-written config behind:

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

- **Every operation has throwing and `error_code` overloads.** Filesystem races make errors *normal*, not exceptional — prefer the `error_code` overloads in long-running code and library code.
- **TOCTOU races:** `if (fs::exists(p)) open(p)` is check-then-use; the file can change between the calls. For security-sensitive code, just open and handle the failure — see [secure-coding](../../../_shared/secure-coding/SKILL.md).
- **Path encoding differs per OS.** `path::native()` is `wchar_t`-based on Windows, `char`-based on POSIX. Use `path::u8string()`/`fs::u8path` (C++17; revised around `char8_t` in C++20) at serialization boundaries instead of assuming `.string()` is UTF-8.
- **Older toolchains need an extra link library:** GCC 8 requires `-lstdc++fs`, pre-LLVM-9 libc++ requires `-lc++fs`. Modern toolchains need nothing — verify against your toolchain before adding the flag unconditionally.
- **`fs::remove_all` deletes recursively** and returns a count; double-check the path construction above any call to it.
- **`operator/` replaces on absolute right-hand sides:** `fs::path("/a") / "/etc"` yields `/etc`, not `/a/etc`. Validate untrusted path components before joining.

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
| libstdc++ (GCC 9+) | Parallel policies are implemented **on top of Intel oneTBB**. Without TBB headers at compile time and `-ltbb` at link time, `<execution>` use fails to compile or silently degrades. Some GCC/oneTBB version pairings have been incompatible — verify against your toolchain. |
| libc++ | Support has historically been absent/partial; newer LLVM releases ship a PSTL behind experimental flags. Verify against your toolchain before depending on it. |
| MSVC STL | Implemented natively since VS 2017 15.7; no extra dependency. |

Fallback row: if you cannot guarantee TBB on every target, keep the serial call and parallelize explicitly (thread pool, OpenMP), or gate with a CMake check for `TBB::tbb`:

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

- **An exception escaping the element function calls `std::terminate`** for all execution policies. Catch inside the lambda.
- **`par_unseq` forbids vectorization-unsafe operations** in the element function: no locking, no memory allocation, nothing that synchronizes between iterations.
- **Data races are your problem.** The policy parallelizes; it does not synchronize your shared state.
- **Measure before and after.** For small ranges or memory-bound loops, `par` is routinely slower than `seq`. Use `hyperfine` or Google Benchmark — see [profiling-tools](../../../tooling/diagnostics/references/profiling-tools.md).

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

- **Braces vs parentheses change the meaning for containers:**

```cpp
std::vector v1{3, 0};   // vector<int> with elements {3, 0}
std::vector v2(3, 0);   // vector<int> with elements {0, 0, 0}
std::vector v3{v1};     // vector<int> (copy), NOT vector<vector<int>>
```

  In deduced contexts, prefer parentheses for count/value constructors and be suspicious of single-brace copies.
- **All-or-nothing:** you cannot supply some template arguments and deduce the rest. `std::pair<int>{1, 2.0}` is an error.
- **Aggregates deduce only from C++20** (P1816). On C++17, aggregates need explicit arguments or a hand-written guide.
- **`std::make_*` factories are not dead:** `make_shared` and `make_unique` still allocate/own; CTAD does not replace them.
- **Deduced `string` is the trap:** `std::pair p{"a", "b"}` deduces `pair<const char*, const char*>`. Use `"a"s` / `"a"sv` literals when you mean `string`/`string_view`.

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

- **Empty packs:** unary folds over most operators are ill-formed for an empty pack. Only `&&` (→ `true`), `||` (→ `false`), and `,` (→ `void()`) have defined empty results. Use a binary fold with an identity element (`(0 + ... + args)`) when the pack may be empty.
- **Associativity is encoded in the syntax:** `(args - ...)` is a *right* fold `a1 - (a2 - a3)`; `(... - args)` is a *left* fold `(a1 - a2) - a3`. For non-associative operators this changes the answer.
- **Parentheses are mandatory.** A fold expression is only valid inside its own parentheses.
- **Short-circuiting works** in `&&`/`||` folds, evaluation order is left-to-right — folds over `,` are the idiomatic "loop over a pack."

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

Mechanical upgrades worth doing in bulk (clang-tidy `modernize-*` checks automate most of them — route batches through `Task(system-developer:sys-code-fixer)` or `/system-developer:code-modernize`):

| Old pattern | C++17 replacement | clang-tidy check |
|---|---|---|
| `std::tie(a, b) = f();` | `auto [a, b] = f();` | — (manual) |
| Tag dispatch / `enable_if` chains | `if constexpr` | — (manual) |
| `T* p` or sentinel values meaning "maybe absent" | `std::optional<T>` | — (manual, API-level) |
| `const std::string&` parameters that only read | `std::string_view` | `modernize-*`, review lifetimes first |
| Type-code `enum` + `union` | `std::variant` | — (manual) |
| `boost::filesystem` | `std::filesystem` | mostly find-and-replace; API near-identical |
| `make_pair`/`make_tuple` noise | CTAD | `modernize-use-ctad` (name varies; verify against your toolchain) |
| Recursive variadic helpers | Fold expressions | — (manual) |
| Header-global `static`/`extern` constants | `inline constexpr` | — (manual) |
| `typedef` | `using` | `modernize-use-using` |

Behavioral changes to be aware of when flipping `-std=c++17` on old code:

- **Exception specifications joined the type system** — `void (*p)() noexcept` no longer converts to a potentially-throwing function pointer type.
- **`auto x{1}`** deduces `int` (was `initializer_list<int>`).
- **Trigraphs and `register`** are gone; `++` on `bool` is gone.
- **Guaranteed copy elision** can change observable behavior in code that counted copies (test mocks, instrumented types).
- **Evaluation order is (partially) fixed** — `a(b(), c())` argument order is still unspecified, but `a << b() << c()` and assignments gained ordering guarantees; code that "worked by accident" may change behavior in either direction.

One standard jump at a time: go 11/14 → 17, stabilize under `-Wall -Wextra -Werror` plus a sanitizer pass, then consider 20. See `/system-developer:code-modernize` for the ledger-driven workflow.

## Related References

- [cpp20-features.md](cpp20-features.md) — concepts, `<=>`, `span`, `format`, modules.
- [cpp23-features.md](cpp23-features.md) — `expected`, `print`, deducing this, monadic `optional`.
- [ranges.md](ranges.md) — the C++20 replacement for iterator-pair pipelines.
- [error-handling.md](error-handling.md) — choosing between exceptions, `optional`, and `expected`.
- [../SKILL.md](../SKILL.md) — standard-selection table and modern-C++ core rules.
- [version-feature-matrix.md](../../../_shared/version-feature-matrix.md) — canonical toolchain minimums.
