# C23 Feature Catalog

Use this when:

- You need the complete list of C23 (ISO/IEC 9899:2024) changes with per-feature compiler support.
- You are deciding whether a specific C23 feature is safe for your minimum toolchain.
- You need the C17 fallback for a feature you cannot adopt yet.

Skip this file if:

- You only need the headline quick wins and selection table. Use [../SKILL.md](../SKILL.md).
- Your question is about threads or atomics. Use [c-concurrency-atomics.md](c-concurrency-atomics.md).

Jump to:

- Support Summary
- Language Features
- Preprocessor Features
- Library Additions
- Removals and Semantic Changes
- Migration Checklist (C17 -> C23)

Version minimums below reflect first usable releases as commonly documented;
point releases and target-specific gaps exist — verify against your toolchain
(`gcc --version`, `clang --version`, and a one-line compile probe) before
committing a hard dependency. MSVC C23 support is partial and evolving; treat
MSVC as C17-only unless you have verified a specific feature.

## Support Summary

| Tier | Features | Minimum toolchain |
|------|----------|-------------------|
| Core (adopt freely) | `nullptr`, `bool` keywords, `{}` init, `typeof`, `constexpr` objects, digit separators, binary literals, attributes, `static_assert` 1-arg | GCC 13+ / Clang 16+ |
| Near-core | enum underlying types, `auto`, `<stdckdint.h>`, `unreachable()` | GCC 13+ / Clang 16-17+ (verify) |
| Late arrivals | `_BitInt` (GCC), `constexpr` (Clang), `<stdbit.h>` | GCC 14+ / Clang 19+ |
| Latest | `#embed` | GCC 15+ / Clang 19+ |
| Library-bound | `memset_explicit`, `%b`/`%wN` printf, `free_sized` | Depends on libc, not compiler |

`-std` spelling: `-std=c23` exists from GCC 14 and Clang 18; older releases
(GCC 9-13, Clang 9-17) accept the same features under `-std=c2x`.
Feature-test macro: `__STDC_VERSION__ >= 202311L`.

---

## Language Features

### nullptr and nullptr_t

A null pointer constant with its own type. Unlike `NULL` (which may expand to
`0` or `((void *)0)`), `nullptr` is never misread as an integer — important in
`_Generic` selections and variadic calls.

```c
int *p = nullptr;

// _Generic finally distinguishes null pointers from integers
#define DESCRIBE(x) _Generic((x), \
    nullptr_t: "null pointer",    \
    int:       "int",             \
    int *:     "int pointer")(x)

// Varargs: nullptr always passes as a pointer; NULL as bare 0 may not
execl("/bin/ls", "ls", "-l", nullptr);
```

| Toolchain | Minimum |
|-----------|---------|
| GCC | 13 |
| Clang | 16 |
| C17 fallback | `NULL`; in varargs cast explicitly: `(char *)NULL` |

### bool, true, false as Keywords

`bool`, `true`, and `false` are first-class keywords. `<stdbool.h>` still
exists but is empty of purpose (it keeps a couple of compatibility macros).

```c
bool ready = false;     // no include needed in C23
```

| Toolchain | Minimum |
|-----------|---------|
| GCC | 13 |
| Clang | 15 |
| C17 fallback | `#include <stdbool.h>` |

### Empty Initializer {}

`= {}` zero-initializes any complete object type, matching C++ syntax. Also
valid for VLAs (which `{0}` never was).

```c
struct sockaddr_in addr = {};
int matrix[4][4] = {};
size_t n = runtime_size();
char vla[n];
// C23: char vla[n] = {}; is still NOT allowed - VLAs cannot be initialized.
// Use memset for VLAs in every standard.
```

| Toolchain | Minimum |
|-----------|---------|
| GCC | 13 (long-standing extension before) |
| Clang | 16 (extension before) |
| C17 fallback | `= {0}` (first member zeroed, rest implicitly zero) |

Note: neither `{}` nor `{0}` guarantees padding bytes are zeroed when you
later `memcmp` structs — use `memset` if byte-exact zeroing matters.

### constexpr (Objects Only)

`constexpr` declares an object whose value is a compile-time constant, usable
in array bounds, `case` labels, `static_assert`, and other constant
expressions. **C has no constexpr functions** — that is C++ only. This is the
single most common C/C++ confusion in C23 adoption.

