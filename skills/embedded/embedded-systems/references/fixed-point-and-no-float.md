# Fixed-Point Arithmetic and Avoiding Float

If the part has an FPU and float fits the flash and time budget, use `float` (enable the FPU in startup, build with `-mfloat-abi=hard`).

## Why Not Float

Without a hardware FPU (Cortex-M0/M0+/M3 and many others), each `float`/`double` operation is a call into a soft-float library (`__aeabi_fadd`, `__aeabi_fmul`, ...): tens to hundreds of cycles plus the library's flash. `double` is worse, and it is the type of unsuffixed literals like `1.5` and of `printf`'s `%f`. Fixed-point keeps fractions in integers with an agreed scale, using the integer ALU.

Even with an FPU, fixed-point gives bit-exact results across parts and more precision than single-precision-only hardware.

## Q-Format: The Implied Scale

Q*m.n*: *m* integer bits (sign included), *n* fractional bits, *m+n* = word width. The stored integer is the real value times 2ⁿ. Q16.16 in an `int32_t`: real = stored / 65536.

```c
#include <stdint.h>
typedef int32_t q16_16;
#define Q          16                    /* fractional bits */
#define Q_ONE      (1 << Q)              /* 1.0 */
```

Resolution is 2⁻ⁿ (Q16.16 ≈ 1.5e-5); range is ±2ᵐ⁻¹. Integer and fractional bits share the word.

## Conversions

```c
#define Q16(x)  ((q16_16)((x) * (double)Q_ONE))   /* literals: folded at compile time */

static inline q16_16  int_to_q(int32_t v)        { return v * Q_ONE; }   /* |v| < 2^15 */
static inline int32_t q_to_int(q16_16 v)         { return v >> Q; }      /* floors */
static inline int32_t q_to_int_round(q16_16 v)   { return (v + (Q_ONE >> 1)) >> Q; }
```

### Shift Caveats

- Left-shifting a negative signed value is undefined in C, C23 included (C++20 defines it), so `int_to_q` multiplies. Overflow is undefined either way; bound the input.
- Right-shifting a negative value is implementation-defined; GCC and Clang shift arithmetically, rounding toward negative infinity.
- `Q16(0.1)` is fine because the compiler does the float math. `(q16_16)(runtime_float * Q_ONE)` on an FPU-less part is the soft float you are avoiding.

## Addition and Subtraction

Same-format values add directly: `q16_16 c = a + b;`. Overflow behaves as for any integer (see Saturation). Shift one operand to the other's scale before mixing formats.

## Multiplication: Widen First

Two Q16.16 values multiply to a Q32.32 result that needs 64 bits:

```c
static inline q16_16 q_mul(q16_16 a, q16_16 b) {
    return (q16_16)(((int64_t)a * b) >> Q);    /* widen, multiply, rescale */
}
```

- Cast one operand before multiplying; `(int64_t)(a * b)` is too late.
- `>> Q` truncates; add `(int64_t)1 << (Q - 1)` before the shift to round.
- A 64-bit multiply is cheap next to soft float. If it isn't affordable, use a smaller format (Q8.8 in `int16_t`, widened to `int32_t`).

## Division and Rounding

Pre-scale the dividend so the quotient lands at the right scale:

```c
static inline q16_16 q_div(q16_16 a, q16_16 b) {
    return (q16_16)(((int64_t)a * Q_ONE) / b);   /* caller guarantees b != 0 */
}
```

Guard `b == 0`: there is no infinity or NaN, only a fault or garbage. Integer division truncates toward zero, while `>>` floors; pick one rounding rule and apply it explicitly.

## Saturation

Wraparound can be worse than clamping (a sensor value wrapping from max to min can slam an actuator):

```c
static inline q16_16 q_add_sat(q16_16 a, q16_16 b) {
    int64_t s = (int64_t)a + b;
    if (s > INT32_MAX) return INT32_MAX;
    if (s < INT32_MIN) return INT32_MIN;
    return (q16_16)s;
}
```

Cores with saturating instructions (`__SSAT`, `__QADD` in CMSIS) do this in one op; use them in hot paths.

## Choosing a Q Format

1. Range sets *m*: the largest magnitude, plus headroom for intermediates, must fit in 2ᵐ⁻¹.
2. Precision sets *n*: the smallest step must be ≥ 2⁻ⁿ.
3. Word size fixes *m+n*: 16 in `int16_t`, 32 in `int32_t`.
4. One format per expression, explicit conversion at boundaries, and a typedef per format so every variable's Q is documented.

## Float-Free printf

One `printf("%f", x)` links the float formatter. newlib-nano (`--specs=nano.specs`) omits it unless you add `-u _printf_float`. Print fixed-point as integers instead:

```c
/* Q16.16 as "-1.500": format the magnitude, then the sign. */
uint32_t mag   = v < 0 ? 0u - (uint32_t)v : (uint32_t)v;
uint32_t whole = mag >> Q;
uint32_t milli = (uint32_t)(((uint64_t)(mag & (Q_ONE - 1)) * 1000) >> Q);
printf("%s%lu.%03lu\n", v < 0 ? "-" : "", (unsigned long)whole, (unsigned long)milli);
```

Check the map file for `*float*` or `*dtoa*` symbols to confirm nothing slipped in.

## Pitfalls

| Pitfall | Fix |
|---------|-----|
| `(int64_t)(a * b)` (32-bit product already overflowed) | `(int64_t)a * b` |
| `(q16_16)(runtime_float * Q_ONE)` | Integer conversion; float only in literals |
| Mixed Q formats in one expression | Shift to one scale first |
| `>>` assumed to round toward zero | Explicit rounding |
| No divide-by-zero guard | Check the divisor |
| Overflow wraps a sensor/actuator value | Saturate |
| Unsuffixed `double` literals on an FPU-less part | `f` suffix or fixed-point |

Map files and newlib-nano: [linker-scripts-and-memory.md](linker-scripts-and-memory.md). Fixed-width types and `_BitInt`: [modern-c](../../../c/modern-c/SKILL.md).
