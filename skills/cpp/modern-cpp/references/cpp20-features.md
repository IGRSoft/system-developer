# C++20 Features

C++20 facilities with worked patterns and traps: concepts, `<=>`, `span`, `format`, `consteval`/`constinit`, designated initializers, modules, and the C++17 → 20 breakage list. Ranges live in [ranges.md](ranges.md); coroutines in [coroutines.md](../../cpp-concurrency/references/coroutines.md).

## Compiler and Library Support Summary

The core language is solid in GCC/Clang/MSVC; library features landed unevenly, and modules are the outlier. Versions are first-usable releases; canonical minimums: [version-feature-matrix.md](../../../_shared/version-feature-matrix.md).

### Language features

| Feature | Standard | GCC | Clang | MSVC | Fallback if unavailable |
|---|---|---|---|---|---|
| Concepts | C++20 | 10+ | 10+ | 19.23+ (solid by 19.30) | `enable_if`/SFINAE, `static_assert` on traits |
| `<=>` + `<compare>` | C++20 | 10+ | 10+ | 19.20+ | Hand-written six operators |
| `constinit` / `consteval` | C++20 | 10+ | 10/11+ | 19.29+ | `constexpr` + manual discipline |
| Designated initializers | C++20 | 8+ | 10+ | 19.21+ | Ordered aggregate init + comments |
| Modules | C++20 | 14+ (improving) | 16+ | 19.28+ (most mature) | Headers + precompiled headers |

### Library features

| Feature | Standard | GCC | Clang | MSVC | Fallback if unavailable |
|---|---|---|---|---|---|
| `std::span` | C++20 | 10+ | 7+ (libc++) | 19.26+ | `gsl::span`, pointer + length pair |
| `std::format` | C++20 | 13+ (libstdc++) | libc++ 14+ (maturing later) | 19.29+ | `{fmt}` library (API-compatible superset) |
| `std::bit_cast` | C++20 | 11+ | 14+ (libc++; builtin earlier) | 19.27+ | `std::memcpy` (runtime only) |
| `std::source_location` | C++20 | 11+ | 15+ | 19.29+ | `__FILE__`/`__LINE__` macros |

## Concepts

Named, composable compile-time predicates on template parameters. They replace `enable_if` for overload control and turn template error novels into one-line diagnostics.

### Using the standard concepts

`<concepts>` ships the vocabulary; use it before writing your own.

```cpp
#include <concepts>

template <std::integral T>
constexpr T midpoint_floor(T a, T b) { return a + (b - a) / 2; }

template <std::floating_point T>
T normalize(T v);

void run(std::invocable<int> auto callback);   // callable with an int

template <std::ranges::input_range R>          // from <ranges>
void consume(R&& range);
```

Most useful ones: `same_as`, `convertible_to`, `integral`, `signed_integral`, `unsigned_integral`, `floating_point`, `constructible_from`, `default_initializable`, `movable`, `copyable`, `regular` (copyable + default-init + equality), `equality_comparable`, `totally_ordered`, `invocable`/`predicate`, and the `std::ranges::*_range` family.

### Four equivalent constraint syntaxes

```cpp
// 1. requires-clause after the template header
template <typename T> requires std::integral<T>
T twice(T v) { return v + v; }

// 2. trailing requires-clause (works on member functions of class templates)
template <typename T>
T thrice(T v) requires std::integral<T> { return 3 * v; }

// 3. constrained template parameter
template <std::integral T>
T quad(T v) { return 4 * v; }

// 4. abbreviated function template
std::integral auto half(std::integral auto v) { return v / 2; }
```

Prefer 3 for ordinary cases, 2 for constraining members of class templates, 1 when the constraint mentions several parameters. Form 4 is fine for small utilities; remember each `auto` is an independent template parameter.

Constrained `auto` also works on variables and return types: `std::integral auto n = parse_count(s);`.

### Constraining class-template members

Constraining individual members of a class template (trailing `requires`) keeps the class usable for types that lack optional capabilities:

```cpp
template <typename T>
class Buffer {
public:
    void push(T v);                                  // always available

    void sort() requires std::totally_ordered<T> {  // only when T can be ordered
        std::ranges::sort(items_);
    }

    Buffer clone() const requires std::copyable<T>;  // move-only T still gets push/sort
private:
    std::vector<T> items_;
};
```

