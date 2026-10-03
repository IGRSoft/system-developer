# Undefined Behavior Catalog

UB classes with the sanitizer flag that detects each and the correct rewrite. Allocators and alignment APIs: `allocators-and-arenas.md`; ownership and cleanup: the parent `SKILL.md`; sanitizer CI wiring: the `diagnostics` skill.

## Why UB Is Not "It Crashes"

The optimizer may assume UB never happens: a null check after a dereference can be deleted, `if (x + 1 < x)` on signed `x` can fold to `false`, and a later UB statement can license transforming earlier code on the same path. So code that works at `-O0` and fails at `-O2`, or on one compiler but not another, was wrong all along. Detect UB with sanitizers in testing and rewrite it out.

## UB vs Unspecified vs Implementation-Defined

Triage findings into the right bucket before deciding severity:

| Category | Meaning | Example | Review action |
|---|---|---|---|
| Undefined behavior | No requirements at all; whole-program license to misbehave | Signed overflow, OOB write | Must fix — this catalog |
| Unspecified behavior | One of several outcomes, may vary call to call, need not be documented | Evaluation order of `f() + g()` | Fix if the code depends on a particular outcome |
| Implementation-defined | One documented choice per implementation | `sizeof(int)`, right shift of negative values, `char` signedness | Acceptable if documented and tested on all target platforms |
| Locale-specific | Depends on locale settings | `islower('I')` in Turkish locales | Pin the locale or use locale-independent APIs |

Two common misclassifications:

- "GCC wraps signed overflow, so it's implementation-defined": no, it is UB; GCC emits wrapping code only until the optimizer has a reason not to. `-fwrapv` defines it, but that is a dialect flag, not standard C.
- "Unspecified order means any interleaving": function calls are indeterminately sequenced and do not interleave. UB needs unsequenced side effects on the same scalar (see Sequencing Violations).

## Detection Cheat Sheet

| UB class | Primary detector | Flag / tool | Notes |
|---|---|---|---|
| Signed overflow | UBSan | `-fsanitize=signed-integer-overflow` | In `-fsanitize=undefined` |
| Invalid shift | UBSan | `-fsanitize=shift` | Base and exponent checks |
| Division by zero, `INT_MIN / -1` | UBSan | `-fsanitize=integer-divide-by-zero,signed-integer-overflow` | In `-fsanitize=undefined` |
| Heap/stack/global out-of-bounds | ASan | `-fsanitize=address` | Redzone-based; misses far-OOB strides |
| Constant-offset array OOB | UBSan | `-fsanitize=bounds` | Compile-time-known bounds only |
| Pointer arithmetic overflow | UBSan | `-fsanitize=pointer-overflow` | Forming the pointer, not using it |
| Cross-object pointer compare/subtract | ASan extension | `-fsanitize=pointer-compare,pointer-subtract` + `ASAN_OPTIONS=detect_invalid_pointer_pairs=2` | GCC 8+/Clang |
| Use-after-free | ASan | `-fsanitize=address` | Three-stack reports |
| Use-after-return | ASan | `ASAN_OPTIONS=detect_stack_use_after_return=1` | Default in Clang 15+ on Linux |
| Use-after-scope | ASan | `-fsanitize=address` | On by default in GCC 7+/Clang |
| Uninitialized read | MSan / Valgrind | `-fsanitize=memory` / `valgrind` | MSan: Clang, Linux, all code instrumented |
| Null dereference | UBSan | `-fsanitize=null` | ASan reports the SEGV too |
| Misaligned access | UBSan | `-fsanitize=alignment` | |
| Strict aliasing | No production sanitizer | `-Wstrict-aliasing` (GCC, shallow); experimental `-fsanitize=type` (Clang 20+) | Mitigate with `-fno-strict-aliasing` |
| Unsequenced modification | Compiler warning only | `-Wsequence-point` (GCC), `-Wunsequenced` (Clang) | No runtime detector |
| Overlapping `memcpy`, bad `free` | ASan interceptors | `-fsanitize=address` | `strict_string_checks=1` widens coverage |
| Data race | TSan | `-fsanitize=thread` | Exclusive with ASan/MSan |

UBSan checks are recoverable by default; add `-fno-sanitize-recover=all` in CI so the first report fails the run, and `UBSAN_OPTIONS=print_stacktrace=1` for stacks.

## Signed Integer Overflow

