---
name: embedded-systems
description: >-
  Language-agnostic embedded and bare-metal core for C and C++: freestanding
  vs hosted environments, memory-mapped I/O and register access, correct
  volatile semantics (and why volatile is not concurrency), interrupt service
  routines and startup/crt0, no-heap static and arena allocation, fixed-point
  arithmetic, linker scripts, and cross-compilation toolchains. Use when
  targeting a microcontroller or bare-metal, accessing hardware registers,
  writing ISRs, removing the heap, or bringing up a cross-compiler.
---

# Embedded Systems (Bare-Metal Core)

**Freestanding C/C++ on constrained targets: registers, interrupts, startup, no heap**

## When to Use

- Targeting a microcontroller or bare-metal system with no OS and no full libc
- Accessing hardware peripherals through memory-mapped registers
- Writing interrupt service routines and sharing state with `main`
- Removing dynamic allocation from a constrained target
- Replacing floating point with fixed-point arithmetic
- Bringing up a cross-compiler, linker script, or startup code

This skill is language-agnostic — it applies to C and to the C subset of C++.
For C++-specific constraints (`-fno-exceptions -fno-rtti`, RAII without
unwinding, ROM-able objects), use [embedded-cpp](../embedded-cpp/SKILL.md).

## Freestanding vs Hosted (start here)

Every embedded decision flows from which **execution environment** the C/C++
standard guarantees you. Hosted assumes an OS and a complete library; a
freestanding (bare-metal) target gives you almost none of it.

| Aspect | Hosted (`__STDC_HOSTED__ == 1`) | Freestanding (`__STDC_HOSTED__ == 0`) |
|--------|--------------------------------|---------------------------------------|
| Entry point | `main()` called by the runtime | Reset handler you write; `main` is just a function |
| Standard library | Complete (`stdio`, `malloc`, `time`, threads) | Only the **freestanding headers** are guaranteed |
| `malloc`/`free` | Provided | Not provided unless you (or newlib + `_sbrk`) supply it |
| I/O | `printf`, files, sockets | None — you write to registers/UART yourself |
| OS services | Processes, files, signals | None |

**Freestanding-guaranteed headers** (usable with `-ffreestanding`, no OS):
`<stddef.h>`, `<stdint.h>`, `<stdbool.h>`, `<stdalign.h>`, `<stdarg.h>`,
`<stdnoreturn.h>`, `<float.h>`, `<limits.h>`, `<iso646.h>`, and C11+
`<stdatomic.h>`. Everything else (`<stdio.h>`, `<stdlib.h>`, `<string.h>`,
`<math.h>`) is hosted-only in principle — though most toolchains ship usable
freestanding `<string.h>`/`<stdlib.h>` subsets via newlib. **Assume nothing;
verify what your libc actually provides.**

```c
#if __STDC_HOSTED__ == 0
/* No printf, no malloc unless we provide them. */
#endif
```

```sh
-ffreestanding   # tell the compiler main() may not exist and libc may be absent
-fno-builtin     # do not assume libc semantics for memcpy/printf/etc.
-nostdlib        # do not link the standard startup files or libc
-nostartfiles    # keep libc but supply your own crt0/startup
```

`-ffreestanding` also stops the compiler from "recognizing" library functions
and rewriting your loops into a `memcpy` call that does not exist on the
target. See the **freestanding caveat** beside each topic below.

## Memory-Mapped I/O and Register Access

Peripherals are registers at fixed addresses. The access **must** be `volatile`
so the compiler never caches, reorders within the access, or elides a read
whose only effect is on hardware.

```c
#include <stdint.h>

/* One register, the verbose-but-correct way: */
#define UART0_DR (*(volatile uint32_t *)0x4000C000u)
UART0_DR = 'A';                 /* every write reaches the device */

/* A peripheral block as a volatile struct (preferred): */
typedef struct {
    volatile uint32_t DR;       /* 0x00 data */
    volatile uint32_t SR;       /* 0x04 status */
    volatile uint32_t CR;       /* 0x08 control */
} uart_regs;
#define UART0 ((uart_regs *)0x4000C000u)

while (!(UART0->SR & SR_TXE)) { } /* poll: volatile read each iteration */
UART0->DR = byte;
```