`Buffer<std::unique_ptr<int>>` compiles; calling `clone()` on it is the only error.

### Writing your own

A `concept` is a named boolean constant expression; `requires`-expressions let it check syntax:

```cpp
template <typename T>
concept Hashable = requires(const T& t) {
    { std::hash<T>{}(t) } -> std::convertible_to<std::size_t>;
};

template <typename T>
concept Serializable = requires(const T& t, std::ostream& os) {
    typename T::serialized_tag;            // type requirement
    { t.serialize(os) } -> std::same_as<void>;  // compound requirement
    requires std::default_initializable<T>;     // nested requirement
};

template <typename C>
concept ByteSink = requires(C& c, std::span<const std::byte> data) {
    { c.write(data) } -> std::same_as<std::size_t>;
};
```

### The four requirement kinds

Inside `requires (...) { ... }`:

| Kind | Syntax | Checks |
|---|---|---|
| Simple | `t.serialize(os);` | Expression compiles |
| Type | `typename T::value_type;` | Type exists |
| Compound | `{ expr } noexcept -> Concept<args>;` | Expression compiles, optional noexcept, result satisfies concept |
| Nested | `requires SomeConcept<T>;` | A further constant expression holds |

### Concepts as customization points

An ad-hoc `requires`-expression works directly inside `if constexpr`, which makes capability probing trivial:

```cpp
// Extension point: users provide format_for_log(T, string&), found by ADL.
template <typename T>
concept LogFormattable = requires(const T& t, std::string& out) {
    { format_for_log(t, out) } -> std::same_as<void>;
};

template <typename T>
void log_value(const T& value) {
    if constexpr (LogFormattable<T>) {
        std::string buf;
        format_for_log(value, buf);                     // user hook
        sink(buf);
    } else if constexpr (requires { std::formatter<T>{}; }) {  // C++23: std::formattable<T, char>
        sink(std::format("{}", value));                 // inline capability probe
    } else {
        sink("<unformattable>");
    }
}
```

This replaces detection-idiom machinery (`std::void_t`, `is_detected`) wholesale.

### Pitfalls when writing concepts

- The arrow takes a concept, not a type: `{ t.size() } -> std::size_t;` is ill-formed. Write `-> std::same_as<std::size_t>` or `-> std::convertible_to<std::size_t>`; the result type is passed as the concept's first argument.
- `requires requires(T t) { t.foo(); }` is legal but can't participate in subsumption or be reused. Name it.
- Concepts check syntax, not semantics: `std::equality_comparable` can't verify `==` is an equivalence relation. Document semantic requirements and cover them with property-based tests (rapidcheck, or hand-rolled under GoogleTest/Catch2).
- A failed concept removes the overload silently. If a worse overload remains, you get wrong behavior with no diagnostic. Keep an unconstrained `static_assert` fallback overload in tricky overload sets while migrating.
- Constrain the public API; let internals fail naturally. Every constraint is a contract you maintain.

### Finding the failing sub-requirement

When a type unexpectedly fails a concept, `static_assert` the sub-requirements to find the culprit:

```cpp
static_assert(std::movable<Widget>);            // fails? check next lines
static_assert(std::is_object_v<Widget>);
static_assert(std::move_constructible<Widget>);
static_assert(std::assignable_from<Widget&, Widget>);  // ← the actual failure
static_assert(std::swappable<Widget>);
```

### Subsumption basics

When two constrained overloads both match, the compiler picks the one whose constraints *subsume* the other's (logically imply them).

```cpp
template <std::integral T>
void store(T v) { /* general integer path */ }

template <std::signed_integral T>   // signed_integral = integral<T> && ...
void store(T v) { /* sign-aware path */ }

store(42);   // picks signed_integral overload: it subsumes integral
```

- Subsumption decomposes constraints into atomic constraints through named concepts (`&&`/`||` trees). It doesn't look inside a `requires`-expression body or prove math (`sizeof(T) > 4` does not subsume `sizeof(T) > 2`).
- Two textually identical expressions are different atoms unless they come from the same concept: `std::is_integral_v<T>` in two places doesn't subsume, `std::integral<T>` does. Build constraint hierarchies from named concepts, not raw traits.
- If neither constraint subsumes the other and both overloads match, the call is ambiguous.

