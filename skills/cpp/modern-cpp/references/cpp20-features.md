# C++20 Features

Use this when:

- Your project baseline is C++20 and you want concepts, `<=>`, `span`, and `format` used correctly.
- You are migrating C++17 code and need the interop pitfalls (rewritten comparison operators, variant conversion changes).
- You are evaluating whether C++20 modules are realistic for your build today.

Skip this file if:

- You need C++17 facilities (`optional`, `string_view`, CTAD, parallel algorithms). Use `cpp17-features.md`.
- You need ranges pipelines — they are C++20 but large enough to own a file. Use `ranges.md`.
- You need coroutines — language feature is C++20, but the usable library types arrive later. Use [../../cpp-concurrency/references/coroutines.md](../../cpp-concurrency/references/coroutines.md).
- You are choosing *which* standard to target. Use the standard-selection table in [../SKILL.md](../SKILL.md).

Jump to:

- Compiler and Library Support Summary
- Concepts
- Three-Way Comparison (`<=>`)
- std::span
- std::format
- constinit and consteval
- Designated Initializers
- std::bit_cast
- std::source_location
- Modules
- Smaller Features Worth Using
- Migration Notes: C++17 to C++20 Breakage

## Compiler and Library Support Summary

C++20 core language has been solid in GCC/Clang/MSVC for years; the library features landed unevenly, and modules remain the outlier. Versions below are first-usable releases — verify against your toolchain, and treat [version-feature-matrix.md](../../../_shared/version-feature-matrix.md) as canonical.

| Feature | Standard | GCC | Clang | MSVC | Fallback if unavailable |
|---|---|---|---|---|---|
| Concepts | C++20 | 10+ | 10+ | 19.23+ (solid by 19.30) | `enable_if`/SFINAE, `static_assert` on traits |
| `<=>` + `<compare>` | C++20 | 10+ | 10+ | 19.20+ | Hand-written six operators |
| `std::span` | C++20 | 10+ | 7+ (libc++) | 19.26+ | `gsl::span`, pointer + length pair |
| `std::format` | C++20 | 13+ (libstdc++) | libc++ 14+ (maturing later) | 19.29+ | `{fmt}` library (API-compatible superset) |
| `constinit` / `consteval` | C++20 | 10+ | 10/11+ | 19.29+ | `constexpr` + manual discipline |
| Designated initializers | C++20 | 8+ | 10+ | 19.21+ | Ordered aggregate init + comments |
| `std::bit_cast` | C++20 | 11+ | 14+ (libc++; builtin earlier) | 19.27+ | `std::memcpy` (runtime only) |
| `std::source_location` | C++20 | 11+ | 15+ | 19.29+ | `__FILE__`/`__LINE__` macros |
| Modules | C++20 | 14+ (improving) | 16+ | 19.28+ (most mature) | Headers + precompiled headers |

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

The four requirement kinds inside `requires (...) { ... }`:

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
    } else if constexpr (requires { std::format("{}", value); }) {
        sink(std::format("{}", value));                 // inline capability probe
    } else {
        sink("<unformattable>");
    }
}
```

This replaces detection-idiom machinery (`std::void_t`, `is_detected`) wholesale.

### Pitfalls when writing concepts

- **The arrow takes a concept, not a type:** `{ t.size() } -> std::size_t;` is ill-formed. Write `-> std::same_as<std::size_t>` or `-> std::convertible_to<std::size_t>`. The result type is implicitly passed as the concept's first argument.
- **`requires requires` is legal but a smell.** An inline anonymous `requires`-expression in a `requires`-clause (`requires requires(T t) { t.foo(); }`) cannot participate in subsumption and cannot be reused. Name it.
- **Concepts check syntax, not semantics.** `std::equality_comparable` cannot verify that `==` is an equivalence relation. Document semantic requirements and test them with property-based tests (rapidcheck, or hand-rolled properties under GoogleTest/Catch2 — `Task(system-developer:sys-test-generator)` generates these).
- **Use a concept as a diagnostic, not just a constraint.** When a type unexpectedly fails a concept, `static_assert` the sub-requirements to find the culprit fast:

```cpp
static_assert(std::movable<Widget>);            // fails? check next lines
static_assert(std::is_object_v<Widget>);
static_assert(std::move_constructible<Widget>);
static_assert(std::assignable_from<Widget&, Widget>);  // ← the actual failure
static_assert(std::swappable<Widget>);
```
- **A failed concept removes the overload silently.** If no overload remains you get a decent error; if a *worse* overload remains, you get wrong behavior with no diagnostic. Keep an unconstrained `static_assert` fallback overload in tricky overload sets while migrating.
- **Don't over-constrain implementations.** Constrain the public API; let internals fail naturally. Every constraint you write is a contract you must maintain.

### Subsumption basics

When two constrained overloads both match, the compiler picks the one whose constraints *subsume* the other's (logically imply them).

```cpp
template <std::integral T>
void store(T v) { /* general integer path */ }

