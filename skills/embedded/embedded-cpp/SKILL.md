---
name: embedded-cpp
description: >-
  The embedded C++ subset for bare-metal and microcontroller targets: RAII
  without exceptions or RTTI (-fno-exceptions -fno-rtti -ffreestanding), the
  freestanding standard-library subset, static and placement-new construction,
  constexpr/constinit ROM-able data, and avoiding hidden allocations. Use when
  running C++ on a flash- and RAM-limited device or deciding which C++
  features it can afford.
---

# Embedded C++

The C++ layer over [embedded-systems](../embedded-systems/SKILL.md), whose language-agnostic core (MMIO, `volatile`, ISRs, startup, linker scripts, fixed-point) applies unchanged.

## The Embedded C++ Flag Set

```sh
-ffreestanding          # no hosted-environment / full-libc assumptions
-fno-exceptions         # no exception support: throw -> std::terminate
-fno-rtti               # no typeid / dynamic_cast; drops type-info tables
-fno-threadsafe-statics # no guard locks around function-local statics
-fno-use-cxa-atexit     # register static dtors with atexit, not __cxa_atexit
-fno-unwind-tables -fno-asynchronous-unwind-tables  # drop unwind metadata
```

The first three are the defining choices; the rest trim runtime support a target that never exits and has no threads doesn't need.

## Why Exceptions and RTTI Cost Flash and RAM

- **Exceptions** pull in unwind tables (`.eh_frame`/`.ARM.extab`), the personality routine, and `__cxa_throw`/`__cxa_allocate_exception`. That is kilobytes of flash even on paths that never throw; throwing needs the heap, and unwinding time is non-deterministic, which hard real-time can't accept.
- **RTTI** emits `type_info` for every polymorphic class, used only by `dynamic_cast`/`typeid`.

Under `-fno-exceptions`, any `throw`, including library ones (`vector::at` out of range, a failed throwing `new`), calls `std::terminate`. Use error-return types instead. Under `-fno-rtti`, `dynamic_cast` and `typeid` don't compile.

## RAII Without Exceptions

Destructors still run on every normal scope exit; `-fno-exceptions` removes only throwing and unwinding, so RAII stays the core idiom:

```cpp
class ScopedLock {
    Mutex& m_;
public:
    explicit ScopedLock(Mutex& m) : m_(m) { m_.lock(); }
    ~ScopedLock() { m_.unlock(); }
    ScopedLock(const ScopedLock&) = delete;
};
```

What changes versus hosted C++:

- Constructors can't report failure by throwing. Make construction infallible, or keep the constructor private behind a factory that returns an error type.
- Recoverable errors use `std::expected<T, Err>` (C++23) or, on older standards, a small result type or out-param plus status. See [error-handling](../../cpp/modern-cpp/references/error-handling.md); on embedded the answer is always `expected` or codes.

## No Heap: Static and Placement-New Construction

Dynamic allocation is usually banned (see [embedded-systems](../embedded-systems/SKILL.md) > No-Heap Allocation). Construct objects without `new`:

```cpp
#include <new>          // placement new (freestanding)

static Driver g_driver{config};    // constructed at startup via .init_array

// Deferred construction into static storage you control:
alignas(Driver) static unsigned char storage[sizeof(Driver)];
Driver* make_driver(const Config& c) { return ::new (storage) Driver{c}; }
void destroy_driver(Driver* d) { d->~Driver(); }   // not `delete d`
```

### Placement-new lifetime rules

- Storage must be aligned (`alignas(T)`) and large enough (`sizeof(T)`); misalignment is UB and faults on strict-alignment cores.
- Lifetime ends at the explicit destructor call. `delete` would call `operator delete` on memory that was never allocated.
- Destroy the old object before reusing the storage.
- Prefer `std::optional<T>` or a fixed-capacity `inplace_vector` (C++26; hand-rolled before) to raw placement new where available.

For pools and arenas over static storage, use [allocators-and-arenas](../../c/c-memory-ownership/references/allocators-and-arenas.md); the C++ layer is placement new into the pool's blocks.

## constexpr / constinit for ROM-able Data

Constant tables belong in FLASH (`.rodata`), built at compile time with no runtime constructor and no RAM copy:

```cpp
// Constant initializer -> .rodata (FLASH), not .data (RAM)
constexpr std::array<uint16_t, 256> kSineTable = make_sine_table();

// Compile-time init of a mutable global: no startup ctor, no init-order fiasco
constinit Logger g_log{Level::Warn};
```

- Mark constant tables `constexpr` (or at least `const`) so they stay in FLASH.
- `constinit` guarantees static initialization for a possibly-mutable global; without it, a non-`constexpr` global runs a constructor from `.init_array` at startup.
- A non-`const`, non-`constinit` global with a non-trivial constructor costs a startup constructor and RAM; avoid it for large tables.

The full `constexpr`/`consteval`/`constinit` distinction is in [modern-cpp](../../cpp/modern-cpp/SKILL.md).

## Avoiding Hidden Allocations and Dynamic Dispatch

Per-feature detail: [references/freestanding-stdlib-subset.md](references/freestanding-stdlib-subset.md).

| Avoid | Why | Use instead |
|-------|-----|-------------|
| `std::string`, `std::vector`, `std::map` | Heap | `std::array`, ring buffer, fixed-capacity vector |
| `std::function` | Heap for large callables | Function pointer, template, inline delegate |
| `std::shared_ptr` | Atomic refcount + heap control block | `std::unique_ptr` with a non-heap deleter |
| `dynamic_cast` / `typeid` | Needs RTTI | Tagged union, `std::variant`, virtual `kind()` |
| `<iostream>` | Static init, locale, heap | `printf`-over-UART ([float-free printf](../embedded-systems/references/fixed-point-and-no-float.md)) |
| Virtual calls in hot paths with a known type | Indirection, blocks inlining | CRTP or templates |

Virtual functions are fine for genuine runtime polymorphism; the vtable lives in FLASH.

## MISRA-Adjacent Discipline

Embedded C++ codebases often follow MISRA C++ / AUTOSAR / High-Integrity C++. The rules that overlap this skill:

- No dynamic allocation after initialization (or none at all).
- No exceptions, no RTTI.
- No recursion where stack depth must be bounded.
- Fixed-width types (`uint32_t`, not `int`) at hardware boundaries.
- Initialize every object; no implicit narrowing.
- Standard library limited to the freestanding, non-allocating subset.

## Diagnostics

### Build and link

| Symptom | Cause | Fix |
|---------|-------|-----|
| `dynamic_cast`/`typeid` does not compile | Built with `-fno-rtti` | Tagged union / `std::variant` / virtual `kind()` |
| Image bloated by kilobytes of unwind tables | Exceptions enabled | `-fno-exceptions -fno-unwind-tables` |
| `malloc`/`_sbrk` reference links in | A container or `std::function` allocates | Fixed-capacity container; non-allocating delegate |
| `static` local has a guard variable / lock | Thread-safe statics enabled | `-fno-threadsafe-statics` (single-threaded), or a `constinit` global |

### Runtime

| Symptom | Cause | Fix |
|---------|-------|-----|
| `std::terminate` on an error | Code or a library throws under `-fno-exceptions` | `std::expected`/error codes; avoid throwing APIs (`vector::at`, throwing `new`) |
| Slow startup / RAM spent on a const table | Table is non-`constexpr`, constructed into RAM | `constexpr`/`const` so it stays in FLASH |
| Placement-new object corrupts / faults | Storage misaligned, too small, or `delete`d | `alignas(T)`/`sizeof(T)`; destroy with `p->~T()` |
| Global ctor order bug across TUs | Static initialization order fiasco | `constinit`, or function-local-static init |

## Related Skills

- [references/freestanding-stdlib-subset.md](references/freestanding-stdlib-subset.md) — what is available, unavailable, or costly under the flag set, with replacements
- [embedded-systems](../embedded-systems/SKILL.md) — the language-agnostic core C++ runs on
- [modern-cpp](../../cpp/modern-cpp/SKILL.md) — full RAII, smart-pointer, and `constexpr`/`constinit` rules this subset constrains
- [c-memory-ownership](../../c/c-memory-ownership/SKILL.md) — arena/pool allocators placement new builds into
- [cpp-skills](../../cpp/SKILL.md) — standard-selection table for the features named above