```c
constexpr size_t PAGE = 4096;
constexpr double SCALE = 1.5;          // works for non-integers, unlike enum

static uint8_t pool[PAGE * 4];         // OK: constant expression
static_assert(PAGE % 256 == 0);

// constexpr size_t f(void) { return 4096; }   // ERROR in C - C++ only
```

Constraints: the initializer must be a constant expression; pointers can only
be `nullptr` or address constants; no `constexpr` on VLA types.

| Toolchain | Minimum |
|-----------|---------|
| GCC | 13 |
| Clang | 19 |
| C17 fallback | `enum { PAGE = 4096 }` for ints; `#define` for other types. `static const` is NOT a constant expression in C |

### typeof and typeof_unqual

Standardizes the decades-old GNU `typeof` extension. `typeof_unqual` strips
qualifiers (`const`, `volatile`, `restrict`) and atomicity.

```c
#define MAX(a, b) ({ typeof(a) a_ = (a); typeof(b) b_ = (b); \
                     a_ > b_ ? a_ : b_; })          // statement expr = GNU ext

const volatile uint32_t reg = 0;
typeof_unqual(reg) snapshot = reg;     // plain uint32_t

typeof(int [4]) rows;                  // array of 4 int - type position too
```

| Toolchain | Minimum |
|-----------|---------|
| GCC | 13 (`__typeof__` extension since forever) |
| Clang | 16 (`__typeof__` extension before) |
| C17 fallback | `__typeof__(x)` works on both GCC and Clang in any mode |

### auto Type Inference

`auto` infers an object's type from its initializer. Objects only, single
declarator, initializer required.

```c
auto n = 42u;                 // unsigned int
auto p = malloc(64);          // void *
// auto x;                    // ERROR: no initializer
```

Style: keep `auto` for locals with obvious initializers and macro internals;
never in public headers or struct definitions.

| Toolchain | Minimum |
|-----------|---------|
| GCC | 13 |
| Clang | 16+ (completeness varies by release — verify against your toolchain) |
| C17 fallback | Spell the type; in macros use `__auto_type` (GNU extension, GCC 4.9+/Clang 3.8+) |

### Enums with Fixed Underlying Type

`enum E : type` pins size and signedness — finally safe in wire formats,
ABIs, and public structs. C23 also guarantees enumerators wider than `int`
work in plain enums.

```c
enum opcode : uint8_t  { OP_NOP = 0x00, OP_HALT = 0xFF };
enum offset : int64_t  { OFF_MIN = -(1LL << 40), OFF_MAX = (1LL << 40) };

struct packet {
    enum opcode op;            // exactly 1 byte, guaranteed
    uint8_t     len;
};
```

| Toolchain | Minimum |
|-----------|---------|
| GCC | 13 |
| Clang | 17 |
| C17 fallback | Store as `uint8_t` field + plain enum for names; `static_assert(sizeof(enum opcode) == ...)` to catch drift |

### _BitInt(N)

Bit-precise integers with exact width and — critically — **no integer
promotion**: `_BitInt(8) + _BitInt(8)` stays 8 bits wide instead of silently
promoting to `int`. Literal suffixes `wb` (signed) and `uwb` (unsigned).

```c
_BitInt(24)          sample  = -8388608wb;     // exact 24-bit signed
unsigned _BitInt(12) channel = 0xFFFuwb;

// Hardware register packing without promotion bugs:
unsigned _BitInt(3) priority = 7uwb;
unsigned _BitInt(3) doubled = priority + priority;  // wraps in 3 bits (unsigned)
```

Width limit is `BITINT_MAXWIDTH` (`<limits.h>`), at least `ULLONG_WIDTH`;
real caps are large but implementation-defined — verify against your
toolchain. Signed `_BitInt` overflow is still UB, like all signed overflow.

| Toolchain | Minimum |
|-----------|---------|
| GCC | 14 (initially 64-bit targets — verify yours) |
| Clang | 14 (`_ExtInt` precursor since 11) |
| C17 fallback | Fixed-width `uintN_t` + manual masking: `(x + y) & 0x7u` |

### Digit Separators and Binary Literals

```c
const uint32_t crc_poly  = 0b1110'1101'1011'1000'1000'0011'0010'0000;
const int64_t  budget_ns = 16'666'667;        // 60 Hz frame budget
```