template <std::signed_integral T>   // signed_integral = integral<T> && ...
void store(T v) { /* sign-aware path */ }

store(42);   // picks signed_integral overload: it subsumes integral
```

Rules that actually matter in practice:

- Subsumption compares constraints **decomposed into atomic constraints through named concepts** (`&&`/`||` trees). It never looks inside a `requires`-expression body and never proves math (`sizeof(T) > 4` does not subsume `sizeof(T) > 2`).
- **Two textually identical expressions are different atoms unless they come from the same concept.** `requires std::is_integral_v<T>` in two places does not subsume; `std::integral<T>` in two places does. Consequence: build constraint hierarchies out of named concepts, never raw traits, if you want overload refinement to work.
- If neither constraint subsumes the other and both overloads match, the call is **ambiguous** — add a more specific overload or combine concepts explicitly.

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

Defaulted `<=>` compares members lexicographically in declaration order. Defaulting `<=>` also implicitly declares a defaulted `operator==` — you get all six operators from the one line above.

### Comparison categories

| Category | Meaning | Typical source |
|---|---|---|
| `std::strong_ordering` | `equal` implies substitutability | Integers, strings, lexicographic structs |
| `std::weak_ordering` | Equivalent values may differ | Case-insensitive strings |
| `std::partial_ordering` | Some pairs unordered (`unordered`) | Floating point (NaN) |

With `auto` return type, the category is deduced as the weakest among members — a single `double` member makes the whole struct `partial_ordering`.

### Heterogeneous comparison comes free

Operator rewriting means one direction suffices — the compiler synthesizes the reversed forms:

```cpp
struct Price {
    std::int64_t cents;
    std::strong_ordering operator<=>(std::int64_t c) const { return cents <=> c; }
    bool operator==(std::int64_t c) const { return cents == c; }
    auto operator<=>(const Price&) const = default;
};