Rule (C17 6.5; unchanged in C23): signed integer overflow is UB. C23's two's complement mandate fixes the representation, not what `INT_MAX + 1` means. Unsigned arithmetic wraps modulo 2^N and is never UB, though silent wrap is usually a logic bug.

```c
/* BROKEN: the optimizer may fold this check to false */
int next(int x) {
    if (x + 1 < x) return -1;   /* "signed overflow can't happen" */
    return x + 1;
}
```

Detection: `-fsanitize=signed-integer-overflow`. Clang's opt-in `-fsanitize=unsigned-integer-overflow` flags defined-but-suspicious unsigned wrap (noisy). `-fwrapv` is a mitigation, not a detector or a fix.

Rewrite: check against the limit before the operation:

```c
#include <limits.h>
int next_checked(int x, int *out) {
    if (x == INT_MAX) return -1;
    *out = x + 1;
    return 0;
}
```

For general arithmetic use C23 checked operations (GCC 14+/Clang 18+), with builtins as the pre-C23 fallback:

```c
#include <stdckdint.h>            /* C23 */
int total;
if (ckd_add(&total, a, b)) return -1;       /* true => would overflow */

/* Pre-C23 fallback (GCC/Clang builtin): */
if (__builtin_add_overflow(a, b, &total)) return -1;
```

Promotion trap: `uint16_t a, b; a * b` multiplies as `int` on 32-bit-int platforms, so `0xFFFF * 0xFFFF` is *signed* overflow. Cast to `unsigned` before multiplying narrow types.

## Shift Violations

Rule (C17 6.5.7; same in C23), for `E1 << E2` / `E1 >> E2`:

| Condition | Status |
|---|---|
| `E2` negative or `E2 >= width(E1)` | UB (both directions) |
| `E1` negative, left shift | UB, even under C23 two's complement (C++20 defines it) |
| Left shift of nonnegative `E1` whose result is unrepresentable | UB |
| Right shift of negative `E1` | Implementation-defined, C23 included (C++20 defines it as arithmetic) |

```c
/* BROKEN: three separate UB candidates */
int mask = 1 << 31;            /* overflows int */
int x    = -8 << 2;            /* negative left operand */
int y    = value >> shift;     /* if shift >= 32 or negative */
```

Detection: `-fsanitize=shift` (`shift-base` and `shift-exponent`).

Rewrite: shift in unsigned and validate counts:

```c
unsigned mask = 1u << 31;                       /* fine: unsigned wraps are defined */
uint64_t bit  = (uint64_t)1 << n;               /* widen BEFORE shifting */
if (shift >= 64) return 0;                      /* clamp or reject out-of-range counts */
```

The classic trap is `1 << n` for `n >= 31` when building 64-bit masks: the literal `1` is `int`.

## Division Violations

Rule (C17 6.5.5): division or remainder by zero is UB. `INT_MIN / -1` and `INT_MIN % -1` are UB because the quotient overflows.

```c
/* BROKEN: both operands attacker-influenced */
int avg = total / count;            /* count == 0? */
int q   = a / b;                    /* a == INT_MIN, b == -1? */
```

Detection: `-fsanitize=integer-divide-by-zero`; `INT_MIN / -1` is reported by `-fsanitize=signed-integer-overflow`.

Rewrite:

```c
if (b == 0 || (a == INT_MIN && b == -1)) return ERR_DIV;
int q = a / b;
```

## Out-of-Bounds Access

Rule (C17 6.5.6, 6.5.2.1): reading or writing outside an object's bounds is UB. A one-past-the-end pointer may be formed and compared but not dereferenced.

```c
/* BROKEN: classic variants */
char buf[16];
strcpy(buf, user_input);                 /* unbounded write */
buf[16] = '\0';                          /* off-by-one: valid indexes 0..15 */
int *a = malloc(n * sizeof *a);
for (size_t i = 0; i <= n; i++) a[i] = 0;   /* <= walks one past */
```

Detection: ASan (heap, stack, global redzones), `-fsanitize=bounds` (compile-time-known array bounds), `_FORTIFY_SOURCE` in production, Valgrind for heap only. A stride that jumps over the redzone (`p[1 << 20]`) lands in valid memory and goes unreported, so large indexes need an explicit bound check.

Rewrite: carry lengths with pointers and bound every write:

```c
int copy_name(char *dst, size_t cap, const char *src) {
    size_t n = strlen(src);
    if (n >= cap) return -1;            /* refuse, don't truncate silently */
    memcpy(dst, src, n + 1);
    return 0;
}
```

Use `sizeof buf` only where `buf` is a true array in scope; on a function parameter it measures the pointer. Size allocations off the object, not the type: `p = malloc(n * sizeof *p);` survives type changes.

### VLAs and `alloca`

A VLA with a zero or negative size is UB (C17 6.7.6.2), and an oversized one is a silent stack overflow; ASan's `dynamic-stack-buffer-overflow` covers only OOB access within it. Automatic VLAs are optional since C11 (`__STDC_NO_VLA__`); C23 requires only variably-modified types.

```c
/* BROKEN: n from input — zero, negative, or huge are all bad */
void handle(int n) { char buf[n]; ... }

/* Rewrite: validate, cap, or take the heap path */
void handle(int n) {
    if (n <= 0 || n > 4096) { handle_big(n); return; }
    char buf[4096];                  /* fixed cap, n bounded above */
    ...
}
```

`alloca` is worse: non-standard, no failure signal, UB on stack exhaustion. Don't use either with attacker-influenced sizes.

## Invalid Pointer Arithmetic and Comparison

Rule (C17 6.5.6, 6.5.8, 6.5.9): pointer arithmetic is defined only within one object plus one past the end. It is UB to:

- Form a pointer before the start or more than one past the end, even without dereferencing.
- Subtract pointers into different objects.
- Compare pointers into different objects with `<`, `<=`, `>`, `>=` (equality `==`/`!=` is fine).

```c
/* BROKEN */
char *end = buf - 1;                     /* before-begin pointer: UB at formation */
if (p3 >= heap_lo && p3 < heap_hi) ...   /* relational compare across objects */
ptrdiff_t d = p_in_a - p_in_b;           /* different objects */
```

Detection: `-fsanitize=pointer-overflow` at formation; `pointer-compare,pointer-subtract` for cross-object pairs (see cheat sheet); ASan only once the bad pointer is dereferenced.

Rewrite: iterate with indexes, or with `end` one past the last element:

```c
for (char *p = buf; p != buf + len; ++p) { ... }     /* end is one-past: legal */
```

For "is this pointer inside this buffer" checks, compare indexes from a known-derived pointer, or `uintptr_t` casts as a documented last resort, not raw relational comparisons. Objects larger than `PTRDIFF_MAX` overflow pointer differences; allocators commonly refuse them.

## Use-After-Free and Lifetime Violations

Rule (C17 6.2.4, 7.22.3): an object's lifetime ends at `free()`, scope exit, or a `realloc` move. Dereferencing a pointer to it is then UB, and the pointer value itself is indeterminate, so even `if (p == old)` is UB.

| Variant | Example |
|---|---|
| Heap use-after-free | Access via alias after owner freed |
| Double-free | Two owners both call `free` |
| Use of old pointer after successful `realloc` | `realloc` may move; old value indeterminate |
| Returning the address of a local | `return buf;` where `buf` is automatic |
| Escaped pointer used after scope | Pointer to a block-scope object used after the block |
| Compound literal escape | `int *p = &(int){42};` inside a block: the literal has block lifetime |

```c
/* BROKEN: realloc variant — q dangles even though realloc succeeded */
char *q = p + offset;
p = realloc(p, bigger);
use(q);                       /* UB: q points into the old block */
```

Detection: ASan for heap variants, use-after-return, and use-after-scope (see cheat sheet); `-Wreturn-local-addr` (GCC) / `-Wreturn-stack-address` (Clang) for a direct `return &local;`; Valgrind on uninstrumented binaries.

Rewrite: these are ownership bugs. Establish a single owner (parent `SKILL.md`) and re-derive pointers after any `realloc`:

```c
size_t offset = (size_t)(q - p);       /* save the index, not the pointer */
char *tmp = realloc(p, bigger);
if (!tmp) return -1;
p = tmp;
q = p + offset;                        /* re-derive from the new base */
```

To return a buffer, allocate and transfer ownership, take a caller buffer, or use `static` storage with a documented thread-safety caveat; never return automatic storage.

## Uninitialized Reads

Rule (C17 6.3.2.1, 6.7.9): automatic objects start indeterminate. Reading one before assignment is UB if its address is never taken, and can be UB via trap representations otherwise. `malloc` memory is likewise uninitialized; `calloc` zeroes.

