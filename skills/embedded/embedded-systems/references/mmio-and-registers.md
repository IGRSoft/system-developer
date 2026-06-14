# Memory-Mapped I/O and Register Access

Use this when:

- You are reading or writing hardware peripheral registers.
- You need a correct, portable register-map definition.
- A register access "does nothing", reads stale, or ordering is wrong.

Skip this file if:

- Your question is about `volatile` semantics in general or ISR sharing. Use
  [interrupts-and-startup.md](interrupts-and-startup.md).
- You are placing the peripheral region in memory. Use
  [linker-scripts-and-memory.md](linker-scripts-and-memory.md).

Jump to:

- Why volatile, Precisely
- Defining a Register Map
- Access Width Matters
- Bit-Fields Are a Trap
- Read-Modify-Write and Atomicity
- Write-1-to-Clear and Read-to-Clear
- Ordering: volatile vs Memory Barriers
- DMA and Cache Coherency
- Pitfalls

## Why volatile, Precisely

A peripheral register is not normal memory: reading it can have side effects
(clearing a flag), its value can change with no store from your program (a
status bit the hardware sets), and a write must actually be issued (it commands
the device). The compiler, left to optimize normal memory, would cache the
value in a register, drop a "redundant" second read, or hoist a write out of a
loop. `volatile` forbids all three for accesses to that object:

- every read in the source becomes a real load,
- every write becomes a real store,
- the compiler does not reorder volatile accesses **relative to each other**.

```c
uint32_t status = REG;          /* must load from the device, not reuse a cache */
while (REG & BUSY) { }          /* must re-load REG every iteration */
REG = CMD_START;                /* must store, even if REG is never read after */
```

Without `volatile`, the `while` can become an infinite loop on a stale cached
value, and the final store can be deleted as dead.

## Defining a Register Map

Two correct idioms. Prefer the struct form for a peripheral block.

```c
#include <stdint.h>

/* Single register macro: cast a literal address to a volatile pointer. */
#define GPIOA_ODR (*(volatile uint32_t *)0x48000014u)

/* Peripheral block as a volatile struct at a base address (preferred): */
typedef struct {
    volatile uint32_t MODER;    /* 0x00 */
    volatile uint32_t OTYPER;   /* 0x04 */
    volatile uint32_t OSPEEDR;  /* 0x08 */
    volatile uint32_t PUPDR;    /* 0x0C */
    volatile uint32_t IDR;      /* 0x10 input  - read-only in hardware */
    volatile uint32_t ODR;      /* 0x14 output */
} gpio_regs;

#define GPIOA ((gpio_regs *)0x48000000u)
GPIOA->ODR |= (1u << 5);        /* set pin 5 */
```

- **`volatile` goes on each member** (or the access), qualifying the register
  word — not the pointer. `gpio_regs *` is an ordinary pointer to volatile data.
- **Offsets must match the datasheet exactly.** Insert `volatile uint32_t
  reserved[N];` (or named `RESERVEDx`) for gaps so later members land at the
  right offset. `static_assert(offsetof(gpio_regs, ODR) == 0x14, "layout");`
  catches drift at compile time.
- **Mark read-only and write-only registers** with `const volatile` (read-only
  status/input) where it helps the compiler and the reader; a write to a
  `const volatile` is then a compile error.

## Access Width Matters

Many peripherals require a specific access size; an 8-bit write to a 32-bit
control register, or a 32-bit write split into bytes, can corrupt the device or
trigger a bus fault. The C type you choose **is** the access width:

```c
*(volatile uint8_t  *)addr = v;   /* byte (strb) */
*(volatile uint16_t *)addr = v;   /* half-word (strh) */
*(volatile uint32_t *)addr = v;   /* word (str) */
```

Pick the type that matches the datasheet's documented access size. Do not
`memcpy` into a register region — `memcpy` is free to use any width and to
split or merge accesses.

## Bit-Fields Are a Trap

Do **not** model hardware registers with C bit-fields:

```c
struct bad { uint32_t en:1; uint32_t mode:2; uint32_t :29; };  /* DON'T */
```

Bit-field allocation order (LSB-first vs MSB-first), straddling, padding, and
the access width the compiler chooses are all implementation-defined. The
compiler may read-modify-write the whole word, or access it at the wrong size,
in ways the datasheet never sanctions. Use explicit masks and shifts:

```c
#define MODE_Pos   1u
#define MODE_Msk   (0x3u << MODE_Pos)
reg = (reg & ~MODE_Msk) | ((val << MODE_Pos) & MODE_Msk);
```

## Read-Modify-Write and Atomicity