## Three-Way Comparison (`<=>`)

One defaulted operator generates the entire comparison family.

```cpp
#include <compare>

struct Version {
    int major, minor, patch;
    auto operator<=>(const Version&) const = default;  // ==, !=, <, <=, >, >= all work
};

static_assert(Version{1, 2, 3} < Version{1, 3, 0});
```

Defaulted `<=>` compares members lexicographically in declaration order and implicitly declares a defaulted `operator==`, so the one line gives all six operators.

### Comparison categories

| Category | Meaning | Typical source |
|---|---|---|
| `std::strong_ordering` | `equal` implies substitutability | Integers, strings, lexicographic structs |
| `std::weak_ordering` | Equivalent values may differ | Case-insensitive strings |
| `std::partial_ordering` | Some pairs unordered (`unordered`) | Floating point (NaN) |

With `auto` return type, the category is the weakest among members: one `double` member makes the struct `partial_ordering`.

### Heterogeneous comparison comes free

Operator rewriting means one direction suffices; the compiler synthesizes the reversed forms:

```cpp
struct Price {
    std::int64_t cents;
    std::strong_ordering operator<=>(std::int64_t c) const { return cents <=> c; }
    bool operator==(std::int64_t c) const { return cents == c; }
    auto operator<=>(const Price&) const = default;
};

Price p{499};
bool a = p < 500;    // direct: p.operator<=>(500) < 0
bool b = 500 > p;    // rewritten + reversed: 0 > p.operator<=>(500)
bool c = 500 == p;   // reversed operator==
```

Pre-C++20 this required six member operators plus six free functions per mixed-type pair.

### Pitfalls: mixing defaulted and hand-written operators

- A user-provided `operator<=>` doesn't give you `operator==`; only the defaulted form does. Write or default `==` too, or `a == b` fails to compile, or finds a stale pre-C++20 `==` with different semantics.

```cpp
struct Id {
    std::string label;  // ignored in ordering
    std::uint64_t key;
    std::strong_ordering operator<=>(const Id& o) const { return key <=> o.key; }
    bool operator==(const Id& o) const { return key == o.key; }  // required, easy to forget
};
```

- Don't implement `==` via `<=>`: `(a <=> b) == 0` on strings can't short-circuit on length. A defaulted `==` does the right thing.
- A member with only `<` and `==` (legacy type) makes `auto operator<=>(...) = default;` deleted. Name the category, `std::strong_ordering operator<=>(const T&) const = default;`, and the compiler synthesizes it from the member's `<` and `==`.
### Pitfalls: NaN, reversed operators, C++17 headers

- `std::sort` with a comparator from a `partial_ordering` type is UB when NaN appears. For float-bearing structs, exclude the float, use `std::strong_order(a, b)` (total order over IEEE bits), or assert NaN-freedom at the boundary.
- In C++20, `a == b` also considers reversed `b == a`, and `a != b` is rewritten from `==`. Asymmetric legacy operators can become ambiguous (`-Wambiguous-reversed-operator`). The classic offender:

```cpp
struct Legacy {
    bool operator==(const Legacy& o);  // non-const — fine in C++17
};
// C++20: a == b considers both operator==(a, b) and reversed operator==(b, a);
// the non-const member and the reversed candidate now collide → warning/ambiguity.
```

  Fix the operator (`const`, symmetric, ideally a hidden friend) rather than suppressing the warning.
- Don't expose defaulted `<=>` in headers consumed by C++17 TUs: overload resolution then differs per TU. Keep public headers standard-consistent.

## std::span

A non-owning view over contiguous memory: `(pointer, length)`, two words, pass by value. It replaces `(T*, size_t)` parameter pairs:

```cpp
// Before: two parameters that can disagree, no iteration support, casts at call sites
int checksum(const unsigned char* data, size_t len);

// After: one parameter, range-based for, subviews, every contiguous container accepted
int checksum(std::span<const unsigned char> data);
```

```cpp
// Accepts std::vector, std::array, C arrays, other spans — one signature:
double mean(std::span<const double> xs) {
    if (xs.empty()) return 0.0;
    return std::reduce(xs.begin(), xs.end(), 0.0) / static_cast<double>(xs.size());
}

std::vector<double> v = load();
double a[4] = {1, 2, 3, 4};
mean(v);
mean(a);
mean(std::span{a}.subspan(1, 2));   // view of {2, 3}
```

