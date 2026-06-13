# Undefined Behavior Catalog

Use this when:

- A program misbehaves only at `-O2`, only on one compiler, or only sometimes.
- You need the exact sanitizer flag that detects a specific UB class.
- You are reviewing C code for latent UB and need the correct rewrite, not just the diagnosis.
- A sanitizer report names a check (`signed-integer-overflow`, `pointer-overflow`, `alignment`) and you need context.

Skip this file if:

- You need allocator implementations or alignment APIs. Use `allocators-and-arenas.md`.
- You need ownership conventions or cleanup patterns. Use the parent `SKILL.md`.
- You need sanitizer build-system wiring and CI matrices. Use the `tooling/diagnostics` skill.

Jump to:

- Why UB Is Not "It Crashes"
- UB vs Unspecified vs Implementation-Defined
- Detection Cheat Sheet
- Signed Integer Overflow
- Shift Violations
- Division Violations
- Out-of-Bounds Access
- Invalid Pointer Arithmetic and Comparison
- Use-After-Free and Lifetime Violations
- Uninitialized Reads
- Null Pointer Dereference
- Misaligned Access
- Strict Aliasing Violations
- Sequencing Violations
- Invalid Function Pointer Calls
- Const and String Literal Violations
- Library Function Contract Violations
- Data Races
- Loop Termination Assumptions
- Recommended Build Profiles
- UBSan Check Name Index

## Why UB Is Not "It Crashes"

The standard places no requirements on a program that executes undefined behavior. The optimizer is allowed to assume UB never happens, and modern compilers exploit that assumption aggressively:

- A null check **after** a dereference can be deleted, because the dereference "proved" the pointer non-null.
- An overflow check written as `if (x + 1 < x)` on a signed `x` can be folded to `false`, because signed overflow "cannot happen".
- UB can appear to **time-travel**: a later UB statement licenses transformations of earlier, otherwise-correct code on the same path.

Consequences in practice: code that works at `-O0` and fails at `-O2`, works on GCC and fails on Clang, or works until a compiler upgrade. None of those are compiler bugs — the program was wrong all along. The only reliable strategy is to detect UB with sanitizers during testing and rewrite it out.

## UB vs Unspecified vs Implementation-Defined

Not every "the standard doesn't say" is equally dangerous. Triage findings into the right bucket before deciding severity:

| Category | Meaning | Example | Review action |
|---|---|---|---|
| **Undefined behavior** | No requirements at all; whole-program license to misbehave | Signed overflow, OOB write | Must fix — this catalog |
| **Unspecified behavior** | One of several outcomes, may vary call to call, need not be documented | Evaluation order of `f() + g()` | Fix if the code depends on a particular outcome |
| **Implementation-defined** | One documented choice per implementation | `sizeof(int)`, right shift of negative values (pre-C23), `char` signedness | Acceptable if documented and tested on all target platforms |
| **Locale-specific** | Depends on locale settings | `islower('I')` in Turkish locales | Pin the locale or use locale-independent APIs |

Two classification traps reviewers hit repeatedly:

- "It's implementation-defined, GCC wraps signed overflow" — false. Signed overflow is UB; GCC merely *often* emits wrapping code until the optimizer has a reason not to. `-fwrapv` would make it defined, but that is a dialect flag, not standard C.
- "Unspecified order means any interleaving" — evaluation order of function-call arguments is unspecified, but the calls themselves are *indeterminately sequenced*: they do not interleave. UB only enters when unsequenced side effects hit the same scalar (see Sequencing Violations).

## Detection Cheat Sheet