`reg |= BIT;` is **read, OR, write** — three steps. If an interrupt (or another
bus master) modifies the same register between the read and the write, the
update is lost. `volatile` does not help: it guarantees each access happens, not
that the trio is indivisible.

Options, in order of preference:

1. **Set/clear registers**: many devices expose `BSRR`-style write-1-to-set and
   write-1-to-clear registers so a single write changes one bit without RMW.
2. **Bit-banding** (Cortex-M3/M4): an aliased address region where each word
   maps to one bit, making single-bit updates atomic.
3. **Critical section**: disable the interrupting source (or all interrupts)
   around the RMW, then restore.

```c
GPIOA->BSRR = (1u << 5);          /* atomic set of pin 5, no RMW */
GPIOA->BSRR = (1u << (5 + 16));   /* atomic clear of pin 5 */
```

## Write-1-to-Clear and Read-to-Clear

Status/flag registers often clear differently than you write data:

- **Write-1-to-clear (W1C)**: write a 1 to the bit to clear it; writing 0 leaves
  it. A read-modify-write `SR &= ~FLAG` is wrong here — it writes 1s back to
  *other* pending flags and clears them too. Write only the bit you mean to
  clear: `SR = FLAG;`.
- **Read-to-clear (RC)**: reading the register clears the flag as a side effect.
  A "harmless" extra read in a debugger or a logging line can lose an event.
  This is exactly why the access must be `volatile` and why you must not add
  speculative reads.

## Ordering: volatile vs Memory Barriers

`volatile` orders volatile accesses **to the same and other volatile objects**
in program order *as the compiler emits them* — but it issues **no CPU memory
barrier**. On a core with a write buffer or weak memory ordering:

- a peripheral write may still be sitting in the store buffer when a later,
  non-volatile RAM write becomes visible to DMA or another master;
- enabling a peripheral and then immediately using it may race the device's
  internal latching.

When ordering must hold across the bus or against non-volatile memory, insert an
explicit barrier:

```c
PERIPH->CR = ENABLE;
__DSB();        /* drain the store buffer: the enable is visible before... */
start_dma();    /* ...DMA begins reading the buffer */
```

- `__DMB()` — data memory barrier: orders memory accesses before/after it.
- `__DSB()` — data synchronization barrier: also waits for completion.
- `__ISB()` — instruction sync barrier: after changing config that affects
  fetched instructions (e.g., remapping memory, enabling the FPU).

These are CMSIS intrinsics on ARM; other architectures have equivalents. The
compiler-level analogue (`atomic_signal_fence`, `__asm__ volatile("":::"memory")`)
stops compiler reordering but emits no hardware barrier — you often need both.

## DMA and Cache Coherency

On parts with a data cache (Cortex-M7, application cores), a buffer the CPU
filled may sit in cache while DMA reads stale RAM, or DMA may write RAM the CPU
later reads from cache:

- **Before DMA reads a CPU-written buffer**: clean (write back) the cache lines.
- **After DMA writes a buffer the CPU will read**: invalidate the cache lines.
- Or place DMA buffers in a **non-cacheable** MPU region and avoid the dance.

`volatile` does nothing for cache coherency — it is a compiler directive, not a
cache operation. Use the cache-maintenance intrinsics (`SCB_CleanDCache_by_Addr`,
`SCB_InvalidateDCache_by_Addr`) and align/size buffers to the cache line.

## Pitfalls

| Pitfall | Consequence | Fix |
|---------|-------------|-----|
| Register pointer not `volatile` | Reads cached, writes elided, polling hangs | `volatile` on the register type |
| Bit-fields for a register map | Wrong layout/width, RMW of the whole word | Explicit masks and shifts |
| `SR &= ~FLAG` on a W1C register | Clears other pending flags too | Write only the target bit: `SR = FLAG;` |
| Speculative/extra read of an RC register | Silently consumes an event | Read once, deliberately; no debug reads |
| RMW on a register shared with an ISR | Lost update | Set/clear register, bit-band, or critical section |
| Relying on `volatile` for cross-object ordering | Out-of-order vs DMA/other master | Add `__DMB()`/`__DSB()` |
| DMA buffer in cacheable memory, no maintenance | Stale data both directions | Clean/invalidate, or non-cacheable region |
| Wrong access width | Bus fault or partial register update | Match the datasheet's documented size via the C type |

Cross-references: ISR/`main` sharing and the `volatile`+atomic rule in
[interrupts-and-startup.md](interrupts-and-startup.md); placing the peripheral
and DMA regions in
[linker-scripts-and-memory.md](linker-scripts-and-memory.md); the memory model
behind barriers in
[c-concurrency-atomics](${CLAUDE_SKILL_DIR}/c/modern-c/references/c-concurrency-atomics.md).