### Fixed extent and byte views

Fixed extent encodes length in the type and costs one word:

```cpp
void process_block(std::span<const std::byte, 64> block);   // exactly 64 bytes, checked at compile time where possible

std::array<std::byte, 64> buf{};
process_block(buf);                  // OK
process_block(std::span{buf}.first<64>());  // explicit fixed subview
```

Byte-wise access without UB:

```cpp
std::span<const std::byte> raw = std::as_bytes(std::span{v});
std::span<std::byte> writable = std::as_writable_bytes(std::span{v});
```

### Pitfalls

- `operator[]`, `front()`, and `back()` are unchecked (UB out of range). C++26 adds `span::at`; until then check `size()` yourself. ASan catches overruns ([sanitizers](../../../tooling/diagnostics/references/sanitizers.md)).
- Spans dangle like `string_view`: `std::span<const int> s = make_vector();` views a dead temporary. Don't return a span of a local or store one past the owner; `vector` reallocation invalidates spans into it.
- Constness lives on the element type: `span<const T>` can't write elements; `const span<T>` can't reseat but can write. Take `span<const T>` for read-only parameters.
- No `operator==` (identity vs element-wise is ambiguous). Use `std::ranges::equal(a, b)`.

### Construction and extent limits

- No construction from `initializer_list` until C++26 (P2447): `mean({1.0, 2.0})` fails on C++20; pass an array or named container.
- Dynamic → fixed extent is explicit; a mismatched runtime size is UB, not an exception.
- `span` is one-dimensional; `std::mdspan` is C++23. The C++20 workaround is a row accessor: `std::span<T> row(std::span<T> data, size_t i, size_t cols) { return data.subspan(i * cols, cols); }`.

## std::format

Type-safe, locale-independent-by-default text formatting; printf ergonomics without printf UB.

```cpp
#include <format>

std::string s  = std::format("{} + {} = {}", 2, 2, 4);
std::string h  = std::format("{:#010x}", 48879);        // 0x0000beef
std::string f  = std::format("{:>12.3f}", 3.14159);     //        3.142
std::string i  = std::format("{0} {1} {0}", "ab", "ra"); // ab ra ab — indexed args
std::string e  = std::format("{{literal braces}}");      // {literal braces}
```

Spec mini-language (after the `:`): `[[fill]align][sign][#][0][width][.precision][type]` — `<` `^` `>` align, `+` sign, `#` alternate form, `b/o/x/X` integer bases, `e/f/g` floats, `{}` nested width/precision args.

### Runtime width, precision, and chrono

```cpp
std::format("{:>{}}", name, column_width);            // width from an argument
std::format("{:*^{}.{}f}", x, width, precision);      // both nested
std::format("{:%Y-%m-%d %H:%M}", std::chrono::system_clock::now());  // chrono specs
```

### Format strings are checked at compile time

An invalid format string or argument mismatch is a compile error (P2216, applied retroactively to C++20):

```cpp
std::format("{:d}", "not an int");   // does not compile
```

Consequence: the format string must be a constant expression. For genuinely runtime strings (translations, config):

```cpp
std::string out = std::vformat(translated, std::make_format_args(user, count));
```

`vformat` throws `std::format_error` at runtime on bad specs; test translated strings.

### Formatting your own types

Specialize `std::formatter`; inheriting `parse` from an existing formatter is the low-effort path:

```cpp
template <>
struct std::formatter<Version> : std::formatter<std::string_view> {
    auto format(const Version& v, std::format_context& ctx) const {
        return std::format_to(ctx.out(), "{}.{}.{}", v.major, v.minor, v.patch);
    }
};

std::format("release {}", Version{1, 2, 3});   // "release 1.2.3"
```

`std::format_to(std::back_inserter(buf), ...)` appends without intermediate strings; `std::format_to_n` bounds output; `std::formatted_size` pre-computes length.

### Formatters with their own spec options

A formatter with its own spec options implements `parse` too:

```cpp
struct Temperature { double celsius; };

template <>
struct std::formatter<Temperature> {
    char unit = 'C';

    constexpr auto parse(std::format_parse_context& ctx) {
        auto it = ctx.begin();
        if (it != ctx.end() && (*it == 'C' || *it == 'F')) unit = *it++;
        if (it != ctx.end() && *it != '}')
            throw std::format_error("Temperature: expected C or F");
        return it;
    }

    auto format(const Temperature& t, std::format_context& ctx) const {
        double v = (unit == 'F') ? t.celsius * 9.0 / 5.0 + 32.0 : t.celsius;
        return std::format_to(ctx.out(), "{:.1f}{}", v, unit);
    }
};

std::format("{:F}", Temperature{21.5});   // "70.7F"
std::format("{}",   Temperature{21.5});   // "21.5C"
```

### Pitfalls

- Library support lagged: libstdc++ shipped `<format>` in GCC 13, libc++ matured across LLVM 14–17, MSVC was first (VS 16.10). On older baselines use `{fmt}`; `std::format` is its standardized subset, so migration is mostly `fmt::` → `std::`.
- Output is unlocalized by default (reproducible logs). Locale-aware output needs the `L` spec and an explicit locale.
- `std::print`/`println` are C++23; on C++20 write `std::cout << std::format(...)`.
- Don't pass user input as the format string (`vformat(user_supplied, ...)`): it throws rather than corrupting memory, but it is a DoS vector. Format into `{}` placeholders ([secure-coding](../../../_shared/secure-coding/SKILL.md)).
- Pointers format only as `const void*`. Chrono formatting completeness varies by library version.

## constinit and consteval

Two precision tools that split apart what `constexpr` conflates.

The spectrum:

| Keyword | Guarantees | Use for |
|---|---|---|
| `constexpr` (function) | *Can* run at compile time, may run at runtime | General-purpose |
| `consteval` (function) | *Must* run at compile time (immediate function) | Compile-only work: parsing literals, lookup-table generation, enforcing literal-only APIs |
| `constinit` (variable) | Static/thread-local is constant-initialized; stays mutable | Ending the static-init-order fiasco and runtime init cost |
| `if consteval` | Branch on compile-vs-runtime context | C++23 ([cpp23-features.md](cpp23-features.md)) |

### Compile-time hashing and constant initialization

```cpp
consteval std::uint32_t fnv1a(std::string_view s) {
    std::uint32_t h = 2166136261u;
    for (char c : s) { h ^= static_cast<unsigned char>(c); h *= 16777619u; }
    return h;
}

switch (fnv1a(command)) {            // error unless `command` is a constant expression
    case fnv1a("start"): ...         // each case hashed at compile time
}

// Guaranteed no runtime initializer, no init-order fiasco, still mutable:
constinit std::atomic<int> request_count{0};

// thread_local + constinit avoids the per-first-access init guard:
constinit thread_local int tls_depth = 0;
```

### Compile-time table generation

`consteval` guarantees zero runtime cost:

```cpp
consteval std::array<std::uint32_t, 256> make_crc32_table() {
    std::array<std::uint32_t, 256> table{};
    for (std::uint32_t i = 0; i < 256; ++i) {
        std::uint32_t c = i;
        for (int k = 0; k < 8; ++k)
            c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
        table[i] = c;
    }
    return table;
}

constinit auto crc_table = make_crc32_table();   // baked into .data, no startup code
```

### Pitfalls

- `constinit` constrains initialization only, not mutability. `constinit const` is legal, but plain `constexpr` is usually simpler.
- `constinit` applies only to static and thread-local storage; on locals it is an error.
- `consteval` spreads upward: you can't take its address outside an immediate context or call it with runtime arguments, and in C++20 a `constexpr` function calling it with a non-constant argument is an error (P2564, a DR in GCC 14+/Clang 17+, instead makes such function templates immediate). Start with `constexpr`; tighten to `consteval` only when accidental runtime evaluation is a real bug class.
- "Not a constant expression" diagnostics point at the call site, often deep in a template stack. Keep `consteval` functions small and leaf-like.

## Designated Initializers

Name the members you initialize; suited to config structs.

```cpp
struct ServerOptions {
    std::string host = "127.0.0.1";
    int port = 8080;
    int backlog = 64;
    bool reuse_addr = true;
};

auto opts = ServerOptions{
    .host = "0.0.0.0",
    .port = 9090,
    // backlog, reuse_addr keep their default member initializers
};
```

Unnamed members fall back to their default member initializers (or value-initialization), which makes adding new trailing fields source-compatible.