| UB class | Primary detector | Flag / tool | Notes |
|---|---|---|---|
| Signed overflow | UBSan | `-fsanitize=signed-integer-overflow` | In `-fsanitize=undefined` |
| Invalid shift | UBSan | `-fsanitize=shift` | Base and exponent checks |
| Division by zero, `INT_MIN / -1` | UBSan | `-fsanitize=integer-divide-by-zero,signed-integer-overflow` | In `-fsanitize=undefined` |
| Heap/stack/global out-of-bounds | ASan | `-fsanitize=address` | Redzone-based; misses far-OOB strides |
| Constant-offset array OOB | UBSan | `-fsanitize=bounds` | Compile-time-known bounds only |
| Pointer arithmetic overflow | UBSan | `-fsanitize=pointer-overflow` | Forming the pointer, not using it |
| Cross-object pointer compare/subtract | ASan extension | `-fsanitize=pointer-compare,pointer-subtract` + `ASAN_OPTIONS=detect_invalid_pointer_pairs=2` | GCC 8+/Clang; verify against your toolchain |
| Use-after-free | ASan | `-fsanitize=address` | Three-stack reports |
| Use-after-return | ASan | `ASAN_OPTIONS=detect_stack_use_after_return=1` | Default in recent Clang; verify against your toolchain |
| Use-after-scope | ASan | `-fsanitize-address-use-after-scope` | Lifetime within a function |
| Uninitialized read | MSan / Valgrind | `-fsanitize=memory` / `valgrind` | MSan: Clang, Linux, all code instrumented |
| Null dereference | UBSan | `-fsanitize=null` | ASan reports the SEGV too |
| Misaligned access | UBSan | `-fsanitize=alignment` | |
| Strict aliasing | (no production sanitizer) | `-Wstrict-aliasing` (GCC, shallow); TypeSanitizer is experimental — verify against your toolchain | Mitigate with `-fno-strict-aliasing` |
| Unsequenced modification | Compiler warning only | `-Wsequence-point` (GCC), `-Wunsequenced` (Clang) | No runtime detector |
| Overlapping `memcpy`, bad `free` | ASan interceptors | `-fsanitize=address` | `strict_string_checks=1` widens coverage |
| Data race | TSan | `-fsanitize=thread` | Exclusive with ASan/MSan |

UBSan checks are recoverable by default; add `-fno-sanitize-recover=all` in CI so the first report fails the run, and `UBSAN_OPTIONS=print_stacktrace=1` for stacks.

## Signed Integer Overflow

**Rule (C17 6.5; unchanged in C23).** Signed integer overflow is UB. C23 mandates two's complement *representation*, but arithmetic overflow on signed types remains undefined — the mandate changes what the bits look like, not what `INT_MAX + 1` means.

Unsigned arithmetic is defined to wrap modulo 2^N and is never UB (but silent wrap is still usually a logic bug).

```c
/* BROKEN: the optimizer may fold this check to false */
int next(int x) {
    if (x + 1 < x) return -1;   /* "signed overflow can't happen" */
    return x + 1;
}
```

**Detection.**

| Flag | Catches |
|---|---|
| `-fsanitize=signed-integer-overflow` | Runtime overflow with exact operands |
| `-fsanitize=unsigned-integer-overflow` (Clang) | Defined-but-suspicious unsigned wrap (not UB; noisy — opt-in) |
| `-fwrapv` | Not a detector: redefines signed overflow as wrapping. A mitigation/portability crutch, not a fix |

**Rewrite.** Check before the operation, against the limit:

```c
#include <limits.h>
int next_checked(int x, int *out) {
    if (x == INT_MAX) return -1;
    *out = x + 1;
    return 0;
}
```

For general arithmetic use C23 checked operations (GCC 13+/Clang 16+), with builtins as the pre-C23 fallback:

```c
#include <stdckdint.h>            /* C23 */
int total;
if (ckd_add(&total, a, b)) return -1;       /* true => would overflow */

/* Pre-C23 fallback (GCC/Clang builtin, long-standing): */
if (__builtin_add_overflow(a, b, &total)) return -1;
```

Watch for **promotion traps**: `uint16_t a, b; a * b` multiplies as `int` on 32-bit-int platforms, so `0xFFFF * 0xFFFF` is *signed* overflow. Cast to `unsigned` before multiplying narrow types.

## Shift Violations

**Rule (C17 6.5.7; C23 keeps these undefined).** For `E1 << E2` / `E1 >> E2`:

| Condition | Status |
|---|---|
| `E2` negative or `E2 >= width(E1)` | UB (both directions) |
| `E1` negative, left shift | UB — even under C23 two's complement (unlike C++20, which defined it) |
| Left shift of nonnegative `E1` whose result is unrepresentable | UB |
| Right shift of negative `E1` | Implementation-defined pre-C23; C23 defines it as arithmetic shift |