| Toolchain | Minimum |
|-----------|---------|
| GCC | 13 (binary literals were a GCC 4.3+ extension) |
| Clang | 16 separators / 15 binary (extensions long before) |
| C17 fallback | Hex with comments; `0x0F` instead of `0b1111` |

### Standardized Attributes

C23 adopts the C++ `[[...]]` attribute syntax and a starter set:
`[[deprecated]]`, `[[deprecated("msg")]]`, `[[fallthrough]]`,
`[[maybe_unused]]`, `[[nodiscard]]`, `[[nodiscard("msg")]]`, `[[noreturn]]`,
plus `[[unsequenced]]` and `[[reproducible]]` for function-effect contracts.

```c
[[nodiscard("leaks fd if ignored")]] int open_log(const char *path);

[[noreturn]] void die(const char *msg);

void parse(int kind) {
    [[maybe_unused]] int debug_only = compute();
    switch (kind) {
    case 1: prepare(); [[fallthrough]];
    case 2: finish(); break;
    }
}

// Effect contracts (optimizer hints; misuse is UB):
[[reproducible]] int lookup(const struct table *t, int key);  // no side effects,
[[unsequenced]]  int popcount64(uint64_t x);                  // stateless + independent
```

`__has_c_attribute(nodiscard)` probes availability in the preprocessor.

| Toolchain | Minimum |
|-----------|---------|
| GCC | 13 in `-std=c23`; accepted in `-std=c2x` since GCC 10-12 depending on attribute |
| Clang | 16 in C23 mode; earlier in `-std=c2x`. `[[unsequenced]]`/`[[reproducible]]` parsing varies — verify |
| C17 fallback | `__attribute__((warn_unused_result))`, `__attribute__((noreturn))`, `__attribute__((unused))`, `/* fallthrough */` + `-Wimplicit-fallthrough` |

### static_assert Without Message, and as Keyword

`static_assert` is a keyword (no `<assert.h>` needed) and the message is
optional.

```c
static_assert(sizeof(void *) == 8);
static_assert(CHAR_BIT == 8, "platform assumption");
```

| Toolchain | Minimum |
|-----------|---------|
| GCC | 13 (keyword); `_Static_assert` 1-arg earlier |
| Clang | 16 (keyword) |
| C17 fallback | `#include <assert.h>` + `static_assert(expr, "msg")` (message required) |

### Keyword Spellings: thread_local, alignas, alignof

First-class keywords replacing `_Thread_local`, `_Alignas`, `_Alignof` (old
spellings remain as alternatives).

```c
thread_local int per_thread_errno_shadow;
alignas(64) static uint8_t cacheline_buf[64];
size_t a = alignof(max_align_t);
```

| Toolchain | Minimum |
|-----------|---------|
| GCC | 13 |
| Clang | 16 |
| C17 fallback | `_Thread_local`/`_Alignas`/`_Alignof`, or the convenience macros from `<threads.h>`/`<stdalign.h>` |

### unreachable()

`unreachable()` (macro in `<stddef.h>`) marks control flow the programmer
guarantees cannot execute. Reaching it is UB — the optimizer deletes the
path and warnings about missing returns go away.

```c
#include <stddef.h>

int dispatch(enum opcode op) {
    switch (op) {
    case OP_NOP:  return 0;
    case OP_HALT: return stop();
    }
    unreachable();   // all enumerators handled; new ones caught by -Wswitch
}
```

Pair with assertions in debug builds: `assert(!"unreachable"); unreachable();`

| Toolchain | Minimum |
|-----------|---------|
| GCC | 13 (toolchain `<stddef.h>` — verify header, not just compiler) |
| Clang | 16 (same caveat) |
| C17 fallback | `__builtin_unreachable()` (GCC 4.5+/Clang) |

### Empty Parentheses Mean (void); K&R Definitions Removed

In C23, `void f();` declares a function taking **no arguments** — identical
to `void f(void);`. Before C23 it declared an unspecified parameter list, and
calls with any arguments compiled silently. K&R (identifier-list) definitions
are removed entirely.

```c
// Legal C17, latent bug; ERROR in C23:
void log_msg();
// log_msg("late", 42);     // C17: compiles, UB at runtime. C23: error.

// Removed in C23:
// int add(a, b) int a, b; { return a + b; }
```

