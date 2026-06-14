---
name: embedded-cpp
description: >-
  The embedded C++ subset for bare-metal and microcontroller targets: RAII
  without exceptions or RTTI (-fno-exceptions -fno-rtti -ffreestanding), the
  freestanding standard-library subset, static and placement-new object
  construction without the heap, constexpr/constinit for ROM-able data, and
  avoiding hidden allocations, std::function, and dynamic-dispatch costs. Use
  when running C++ on a constrained device, removing exceptions/RTTI, or
  deciding which C++ features are affordable on flash- and RAM-limited parts.
---

# Embedded C++

**C++ on microcontrollers: RAII without exceptions, no heap, ROM-able data**

## When to Use

- Writing or reviewing C++ for a microcontroller or bare-metal target
- Building with `-fno-exceptions -fno-rtti -ffreestanding` and needing the rules
- Replacing heap, exceptions, RTTI, and `std::function` with affordable patterns
- Deciding whether a C++ standard-library feature fits the flash/RAM budget
- Constructing objects without `new`, or putting constant data in FLASH

This skill is the C++-specific layer. The language-agnostic core — MMIO,
`volatile`, ISRs, startup, linker scripts, fixed-point — is in
[embedded-systems](../embedded-systems/SKILL.md) and applies unchanged to C++.

## The Embedded C++ Flag Set

```sh
-ffreestanding          # no hosted-environment / full-libc assumptions
-fno-exceptions         # no exception support: throw -> std::terminate
-fno-rtti               # no typeid / dynamic_cast; drops type-info tables
-fno-threadsafe-statics # no guard variables/locks around function-local statics
-fno-use-cxa-atexit     # static dtors not registered for an exit that never comes
-fno-unwind-tables -fno-asynchronous-unwind-tables  # drop unwind metadata
```

The first three are the defining choices. The rest shave the runtime support
C++ would otherwise pull in on a target that never exits and has no threads.

## Why Exceptions and RTTI Cost Flash and RAM

| Feature | What it pulls in | Embedded impact |
|---------|------------------|-----------------|
| **Exceptions** | Unwind tables (`.eh_frame`/`.ARM.extab`), the personality routine, `__cxa_throw`/`__cxa_allocate_exception`, and a runtime that *allocates* the exception object | Kilobytes of flash even on paths that never throw; throwing needs the heap; unwinding is non-deterministic — unacceptable for hard real-time |
| **RTTI** | `type_info` objects for every polymorphic class, vtable RTTI pointers | Flash for type-info that bare-metal code almost never uses (`dynamic_cast`, `typeid`) |

Built with `-fno-exceptions`, any `throw` (or a library call that throws, like
`vector::at` out of range or a failed `new`) calls `std::terminate` instead of
unwinding. So the discipline is: **do not rely on exceptions for control flow**,
and use error-return types instead (below). With `-fno-rtti`, `dynamic_cast`
and `typeid` do not compile — design without them.

## RAII Without Exceptions

RAII still works and is still the core idiom — destructors run on scope exit
exactly as always; `-fno-exceptions` only removes *throwing* and stack
*unwinding*, not destructors on normal paths. Keep deterministic cleanup:

```cpp
class ScopedLock {
    Mutex& m_;
public:
    explicit ScopedLock(Mutex& m) : m_(m) { m_.lock(); }
    ~ScopedLock() { m_.unlock(); }          // runs on every normal scope exit
    ScopedLock(const ScopedLock&) = delete;
};

class GpioPin {                              // owns a hardware resource via RAII
    uint32_t pin_;
public:
    explicit GpioPin(uint32_t p) : pin_(p) { gpio_enable(pin_); }
    ~GpioPin() { gpio_disable(pin_); }
};
```

What changes versus hosted C++:

- **Constructors cannot signal failure by throwing.** Either make construction
  infallible (the only failure modes are programmer errors caught in debug), or
  use a factory returning an error type (below) and keep the constructor private.
- **`std::expected`/error codes replace exceptions** for recoverable errors. On
  C++23 use `std::expected<T, Err>`; on older standards use a small result type
  or out-param + status. See
  [error-handling](${CLAUDE_SKILL_DIR}/cpp/modern-cpp/references/error-handling.md)
  for the exceptions-vs-`expected` decision (the embedded answer is always
  `expected`/codes).