```c
/* BROKEN: three separate UB candidates */
int mask = 1 << 31;            /* overflows int */
int x    = -8 << 2;            /* negative left operand */
int y    = value >> shift;     /* if shift >= 32 or negative */
```

**Detection.** `-fsanitize=shift` (splits into `shift-base` and `shift-exponent` on Clang).

**Rewrite.** Shift in unsigned, validate counts:

```c
unsigned mask = 1u << 31;                       /* fine: unsigned wraps are defined */
uint64_t bit  = (uint64_t)1 << n;               /* widen BEFORE shifting */
if (shift >= 64) return 0;                      /* clamp or reject out-of-range counts */
```

The classic trap is `1 << n` for `n >= 31` when building 64-bit masks — the literal `1` is `int`.

## Division Violations

**Rule (C17 6.5.5).** Division or remainder by zero is UB. `INT_MIN / -1` and `INT_MIN % -1` are UB because the quotient overflows.

```c
/* BROKEN: both operands attacker-influenced */
int avg = total / count;            /* count == 0? */
int q   = a / b;                    /* a == INT_MIN, b == -1? */
```

**Detection.** `-fsanitize=integer-divide-by-zero`; the `INT_MIN / -1` case is reported by `-fsanitize=signed-integer-overflow`.

**Rewrite.**

```c
if (b == 0 || (a == INT_MIN && b == -1)) return ERR_DIV;
int q = a / b;
```

## Out-of-Bounds Access

**Rule (C17 6.5.6, 6.5.2.1).** Reading or writing outside an object's bounds is UB — heap blocks, stack arrays, globals, string buffers. A pointer one-past-the-end may be *formed and compared* but not dereferenced.

```c
/* BROKEN: classic variants */
char buf[16];
strcpy(buf, user_input);                 /* unbounded write */
buf[16] = '\0';                          /* off-by-one: valid indexes 0..15 */
int *a = malloc(n * sizeof *a);
for (size_t i = 0; i <= n; i++) a[i] = 0;   /* <= walks one past */
```

**Detection.**

| Flag | Coverage |
|---|---|
| `-fsanitize=address` | Heap, stack, global redzones; the workhorse |
| `-fsanitize=bounds` (UBSan) | Indexing past compile-time-known array bounds |
| `_FORTIFY_SOURCE=2`/`=3` + `-O2` | Hardened libc string/memory functions in production builds |
| Valgrind memcheck | Heap only (no stack/global redzones), uninstrumented binaries |

ASan caveat: a stride that jumps clean over the redzone (e.g., `p[1 << 20]`) lands in unrelated valid memory and goes unreported. Suspicious large indexes need an explicit bound check, not just a green ASan run.

**Rewrite.** Carry lengths with pointers; make every write bounded:

```c
int copy_name(char *dst, size_t cap, const char *src) {
    size_t n = strlen(src);
    if (n >= cap) return -1;            /* refuse, don't truncate silently */
    memcpy(dst, src, n + 1);
    return 0;
}
```

Use `sizeof buf` only where `buf` is a true array in scope — on a function parameter, `sizeof` measures the pointer. Size allocations off the object, not the type: `p = malloc(n * sizeof *p);` survives type changes.

### VLAs and `alloca`

Declaring a variable-length array with a size that is zero or negative is UB (C17 6.7.6.2), and an oversized VLA is a silent stack overflow that no sanitizer flags portably — `-fsanitize=address` reports `dynamic-stack-buffer-overflow` only for OOB access *within* it, not for the blown stack itself. VLAs are also optional since C11 (`__STDC_NO_VLA__`); C23 keeps automatic VLAs optional while requiring variably-modified *types*.

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

`alloca` is worse — not in any C standard, no failure signal, UB on stack exhaustion. Treat both as forbidden for attacker-influenced sizes.

## Invalid Pointer Arithmetic and Comparison

**Rule (C17 6.5.6, 6.5.8, 6.5.9).** Pointer arithmetic is defined only **within one object** (plus the one-past-the-end position). It is UB to:

- Form a pointer before the start or more than one past the end — even without dereferencing.
- Subtract pointers into different objects.
- Compare pointers into different objects with `<`, `<=`, `>`, `>=` (equality `==`/`!=` is fine).

```c
/* BROKEN */
char *end = buf - 1;                     /* before-begin pointer: UB at formation */
if (p3 >= heap_lo && p3 < heap_hi) ...   /* relational compare across objects */
ptrdiff_t d = p_in_a - p_in_b;           /* different objects */
```

**Detection.**

| Flag | Catches |
|---|---|
| `-fsanitize=pointer-overflow` (UBSan) | Pointer arithmetic that wraps or goes out of range at formation |
| `-fsanitize=pointer-compare,pointer-subtract` + `ASAN_OPTIONS=detect_invalid_pointer_pairs=2` | Cross-object `<`/`-` (GCC 8+/Clang; verify against your toolchain) |
| `-fsanitize=address` | Only when the bad pointer is finally dereferenced |

**Rewrite.** Iterate with indexes or with `[begin, end]` where `end` is one-past:

```c
for (char *p = buf; p != buf + len; ++p) { ... }     /* end is one-past: legal */
```

For "is this pointer inside this buffer" checks, compare **indexes** computed from a known-derived pointer, or `uintptr_t` casts as a documented, implementation-specific last resort — not raw relational pointer comparisons.

`ptrdiff_t` is signed; the difference of two pointers into a giant object can overflow it — sizes above `PTRDIFF_MAX` are a portability trap (allocators commonly refuse them for this reason).

## Use-After-Free and Lifetime Violations

**Rule (C17 6.2.4, 7.22.3).** An object's lifetime ends at `free()` (heap), scope exit (automatic), or `realloc` move. After that, dereferencing any pointer to it is UB — and the pointer *value itself* becomes indeterminate, so even `if (p == old)` is UB. Lifetime UB variants:

| Variant | Example |
|---|---|
| Heap use-after-free | Access via alias after owner freed |
| Double-free | Two owners both call `free` |
| Use of old pointer after successful `realloc` | `realloc` may move; old value indeterminate |
| Returning the address of a local | `return buf;` where `buf` is automatic |
| Escaped pointer used after scope | Pointer to a block-scope object used after the block |
| Compound literal escape | `int *p = (int){42}...` compound literals have block lifetime, not function |

```c
/* BROKEN: realloc variant — q dangles even though realloc succeeded */
char *q = p + offset;
p = realloc(p, bigger);
use(q);                       /* UB: q points into the old block */
```

**Detection.**

| Flag / option | Catches |
|---|---|
| `-fsanitize=address` | `heap-use-after-free`, `double-free` with alloc/free/use stacks |
| `ASAN_OPTIONS=detect_stack_use_after_return=1` | Returned-local access (default in recent Clang; verify against your toolchain) |
| `-fsanitize-address-use-after-scope` | Use after an inner scope ends |
| `-Wreturn-local-addr` (GCC) / `-Wreturn-stack-address` (Clang) | The direct `return &local;` at compile time |
| Valgrind memcheck | Heap variants on uninstrumented binaries |

**Rewrite.** These are ownership bugs, not pointer bugs. Establish a single owner (parent `SKILL.md`), recompute derived pointers after any `realloc`:

```c
size_t offset = (size_t)(q - p);       /* save the index, not the pointer */
char *tmp = realloc(p, bigger);
if (!tmp) return -1;
p = tmp;
q = p + offset;                        /* re-derive from the new base */
```

For returning buffers: allocate and transfer ownership, take a caller buffer, or use `static` storage with a documented thread-safety caveat — never return automatic storage.

## Uninitialized Reads

**Rule (C17 6.3.2.1, 6.7.9).** Automatic objects start with an indeterminate value. Reading one before assignment is UB in the common case (C17 makes it unconditionally UB for address-never-taken automatics; otherwise the value is indeterminate and trap representations make it UB on some targets). `malloc` memory is likewise uninitialized; `calloc` zeroes.

```c
/* BROKEN */
int flags;                  /* never set on the error path */
if (parse(&flags) < 0) log_flags(flags);    /* reads garbage */

struct config c;
send(fd, &c, sizeof c, 0);  /* leaks stack garbage in padding + unset fields */
```