Audit step before flipping `-std`: build once with
`-Wstrict-prototypes -Wold-style-definition -Werror` in C17 mode; what it
flags is exactly what C23 will break.

| Toolchain | Minimum |
|-----------|---------|
| GCC | 13 (enforced in C23 mode) |
| Clang | 15 (enforced in C23 mode) |
| C17 fallback | Write `(void)` everywhere; enable the two warnings above |

### Two's Complement Mandated

Signed integers are two's complement, period. `INT_MIN == -INT_MAX - 1` is
guaranteed; bit patterns of negative numbers are portable.

**What did NOT change**: signed overflow is still undefined behavior. Use
`<stdckdint.h>` or unsigned arithmetic for wraparound.

| Toolchain | Minimum |
|-----------|---------|
| All | Every mainstream target was already two's complement; this is a spec guarantee, not a compiler feature |
| C17 fallback | Behaviorally identical on all relevant hardware |

### char8_t and Unicode Literals

`u8` string literals have type `char8_t[]`, where `char8_t` is a typedef of
`unsigned char` from `<uchar.h>` (unlike C++, where it is a distinct type),
and `u8'x'` character literals exist. Delimited `\u{XXXX}` and named escapes
are not in C23 — that is C++ — keep `\uXXXX`.

```c
#include <uchar.h>
const char8_t *s = u8"héllo";
```

| Toolchain | Minimum |
|-----------|---------|
| GCC | 13 |
| Clang | 16 |
| C17 fallback | `u8""` exists since C11 but yields `char[]`; code that needs one type across modes should use explicit `unsigned char` casts |

### Other Language Items (brief)

| Feature | What | Support / fallback |
|---------|------|--------------------|
| Variadic function with no named parameter: `int f(...)` | `va_start(ap)` now takes one argument | GCC 13 / Clang 16; C17: require a named first parameter |
| Storage-class specifiers in compound literals: `(static struct S){...}` | Compound literal with static lifetime | GCC 13 / Clang 18 (verify); C17: named `static` object |
| Labels before declarations and at block end | `label: int x = 0;` and `label: }` both legal | GCC 11+/Clang 18 (verify); C17: add `;` after label |
| Unnamed parameters in definitions: `void cb(int, void *ctx)` | Document-by-omission for unused params | GCC 11 / Clang 13; C17: name it + `(void)param;` |
| `bool` conversion tightening, `(bool)x` semantics | Cleanups, rarely observable | n/a |
| Identifier syntax follows UAX #31 | Confusable/emoji identifiers rejected | Don't use non-ASCII identifiers anyway |

---

## Preprocessor Features

### #embed

Embeds a file's bytes as a comma-separated list at preprocessing time.
Parameters: `limit(N)`, `prefix(...)`, `suffix(...)`, `if_empty(...)`.

```c
static const unsigned char model[] = {
    #embed "weights.bin" if_empty(0)
};
static const size_t model_len = sizeof model;

// Probe support:
#if defined(__has_embed)
#  if __has_embed("weights.bin") == __STDC_EMBED_FOUND__
     /* ... */
#  endif
#endif
```

Orders of magnitude faster than compiling `xxd -i` output; no build-step
codegen to maintain.

| Toolchain | Minimum |
|-----------|---------|
| GCC | 15 |
| Clang | 19 |
| C17 fallback | `xxd -i data.bin > data.h`, or `objcopy -I binary -O default data.bin data.o`, or CMake `file(READ ... HEX)` codegen |

### #elifdef and #elifndef

```c
#ifdef PLATFORM_LINUX
  /* ... */
#elifdef PLATFORM_BSD
  /* ... */
#elifndef NDEBUG
  /* ... */
#endif
```

| Toolchain | Minimum |
|-----------|---------|
| GCC | 12 |
| Clang | 13 |
| C17 fallback | `#elif defined(...)` |

### __VA_OPT__, #warning, __has_include, __has_c_attribute

All standardized in C23; all were near-universal extensions first.

```c
#define LOG(fmt, ...) fprintf(stderr, fmt "\n" __VA_OPT__(,) __VA_ARGS__)

#if !__has_include(<stdckdint.h>)
#  warning "no stdckdint.h - using builtin overflow checks"
#endif
```

