---
name: embedded-systems
description: >-
  Language-agnostic bare-metal core for C and C++: freestanding vs hosted,
  memory-mapped register access, volatile semantics (and why volatile is not
  concurrency), ISRs and startup/crt0, no-heap allocation, fixed-point, linker
  scripts, and cross-compilation. Use when targeting a microcontroller,
  accessing hardware registers, writing ISRs, removing the heap, or bringing up
  a cross-compiler.
---

# Embedded Systems (Bare-Metal Core)

Applies to C and the C subset of C++. For C++-specific constraints (`-fno-exceptions -fno-rtti`, RAII without unwinding, ROM-able objects), use [embedded-cpp](../embedded-cpp/SKILL.md).

## Freestanding vs Hosted

| Aspect | Hosted (`__STDC_HOSTED__ == 1`) | Freestanding (`__STDC_HOSTED__ == 0`) |
|--------|--------------------------------|---------------------------------------|
| Entry point | `main()` called by the runtime | Reset handler you write |
| Library | Complete | Freestanding headers only |
| `malloc`, I/O, OS | Provided | Only what you (or newlib + stubs) supply |

### Freestanding Headers and Flags

C11/C17 guarantee only `<stddef.h>`, `<stdint.h>`, `<stdbool.h>`, `<stdalign.h>`, `<stdarg.h>`, `<stdnoreturn.h>`, `<float.h>`, `<limits.h>`, `<iso646.h>`. GCC and Clang also ship `<stdatomic.h>` as a compiler header. Anything else (`<string.h>`, `<stdlib.h>`) comes from your libc, usually newlib, so check what it provides.

```sh
-ffreestanding   # no hosted assumptions; implies -fno-builtin
-nostdlib        # link neither startup files nor libc
-nostartfiles    # keep libc, supply your own crt0
```

GCC and Clang may still emit calls to `memcpy`, `memmove`, `memset`, and `memcmp` under `-ffreestanding` (struct copies, loops recognized as idioms), so the target must provide them. GCC's `-fno-tree-loop-distribute-patterns` stops the loop rewrite.

## Memory-Mapped I/O and Register Access

Peripherals are registers at fixed addresses, accessed through `volatile` so every read and write reaches the device.

```c
#define UART0_DR (*(volatile uint32_t *)0x4000C000u)   /* single register */

typedef struct {                /* peripheral block (preferred) */
    volatile uint32_t DR;       /* 0x00 data */
    volatile uint32_t SR;       /* 0x04 status */
    volatile uint32_t CR;       /* 0x08 control */
} uart_regs;
#define UART0 ((uart_regs *)0x4000C000u)

while (!(UART0->SR & SR_TXE)) { }   /* re-read every iteration */
UART0->DR = byte;
```

### Register Rules

- `volatile` qualifies the register, not the pointer.
- The C type is the access width; match the datasheet.
- Read-modify-write is not atomic against ISRs or other masters: use set/clear registers, bit-banding, or a critical section.
- Use masks and shifts, not bit-fields (layout and access width are implementation-defined).
- `volatile` keeps volatile accesses in program order but emits no CPU barrier and does not order non-volatile RAM. Add `__DMB()`/`__DSB()` (ARM) when DMA or another master must see writes in order.

Details: [references/mmio-and-registers.md](references/mmio-and-registers.md).

## volatile Is Not Concurrency

`volatile` means "re-read and re-write every access; never optimize it away." That is right for MMIO registers and `setjmp`-modified locals. It gives no atomicity (an interrupt can split a read-modify-write or a 64-bit access) and no ordering between threads, cores, or an ISR and `main`.

```c
volatile uint32_t event_count;  /* wrong: torn reads, lost updates across an ISR */

#include <stdatomic.h>
atomic_uint event_count;        /* right: ISR does atomic_fetch_add(&event_count, 1) */
```

On a single core atomics compile to plain loads/stores plus compiler barriers, so prefer them (or a short interrupt mask) for any state shared with an ISR. Memory-order rules: [c-concurrency-atomics](../../c/modern-c/references/c-concurrency-atomics.md) (C), [atomics-and-memory-model](../../cpp/cpp-concurrency/references/atomics-and-memory-model.md) (C++).

## Interrupts and Startup

ISR rules:

- Keep it short: acknowledge the source, set a flag or queue data, return.
- No blocking, `malloc`, or `printf`.
- Share state with `main` through atomics, a critical section, or a single-producer/single-consumer ring buffer.
- If the ISR can nest, everything it calls must be reentrant.

### Reset Handler Sequence

Order matters:

1. Set the stack pointer (Cortex-M loads it from vector entry 0).
2. Copy `.data` from its FLASH load address to RAM.
3. Zero `.bss`.
4. Run C++ static constructors (`.init_array`), if any.
5. Call `main`; it must not return.