Price p{499};
bool a = p < 500;    // direct: p.operator<=>(500) < 0
bool b = 500 > p;    // rewritten + reversed: 0 < p.operator<=>(500)
bool c = 500 == p;   // reversed operator==
```

Pre-C++20 this required six member operators plus six free functions per mixed-type pair.

### Pitfalls — especially when mixing defaulted and hand-written operators

- **A user-provided `operator<=>` does NOT give you `operator==`.** Only the *defaulted* form implies a defaulted `==`. If you write `<=>` by hand, also write `==` (or default it), or every `a == b` fails to compile — or worse, finds a stale pre-C++20 `==` with different semantics.

```cpp
struct Id {
    std::string label;  // ignored in ordering
    std::uint64_t key;
    std::strong_ordering operator<=>(const Id& o) const { return key <=> o.key; }
    bool operator==(const Id& o) const { return key == o.key; }  // REQUIRED, easy to forget
};
```

- **Don't implement `==` via `<=>`.** `(a <=> b) == 0` for strings compares character-by-character and cannot short-circuit on length. The standard keeps `==` separate precisely so it can be fast; a defaulted `==` does the right thing.
- **Members without `<=>` poison `auto` deduction.** If a member only has `<` and `==` (legacy type), `auto operator<=>(...) = default;` is *deleted*. Fix: name the category explicitly — `std::strong_ordering operator<=>(const T&) const = default;` — which lets the compiler synthesize three-way comparison from the member's `<` and `==`.
- **`partial_ordering` silently breaks sorting.** `std::sort` with a comparator derived from a `partial_ordering` type is UB when NaN appears (strict weak ordering violated). For float-bearing structs, either exclude the float from comparison, use `std::strong_order(a, b)` (total order over IEEE bits, including NaN), or assert NaN-freedom at the boundary.
- **Rewritten candidates can change legacy code's meaning.** In C++20, `a == b` also considers `b == a` (reversed) and `a != b` is rewritten from `==`. Asymmetric legacy operators that compiled in C++17 can become ambiguous — compilers warn (`-Wambiguous-reversed-operator`). The classic offender:

```cpp
struct Legacy {
    bool operator==(const Legacy& o);  // non-const — fine in C++17
};
// C++20: a == b considers both operator==(a, b) and reversed operator==(b, a);
// the non-const member and the reversed candidate now collide → warning/ambiguity.
```

  Fix the operator (make it `const`, symmetric, ideally a hidden friend) rather than suppressing the warning.
- **Mixed-standard builds:** a library compiled as C++17 declaring only `<`/`==` interoperates fine, but don't expose defaulted `<=>` in headers consumed by C++17 TUs — the declaration is invisible pre-C++20 and overload resolution differs per TU. Keep public headers standard-consistent.

## std::span

A non-owning view over *contiguous* memory: `(pointer, length)`, two words, pass by value. The vocabulary type that replaces `(T*, size_t)` parameter pairs.

The refactor it exists for:

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

- **`operator[]` is unchecked.** Out-of-range indexing is UB, same as raw pointers; `front()`/`back()` on an empty span is UB too. C++26 adds `span::at` — verify against your toolchain; until then, check `size()` yourself (ASan catches the overrun at runtime — see [sanitizers](../../../tooling/diagnostics/references/sanitizers.md)).
- **Spans dangle exactly like `string_view`.** `std::span<int> s = make_vector();` views a dead temporary. Never return a span of a local container; never store a span member beyond the owner's lifetime; `vector` reallocation invalidates spans into it.
- **Constness lives on the element type.** `std::span<const T>` = can't write elements; `const std::span<T>` = can't reseat the span but *can* write elements. Take `span<const T>` for read-only parameters.
- **No `operator==`.** Deliberate — unclear whether identity or element-wise was meant. Use `std::ranges::equal(a, b)`.
- **No construction from `initializer_list`** until C++26 (P2447) — `mean({1.0, 2.0})` fails on a C++20 baseline; pass an array or named container. Verify against your toolchain before relying on the C++26 form.
- **Fixed-extent conversions are explicit** from dynamic extent; a mismatched runtime size makes the conversion UB, not an exception.
- **`span` is one-dimensional.** For matrices/tensors, `std::mdspan` is C++23 — see `cpp23-features.md`. The C++20 workaround is a row accessor: `std::span<T> row(std::span<T> data, size_t i, size_t cols) { return data.subspan(i * cols, cols); }`.

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

Runtime width/precision and chrono types:

```cpp
std::format("{:>{}}", name, column_width);            // width from an argument
std::format("{:*^{}.{}f}", x, width, precision);      // both nested
std::format("{:%Y-%m-%d %H:%M}", std::chrono::system_clock::now());  // chrono specs
```

### Format strings are checked at compile time

An invalid format string or argument mismatch is a **compile error** (P2216, applied retroactively to C++20):

```cpp
std::format("{:d}", "not an int");   // does not compile
```

Consequence: the format string must be a constant expression. For genuinely runtime strings (translations, config):

```cpp
std::string out = std::vformat(translated, std::make_format_args(user, count));
```

`vformat` throws `std::format_error` at runtime on bad specs — fuzz or test translated strings.

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

`std::format_to(std::back_inserter(buf), ...)` appends without intermediate strings; `std::format_to_n` bounds output; `std::formatted_size` pre-computes length.

### Pitfalls

- **Library availability lagged the standard.** libstdc++ shipped `<format>` in GCC 13; libc++ matured across LLVM 14–17; MSVC was first (VS 16.10). On older baselines use `{fmt}` — `std::format` is its standardized subset, so migration is mostly `fmt::` → `std::`. That is the fallback row.
- **Output is unlocalized by default** (a feature — reproducible logs). Locale-aware needs the `L` spec and an explicit locale argument.
- **`std::print`/`println` are C++23**, not 20 — on a pure C++20 baseline it is `std::cout << std::format(...)`. See `cpp23-features.md`.
- **Don't pass user input as the format string** (`vformat(user_supplied, ...)`) — classic injection-adjacent bug class; it throws rather than corrupting memory, but it is still a DoS vector. Format *into* `{}` placeholders. See [secure-coding](../../../_shared/secure-coding/SKILL.md).
- **Pointers only format as `const void*`**; chrono types format richly (`{:%Y-%m-%d}`) — support completeness varies by library version, verify against your toolchain.

## constinit and consteval

Two precision tools that split apart what `constexpr` conflates.

The spectrum:

| Keyword | Guarantees | Use for |
|---|---|---|
| `constexpr` (function) | *Can* run at compile time, may run at runtime | General-purpose |
| `consteval` (function) | *Must* run at compile time (immediate function) | Compile-only work: parsing literals, lookup-table generation, enforcing literal-only APIs |
| `constinit` (variable) | Static/thread-local is **constant-initialized**; stays mutable | Killing static-init-order fiasco and runtime init cost |
| `if consteval` | Branch on compile-vs-runtime context | C++23 — see `cpp23-features.md` |

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

Compile-time table generation — `consteval` guarantees zero runtime cost and no "did it constant-fold?" guessing:

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

- **`constinit` is not `const`.** It constrains *initialization* only. `constinit const` is legal when you want both (but then plain `constexpr` is usually simpler).
- **`constinit` applies only to static and thread-local storage.** On locals it is an error.
- **`consteval` is viral upward in awkward ways:** you cannot take its address, can't call it with runtime arguments, and a `constexpr` function calling a `consteval` one with a non-constant argument is an error. Start with `constexpr`; tighten to `consteval` only when accidental runtime evaluation is a real bug class.
- **Diagnostics for "not a constant expression" point at the call site**, often deep in a template stack. Keep `consteval` functions small and leaf-like.

## Designated Initializers

Name the members you initialize — self-documenting aggregate construction, ideal for config structs.

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

### Pitfalls — C++20 is stricter than C99

| C99 allows | C++20 verdict |
|---|---|
| Out-of-order designators `{.y = 1, .x = 2}` | **Error** — must follow declaration order |
| Nested designators `{.pt.x = 1}` | **Error** — nest braces instead: `{.pt = {.x = 1}}` |
| Array designators `{[2] = 5}` | **Error** — not in C++ |
| Mixing designated and positional `{1, .y = 2}` | **Error** — all or nothing |

- **Aggregates only:** no user-declared constructors, no private members, no virtuals. Adding a constructor later silently breaks every designated-init call site — a reason to keep config structs aggregate forever.
- **Reordering members is now an API break** for callers using designators (order must match declaration). Append, don't reorder.
- **Shared C/C++ headers:** stick to the common subset (in-order, non-nested) so the same initializer compiles as C17/C23 and C++20. C-side differences live in [c23-features.md](../../../c/modern-c/references/c23-features.md).

## std::bit_cast

Reinterpret the bytes of one trivially copyable type as another — the *only* type-pun that is both UB-free and `constexpr`.

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

- **Sizes must match exactly** (`sizeof(To) == sizeof(From)`) and both types trivially copyable — enforced at compile time, so failures are loud. Good.
- **Padding bits in the result are unspecified.** Bit-casting *to* a struct with padding then reading the padding is unspecified; comparing such structs bytewise is a bug.
- **Not everything works in `constexpr`:** pointers, unions (mostly), and types with pointer members can't be bit-cast at compile time.
- **It does not fix endianness or representation portability** — it faithfully reproduces the native bytes. Serialization still needs explicit byte-order handling.
- **GCC 11+/Clang 14+ (libc++)/MSVC 19.27+**; on older toolchains fall back to `memcpy` (runtime paths only) — verify against your toolchain.

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

That default-argument evaluation rule is the entire trick: a defaulted `current()` is evaluated where the caller wrote the call, not where `log` is defined. `current()` is `consteval`, so the capture is free at runtime.

Versus the macro approach it retires:

| | `__FILE__`/`__LINE__` macros | `std::source_location` |
|---|---|---|
| Needs a macro wrapper per function | Yes (`#define LOG(m) log_impl(m, __FILE__, __LINE__)`) | No — plain function parameter |
| Function name | `__func__` only inside the function | `function_name()` captured at call site |
| Works in default arguments | No | Yes (that is the design) |
| Namespacing/scoping | None (macros) | Ordinary C++ |
| Column information | No | `column()` (quality varies — verify against your toolchain) |

