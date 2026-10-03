# Freestanding C++ Standard-Library Subset

Which C++ language and library features are affordable under `-fno-exceptions -fno-rtti -ffreestanding`, and the embedded replacement for each that isn't. The flag set, RAII, placement new, and ROM-able data are in [../SKILL.md](../SKILL.md).

## What "Freestanding" Guarantees in C++

The standard requires only a small header set from a freestanding implementation, centred on language support and compile-time utilities:

- **C++20:** `<cstddef>`, `<cstdint>`, `<cstdlib>` (subset), `<limits>`, `<climits>`, `<cfloat>`, `<version>`, `<new>`, `<typeinfo>`, `<exception>`, `<source_location>`, `<initializer_list>`, `<compare>`, `<coroutine>`, `<cstdarg>`, `<concepts>`, `<type_traits>`, `<bit>`, `<atomic>`.
- **C++23** adds `<utility>`, `<tuple>`, `<ratio>`, `<iterator>`, `<ranges>`, and parts of `<memory>` and `<functional>`.
- **C++26** adds, mostly in part, `<array>`, `<optional>`, `<variant>`, `<expected>`, `<string_view>`, `<span>`, `<mdspan>`, `<inplace_vector>`, `<algorithm>`, `<numeric>`, `<charconv>` (integer), `<string>` (`char_traits`), `<cstring>`, `<cwchar>`, `<cmath>`, `<random>`, `<cerrno>`, `<system_error>`, `<execution>`, `<debugging>`, `<contracts>`, and `<stdbit.h>`.

Freestanding conformance varies more than hosted, so check your library version.

### Hosted-only

Anything touching the heap, the OS, locales, or I/O (`<iostream>`, `<string>`, `<vector>`, `<map>`, `<thread>`, `<filesystem>`, `<regex>`, `<chrono>` clocks) is hosted-only. libstdc++/libc++ often let you include them on bare metal, but using them links `malloc`, exception machinery, and static init.

## Language Features Under the Subset

| Feature | Status | Notes / replacement |
|---------|--------|--------------------|
| Classes, RAII, destructors | Available | Destructors run on normal scope exit |
| Templates, `constexpr`, `consteval`, `constinit` | Encouraged | Compile-time work lands in FLASH |
| Lambdas, `auto`, structured bindings | Available | Only lambdas stored in `std::function` cost |
| `throw` / `try` / `catch` | Disabled (`-fno-exceptions`) | `throw` → `std::terminate`; use error-return types |
| `dynamic_cast`, `typeid` | Disabled (`-fno-rtti`) | See Polymorphism Without RTTI |
| Virtual functions | Available | vtable in FLASH |
| Function-local `static`, non-trivial init | Adds a guard | `-fno-threadsafe-statics`, or a `constinit` global |
| Global with non-trivial constructor | Costs startup + RAM | `constexpr`/`constinit`; mind init order |

## Library: Available

Allocation-free; use freely:

- `std::array<T, N>` — the default container.
- `std::span<T>` (C++20) — the parameter type for "a buffer and its length."
- `std::string_view` — replaces `const std::string&` parameters (dangling rules as hosted).
- `std::optional<T>`, `std::variant<...>`, `std::expected<T, E>` (C++23) — in-object storage; `expected` is the embedded error type.
- `<type_traits>`, `<concepts>`, `<bit>`, `<utility>`, `<limits>` — compile-time only.
- `std::atomic<T>` — for ISR/`main` sharing (see embedded-systems).
- Algorithms (`std::sort`, `std::find`, ...) over `array`/`span` — only containers allocate.

## Library: Unavailable or Costly

### Allocates or throws

| Feature | Cost | Replacement |
|---------|------|-------------|
| `std::string` | Heap beyond SSO; throws | `std::array<char, N>` + `std::string_view` |
| `std::vector`, `deque`, `list` | Heap, non-deterministic timing | `std::array`, ring buffer, fixed-capacity vector |
| `std::map`, `unordered_map` | Node allocation per element | Sorted `std::array` + binary search; flat fixed map |
| `std::function` | Heap for large callables; throws | See The std::function Problem |
| `std::shared_ptr` | Refcount + heap control block | `std::unique_ptr` with non-heap deleter |
| `<iostream>`, `stringstream` | Static init, locale, heap, exceptions | `printf`-over-UART; `std::to_chars`/`from_chars` + fixed buffer |
| `<regex>` | Large code, heap | Table-driven matcher |
| Throwing `new`, `vector::at` | `std::terminate` under `-fno-exceptions` | `new (std::nothrow)` + null check; bounds-check before `[]` |

### Needs an OS

| Feature | Cost | Replacement |
|---------|------|-------------|
| `<thread>`, `<mutex>`, `<future>` | Needs OS threads | RTOS primitives, or ISR + atomics |
| `<chrono>` clocks | Needs an OS clock | Hardware-timer tick counter |

## The std::function Problem

`std::function` is the most common accidental allocation. A callable larger than its small-object buffer (a capturing lambda, a bound member) is heap-allocated, and construction can throw. Escapes, by preference:

```cpp
// 1. Template the callable: no type erasure, fully inlined
template <class Fn>
void for_each_sample(Fn&& fn) { for (auto s : samples) fn(s); }

// 2. Function pointer + context, when a uniform signature is needed
using Callback = void (*)(void* ctx, int event);

// 3. Fixed-capacity inline delegate: static_asserts if the callable won't fit,
//    never allocates (SG14 inplace_function shown; ETL and others have equivalents)
stdext::inplace_function<void(int), 16> cb = [](int x) { handle(x); };
```

Use type erasure only for a heterogeneous, runtime-decided callback list, and then a bounded inline delegate.

## Containers Without the Heap

Containers own inline storage sized at compile time and fail (or static-assert) at capacity instead of allocating:

- `std::array<T, N>` for fixed N.
- A ring buffer (`std::array` + head/tail) for queues, including ISR/`main` hand-off.
- A fixed-capacity vector: up to N elements, runtime size, push fails when full. `std::inplace_vector` (C++26) standardizes it; before that, ETL (`etl::vector`) or a small hand-rolled type.

For variable-lifetime objects over static storage, back these with [allocators-and-arenas](../../../c/c-memory-ownership/references/allocators-and-arenas.md).

## Polymorphism Without RTTI

- `std::variant` + `std::visit` — closed, compile-time-known set of types.
- Tagged union or `enum kind` + virtual `kind()` — a cheap discriminator when you own the hierarchy.
- CRTP / templates — concrete type known at the call site; no vtable, inlinable.
- Plain virtual functions — still available for open runtime polymorphism; only `dynamic_cast`/`typeid` are gone.

## Pitfalls

| Pitfall | Consequence | Fix |
|---------|-------------|-----|
| Including `<vector>`/`<string>` "just for one" | Links heap + exception machinery | Fixed-capacity container; `string_view` |
| `std::function` member for a callback | Hidden heap allocation, can throw | Function pointer / template / inline delegate |
| Assuming a C++23/26 freestanding header exists | Build break on an older stdlib | Check your library version's freestanding subset |
| `std::cout` for debug output | iostream weight | `printf`-over-UART or fixed-buffer formatter |