- **`volatile` qualifies the pointed-to register, not the pointer.** The
  hardware word is what must not be cached.
- **Match the access width** the peripheral expects (byte/half/word). A 32-bit
  register written as four bytes may misbehave; pick the type deliberately.
- **Read-modify-write is not atomic** against interrupts or other masters —
  disable the interrupt, or use a bit-band / set-clear register if the device
  provides one.
- **Avoid bit-fields for hardware registers**: bit-field layout, ordering, and
  access width are implementation-defined. Use explicit masks and shifts.

`volatile` orders accesses *to the same volatile object* relative to each
other, but does **not** insert CPU memory barriers — on a core with a store
buffer or weak ordering, a write to a peripheral and a later write to RAM can
still be observed out of order by DMA or another master. Add the right barrier
(`__DMB()`/`__DSB()` on ARM) when ordering across objects matters. Full
treatment: [references/mmio-and-registers.md](references/mmio-and-registers.md).

## volatile: What It Is and Is Not

`volatile` means "this object may change, or have side effects, outside the
visible program flow — re-read it every time, write it every time, never
optimize the access away." That is exactly right for **MMIO registers**,
**variables shared with an ISR**, and **`setjmp`/`longjmp`-modified locals**.

**`volatile` does NOT provide:**

- **Atomicity** — a `volatile uint32_t` read-modify-write is still three steps
  an interrupt can split.
- **Inter-thread / inter-core ordering** — it issues no CPU memory barriers and
  establishes no happens-before relationship.
- **A concurrency primitive** — it is not a substitute for atomics or a lock.

For an ISR sharing a multi-byte or compound value with `main`, `volatile`
alone is insufficient: use `_Atomic`/`std::atomic` (which on a single core
compiles to plain loads/stores plus the needed compiler barriers), or briefly
mask the interrupt around the access. The concurrency/ordering rules live in
the C and C++ atomics material —
[c-concurrency-atomics](${CLAUDE_SKILL_DIR}/c/modern-c/references/c-concurrency-atomics.md)
and
[atomics-and-memory-model](${CLAUDE_SKILL_DIR}/cpp/cpp-concurrency/references/atomics-and-memory-model.md).

```c
/* WRONG on its own: torn reads and lost updates across an ISR boundary. */
volatile uint32_t event_count;

/* RIGHT: atomic for the data race, volatile only where it is truly MMIO. */
#include <stdatomic.h>
atomic_uint event_count;        /* ISR: atomic_fetch_add(&event_count, 1); */
```

A single `volatile sig_atomic_t flag` set by an ISR and polled by `main` is the
one classic case where `volatile` is *almost* enough on a single core — and
even there, prefer `atomic_bool` for documented ordering. See
[references/interrupts-and-startup.md](references/interrupts-and-startup.md).

## Interrupts and Startup

An ISR runs on hardware events, outside normal control flow. Rules:

- **Keep it short**; do the minimum, set a flag/queue, return. Long ISRs starve
  the system.
- **Share state with `main` only through `volatile` + atomic access** (above),
  or a lock-free ring buffer with a single producer/consumer.
- **No blocking, no `malloc`, no `printf`** inside an ISR.
- **Reentrancy**: if the same ISR can nest, every function it calls must be
  reentrant (no shared mutable statics).

Startup (the `Reset_Handler` / crt0) runs *before* `main` and is responsible
for the C runtime environment the language assumes:

1. Set the stack pointer (often loaded from the vector table by the core).
2. **Copy `.data`** (initialized globals) from its load address in FLASH to its
   run address in RAM.
3. **Zero `.bss`** (zero-initialized globals) — the C standard guarantees
   uninitialized statics are zero; on bare metal *you* must make that true.
4. Run C++ static constructors (`.init_array`) if using C++.
5. Call `main`.

Skip step 2 or 3 and your globals are garbage at `main` entry — a classic
"works in debug, fails in release" bug. Vector tables, the full startup
sequence, and ISR/`main` sharing patterns:
[references/interrupts-and-startup.md](references/interrupts-and-startup.md).

## No-Heap Allocation