### Pitfalls: C++20 is stricter than C99

| C99 allows | C++20 |
|---|---|
| Out-of-order designators `{.y = 1, .x = 2}` | ill-formed: follow declaration order |
| Nested designators `{.pt.x = 1}` | ill-formed: nest braces, `{.pt = {.x = 1}}` |
| Array designators `{[2] = 5}` | ill-formed |
| Mixing designated and positional `{1, .y = 2}` | ill-formed: all or nothing |

GCC rejects these; Clang accepts them as C99 extensions with a warning, so code that builds on Clang can fail on GCC.

- Aggregates only: no user-declared constructors, private members, or virtuals. Adding a constructor later breaks every designated-init call site.
- Reordering members breaks callers using designators. Append, don't reorder.
- Shared C/C++ headers: stick to the common subset (in-order, non-nested). C-side differences: [c23-features.md](../../../c/modern-c/references/c23-features.md).

## std::bit_cast

Reinterpret the bytes of one trivially copyable type as another: the only type-pun that is both UB-free and `constexpr`.

```cpp
#include <bit>

float f = 1.5f;
auto bits = std::bit_cast<std::uint32_t>(f);      // well-defined, constexpr-capable

// The classic Quake trick, now legal and compile-time:
constexpr float fast_inv_sqrt_seed(float x) {
    return std::bit_cast<float>(0x5f3759df - (std::bit_cast<std::uint32_t>(x) >> 1));
}
```

Replaces both flavors of wrong:

```cpp
auto b1 = *reinterpret_cast<std::uint32_t*>(&f);  // UB: strict aliasing violation
std::uint32_t b2; std::memcpy(&b2, &f, 4);        // OK but runtime-only and clunky
```

Pair with `std::endian` for serialization:

```cpp
if constexpr (std::endian::native == std::endian::big) {
    bits = std::byteswap(bits);   // std::byteswap is C++23; use a local swap on C++20
}
```

### Pitfalls

- Sizes must match (`sizeof(To) == sizeof(From)`) and both types be trivially copyable; enforced at compile time.
- Padding bits in the result are unspecified; comparing such structs bytewise is a bug.
- Not constant-evaluable when either type is or contains a union, pointer, pointer-to-member, reference, or volatile member.
- It reproduces native bytes; serialization still needs explicit byte-order handling.

## std::source_location

Capture file/line/function of the *call site* without macros — via a defaulted argument.

```cpp
#include <source_location>

void log(std::string_view msg,
         std::source_location loc = std::source_location::current()) {
    std::clog << loc.file_name() << ':' << loc.line()
              << " [" << loc.function_name() << "] " << msg << '\n';
}

void connect() {
    log("connecting");   // prints connect()'s file:line — current() evaluated at the CALL site
}
```

A defaulted `current()` is evaluated where the caller wrote the call, not where `log` is defined. `current()` is `consteval`, so the capture is free at runtime.

### Versus `__FILE__`/`__LINE__` macros

The macro approach it retires:

| | `__FILE__`/`__LINE__` macros | `std::source_location` |
|---|---|---|
| Needs a macro wrapper per function | Yes (`#define LOG(m) log_impl(m, __FILE__, __LINE__)`) | No: plain function parameter |
| Function name | `__func__` only inside the function | `function_name()` captured at call site |
| Works in default arguments | No | Yes (that is the design) |
| Namespacing/scoping | None (macros) | Ordinary C++ |
| Column information | No | `column()` (quality varies) |

### Pitfalls

- Wrappers eat the location: if `log_error` calls `log` without forwarding one, every report points at the wrapper. Thread the parameter through every layer.
- Variadic functions can't put a defaulted parameter after the pack; make the format-string wrapper carry the location:

```cpp
struct fmt_loc {
    std::string_view fmt;
    std::source_location loc;
    consteval fmt_loc(const char* f,
                      std::source_location l = std::source_location::current())
        : fmt(f), loc(l) {}
};

template <typename... Args>
void logf(fmt_loc f, Args&&... args);   // call sites: logf("x={}", x);
```

- `function_name()` format is implementation-defined (full signature or bare name). Don't parse it or assert on it in tests.
- In default member initializers, `current()` captures the constructor call site.
- Older than GCC 11, Clang 15, or MSVC 19.29: keep a macro shim.

## Modules

