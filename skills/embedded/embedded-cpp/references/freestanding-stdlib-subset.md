# Freestanding C++ Standard-Library Subset

Use this when:

- You are deciding whether a C++ language or library feature is affordable under
  `-fno-exceptions -fno-rtti -ffreestanding`.
- A symbol you expected (`std::vector`, `std::function`, `dynamic_cast`) is
  unavailable, costly, or pulls in the heap.
- You need the idiomatic embedded replacement for a hosted-C++ feature.

Skip this file if:

- You need the flag set, RAII, placement-new, or ROM-able-data rules. Use
  [../SKILL.md](../SKILL.md).
- Your question is the language-agnostic core (MMIO, ISRs, startup). Use
  [../../embedded-systems/SKILL.md](../../embedded-systems/SKILL.md).

Jump to:

- What "Freestanding" Guarantees in C++
- Language Features Under the Subset
- Library: Available
- Library: Unavailable or Costly
- The std::function Problem
- Containers Without the Heap
- Polymorphism Without RTTI
- Replacement Quick Table
- Pitfalls

## What "Freestanding" Guarantees in C++

The C++ standard defines a small set of headers a **freestanding implementation**
must provide; everything else is a hosted-only quality-of-implementation matter.
The guaranteed-useful freestanding headers cluster around language support and
compile-time utilities, not runtime services:

`<cstddef>`, `<cstdint>`, `<cstdlib>` (subset), `<limits>`, `<climits>`,
`<cfloat>`, `<version>`, `<type_traits>`, `<concepts>` (C++20), `<bit>` (C++20),
`<utility>` (subset), `<initializer_list>`, `<new>` (placement new),
`<atomic>`, `<array>` (in practice, header-only and allocation-free),
`<ratio>`, `<compare>` (C++20). C++23 widened the freestanding subset
substantially (much of `<expected>`, `<optional>`, `<span>`, `<string_view>`,
`<charconv>` is freestanding-friendly) — **verify against your specific
standard-library implementation and version**; freestanding conformance varies
more than hosted.

Anything touching the heap, the OS, locales, or I/O (`<iostream>`, `<string>`,
`<vector>`, `<map>`, `<thread>`, `<filesystem>`, `<regex>`, `<chrono>` clocks)
is hosted-only in principle. libstdc++/libc++ often *let* you include them on a
bare-metal target, but using them links `malloc`, exception machinery, and
static init you are trying to avoid.

## Language Features Under the Subset

| Feature | Status | Notes / replacement |
|---------|--------|--------------------|
| Classes, RAII, destructors | Available | Destructors run on normal scope exit; core idiom |
| Templates, `constexpr`, `consteval`, `constinit` | Available, encouraged | Compile-time work → FLASH, no runtime cost |
| References, `auto`, structured bindings, lambdas | Available | Lambdas are fine; their *captures into `std::function`* are the cost |
| `std::array`, `std::span`, `std::string_view`, `std::optional` | Available (allocation-free) | The vocabulary types you keep |
| `throw` / `try` / `catch` | **Disabled** by `-fno-exceptions` | `throw` → `std::terminate`; use error-return types |
| `dynamic_cast`, `typeid` | **Disabled** by `-fno-rtti` | Tagged union, `std::variant`, virtual `kind()` |
| Virtual functions | Available | vtable in FLASH; avoid only in hot/size-critical known-type paths |
| Function-local `static` with non-trivial init | Available but adds a guard | `-fno-threadsafe-statics` drops the lock (single-threaded); or `constinit` global |
| Global with non-trivial constructor | Available, costs startup + RAM | Prefer `constexpr`/`constinit`; mind init-order fiasco |

## Library: Available

These are allocation-free and freestanding-friendly — use them freely:

- `std::array<T, N>` — fixed-size, no heap, the default container.
- `std::span<T>` (C++20) — non-owning view over contiguous storage; the right
  parameter type for "a buffer and its length."
- `std::string_view` — non-owning view over characters; replaces `const
  std::string&` parameters (mind dangling, same as hosted).
- `std::optional<T>` — in-object presence, no heap.
- `std::expected<T, E>` (C++23) — the embedded error-handling type, no heap.
- `std::variant<...>` — closed set of types, no heap; the RTTI-free way to be
  polymorphic over a known set.
- `<type_traits>`, `<concepts>`, `<bit>`, `<utility>`, `<limits>` — pure
  compile-time / header-only.
- `std::atomic<T>` — for the ISR/`main` sharing problem (see embedded-systems).
- Algorithms over fixed ranges (`std::sort`, `std::find`, ... on `array`/`span`)
  — they do not allocate; only the *containers* do.

## Library: Unavailable or Costly

| Feature | Cost on a constrained target | Replacement |
|---------|------------------------------|-------------|
| `std::string` | Heap allocation, SSO still grows; throws | Fixed-capacity char buffer + `std::string_view`; `std::array<char, N>` |
| `std::vector`, `std::deque`, `std::list` | Heap allocation, reallocation, non-deterministic timing | `std::array`, ring buffer, fixed-capacity static-storage vector |
| `std::map`, `std::unordered_map` | Node allocation per element | Sorted `std::array` + binary search; flat fixed-capacity map; perfect-hash table |
| `std::function` | Heap for large callables; indirect call; throws | Function pointer; template callable; `inplace_function`/non-allocating delegate |
| `std::shared_ptr` | Atomic refcount + control-block heap allocation | `std::unique_ptr` with non-heap deleter; plain single ownership |
| `<iostream>` (`std::cout`) | Massive static init, locale, heap, exceptions | `printf`-over-UART; fixed-buffer formatter |
| `std::stringstream` | Heap + iostream weight | `std::to_chars`/`std::from_chars` (`<charconv>`, allocation-free) |
| `<regex>` | Very large code, heap | Hand-written parser / table-driven matcher |
| `<thread>`, `<mutex>`, `<future>` | OS threading the target lacks | RTOS primitives, or ISR + atomics |
| `<chrono>` clocks | Needs an OS clock source | A hardware-timer tick counter you maintain |
| Throwing `new` / `vector::at` | Throws → `std::terminate` under `-fno-exceptions` | `new (std::nothrow)` and check; bounds-check before `operator[]` |

