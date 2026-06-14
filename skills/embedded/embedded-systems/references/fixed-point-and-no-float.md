# Fixed-Point Arithmetic and Avoiding Float

Use this when:

- Your target has no FPU and `float`/`double` is too slow or too large.
- You need fractional math in integers (Q-format) with correct scaling.
- `printf` or a math call is pulling in software-float bloat.

Skip this file if:

- Your part has a hardware FPU and float fits the flash/time budget — just use
  `float` (and enable the FPU in startup; set `-mfloat-abi=hard`).
- You need register access or startup. Use the other references in this skill.

Jump to:

- Why Not Float
- Q-Format: The Implied Scale
- Conversions
- Addition and Subtraction
- Multiplication: Widen First
- Division and Rounding
- Saturation
- Choosing a Q Format
- Float-Free printf
- Pitfalls

## Why Not Float

On a core without a hardware FPU (Cortex-M0/M0+/M3, many others), every
`float`/`double` operation becomes a call into a software-emulation library
(`__aeabi_fadd`, `__aeabi_fmul`, ...): tens to hundreds of cycles each, plus
the flash the library occupies. `double` is worse than `float` and is the
*default* type of literals like `1.5` and of `printf`'s `%f`. Fixed-point keeps
fractional values in plain integers with an agreed scale, so arithmetic is the
integer ALU operations the core already has.

Even **with** an FPU, prefer fixed-point when you need bit-exact, deterministic
results across parts, or when only single-precision is available and you need
more.

## Q-Format: The Implied Scale

Q*m.n* notation: *m* integer bits, *n* fractional bits, in an *m+n*(+sign)-bit
integer. The stored integer is the real value times 2ⁿ. Q16.16 in an `int32_t`:
16 integer bits, 16 fractional, real value = stored / 65536.

```c
#include <stdint.h>
typedef int32_t q16_16;                  /* Q16.16 */
#define Q          16                    /* fractional bits */
#define Q_ONE      (1 << Q)              /* 1.0 represented */
```

Resolution is 2⁻ⁿ (Q16.16 ≈ 1.5e-5); range is ±2ᵐ⁻¹. Trade *n* up for
precision, *m* up for range — they share the word.

## Conversions

```c
/* Compile-time literal: the float multiply is folded by the compiler, none at runtime. */
#define Q16(x)        ((q16_16)((x) * (double)Q_ONE))

/* Runtime integer <-> fixed (no float involved): */
static inline q16_16 int_to_q(int32_t v)  { return v << Q; }   /* see signed-shift caveat */
static inline int32_t q_to_int(q16_16 v)  { return v >> Q; }   /* truncates toward -inf for signed >> */
static inline int32_t q_to_int_round(q16_16 v) { return (v + (Q_ONE >> 1)) >> Q; }
```

Signed-shift caveat: left-shifting a *negative* `int32_t`, or shifting a value
whose result will not fit, is undefined behavior before C23 (C23 mandates
two's-complement and defines the bit pattern, but signed *overflow* is still UB
in every standard). `int_to_q` is only safe for `v` in `[-2^15, 2^15)` here —
bound the input, or do the shift on an unsigned type and convert
(`(int32_t)((uint32_t)v << Q)`) when the range cannot be guaranteed.

`Q16(0.1)` is fine — the float arithmetic happens **in the compiler**, not on
the MCU. Never do `(q16_16)(runtime_float * Q_ONE)` on an FPU-less part; that is
the software-float you are trying to avoid.

## Addition and Subtraction

Same-format fixed-point adds and subtracts directly — the scale is identical, so
the integers add:

```c
q16_16 c = a + b;        /* both Q16.16 -> result Q16.16 */
```

Watch for overflow exactly as with any integer (see Saturation). Mixing formats
requires shifting one operand to the other's scale first.

## Multiplication: Widen First

Multiplying two Qm.n values yields a Q(2m).(2n) value in **double the bits** —
two Q16.16 numbers multiply to a Q32.32 result that needs 64 bits. You must
widen before multiplying or the product overflows:

```c
static inline q16_16 q_mul(q16_16 a, q16_16 b) {
    return (q16_16)(((int64_t)a * b) >> Q);    /* widen to 64, multiply, rescale */
}
```

- Cast **one** operand to `int64_t` so the multiply is 64-bit; `(int64_t)(a*b)`
  is too late — the 32-bit `a*b` already overflowed.