## No Heap: Static and Placement-New Construction

Dynamic allocation is usually banned (no `malloc`, fragmentation, non-determinism
— see [embedded-systems](../embedded-systems/SKILL.md) > No-Heap Allocation).
Construct objects without `new`:

```cpp
#include <new>          // placement new (freestanding-available)
#include <cstdint>

// 1. Plain static/global object: constructed at startup via .init_array.
static Driver g_driver{config};

// 2. Placement new into static storage you control (deferred construction):
alignas(Driver) static unsigned char storage[sizeof(Driver)];
Driver* make_driver(const Config& c) {
    return ::new (storage) Driver{c};       // no allocation; constructs in place
}
// You must call the destructor explicitly; placement new does NOT pair with delete:
void destroy_driver(Driver* d) { d->~Driver(); }   // never `delete d;`
```

Placement-new lifetime rules to respect:

- The storage must be **correctly aligned** (`alignas(T)`) and **large enough**
  (`sizeof(T)`); misalignment is UB and faults on strict-alignment cores.
- The object's lifetime begins at the placement-new and ends at the **explicit
  destructor call** — `delete` is wrong (it would call `operator delete`, i.e.
  free memory you never allocated).
- Reusing the storage for a new object requires destroying the old one first.
- `std::optional<T>` and a fixed-capacity `inplace_vector` (C++26;
  hand-rolled before) wrap this pattern safely — prefer them to raw placement
  new where available.

For pools and arenas over static storage, reuse
[allocators-and-arenas](${CLAUDE_SKILL_DIR}/c/c-memory-ownership/references/allocators-and-arenas.md);
the C++ layer is just placement new into the pool's blocks.

## constexpr / constinit for ROM-able Data

Constant tables should live in FLASH (`.rodata`), constructed at compile time,
with **no runtime constructor and no RAM copy**:

```cpp
#include <array>

// constexpr: value computed at compile time; a constexpr global with a
// constant initializer lands in .rodata (FLASH), not .data (RAM).
constexpr std::array<uint16_t, 256> kSineTable = make_sine_table();  // computed by the compiler

// constinit: forces constant (compile-time) initialization, guaranteeing no
// runtime init and dodging the static-init-order fiasco. Object may be mutable.
constinit Logger g_log{Level::Warn};       // initialized before any dynamic init runs
```

- **`constexpr` global with a constant initializer** → ROM-able: no startup
  constructor, no RAM unless you take a mutable copy. Mark constant tables
  `constexpr` (or at least `const`) so they stay in FLASH.
- **`constinit`** guarantees *static* initialization (compile-time) for a
  possibly-mutable global, eliminating the runtime constructor and the static
  initialization order fiasco — without it, a non-`constexpr` global runs a
  constructor from `.init_array` at startup.
- A non-`const`, non-`constinit` global with a non-trivial constructor costs a
  startup constructor *and* RAM — avoid for large tables.

The full `constexpr`/`consteval`/`constinit` distinction is in
[modern-cpp](${CLAUDE_SKILL_DIR}/cpp/modern-cpp/SKILL.md); the embedded emphasis
is "compile-time init → FLASH, no startup cost."

## Avoiding Hidden Allocations and Dynamic Dispatch

The freestanding stdlib subset and the cost of each banned feature are detailed
in
[references/freestanding-stdlib-subset.md](references/freestanding-stdlib-subset.md).
The headline rules:

| Avoid | Why | Use instead |
|-------|-----|-------------|
| `std::string`, `std::vector`, `std::map` | Heap allocation, non-deterministic | Fixed-capacity containers (`std::array`, ring buffers, static-storage vectors) |
| `std::function` | Heap allocation for large callables; indirect call | Function pointer, a template parameter, or an `inplace_function`/non-allocating delegate |
| `std::shared_ptr` | Atomic refcount + control-block allocation | `std::unique_ptr` with a custom non-heap deleter, or plain ownership |
| `dynamic_cast` / `typeid` | Needs RTTI (off) | Tagged unions, `std::variant`, a virtual `kind()` |
| `<iostream>` | Pulls in huge static init + locale + heap | `printf`-over-UART, or a fixed-buffer formatter (see fixed-point ref) |
| Virtual functions in hot/ROM paths | vtable indirection, blocks inlining/devirtualization | CRTP or templates where the type is known at compile time |