The language feature works; the ecosystem is the constraint. Key semantic wins: macros do not leak in or out; declaration order between modules stops mattering; internal symbols are genuinely unreachable; one parse instead of N textual inclusions.

### Syntax

```cpp
// math.cppm (Clang convention; .ixx for MSVC; GCC accepts .cpp with flags)
module;                 // global module fragment: legacy #includes go here
#include <cassert>

export module math;     // module declaration

import other_module;    // visible inside this module only; `export import` re-exports

export int add(int a, int b) { return a + b; }   // exported: visible to importers

export namespace math {                          // export a whole namespace block
    double mean(std::span<const double> xs);
}

int helper() { return 42; }                      // not exported: module-private
```

Consumer:

```cpp
import math;

int main() { return add(2, 2) - 4; }
```

### Partitions and implementation units

Partitions split large modules without exposing structure to consumers:

```cpp
export module math:stats;       // partition interface
export module math;             // primary interface
export import :stats;           // re-export the partition
```

Implementation units keep definitions out of the interface (faster rebuilds when only bodies change):

```cpp
// math_impl.cpp — implementation unit: no `export` keyword on the module declaration
module math;

double math::mean(std::span<const double> xs) {
    return xs.empty() ? 0.0
         : std::reduce(xs.begin(), xs.end(), 0.0) / static_cast<double>(xs.size());
}
```

### Build reality

| Concern | State | Practical guidance |
|---|---|---|
| Compiler maturity | MSVC most complete; Clang 16+ solid for named modules; GCC 14+ workable with rough edges | Pin compiler versions in CI |
| Build system | CMake 3.28+ supports named modules via `FILE_SET CXX_MODULES` with Ninja 1.11+ or Visual Studio generators only; Makefile generators don't work | Hard requirement; see [cmake-modern](../../../tooling/build-systems/references/cmake-modern.md) |
| Dependency scanning | Build-time scanning (`clang-scan-deps` etc.) is automatic under CMake but adds a build phase | Expect slower cold configures; incremental builds usually win overall |
| `import std;` | C++23 feature; CMake support is experimental (opt-in flag) | Don't make it a hard requirement yet |
| Header units (`import <vector>;`) | Portability poor across all three compilers and CMake support is limited | Avoid; use the global module fragment for legacy headers |

### Distribution, tooling, and macros

| Concern | State | Practical guidance |
|---|---|---|
| Distributing modules in libraries | BMI files are compiler-, version-, and flag-specific, not a distribution format; consumers rebuild interfaces from your `.cppm` sources | Ship module interface sources; expect mixed header/module consumers |
| Tooling (IDEs, clangd, formatters, coverage) | Catching up; clangd module support improving but uneven | Budget for tooling friction; keep a header-based escape hatch for analysis runs |
| Macros | Cannot be exported from modules | Config macros stay in headers or move to `consteval` functions/constants |

### Minimal CMake setup

```cmake
# Minimal CMake (3.28+) for a module library
add_library(math)
target_sources(math
    PUBLIC FILE_SET CXX_MODULES FILES math.cppm)
target_compile_features(math PUBLIC cxx_std_20)
```

### Recommendations

| Situation | Verdict |
|---|---|
| Greenfield app, single pinned toolchain, CMake+Ninja | Modules are viable today; start with a few large modules, not one-per-class |
| Library shipped to third parties | Provide headers (or dual-ship); module-only public APIs are still hostile to consumers |
| Existing large codebase | Migrate bottom-up only if build time is a measured pain; the global module fragment makes incremental adoption possible but conversion is real work |
| Needs Make, or compilers older than the table above | Don't. Use precompiled headers for the build-time win |

## Smaller Features Worth Using

### Language

| Feature | One-liner | Watch out for |
|---|---|---|
| Coroutines | `co_await`/`co_yield` language support | No std library types until `std::generator` (C++23); see [coroutines](../../cpp-concurrency/references/coroutines.md) |
| `using enum` | `using enum Color;` unqualifies enumerators in a scope | Scope pollution; keep it function-local |
| `[[likely]]`/`[[unlikely]]` | Branch hints on statements | Measure first; misuse pessimizes ([profiling-tools](../../../tooling/diagnostics/references/profiling-tools.md)) |
| `[[no_unique_address]]` | Empty members take zero space | MSVC ignores it; use `[[msvc::no_unique_address]]` |
| `char8_t` | Distinct type for UTF-8 | Breaking: `u8""` literals no longer convert to `const char*` |
| Abbreviated templates | `void f(auto x)` = template | Each `auto` is an independent parameter |