**Detection.**

| Tool | Coverage |
|---|---|
| `-fsanitize=memory` (MSan) | Bit-exact tracking; Clang-only, Linux-only, **every** linked object must be instrumented |
| Valgrind memcheck | Same class, no rebuild needed, ~20x slower |
| `-Wuninitialized` / `-Wmaybe-uninitialized` | Cheap compile-time subset — fix all of these first |
| `-ftrivial-auto-var-init=pattern` (or `=zero`) | Not a detector: hardening that replaces garbage with a deterministic fill |

**Rewrite.** Initialize at declaration; for structs use designated initializers or `= {0}`:

```c
struct config c = {0};            /* all members zero; padding still unspecified */
int flags = 0;
```

For buffers crossing a trust boundary (network, IPC, disk), `memset` the whole struct before filling fields — `= {0}` does not guarantee padding bytes are zeroed.

## Null Pointer Dereference

**Rule (C17 6.5.3.2).** Dereferencing a null pointer is UB — not a guaranteed segfault. The optimizer may delete a null check that appears *after* a dereference on the same path; with the check gone, downstream code runs with a wild assumption.

```c
/* BROKEN: check is dead code — deref already "proved" p != NULL */
int len = strlen(p->name);
if (!p) return -1;
```

**Detection.** `-fsanitize=null` pinpoints the exact dereference site; plain ASan shows `SEGV on unknown address 0x0...` with a stack. `-Wnull-dereference` (GCC) catches simple static cases.

**Rewrite.** Check before first use; for API entry points, decide and document whether NULL is a contract violation (assert) or a runtime condition (error return):

```c
int widget_rename(widget *w, const char *name) {
    if (!w || !name) return -EINVAL;     /* runtime condition: report */
    ...
}
```

`free(NULL)` and (C23) `nullptr` comparisons are fine; the bug class is *dereference*, not mention.

## Misaligned Access

**Rule (C17 6.3.2.3).** Converting a pointer to a type with stricter alignment than the actual object is UB at the *conversion*, before any dereference. On x86 a misaligned load usually works (slowly); on ARM with certain instructions, or with vectorized code the compiler emits assuming alignment, it faults.

```c
/* BROKEN: buf + 3 has no guarantee of uint32_t alignment */
uint32_t value = *(uint32_t *)(buf + 3);
```

**Detection.** `-fsanitize=alignment` (UBSan). Real hardware faults appear as `SIGBUS` on strict targets.

**Rewrite.** `memcpy` through; compilers compile it to a single unaligned load where legal:

```c
uint32_t value;
memcpy(&value, buf + 3, sizeof value);          /* defined, optimal codegen */
```

For deliberately over-aligned objects use `alignas` / `aligned_alloc` — see `allocators-and-arenas.md`.

## Strict Aliasing Violations

**Rule (C17 6.5p7).** An object may be accessed only through an lvalue of a compatible type, a `char`-family type, or a union member. Accessing a `float` through an `int *` ("type punning by cast") is UB; the optimizer's type-based alias analysis (TBAA) assumes differently-typed pointers do not alias and reorders or caches loads accordingly.

```c
/* BROKEN: the canonical fast-inverse-sqrt pun */
float f = 1.5f;
uint32_t bits = *(uint32_t *)&f;     /* UB: int-typed read of a float object */
```

**Detection — the weak spot.** No production sanitizer reliably catches aliasing UB. `-Wstrict-aliasing` (GCC, at `-O2`) flags only blatant cases; TypeSanitizer exists in newer LLVM but is experimental — verify against your toolchain. Symptom-based diagnosis: code breaks at `-O2` but works with `-fno-strict-aliasing`.

**Rewrite.** Three legal forms, in order of preference:

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

`-fno-strict-aliasing` is a legitimate project-wide mitigation (the Linux kernel uses it) but costs optimization and must be applied to every TU — treat it as policy, not a spot fix. `__attribute__((may_alias))` is the per-type GCC/Clang escape hatch.

## Sequencing Violations

**Rule (C17 6.5p2).** If a side effect on a scalar is unsequenced relative to another side effect on, or a value computation using, the same scalar — UB. C11's "sequenced before" wording replaced C99 sequence points, but the classic examples are still undefined:

```c
/* BROKEN */
i = i++ + 1;            /* two unsequenced modifications of i */
a[i] = i++;             /* read of i for indexing unsequenced vs i++ */
f(i++, i++);            /* argument evaluations unsequenced */
printf("%d %d", x, x = 5);   /* same scalar read and written */
```

Note: function calls *are* sequenced internally (the call is indeterminately sequenced, not unsequenced), so `f(g(), h())` is unspecified order but not UB.

**Detection.** Compile-time only: `-Wsequence-point` (GCC), `-Wunsequenced` (Clang). No sanitizer catches the general case — treat the warnings as errors.

**Rewrite.** One modification per statement:

```c
i++;
a[i] = old_i_value;     /* state the order you mean explicitly */
```

## Invalid Function Pointer Calls

**Rule (C17 6.3.2.3p8).** Calling a function through a pointer whose type is incompatible with the function's actual type is UB. The classic offender is the "convenient cast" of a callback:

```c
/* BROKEN: comparator takes strongly-typed args, qsort wants (const void*, const void*) */
int cmp_int(const int *a, const int *b) { return (*a > *b) - (*a < *b); }
qsort(arr, n, sizeof *arr, (int (*)(const void *, const void *))cmp_int);
```

This "works" on conventional ABIs, breaks under control-flow-integrity hardening (`-fsanitize=cfi`, Apple/Windows arm64e pointer authentication), and is real UB everywhere.

**Detection.**

| Flag | Catches |
|---|---|
| `-fsanitize=function` (UBSan) | Indirect call through wrong-typed pointer (Clang; C support is recent — verify against your toolchain) |
| `-fsanitize=cfi-icall` (Clang, needs LTO) | Same class as a production control-flow defense |
| `-Wcast-function-type` (GCC 8+/Clang) | The suspicious cast at compile time |

**Rewrite.** Match the expected signature and cast the *data* pointers inside:

```c
int cmp_int(const void *pa, const void *pb) {
    const int *a = pa, *b = pb;
    return (*a > *b) - (*a < *b);
}
qsort(arr, n, sizeof *arr, cmp_int);          /* no function cast anywhere */
```

C23 note: `void f();` now means `void f(void)` — the old "unspecified parameters" escape hatch that masked mismatched calls is gone, so prototypes mismatching their callers surface as hard errors when you move to C23. Fix the prototypes rather than casting around the errors.

## Const and String Literal Violations

**Rule (C17 6.4.5p7, 6.7.3p6).** Modifying a string literal is UB — literals have type `char[N]` in C (not `const char[N]` as in C++), so the compiler will not stop you. Likewise, casting away `const` and writing through it is UB when the underlying object was defined `const`.

```c
/* BROKEN: both compile cleanly in C */
char *name = "tmpXXXXXX";
mktemp(name);                         /* writes into .rodata: SIGSEGV or silent corruption */

const int limit = 100;
*(int *)&limit = 200;                 /* UB: object defined const */
```

**Detection.** Usually a `SIGSEGV` on write to a read-only page — but only if the literal landed in `.rodata`; small or merged literals may silently corrupt siblings. `-Wwrite-strings` makes literals `const char[]` at compile time and turns every such assignment into a warning. No sanitizer targets this class directly.

**Rewrite.** Own the buffer when you intend to write:

```c
char name[] = "tmpXXXXXX";            /* array copy on the stack: writable */
```

Adopt `-Wwrite-strings` in new code, and treat any `(char *)` cast of a literal or of a `const`-qualified API return as a review finding. Casting away `const` is legal only when the original object was *not* const-defined and you can prove it — document that proof at the cast site.

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
| `memset(p, 0, n)` with `p == NULL` even when `n == 0` | UB pre-C2y direction; treat as forbidden | UBSan `nonnull-attribute` | Skip the call when the buffer is absent |

The last row generalizes: passing NULL to any string/memory function that does not document accepting it is UB **even with a zero length** under C17 — guard the degenerate case. (Standard direction here is evolving; keep the guard for portability.)

## Data Races

