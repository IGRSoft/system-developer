---
name: modern-c
description: >-
  Modern C patterns for C17 and C23: standard selection, C23 quick wins,
  checked integer arithmetic, and hygiene flags. Use when choosing between
  C17 and C23, adopting nullptr, constexpr, typeof, _BitInt, or #embed,
  replacing manual overflow checks with <stdckdint.h>, or hardening C
  compiler flags.
---

# Modern C (C17 / C23)

## C17 vs C23 Selection

| Situation | Target | Why |
|-----------|--------|-----|
| New code, toolchain is GCC 14+/Clang 18+ | C23 (`-std=c23`; `-std=c2x` on GCC 13/Clang 16-17) | Quick wins below are free safety/clarity |
| Must build on older distros, embedded SDKs, MSVC | C17 (`-std=c17`) | C17 is bugfix-only over C11; universally supported |
| Library headers consumed by unknown compilers | C17 in public headers | Gate C23-isms behind `#if __STDC_VERSION__ >= 202311L` |
| Shared headers with C++ | C17 subset + interop care | See [ffi-interop](../../tooling/ffi-interop/SKILL.md) |

`__STDC_VERSION__`: C17 = `201710L`, C23 = `202311L`. GCC 15 defaults to
`gnu23`, so pin `-std` in the build system.

## C23 Quick Wins (adopt first)

Usable from GCC 13+ / Clang 16+ unless noted; per-feature minimums and
fallbacks in [references/c23-features.md](references/c23-features.md).

```c
// nullptr: typed null, never ambiguous in _Generic or varargs
int *p = nullptr;                       // C17: NULL

// bool/true/false are keywords - no <stdbool.h> needed
bool ready = false;

// Empty initializer zeroes every member and the padding
struct config cfg = {};                 // C17: = {0} (padding not guaranteed)

// Enums with fixed underlying type - ABI-stable, usable in headers
enum status : uint8_t { OK = 0, RETRY = 1, FATAL = 2 };

// Digit separators and binary literals
const uint32_t mask = 0b0001'1111;
const int64_t budget_us = 1'500'000;

// Standardized attributes (portable, no __attribute__ guards)
[[nodiscard]] int acquire(void);
[[deprecated("use acquire")]] int old_acquire(void);
switch (kind) { case A: step(); [[fallthrough]]; case B: finish(); }
```

## typeof, typeof_unqual, auto

```c
#define SWAP(a, b) do { typeof(a) tmp_ = (a); (a) = (b); (b) = tmp_; } while (0)

const volatile int cv = 1;
typeof_unqual(cv) plain = cv;   // int - qualifiers stripped

auto count = 0u;                // unsigned int, inferred (objects only)
```

Use `auto` sparingly: iterator-ish locals and macro internals. Spell out types
in public APIs and struct fields.

## constexpr Objects, Not Functions

C23 `constexpr` applies to objects only; C has no `constexpr` functions
(the key difference from C++). Clang 19+ / GCC 13+.

```c
constexpr size_t BUF_CAP = 4096;          // true constant: usable in array
uint8_t buf[BUF_CAP];                     //   sizes, static_assert, case labels

// constexpr int next(int x) { ... }      // ERROR: not C. Use static inline.
```

C17 fallback: `enum { BUF_CAP = 4096 }` for ints, `#define` otherwise
(`static const` is not a constant expression in C).

## Checked Arithmetic: <stdckdint.h>

Replaces manual overflow checks (GCC 14+ / Clang 18+). `ckd_*` returns
`true` on overflow and stores the wrapped result.

```c
#include <stdckdint.h>

size_t total;
if (ckd_mul(&total, count, elem_size) || ckd_add(&total, total, HDR_LEN)) {
    return ERR_OVERFLOW;            // don't allocate with the wrapped size
}
void *p = malloc(total);
```

C17 fallback: `__builtin_add_overflow`/`mul`/`sub` (GCC 5+, Clang 3.8+).
Generate a header that selects the C23 path or the `__builtin` fallback
automatically with `../scripts/gen_checked_arithmetic.sh` instead of writing the
`#if` chain by hand.

## _BitInt(N)