### Library

| Feature | One-liner | Watch out for |
|---|---|---|
| Ranges | Composable algorithm pipelines | See [ranges.md](ranges.md) |
| `std::jthread` | Joins on destruction + built-in `stop_token` | Prefer over `std::thread` ([cpp-concurrency](../../cpp-concurrency/SKILL.md)) |
| `starts_with`/`ends_with` | On `string`/`string_view` | `contains` is C++23 |
| `std::erase`/`erase_if(container, pred)` | Finally kills the erase-remove idiom | Free functions, not members |
| `map.contains(key)` | Replaces `find() != end()` | Heterogeneous overload needs transparent comparator |
| `std::midpoint`/`std::lerp` | Overflow-safe midpoint, correct lerp | `midpoint` of pointers requires same array |
| `constexpr` everything | `vector`, `string`, algorithms usable in constant evaluation | Compile-time allocations cannot leak to runtime |
| `std::numbers` | `std::numbers::pi`, `e`, `sqrt2` as variable templates | Replaces `M_PI` (which is POSIX, not standard C++) |

## Migration Notes: C++17 to C++20 Breakage

Flipping `-std=c++20` on C++17 code is mostly safe, but these changes bite. Audit each before the switch (`/system-developer:fix-modernize --target cpp20` builds the ledger):

### Code that stops compiling

| Change | Symptom | Fix |
|---|---|---|
| `u8""` literals became `const char8_t*` | `const char* s = u8"...";` stops compiling | Drop the `u8` prefix where you meant bytes, or adopt `char8_t` end-to-end; `-fno-char8_t`/`/Zc:char8_t-` only as a bridge |
| Aggregates with user-declared constructors (even `= default`) are no longer aggregates (P1008) | `T{1, 2}` brace-init stops compiling for `struct T { T() = default; int a, b; };` | Remove the defaulted declaration or add a real constructor |
| `std::allocator<void>`, `raw_storage_iterator`, others removed | Old allocator-aware code breaks | Modern allocator traits; usually dead code |
| Two-phase template lookup tightened, ADL refinements | Previously-accepted ill-formed templates now diagnosed | Fix the template; the old code was wrong |

### Behavior changes and deprecations

| Change | Symptom | Fix |
|---|---|---|
| Reversed/rewritten comparison candidates | `-Wambiguous-reversed-operator` warnings, rare behavior changes | Make `operator==` const and symmetric (see `<=>` section) |
| `std::variant` converting constructor narrowed (P0608) | Different alternative selected vs C++17 | Audit `variant` implicit constructions (see [cpp17-features.md](cpp17-features.md) variant pitfalls) |
| Implicit `this` capture in `[=]` deprecated | Deprecation warnings in lambda-heavy code | Capture `this` (or `*this`) explicitly |
| Many `volatile` uses deprecated (compound assignment, etc.) | `-Wdeprecated-volatile` noise, especially near device registers | Split read-modify-write into explicit loads/stores (better for embedded correctness anyway) |

### Rollout

Enable C++20 with warnings-as-errors in a branch, fix the list above, run the full suite plus ASan/UBSan ([sanitizers](../../../tooling/diagnostics/references/sanitizers.md)), and only then start using C++20 features.

## Related References

- [cpp17-features.md](cpp17-features.md) — the baseline this file builds on.
- [cpp23-features.md](cpp23-features.md) — `expected`, `print`, deducing this, `if consteval`, `import std`.
- [ranges.md](ranges.md) — C++20 ranges and views in depth.
- [error-handling.md](error-handling.md) — exceptions vs `std::expected` decision guide.
- [coroutines.md](../../cpp-concurrency/references/coroutines.md) — C++20 coroutine machinery and C++23 `std::generator`.
- [cmake-modern.md](../../../tooling/build-systems/references/cmake-modern.md) — module builds, presets, toolchain pinning.
- [../SKILL.md](../SKILL.md) — standard-selection table and modern-C++ core rules.
- [version-feature-matrix.md](../../../_shared/version-feature-matrix.md) — canonical toolchain minimums.