- The `>> Q` rescales Q32.32 back to Q16.16, discarding the low fractional bits
  (truncation; add `Q_ONE >> 1` before the shift to round).
- On 32-bit parts a 64-bit multiply is a few instructions but far cheaper than
  software float. If you cannot afford 64-bit, pick a smaller format (e.g.,
  Q8.8 in `int16_t` widened to `int32_t`).

## Division and Rounding

Division needs the dividend widened and pre-scaled so the quotient lands at the
right scale:

```c
static inline q16_16 q_div(q16_16 a, q16_16 b) {
    return (q16_16)(((int64_t)a << Q) / b);    /* pre-shift dividend, then divide */
}
```

- Guard `b == 0` — there is no FPU infinity/NaN to fall back on; a divide-by-zero
  is a fault or garbage.
- Signed right shift truncates toward negative infinity, not toward zero; if you
  need round-to-nearest or round-toward-zero, add the half-LSB or branch on sign
  explicitly.

## Saturation

Wraparound on overflow is often worse than clamping (a sensor reading that wraps
from max to min can command a violent actuator move). Saturate at the type
bounds:

```c
static inline q16_16 q_add_sat(q16_16 a, q16_16 b) {
    int64_t s = (int64_t)a + b;
    if (s > INT32_MAX) return INT32_MAX;
    if (s < INT32_MIN) return INT32_MIN;
    return (q16_16)s;
}
```

Some cores have saturating instructions (`__SSAT`/`__QADD` via CMSIS DSP) that
do this in one op; prefer them in hot paths.

## Choosing a Q Format

1. **Range** sets the integer bits: the largest magnitude you must represent
   needs ≤ 2ᵐ⁻¹ (signed). Add headroom for intermediate results.
2. **Precision** sets the fractional bits: the smallest step you must resolve
   needs ≤ 2⁻ⁿ.
3. **Word size** caps *m+n*: 15+ sign in `int16_t`, 31+ sign in `int32_t`.
4. **Keep one format per expression**; convert explicitly at boundaries and
   document the Q of every fixed-point variable (a `q16_16` typedef per format
   beats a bare `int32_t`).

## Float-Free printf

`printf("%f", x)` drags in the floating-point formatting code (large) even if
you have only one such call. To keep it out:

- **newlib-nano** (`--specs=nano.specs`) excludes float `printf` by default;
  re-enable only deliberately with `-u _printf_float`.
- **Print fixed-point as integers**: split into whole and fractional parts and
  format with `%d`:

```c
/* Print a Q16.16 value as "12.345" with 3 decimals, no float in sight. */
q16_16 v = ...;
int32_t whole = q_to_int(v);
int32_t frac  = (int32_t)(((int64_t)(v & (Q_ONE - 1)) * 1000) >> Q);  /* milli-units */
printf("%ld.%03ld\n", (long)whole, (long)(frac < 0 ? -frac : frac));
```

- Or a dedicated lightweight integer-only formatter (many embedded projects ship
  one). Verify with the map file that no `*float*`/`*dtoa*` symbols linked.

## Pitfalls

| Pitfall | Consequence | Fix |
|---------|-------------|-----|
| `a * b` then cast to 64-bit | 32-bit product already overflowed | Widen **before** the multiply: `(int64_t)a * b` |
| `(q16_16)(runtime_float * Q_ONE)` | Pulls in software float at runtime | Convert via integers; only literals may use float |
| Mixing Q formats in one expression | Silent wrong scale | One format per expression; shift to align |
| Signed `>>` assumed to round toward zero | Off-by-one for negatives | Add half-LSB, or handle sign explicitly |
| No divide-by-zero guard | Fault or garbage (no NaN) | Check the divisor |
| Overflow wraps a sensor/actuator value | Dangerous discontinuity | Saturate, or use `__SSAT`/`__QADD` |
| One `%f` in `printf` | Float formatting bloats flash | newlib-nano; integer-split formatting |
| `double` literals on an FPU-less part | Slow double-precision software math | `float`/`f` suffix, or fixed-point |

Cross-references: software-float bloat shows up as image size — measure with the
map file per [linker-scripts-and-memory.md](linker-scripts-and-memory.md);
choosing newlib-nano is covered there too;
[modern-c](${CLAUDE_SKILL_DIR}/c/modern-c/SKILL.md) covers `_BitInt`/fixed-width
integer types these formats are built on.