```c
/* BROKEN */
int flags;                  /* never set on the error path */
if (parse(&flags) < 0) log_flags(flags);    /* reads garbage */

struct config c;
send(fd, &c, sizeof c, 0);  /* leaks stack garbage in padding + unset fields */
```

Detection: fix `-Wuninitialized` / `-Wmaybe-uninitialized` first; then MSan (Clang, Linux, every linked object instrumented) or Valgrind (no rebuild, ~20x slower). `-ftrivial-auto-var-init=pattern|zero` is hardening, not detection.

Rewrite: initialize at declaration; for structs use designated initializers or `= {0}`:

```c
struct config c = {0};            /* all members zero; padding still unspecified */
int flags = 0;
```

For structs crossing a trust boundary (network, IPC, disk), `memset` the whole struct before filling fields; `= {0}` does not guarantee zeroed padding.

## Null Pointer Dereference

Rule (C17 6.5.3.2): dereferencing a null pointer is UB, not a guaranteed segfault. The optimizer may delete a null check that follows a dereference on the same path.

```c
/* BROKEN: check is dead code; deref already "proved" p != NULL */
int len = strlen(p->name);
if (!p) return -1;
```

Detection: `-fsanitize=null` pinpoints the site; ASan shows `SEGV on unknown address 0x0...`; `-Wnull-dereference` catches simple static cases.

Rewrite: check before first use; at API entry points, document whether NULL is a contract violation (assert) or a runtime condition (error return):

```c
int widget_rename(widget *w, const char *name) {
    if (!w || !name) return -EINVAL;     /* runtime condition: report */
    ...
}
```

## Misaligned Access

Rule (C17 6.3.2.3): converting a pointer to a type with stricter alignment than the object is UB at the conversion. x86 usually tolerates the load; strict targets and vectorized code fault.

```c
/* BROKEN: buf + 3 has no guarantee of uint32_t alignment */
uint32_t value = *(uint32_t *)(buf + 3);
```

Detection: `-fsanitize=alignment`; `SIGBUS` on strict hardware.

Rewrite: `memcpy`, which compiles to a single unaligned load where legal:

```c
uint32_t value;
memcpy(&value, buf + 3, sizeof value);          /* defined, optimal codegen */
```

For over-aligned objects use `alignas` / `aligned_alloc` (see `allocators-and-arenas.md`).

## Strict Aliasing Violations

Rule (C17 6.5p7): an object may be accessed only through a compatible type, a `char`-family type, or a union member. Reading a `float` through a `uint32_t *` is UB; type-based alias analysis assumes differently-typed pointers don't alias and reorders loads.

```c
/* BROKEN: the canonical fast-inverse-sqrt pun */
float f = 1.5f;
uint32_t bits = *(uint32_t *)&f;     /* UB: int-typed read of a float object */
```

Detection is weak: `-Wstrict-aliasing` (GCC, `-O2`) flags only blatant cases and `-fsanitize=type` (Clang 20+) is experimental. Symptom: breaks at `-O2`, works with `-fno-strict-aliasing`.

Rewrite, in order of preference:

```c
/* 1. memcpy — the portable idiom, compiles to a register move */
uint32_t bits;
memcpy(&bits, &f, sizeof bits);

/* 2. Union punning — legal in C (C17 6.5.2.3 fn.), UB in C++ */
union { float f; uint32_t u; } pun = { .f = 1.5f };
uint32_t bits2 = pun.u;

/* 3. char-family access — always allowed for byte inspection */
unsigned char *raw = (unsigned char *)&f;
```

`-fno-strict-aliasing` is a legitimate project-wide policy (the Linux kernel uses it) but must cover every TU; it is not a spot fix. `__attribute__((may_alias))` is the per-type GCC/Clang escape hatch.

## Sequencing Violations

Rule (C17 6.5p2): a side effect on a scalar unsequenced relative to another side effect on, or a value computation using, the same scalar is UB:

```c
/* BROKEN */
i = i++ + 1;            /* two unsequenced modifications of i */
a[i] = i++;             /* read of i for indexing unsequenced vs i++ */
f(i++, i++);            /* argument evaluations unsequenced */
printf("%d %d", x, x = 5);   /* same scalar read and written */
```