Skipping step 2 or 3 leaves globals as garbage at `main`. Vector tables, ISR sharing patterns, and a full `Reset_Handler`: [references/interrupts-and-startup.md](references/interrupts-and-startup.md).

## No-Heap Allocation

`malloc` may not exist, fragments over long uptime, and has non-deterministic timing. Prefer storage sized at link time:

| Strategy | When |
|----------|------|
| Static objects | Fixed, known set of objects; the linker reports if RAM fits |
| Fixed-capacity containers | Bounded collections (ring buffers, slot arrays) |
| Arena / bump allocator | Many allocations sharing one lifetime; one reset frees all |
| Pool / fixed-block | Same-size objects freed in any order; O(1), no fragmentation |
| `malloc` via newlib `_sbrk` | Only if needed; bound the heap region and handle NULL |

Arena and pool code is the same as hosted ([allocators-and-arenas](../../c/c-memory-ownership/references/allocators-and-arenas.md)); only the backing store changes to a static array or linker-script region.

### Pool Over Static Storage

```c
static uint8_t pool_mem[POOL_N][BLOCK_SZ];   /* .bss, sized at link */
static pool_t  pool;
pool_init(&pool, pool_mem, POOL_N, BLOCK_SZ);
void *p = pool_alloc(&pool);                 /* NULL when full */
```

## Fixed-Point Arithmetic

Without an FPU, `float`/`double` become slow, flash-hungry library calls. Q-format keeps fractions in integers with an implied scale.

```c
typedef int32_t q16_16;                                        /* 16.16 */
#define Q16(x)        ((q16_16)((x) * 65536.0))                /* literals only */
#define Q16_MUL(a, b) ((q16_16)(((int64_t)(a) * (b)) >> 16))   /* widen first */
```

Widen before multiplying, keep one scale per expression, and saturate where wraparound is a hazard. Division, rounding, choosing a format, and float-free `printf`: [references/fixed-point-and-no-float.md](references/fixed-point-and-no-float.md).

## Linker Scripts and Cross-Compilation

The linker script maps sections onto the chip's memory and exports the symbols startup uses (`_sdata`, `_edata`, `_sidata`, `_sbss`, `_ebss`, `_estack`).

```ld
MEMORY {
  FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 256K
  RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}
/* .text/.rodata -> FLASH; .data VMA in RAM, LMA in FLASH; .bss in RAM */
```

`arm-none-eabi-gcc` is the usual bare-metal cross-compiler (`none` = no OS), with newlib or the smaller newlib-nano (`--specs=nano.specs`, no float `printf` by default). Sections, `.noinit`, stack/heap sizing, toolchain flags, and newlib syscall stubs: [references/linker-scripts-and-memory.md](references/linker-scripts-and-memory.md). CMake/Meson toolchain files: [build-systems](../../tooling/build-systems/SKILL.md).

## Diagnostics

### Runtime

| Symptom | Cause | Fix |
|---------|-------|-----|
| Register write has no effect / reads stale | Access not `volatile`, or wrong width | `volatile` register type of the datasheet width |
| DMA sees a RAM write before the peripheral write | No CPU barrier | `__DMB()`/`__DSB()` between them |
| ISR and `main` disagree, or a value tears | Shared state not atomic | Atomics or an interrupt mask |
| Globals garbage at `main` | `.data` not copied or `.bss` not zeroed | Fix the startup loops |
| Hard fault on first interrupt | Vector table missing or misplaced | Place and align it at the reset address |
| `malloc` returns NULL after long uptime | Heap fragmentation | Static, arena, or pool allocation |

### Build and Link

| Symptom | Cause | Fix |
|---------|-------|-----|
| `region 'FLASH'/'RAM' overflowed` | Sections exceed the region | `-Os`, `--gc-sections`, LTO, or resize |
| `undefined reference to '_sbrk'/'_write'/'_exit'` | newlib syscall stubs missing | Write stubs or `--specs=nosys.specs` |
| `undefined reference to 'memcpy'/'memset'` | Compiler-emitted call, no libc | Provide them or link newlib |
| Image far larger than expected | Float `printf`, full libc | newlib-nano, map file, `--gc-sections` |
| `__aeabi_fmul` and similar linked | Software float on an FPU-less part | Fixed-point |

## Related Skills

- [embedded-cpp](../embedded-cpp/SKILL.md) — C++ on the same targets
- [c-memory-ownership](../../c/c-memory-ownership/SKILL.md) — arena and pool allocators
- [modern-c](../../c/modern-c/SKILL.md) — fixed-width types, `_BitInt`, `<stdatomic.h>`
- [build-systems](../../tooling/build-systems/SKILL.md) — cross toolchain files and linker flags