Exact-width integers without promotion surprises (`_BitInt(8)` arithmetic
stays in `_BitInt(8)`; no silent promotion to `int`). GCC 14+ (64-bit
targets), Clang 14+. Width cap is the implementation-defined
`BITINT_MAXWIDTH`.

```c
_BitInt(24) sample = 0wb;          // wb/uwb literal suffixes
unsigned _BitInt(12) addr = 0x7FFuwb;
```

## #embed (GCC 15+ / Clang 19+)

```c
static const unsigned char font[] = {
    #embed "font.ttf"
};
```

C17 fallback: `xxd -i` / `objcopy` at build time. Gate with
`#ifdef __has_embed` where mixed toolchains build the same file.

## unreachable() and memset_explicit()

```c
#include <stddef.h>
switch (state) {
case S_A: return run_a();
case S_B: return run_b();
}
unreachable();                     // UB if reached - optimizer hint

#include <string.h>
memset_explicit(key, 0, sizeof key);   // zeroization the optimizer must keep
```

Fallbacks: `__builtin_unreachable()`; `explicit_bzero` (glibc/BSD) or
`memset_s` (Annex K, macOS). `memset_explicit` needs glibc 2.37+.

## Semantic Changes

| Change | Consequence |
|--------|-------------|
| `void f();` now means `void f(void);` | Calls with arguments through `()` declarations are errors in C23 — audit old headers before switching `-std` |
| K&R function definitions removed | `int f(a) int a; { }` no longer compiles |
| Two's complement mandated | Sign-magnitude/ones'-complement assumptions gone; signed overflow is still UB |
| `realloc(p, 0)` is UB | Never use it as `free` |
| `ATOMIC_VAR_INIT` removed | Initialize atomics directly: `_Atomic int n = 0;` |

## Hygiene Flags

```sh
-std=c23 -Wall -Wextra -Werror -Wpedantic
-Wshadow -Wconversion -Wvla -Wundef -Wdouble-promotion
# C17 builds only (redundant in C23 where () means (void)):
-Wstrict-prototypes -Wold-style-definition
```

Hardening: GCC 14+ `-fhardened` bundles `-D_FORTIFY_SOURCE=3`,
`-fstack-protector-strong`, PIE/RELRO, and `-ftrivial-auto-var-init=zero`.
Full doctrine: [secure-coding](../../_shared/secure-coding/SKILL.md).

## Diagnostics

| Error | Cause | Fix |
|-------|-------|-----|
| `'nullptr' undeclared` | Not in C23 mode | `-std=c23` (GCC 14+/Clang 18+) or `-std=c2x` |
| `constexpr` rejected on a function | C has no constexpr functions | `static inline` |
| `#embed` unknown directive | Below GCC 15/Clang 19 | `xxd -i`/`objcopy` fallback |
| `'ckd_add' undeclared` | Header missing or old toolchain | `__builtin_add_overflow` |
| `undefined reference to 'memset_explicit'` | libc below glibc 2.37 | `explicit_bzero` / `memset_s` |
| Call through `()` declaration fails | `()` now means `(void)` | Declare real prototypes |
| `old-style function definition` error | K&R removed in C23 | Prototype form |
| `'threads.h' file not found` | No C11 threads (e.g., macOS) | pthreads |
| TSan data race report | Unsynchronized shared access | `_Atomic` with explicit order, or mutex |
| `-Wvla` warning | Runtime-sized stack array | Fixed cap or heap allocation |

## Deep-Dive References

- [references/c23-features.md](references/c23-features.md) — complete C23 catalog, per-feature compiler support, C17 fallbacks
- [references/c-concurrency-atomics.md](references/c-concurrency-atomics.md) — `<threads.h>`, `_Atomic`, memory orders, TLS

## Related Skills

- [c-memory-ownership](../c-memory-ownership/SKILL.md) — ownership conventions, allocators, UB catalog
- [modern-cpp](../../cpp/modern-cpp/SKILL.md) — constexpr/feature differences when sharing headers with C++
- [diagnostics](../../tooling/diagnostics/SKILL.md) — sanitizer and debugger workflows
- [version-feature-matrix](../../_shared/version-feature-matrix.md) — canonical toolchain minimums