`f(g(), h())` is unspecified order but not UB: calls are indeterminately sequenced.

Detection: compile-time only, `-Wsequence-point` (GCC) / `-Wunsequenced` (Clang); treat them as errors.

Rewrite: one modification per statement:

```c
i++;
a[i] = old_i_value;     /* state the order you mean explicitly */
```

## Invalid Function Pointer Calls

Rule (C17 6.3.2.3p8): calling a function through a pointer of incompatible type is UB. The classic offender is a cast callback:

```c
/* BROKEN: comparator takes strongly-typed args, qsort wants (const void*, const void*) */
int cmp_int(const int *a, const int *b) { return (*a > *b) - (*a < *b); }
qsort(arr, n, sizeof *arr, (int (*)(const void *, const void *))cmp_int);
```

It works on conventional ABIs and breaks under CFI (`-fsanitize=cfi`) and arm64e pointer authentication.

Detection: `-fsanitize=function` (Clang 17+ for C), `-fsanitize=cfi-icall` (Clang, LTO) as a production defense, `-Wcast-function-type` at compile time.

Rewrite: match the expected signature and cast the data pointers inside:

```c
int cmp_int(const void *pa, const void *pb) {
    const int *a = pa, *b = pb;
    return (*a > *b) - (*a < *b);
}
qsort(arr, n, sizeof *arr, cmp_int);          /* no function cast anywhere */
```

In C23 `void f();` means `void f(void)`, so mismatched old-style calls become hard errors; fix the prototypes rather than casting around them.

## Const and String Literal Violations

Rule (C17 6.4.5p7, 6.7.3p6): modifying a string literal is UB, and C types literals as `char[N]`, so the compiler won't stop you. Writing through a cast-away `const` is UB when the object was defined `const`.

```c
/* BROKEN: both compile cleanly in C */
char *name = "tmpXXXXXX";
mktemp(name);                         /* writes into .rodata: SIGSEGV or silent corruption */

const int limit = 100;
*(int *)&limit = 200;                 /* UB: object defined const */
```

Detection: usually `SIGSEGV` on a read-only page, but merged literals may silently corrupt. `-Wwrite-strings` makes literals `const char[]` so such assignments warn. No sanitizer covers this class.

Rewrite: own the buffer when you intend to write:

```c
char name[] = "tmpXXXXXX";            /* array copy on the stack: writable */
```

Use `-Wwrite-strings` in new code and treat a `(char *)` cast of a literal or `const` API return as a review finding. Casting away `const` is legal only when the original object was not defined `const`; document why at the cast site.

## Library Function Contract Violations

Calling a standard library function outside its contract is UB even when your own pointer arithmetic is clean (C17 7.1.4).

| Violation | UB form | Detection | Rewrite |
|---|---|---|---|
| `memcpy` with overlapping ranges | Restrict violation | ASan `memcpy-param-overlap` interceptor | `memmove` |
| `strlen`/`strcpy` on a non-NUL-terminated buffer | OOB read | ASan (`strict_string_checks=1` widens) | `memchr` with a bound; track lengths |
| `free`/`realloc` on a non-`malloc` or interior pointer | Invalid free | ASan `attempting free on address which was not malloc()-ed` | Free only stored base pointers |
| `printf` format vs argument mismatch | Wrong-type varargs read | `-Wformat -Werror=format-security` (compile time) | Match specifiers; `%zu` for `size_t`, `PRIu64` for `uint64_t` |
| User data as format string | Format-string attack + UB | `-Wformat-security` | `printf("%s", user)` — never `printf(user)` |
| `fclose(NULL)`, `fflush` on closed stream | UB (unlike `free(NULL)`) | None reliable | Guard: `if (f) fclose(f);` |
| `va_arg` past the last argument / wrong type | Indeterminate read | None reliable | Sentinel or count parameter, documented |
| `memset(p, 0, n)` with `p == NULL`, even when `n == 0` | UB through C23 (C2y defines the zero-length case) | UBSan `nonnull-attribute` | Skip the call when the buffer is absent |

Generally, passing NULL to a string/memory function that doesn't document accepting it is UB even with a zero length; guard the degenerate case.

## Data Races

Rule (C17 5.1.2.4): two conflicting accesses from different threads, at least one a write, neither atomic, with no happens-before ordering, are full UB, including torn reads and miscompiled loops.