## The std::function Problem

`std::function` is the most common accidental allocation in embedded C++. It
type-erases any callable; if the callable (a lambda with captures, a bound
member) exceeds the small-object buffer, it **heap-allocates**, and its
construction can throw. Three escapes, by preference:

```cpp
// 1. Template the callable — zero overhead, fully inlined, no type erasure:
template <class Fn>
void for_each_sample(Fn&& fn) { for (auto s : samples) fn(s); }

// 2. Plain function pointer + context, when a uniform signature is needed:
using Callback = void (*)(void* ctx, int event);

// 3. A fixed-size, non-allocating delegate (inplace_function-style): stores the
//    callable inline up to a capacity, static_asserts if it would not fit —
//    never allocates, never throws.
etl::delegate<void(int)> cb = [](int x) { handle(x); };
```

Use type erasure only when you genuinely need a heterogeneous, runtime-decided
callback list, and then a bounded inline delegate, not `std::function`.

## Containers Without the Heap

The pattern: a container that owns **inline storage** sized at compile time and
refuses (or static-asserts) rather than allocating.

- `std::array<T, N>` for fixed N.
- A ring buffer (`std::array` + head/tail indices) for queues — also the
  ISR/`main` hand-off structure.
- A fixed-capacity vector: contiguous storage for up to N, a runtime size,
  push/pop that fail at capacity. `std::inplace_vector` (C++26) standardizes
  this; before it, libraries like ETL (`etl::vector`) or a small hand-rolled
  type fill the gap.
- `std::to_chars`/`std::from_chars` (`<charconv>`) for number↔text without
  `stringstream` or locale, and without allocation.

Back these with the arena/pool allocators from
[allocators-and-arenas](${CLAUDE_SKILL_DIR}/c/c-memory-ownership/references/allocators-and-arenas.md)
when you need variable-lifetime objects over static storage.

## Polymorphism Without RTTI

With `-fno-rtti`, `dynamic_cast` and `typeid` are gone. Options:

- **`std::variant` + `std::visit`** — a closed, compile-time-known set of types;
  the standard, allocation-free, RTTI-free sum type.
- **A tagged union / `enum kind` + virtual `kind()`** — when you control the
  hierarchy and want a cheap discriminator.
- **Static polymorphism (CRTP / templates)** — when the concrete type is known
  at the call site; no vtable, fully inlinable.
- **Plain virtual functions** remain available for open runtime polymorphism —
  only `dynamic_cast`/`typeid` are removed, not `virtual`. The vtable lives in
  FLASH.

## Replacement Quick Table

| Hosted C++ | Embedded replacement |
|------------|----------------------|
| `throw` / exceptions | `std::expected` / error codes |
| `dynamic_cast` / `typeid` | `std::variant` / tagged union / virtual `kind()` |
| `std::string` | `std::string_view` + fixed char buffer |
| `std::vector` | `std::array` / ring buffer / fixed-capacity vector |
| `std::map` | sorted `std::array` + binary search / flat map |
| `std::function` | function pointer / template / inline delegate |
| `std::shared_ptr` | `std::unique_ptr` (non-heap deleter) / single ownership |
| `std::cout` / iostream | `printf`-over-UART / `to_chars` + fixed buffer |
| `stringstream` | `std::to_chars` / `std::from_chars` |
| `new T` (throwing) | `new (std::nothrow) T` + null check, or placement new |
| `std::thread` / `std::mutex` | RTOS primitives / ISR + atomics |

## Pitfalls

| Pitfall | Consequence | Fix |
|---------|-------------|-----|
| Including `<vector>`/`<string>` "just for one" | Links heap + exception machinery | Fixed-capacity container; `string_view` |
| `std::function` member for a callback | Hidden heap allocation, can throw | Function pointer / template / inline delegate |
| Calling `vector::at` or throwing `new` | `std::terminate` under `-fno-exceptions` | Bounds-check; `new (std::nothrow)` + check |
| `dynamic_cast` in a `-fno-rtti` build | Does not compile | `variant` / tagged union / virtual `kind()` |
| Large `const` table not `constexpr`/`const` | Runs a ctor into RAM at startup | `constexpr`/`const` → stays in FLASH |
| Assuming a C++23 freestanding header is present | Build break on an older stdlib | Verify the freestanding subset of *your* library version |
| `std::cout` for debug output | Pulls in iostream weight | `printf`-over-UART or fixed-buffer formatter |

Cross-references: the flag set, RAII-without-exceptions, placement new, and
ROM-able-data rules in [../SKILL.md](../SKILL.md); the no-heap allocation
strategies and their static-storage backing in
[../../embedded-systems/SKILL.md](../../embedded-systems/SKILL.md); the
exceptions-vs-`expected` decision in
[error-handling](${CLAUDE_SKILL_DIR}/cpp/modern-cpp/references/error-handling.md);
standard minimums in
[version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md).