Constrained targets often forbid the heap: `malloc` may not exist, can
fragment fatally over a long uptime, and gives non-deterministic timing. Prefer
allocation strategies whose footprint is known at link time.

| Strategy | When | Cost |
|----------|------|------|
| **Static / global objects** | Fixed, known-at-build-time set of objects | Counts against RAM at link time — the linker tells you if it fits |
| **Fixed-capacity containers** | Bounded collections (ring buffers, slot arrays) | Reserve the max; over-provision deliberately |
| **Arena / bump allocator** | Many short-lived allocations sharing one lifetime | One reset frees all; no per-object free |
| **Pool / fixed-block allocator** | Same-size objects, alloc/free in any order | O(1), fragmentation-free, deterministic |
| **`malloc` (newlib `_sbrk`)** | Only if truly needed and uptime is bounded | Fragmentation + non-determinism; size the heap region explicitly |

The arena and pool implementations are identical to the hosted ones — reuse
[allocators-and-arenas](${CLAUDE_SKILL_DIR}/c/c-memory-ownership/references/allocators-and-arenas.md).
The embedded difference is **placement**: the backing storage is a static
array or a dedicated linker-script region, not heap memory.

```c
/* Pool over static storage — no malloc anywhere. */
static uint8_t pool_mem[POOL_N][BLOCK_SZ];   /* lives in .bss, sized at link */
static pool_t  pool;
pool_init(&pool, pool_mem, POOL_N, BLOCK_SZ);
void *p = pool_alloc(&pool);                 /* O(1), returns NULL when full */
```

If you must allow `malloc`, give it a bounded heap region in the linker script
and treat OOM as a hard, handled error — never assume it succeeds.

## Fixed-Point Arithmetic

Many embedded parts have no FPU; `float`/`double` then compile to slow,
flash-hungry software-emulation calls. Fixed-point keeps fractional math in
integers with an implied scale (Q-format).

```c
typedef int32_t q16_16;                       /* 16 integer, 16 fractional bits */
#define Q16(x)        ((q16_16)((x) * 65536.0))      /* compile-time literal only */
#define Q16_MUL(a, b) ((q16_16)(((int64_t)(a) * (b)) >> 16))   /* widen, then shift */
```

- **Widen before multiply**: `int32_t * int32_t` overflows; promote to
  `int64_t`, multiply, then shift back.
- **Pick the scale from the data's range and precision needs**, and keep it
  consistent across an expression.
- **Saturate** at boundaries instead of wrapping where wraparound is a hazard.

Scaling, rounding, division, the software-float cost model, and float-free
`printf`: [references/fixed-point-and-no-float.md](references/fixed-point-and-no-float.md).

## Linker Scripts and Cross-Compilation

The linker script maps your sections (`.text`, `.data`, `.bss`, `.rodata`,
vectors) onto the chip's physical memory (FLASH at one address, RAM at
another), and exports the symbols (`_sdata`, `_edata`, `_sbss`, `_ebss`,
`_estack`) that startup code uses to copy `.data` and zero `.bss`.

```ld
MEMORY {
  FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 256K
  RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}
/* .text/.rodata -> FLASH; .data has LMA in FLASH, VMA in RAM; .bss in RAM */
```

Cross-compilation runs a host compiler that emits target code:
`arm-none-eabi-gcc` (the `none` = no OS, the bare-metal triple), with
**newlib** or the smaller **newlib-nano** as the C library and a **sysroot**
holding target headers and libs. `newlib-nano` (`--specs=nano.specs`) trades a
float-`printf` and some features for far less flash. Memory regions, section
placement, `.noinit`, heap/stack sizing, triples, sysroots, and the newlib
syscall stubs (`_sbrk`, `_write`, `_exit`):
[references/linker-scripts-and-memory.md](references/linker-scripts-and-memory.md).

Toolchain/standard minimums are canonical in
[version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md);
expressing a cross toolchain in CMake/Meson is in
[build-systems](${CLAUDE_SKILL_DIR}/tooling/build-systems/SKILL.md).

## Diagnostics