| Toolchain | Minimum |
|-----------|---------|
| GCC / Clang | Long-standing extensions; standardized spellings fine on any toolchain this plugin targets |
| C17 fallback | Same spellings work as extensions; `##__VA_ARGS__` (GNU) where `__VA_OPT__` is unavailable |

---

## Library Additions

### <stdckdint.h> — Checked Integer Arithmetic

`ckd_add`, `ckd_sub`, `ckd_mul`. Each returns `true` if the mathematically
correct result does not fit the destination; the destination receives the
wrapped two's-complement value either way. Works across mixed integer types
(not `bool`, not plain `char`, enums are fine via their compatible type).

```c
#include <stdckdint.h>

// The canonical allocation-size guard:
size_t bytes;
if (ckd_mul(&bytes, nmemb, size)) return NULL;
return malloc(bytes);

// Signed accumulate with saturation policy:
int32_t acc = 0;
for (size_t i = 0; i < n; i++) {
    if (ckd_add(&acc, acc, v[i])) { acc = INT32_MAX; break; }
}
```

Replaces the error-prone manual idioms (`a > SIZE_MAX / b`,
`a > INT_MAX - b`) — those stay correct but are easy to get wrong per-type.

| Toolchain | Minimum |
|-----------|---------|
| GCC | 13 (compiler-provided header) |
| Clang | 16+ (verify the header ships with your installation) |
| C17 fallback | `__builtin_add_overflow(a, b, &r)` family (GCC 5+/Clang 3.8+), identical semantics |

### <stdbit.h> — Bit Utilities

Type-generic and width-suffixed bit operations: `stdc_count_ones`,
`stdc_leading_zeros`, `stdc_trailing_zeros`, `stdc_bit_width`,
`stdc_bit_floor`, `stdc_bit_ceil`, `stdc_has_single_bit`, `stdc_first_*`,
plus `__STDC_ENDIAN_NATIVE__` / `__STDC_ENDIAN_LITTLE__` /
`__STDC_ENDIAN_BIG__` endianness macros.

```c
#include <stdbit.h>

unsigned ones = stdc_count_ones(mask);                    // type-generic
size_t cap = stdc_bit_ceil((size_t)needed);               // next power of 2

#if __STDC_ENDIAN_NATIVE__ == __STDC_ENDIAN_LITTLE__
  /* no byte swap needed */
#endif
```

| Toolchain | Minimum |
|-----------|---------|
| GCC | 14 (header availability also depends on libc — glibc 2.39+; verify) |
| Clang | 19 (verify) |
| C17 fallback | `__builtin_popcount`/`__builtin_clz`/`__builtin_ctz` (beware UB on 0 for clz/ctz); endianness via `__BYTE_ORDER__` |

### memset_explicit

Zeroization that the optimizer is forbidden to elide — for keys, passwords,
tokens before `free`.

```c
#include <string.h>
memset_explicit(secret, 0, sizeof secret);
free(secret_buf);
```

| Platform | Status |
|----------|--------|
| glibc | 2.37+ |
| musl | recent releases (verify) |
| macOS / BSD libc | Not as of this writing — use `memset_s` (macOS, with `__STDC_WANT_LIB_EXT1__`) or `explicit_bzero` (BSD/glibc) |
| C17 fallback | `explicit_bzero`, `memset_s`, or `memset` + compiler barrier `__asm__ __volatile__("" ::: "memory")` |

### POSIX Functions Absorbed: strdup, strndup, memccpy, gmtime_r, localtime_r, timegm

Long-standing POSIX functions are now ISO C. Practical effect: no more
`_POSIX_C_SOURCE`/`_DEFAULT_SOURCE` feature-test-macro dance to see them in
strict mode, once your libc catches up.

```c
char *copy = strdup(name);            // ISO C in C23
struct tm tm;
gmtime_r(&epoch, &tm);                // reentrant, now portable C
```

| Toolchain | Minimum |
|-----------|---------|
| glibc/musl/BSD | Functions existed for decades; C23-mode visibility without feature macros depends on libc headers — verify |
| C17 fallback | Same functions with `#define _DEFAULT_SOURCE` (glibc) or equivalent |

### printf/scanf: %b and %wN Length Modifiers

`%b` prints binary; `%w32d`, `%w64u`, `%wf32`... print exact-width and
`_BitInt` values without `PRIu64` macro noise.