### Pitfalls

- **Wrappers eat the location.** If `log_error` calls `log` without forwarding a location parameter, every report points at the wrapper. Thread the `source_location` parameter through every layer explicitly.
- **Variadic forwarding functions can't put it last.** A defaulted parameter cannot follow a parameter pack in the natural way; the working idiom makes the *format-string wrapper* carry the location:

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

- **`function_name()` format is implementation-defined** — full signature on some compilers, bare name on others. Don't parse it; don't assert on it in tests.
- **In default *member* initializers**, `current()` captures the constructor call site — usually what you want, occasionally surprising.
- **Support arrived late on some toolchains** (GCC 11, Clang 15, MSVC 19.29) — keep a macro shim if you must build older; verify against your toolchain.

## Modules

The language feature is real; the ecosystem is the constraint. Syntax first, then the build reality you must plan around.

### Syntax

```cpp
// math.cppm (Clang convention; .ixx for MSVC; GCC accepts .cpp with flags)
module;                 // global module fragment: legacy #includes go here
#include <cassert>

export module math;     // module declaration

import std_compat_shim; // imports visible to this module only

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

Key semantic wins: macros do not leak in or out; declaration order between modules stops mattering; internal symbols are genuinely unreachable; one parse instead of N textual inclusions.

### Build reality (honest assessment, mid-2026)

| Concern | State | Practical guidance |
|---|---|---|
| Compiler maturity | MSVC most complete; Clang 16+ solid for named modules; GCC 14+ workable with rough edges | Verify against your toolchain; pin compiler versions in CI |
| Build system | CMake 3.28+ supports named modules via `FILE_SET CXX_MODULES` — **Ninja 1.11+ or Visual Studio generators only**; Makefile generators do not work | Hard requirement; see [cmake-modern](../../../tooling/build-systems/references/cmake-modern.md) |
| Dependency scanning | Build-time scanning (`clang-scan-deps` etc.) is automatic under CMake but adds a build phase | Expect slower cold configures; incremental builds usually win overall |
| `import std;` | C++23 feature; CMake support has been experimental (opt-in flag) — maturing | Hedge: do not make `import std` a hard requirement yet; verify against your toolchain |
| Header units (`import <vector>;`) | Portability poor across all three compilers and CMake support is limited | Avoid; use the global module fragment for legacy headers |
| Distributing modules in libraries | BMI files are compiler-, version-, and flag-specific — **not** a distribution format; consumers rebuild interfaces from your `.cppm` sources | Ship module interface sources; expect mixed header/module consumers for years |
| Tooling (IDEs, clangd, formatters, coverage) | Catching up; clangd module support improving but uneven | Budget for tooling friction; keep a header-based escape hatch for analysis runs |
| Macros | Cannot be exported from modules | Config macros stay in headers or move to `consteval` functions/constants |

```cmake
# Minimal CMake (3.28+) for a module library
add_library(math)
target_sources(math
    PUBLIC FILE_SET CXX_MODULES FILES math.cppm)