| Symptom | Cause | Fix | Reference |
|---------|-------|-----|-----------|
| Register write has no effect / reads stale | Access not `volatile`, optimized away or cached | `volatile` on the register type; verify access width | [mmio-and-registers.md](references/mmio-and-registers.md) |
| Peripheral write reaches device after a later RAM write | `volatile` orders same-object only, not across objects | Insert `__DMB()`/`__DSB()` barrier between the accesses | [mmio-and-registers.md](references/mmio-and-registers.md) |
| ISR and `main` see different values of a shared var | Shared state `volatile` but not atomic, or not even `volatile` | `_Atomic`/`atomic_*`, or mask the interrupt around the access | [interrupts-and-startup.md](references/interrupts-and-startup.md) |
| Torn read of a 32/64-bit shared value | Multi-step access split by an interrupt | Atomic access, or critical section | [interrupts-and-startup.md](references/interrupts-and-startup.md) |
| Globals are garbage at `main` entry | crt0 did not zero `.bss` or copy `.data` | Fix startup `.data` copy and `.bss` zero loops | [interrupts-and-startup.md](references/interrupts-and-startup.md) |
| Hard fault on first interrupt | Vector table missing, misaligned, or wrong address | Place vectors at the reset address; align per the core | [interrupts-and-startup.md](references/interrupts-and-startup.md) |
| `region 'FLASH'/'RAM' overflowed by N bytes` | Sections exceed the memory region | Shrink code/data, `-Os`/`--gc-sections`, resize region | [linker-scripts-and-memory.md](references/linker-scripts-and-memory.md) |
| `undefined reference to '_sbrk'/'_write'/'_exit'` | newlib syscall stubs not provided | Add minimal syscall stubs or `--specs=nosys.specs` | [linker-scripts-and-memory.md](references/linker-scripts-and-memory.md) |
| Image far larger than expected | float `printf`, libc, or compiler-inserted `memcpy` pulled in | `newlib-nano`, `-ffreestanding -fno-builtin`, `--gc-sections` | [linker-scripts-and-memory.md](references/linker-scripts-and-memory.md) |
| Math is slow / pulls in `__aeabi_fmul` etc. | Software float on an FPU-less part | Convert to fixed-point | [fixed-point-and-no-float.md](references/fixed-point-and-no-float.md) |
| Heap fragments / `malloc` returns NULL over uptime | Dynamic allocation on a long-running constrained target | Switch to static/arena/pool allocation | this file, No-Heap Allocation |

## Deep-Dive References

- [references/mmio-and-registers.md](references/mmio-and-registers.md) — register maps, bit-field hazards, RMW, write-1-to-clear, barriers vs caches/store buffers
- [references/interrupts-and-startup.md](references/interrupts-and-startup.md) — vector tables, ISR reentrancy, `volatile`+atomic sharing, crt0, `.data`/`.bss` init
- [references/linker-scripts-and-memory.md](references/linker-scripts-and-memory.md) — `MEMORY`/`SECTIONS`/symbols, placement, stack/heap, cross-toolchains, newlib stubs
- [references/fixed-point-and-no-float.md](references/fixed-point-and-no-float.md) — Q-format, scaling/rounding, widening multiply, saturation, software-float cost, float-free printf

## Related Skills

- [embedded-cpp](../embedded-cpp/SKILL.md) — C++ on the same targets: RAII without exceptions/RTTI, freestanding stdlib, ROM-able data
- [c-memory-ownership](${CLAUDE_SKILL_DIR}/c/c-memory-ownership/SKILL.md) — arena/pool allocators reused over static storage on no-heap targets
- [modern-c](${CLAUDE_SKILL_DIR}/c/modern-c/SKILL.md) — `_BitInt`, fixed-width types, and `<stdatomic.h>` used heavily in embedded
- [c-concurrency-atomics](${CLAUDE_SKILL_DIR}/c/modern-c/references/c-concurrency-atomics.md) — atomics/memory orders for the ISR-sharing problem `volatile` does not solve
- [build-systems](${CLAUDE_SKILL_DIR}/tooling/build-systems/SKILL.md) — cross-compile toolchain files and linker-flag wiring in CMake/Meson
- [version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md) — canonical toolchain/standard minimums
```