Virtual functions are not banned — they are fine for genuine runtime
polymorphism and the vtable lives in FLASH — but in performance- or
size-critical paths where the concrete type is known, compile-time
polymorphism (templates, CRTP) avoids the indirection.

## MISRA-Adjacent Discipline

Embedded C++ codebases often follow MISRA C++ / AUTOSAR / High-Integrity C++
style. The recurring rules that overlap this skill:

- No dynamic allocation after initialization (or none at all).
- No exceptions, no RTTI (matching the flag set above).
- No recursion where stack depth must be bounded; prefer iteration.
- Explicit fixed-width types (`uint32_t`, not `int`) at hardware boundaries.
- Initialize every object; no implicit narrowing conversions.
- Restrict the standard library to the freestanding, non-allocating subset.

These are conventions, not language features — treat them as the house rules the
subset gives you in exchange for determinism and small images.

## Diagnostics

| Symptom | Cause | Fix | Reference |
|---------|-------|-----|-----------|
| Binary calls `std::terminate` on an error | Code (or a library) throws under `-fno-exceptions` | Use `std::expected`/error codes; avoid throwing APIs (`vector::at`, throwing `new`) | [freestanding-stdlib-subset.md](references/freestanding-stdlib-subset.md) |
| `dynamic_cast`/`typeid` does not compile | Built with `-fno-rtti` | Tagged union / `std::variant` / virtual `kind()` | [freestanding-stdlib-subset.md](references/freestanding-stdlib-subset.md) |
| Image bloated by kilobytes of unwind tables | Exceptions enabled (no `-fno-exceptions`) | Add `-fno-exceptions -fno-unwind-tables` | this file, Flag Set |
| Unexpected `malloc`/`_sbrk` reference links in | A container or `std::function` allocates | Fixed-capacity container; non-allocating delegate | [freestanding-stdlib-subset.md](references/freestanding-stdlib-subset.md) |
| Large startup time / RAM for a const table | Table is mutable/non-`constexpr`, runs a ctor into RAM | Make it `constexpr`/`const` so it stays in FLASH | this file, ROM-able Data |
| `static` local has a guard variable / lock | thread-safe statics enabled | `-fno-threadsafe-statics` (single-threaded), or use `constinit` global | this file, Flag Set |
| Placement-new object corrupts / faults | Storage misaligned or too small, or `delete`d | `alignas(T)`/`sizeof(T)`; destroy with `p->~T()`, never `delete` | this file, No Heap |
| Global ctor order bug across TUs | Static initialization order fiasco | `constinit`, or constexpr/function-local-static init | this file, ROM-able Data |

## Deep-Dive References

- [references/freestanding-stdlib-subset.md](references/freestanding-stdlib-subset.md) — per-feature table of what is available, unavailable, or costly under `-fno-exceptions -fno-rtti -ffreestanding`, with the idiomatic replacement for each

## Related Skills

- [embedded-systems](../embedded-systems/SKILL.md) — the language-agnostic core (MMIO, `volatile`, ISRs, startup, linkers, fixed-point) C++ runs on
- [modern-cpp](${CLAUDE_SKILL_DIR}/cpp/modern-cpp/SKILL.md) — full RAII, smart-pointer, and `constexpr`/`constinit` rules this subset constrains
- [error-handling](${CLAUDE_SKILL_DIR}/cpp/modern-cpp/references/error-handling.md) — exceptions vs `std::expected` (embedded always picks `expected`/codes)
- [c-memory-ownership](${CLAUDE_SKILL_DIR}/c/c-memory-ownership/SKILL.md) — arena/pool allocators placement-new builds objects into
- [cpp-skills](${CLAUDE_SKILL_DIR}/cpp/SKILL.md) — standard-selection table for the features named above
- [version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md) — canonical toolchain/standard minimums
```