**Rule (C17 5.1.2.4).** Two conflicting accesses to the same memory location from different threads, at least one a write, neither atomic, with no happens-before ordering: UB — not "stale value", full UB, including torn reads and miscompiled loops.

```c
/* BROKEN: flag polling without atomics */
bool done = false;
/* thread A */ while (!done) { work(); }     /* may be hoisted to if(!done) for(;;) */
/* thread B */ done = true;
```

**Detection.** `-fsanitize=thread` (TSan). TSan is mutually exclusive with ASan/MSan — dedicated build. Slowdown ~5-15x, memory ~5-10x.

**Rewrite.** `_Atomic` flags or proper locking:

```c
#include <stdatomic.h>
atomic_bool done = false;
/* A */ while (!atomic_load_explicit(&done, memory_order_acquire)) work();
/* B */ atomic_store_explicit(&done, true, memory_order_release);
```

Full treatment — atomics, memory orders, pthreads patterns — lives in the `modern-c` skill's `c-concurrency-atomics` reference; this catalog only fixes the classification: a race is UB, so "it works on x86" proves nothing.

## Loop Termination Assumptions

**Rule (C17 6.8.5p6).** An iteration statement whose controlling expression is **not** a constant expression, and which performs no I/O, no volatile access, no atomic or synchronization operation, may be assumed by the implementation to terminate. A computation-only spin loop can therefore be removed entirely. (Unlike C++, C exempts loops with constant controlling expressions — `while (1) {}` is safe in C.)

```c
/* BROKEN as a "wait": may be deleted at -O2 */
while (g_not_ready) { }          /* plain global, no atomics */
```

**Detection.** None at runtime; symptom is a loop that vanishes from the disassembly.

**Rewrite.** Make the loop observable: atomic load (see Data Races), `volatile` for hardware registers, or a real blocking primitive (condition variable, futex).

## Recommended Build Profiles

### Development and CI (functional tests)

```sh
CFLAGS="-O1 -g -fno-omit-frame-pointer \
        -fsanitize=address,undefined \
        -fsanitize-address-use-after-scope \
        -fno-sanitize-recover=all \
        -Wall -Wextra -Werror"
ASAN_OPTIONS=detect_stack_use_after_return=1:strict_string_checks=1:check_initialization_order=1
UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1
```

ASan and UBSan combine in one build; expect ~2x slowdown. `-O1` keeps stacks readable while exercising enough optimization to trigger UB-dependent transforms; run at least one CI leg at `-O2` with the same sanitizers.

### Dedicated legs (cannot combine with the above)

| Leg | Flags | Purpose |
|---|---|---|
| TSan | `-fsanitize=thread -O1 -g` | Data races; separate build dir |
| MSan | `-fsanitize=memory -fsanitize-memory-track-origins -O1 -g` | Uninitialized reads; Clang/Linux, all deps instrumented — often impractical, Valgrind is the pragmatic substitute |
| Valgrind | uninstrumented `-O0 -g` build | Third-party binaries, MSan substitute |

### Production hardening (not detection)

```sh
-O2 -D_FORTIFY_SOURCE=3 -fstack-protector-strong \
-ftrivial-auto-var-init=zero -fPIE -pie -Wl,-z,relro,-z,now
```

`-D_FORTIFY_SOURCE=3` needs `-O2`; level 3 on GCC 12+/Clang with recent glibc — verify against your toolchain. Linker rows (`relro`, `now`, PIE) apply to ELF targets; macOS Mach-O hardening differs.

### Triage order when a report fires

1. First report only — `halt_on_error` makes this automatic.
2. Classify against this catalog by report header or UBSan check name.
3. Apply the *rewrite* for the class, not a suppression.
4. Re-run the whole suite; one UB instance frequently masks the next.
5. Suppression files (`ASAN_OPTIONS=suppressions=`, `-fsanitize-blacklist=`) are for third-party code you cannot patch — never for your own.

## UBSan Check Name Index

Map the check name printed in a `runtime error:` line back to the section that explains it:

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

ASan report headers (`heap-use-after-free`, `heap-buffer-overflow`, `stack-use-after-return`, `double-free`, `alloc-dealloc-mismatch`, leak summaries) are indexed with fixes in the parent `SKILL.md` diagnostic table.