target_compile_features(math PUBLIC cxx_std_20)
```

**Recommendation table:**

| Situation | Verdict |
|---|---|
| Greenfield app, single pinned toolchain, CMake+Ninja | Modules are viable today; start with a few large modules, not one-per-class |
| Library shipped to third parties | Provide headers (or dual-ship); module-only public APIs are still hostile to consumers |
| Existing large codebase | Migrate bottom-up only if build time is a measured pain; the global module fragment makes incremental adoption possible but conversion is real work |
| Needs Make, or compilers older than the table above | Don't. Use precompiled headers for the build-time win |

## Smaller Features Worth Using

| Feature | One-liner | Watch out for |
|---|---|---|
| Ranges | Composable algorithm pipelines | Big topic — see [ranges.md](ranges.md) |
| Coroutines | `co_await`/`co_yield` language support | No usable std library types until `std::generator` (C++23) — see [coroutines](../../cpp-concurrency/references/coroutines.md) |
| `std::jthread` | Joins on destruction + built-in `stop_token` | Always prefer over `std::thread` — see [../../cpp-concurrency/SKILL.md](../../cpp-concurrency/SKILL.md) |
| `starts_with`/`ends_with` | On `string`/`string_view` | `contains` is C++23 |
| `std::erase`/`erase_if(container, pred)` | Finally kills the erase-remove idiom | Free functions, not members |
| `map.contains(key)` | Replaces `find() != end()` | Heterogeneous overload needs transparent comparator |
| `std::midpoint`/`std::lerp` | Overflow-safe midpoint, correct lerp | `midpoint` of pointers requires same array |
| `using enum` | `using enum Color;` unqualifies enumerators in a scope | Scope pollution; keep it function-local |
| `[[likely]]`/`[[unlikely]]` | Branch hints on statements | Measure first; misuse pessimizes — see [profiling-tools](../../../tooling/diagnostics/references/profiling-tools.md) |
| `[[no_unique_address]]` | Empty members take zero space | MSVC needs `[[msvc::no_unique_address]]` — verify against your toolchain |
| `char8_t` | Distinct type for UTF-8 | **Breaking**: `u8""` literals no longer convert to `const char*`; affects C++17 code moving to 20 |
| Abbreviated templates | `void f(auto x)` = template | Each `auto` is an independent parameter |
| `constexpr` everything | `vector`, `string`, algorithms usable in constant evaluation | Compile-time allocations cannot leak to runtime |
| `std::numbers` | `std::numbers::pi`, `e`, `sqrt2` as variable templates | Replaces `M_PI` (which is POSIX, not standard C++) |

## Migration Notes: C++17 to C++20 Breakage

Flipping `-std=c++20` on a C++17 codebase is mostly safe, but these changes bite real code. Audit for each before the switch (`/system-developer:fix-modernize --target cpp20` builds the ledger):

| Change | Symptom | Fix |
|---|---|---|
| `u8""` literals became `const char8_t*` | `const char* s = u8"...";` stops compiling | Drop the `u8` prefix where you meant bytes, or adopt `char8_t` end-to-end; `-fno-char8_t`/`/Zc:char8_t-` only as a bridge |
| Aggregates with user-declared constructors (even `= default`) are no longer aggregates (P1008) | `T{1, 2}` brace-init stops compiling for `struct T { T() = default; int a, b; };` | Remove the defaulted declaration or add a real constructor |
| Reversed/rewritten comparison candidates | `-Wambiguous-reversed-operator` warnings, rare behavior changes | Make `operator==` const and symmetric (see `<=>` section) |
| Implicit `this` capture in `[=]` deprecated | Deprecation warnings in lambda-heavy code | Capture `this` (or `*this`) explicitly |
| Many `volatile` uses deprecated (compound assignment, etc.) | `-Wdeprecated-volatile` noise, especially near device registers | Split read-modify-write into explicit loads/stores (better for embedded correctness anyway) |
| `std::allocator<void>`, `raw_storage_iterator`, others removed | Old allocator-aware code breaks | Modern allocator traits; usually dead code |
| Two-phase template lookup tightened, ADL refinements | Previously-accepted ill-formed templates now diagnosed | Fix the template; the old code was wrong |
| `std::variant` converting constructor narrowed (P0608) | Different alternative selected vs C++17 | Audit `variant` implicit constructions (see [cpp17-features.md](cpp17-features.md) variant pitfalls) |

Strategy: enable C++20 with warnings-as-errors in a branch, fix the finite breakage list above, run the full test suite plus ASan/UBSan ([sanitizers](../../../tooling/diagnostics/references/sanitizers.md)), and only then start *using* C++20 features. One standard jump at a time.

## Related References

- [cpp17-features.md](cpp17-features.md) — the baseline this file builds on.
- [cpp23-features.md](cpp23-features.md) — `expected`, `print`, deducing this, `if consteval`, `import std`.
- [ranges.md](ranges.md) — C++20 ranges and views in depth.
- [error-handling.md](error-handling.md) — exceptions vs `std::expected` decision guide.
- [coroutines.md](../../cpp-concurrency/references/coroutines.md) — C++20 coroutine machinery and C++23 `std::generator`.
- [cmake-modern.md](../../../tooling/build-systems/references/cmake-modern.md) — module builds, presets, toolchain pinning.
- [../SKILL.md](../SKILL.md) — standard-selection table and modern-C++ core rules.
- [version-feature-matrix.md](../../../_shared/version-feature-matrix.md) — canonical toolchain minimums.