```c
/* BROKEN: flag polling without atomics */
bool done = false;
/* thread A */ while (!done) { work(); }     /* may be hoisted to if(!done) for(;;) */
/* thread B */ done = true;
```

Detection: TSan (`-fsanitize=thread`) in its own build; ~5-15x slowdown.

Rewrite: `_Atomic` flags or locking:

```c
#include <stdatomic.h>
atomic_bool done = false;
/* A */ while (!atomic_load_explicit(&done, memory_order_acquire)) work();
/* B */ atomic_store_explicit(&done, true, memory_order_release);
```

Atomics, memory orders, and pthreads patterns: the `modern-c` skill's `c-concurrency-atomics` reference.

## Loop Termination Assumptions

Rule (C17 6.8.5p6): a loop with a non-constant controlling expression and no I/O, volatile, atomic, or synchronization operation may be assumed to terminate, so a computation-only spin loop can be removed. Unlike C++, `while (1) {}` is safe in C.

```c
/* BROKEN as a "wait": may be deleted at -O2 */
while (g_not_ready) { }          /* plain global, no atomics */
```

Detection: none at runtime; the loop vanishes from the disassembly.

Rewrite: make the loop observable: atomic load (see Data Races), `volatile` for hardware registers, or a real blocking primitive (condition variable, futex).

## Recommended Build Profiles

### Development and CI (functional tests)

```sh
CFLAGS="-O1 -g -fno-omit-frame-pointer \
        -fsanitize=address,undefined \
        -fno-sanitize-recover=all \
        -Wall -Wextra -Werror"
ASAN_OPTIONS=detect_stack_use_after_return=1:strict_string_checks=1
UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1
```

ASan and UBSan combine in one build (~2x slowdown). `-O1` keeps stacks readable; run at least one CI leg at `-O2` with the same sanitizers to trigger UB-dependent transforms.

### Dedicated legs (cannot combine with the above)

| Leg | Flags | Purpose |
|---|---|---|
| TSan | `-fsanitize=thread -O1 -g` | Data races; separate build dir |
| MSan | `-fsanitize=memory -fsanitize-memory-track-origins -O1 -g` | Uninitialized reads; Clang/Linux, all deps instrumented, so often impractical |
| Valgrind | uninstrumented `-O0 -g` build | Third-party binaries, MSan substitute |

### Production hardening (not detection)

```sh
-O2 -D_FORTIFY_SOURCE=3 -fstack-protector-strong \
-ftrivial-auto-var-init=zero -fPIE -pie -Wl,-z,relro,-z,now
```

`_FORTIFY_SOURCE` needs optimization; level 3 needs GCC 12+ (or Clang) and glibc 2.34+. The `relro`/`now` linker flags are ELF-only.

### Suppressions

Fix your own code with the class's rewrite; suppression files (`ASAN_OPTIONS=suppressions=`, `-fsanitize-ignorelist=`) are only for third-party code you cannot patch.

## UBSan Check Name Index

Map the phrase in a `runtime error:` line to its section:

| UBSan check / report phrase | Section |
|---|---|
| `signed integer overflow` | Signed Integer Overflow |
| `unsigned integer overflow` (opt-in, not UB) | Signed Integer Overflow — promotion traps |
| `shift exponent ... is too large` / `left shift of negative value` | Shift Violations |
| `division by zero` / `division of INT_MIN by -1` | Division Violations |
| `index ... out of bounds` (`-fsanitize=bounds`) | Out-of-Bounds Access |
| `pointer index expression ... overflowed` | Invalid Pointer Arithmetic and Comparison |
| `applying non-zero offset to null pointer` | Invalid Pointer Arithmetic and Comparison |
| `load of null pointer` / `member access within null pointer` | Null Pointer Dereference |
| `load of misaligned address` | Misaligned Access |
| `variable length array bound evaluates to non-positive value` (`-fsanitize=vla-bound`) | Out-of-Bounds Access — VLAs |
| `call to function ... through pointer to incorrect function type` | Invalid Function Pointer Calls |
| `null pointer passed as argument ... declared to never be null` (`nonnull-attribute`) | Library Function Contract Violations |
| `load of value ... not a valid value for type '_Bool'` | Uninitialized Reads (garbage interpreted as bool) |
| `execution reached an unreachable program point` | Usually fallout from another class — re-triage upstream |

ASan report headers are indexed in the parent `SKILL.md` diagnostic table.