```c
printf("%b\n", 0xAAu);            // 10101010
printf("%w64d\n", (int64_t)x);    // no PRId64
```

| Platform | Status |
|----------|--------|
| glibc | `%b` 2.35+; `%wN` 2.38+ |
| musl / BSD | Varies — verify |
| C17 fallback | `<inttypes.h>` `PRId64` macros; manual binary printing loop |

### free_sized and free_aligned_sized

Size-feedback deallocation (`free_sized(p, n)`) lets allocators skip size
lookup and double-checks the caller's size bookkeeping.

| Platform | Status |
|----------|--------|
| All mainstream libcs | Little to no adoption as of this writing — verify; treat as future-facing |
| C17 fallback | `free(p)` — also the correct C23 fallback today |

### Math and Numeric Additions (brief)

| Addition | What |
|----------|------|
| `<float.h>` `*_IS_IEC_60559`, `INFINITY`/`NAN` tightening | Detect IEEE 754 conformance properly |
| Decimal FP (`_Decimal32/64/128`) | Optional Annex; GCC supports on some targets, Clang largely not — verify before use |
| `<math.h>` additions (`roundeven`, `fromfp`, `llogb`, `powr`, etc.) | IEC 60559:2019 binding; libc-dependent — verify |
| `<limits.h>` `*_WIDTH` macros | Bit widths for every integer type (also in C17 via TS) |

---

## Removals and Semantic Changes

| Change | Impact | Action |
|--------|--------|--------|
| K&R function definitions removed | Old code errors out | Convert to prototypes (mechanical; `-Wold-style-definition` finds them in C17) |
| `void f()` means `void f(void)` | Calls-with-args through empty declarations become errors | Audit with `-Wstrict-prototypes` before migrating |
| Trigraphs removed | `??=` etc. no longer translate | Virtually nobody is affected; grep for `??` if paranoid |
| `realloc(p, 0)` is undefined behavior | Code using it as `free` is broken | `if (n == 0) { free(p); return NULL; }` explicitly |
| `ATOMIC_VAR_INIT` removed (deprecated since C17) | Build error | Plain initialization: `_Atomic int n = 0;` |
| `__alignof_is_defined` / `<stdalign.h>` content emptied | Keywords replace macros | Use `alignas`/`alignof` keywords |
| Old function-pointer laxness tightened | A few implicit conversions now diagnosed | Heed the new errors; they were latent bugs |
| `*_HAS_SUBNORM`, `DBL_DIG`-era macros refreshed | Rarely observable | n/a |

---

## Migration Checklist (C17 -> C23)

1. **Pre-flight in C17 mode**: add `-Wstrict-prototypes -Wold-style-definition
   -Wimplicit-fallthrough -Werror`; fix everything it reports. This is the
   complete list of hard C23 breaks in most codebases.
2. **Grep for removed items**: `ATOMIC_VAR_INIT`, `realloc` with
   possibly-zero size, trigraph sequences.
3. **Flip one target**: change `-std=c17` to `-std=c23` (or `-std=c2x` on
   GCC 13/Clang 16-17) on a leaf library first; build clean with the
   [hygiene flags](../SKILL.md#hygiene-flags).
4. **Adopt core quick wins mechanically**: `NULL` -> `nullptr` in new code
   (do not mass-rewrite), drop `<stdbool.h>` includes opportunistically,
   `{0}` -> `{}` where intent is "zero everything".
5. **Adopt safety features deliberately**: every `malloc(a * b)` becomes a
   `ckd_mul` guard; every secret wipe becomes `memset_explicit` (with libc
   fallback shim); switch-over-enum tails get `unreachable()`.
6. **Gate public headers**: keep installed headers C17-compatible or guard
   with `#if __STDC_VERSION__ >= 202311L` so downstream C17 and C++
   consumers keep building.
7. **Verify in CI on the oldest supported toolchain** — feature availability
   tables above are gates, not guarantees; a one-line compile probe per
   gated feature in CI ends the debate permanently.

Cross-references: standard selection and quick-win summary in
[../SKILL.md](../SKILL.md); canonical toolchain minimums in
`${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md`; sanitizer
verification workflow in `${CLAUDE_SKILL_DIR}/tooling/diagnostics/SKILL.md`.
