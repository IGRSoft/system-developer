# Memory-Mapped I/O and Register Access

## Why volatile

A peripheral register is not normal memory: a read can have side effects (clearing a flag), its value changes without a store from your program, and a write commands the device. Left alone, the compiler would cache the value, drop a "redundant" read, or delete a "dead" store. For a `volatile` object:

- every source read is a real load,
- every source write is a real store,
- volatile accesses stay in program order relative to each other.

```c
uint32_t status = REG;          /* loads from the device */
while (REG & BUSY) { }          /* re-loads every iteration */
REG = CMD_START;                /* stores even if never read back */
```

Without `volatile` the loop can spin forever on a cached value and the final store can vanish.

## Defining a Register Map

```c
#include <stdint.h>

#define GPIOA_ODR (*(volatile uint32_t *)0x48000014u)   /* single register */

typedef struct {                /* peripheral block (preferred) */
    volatile uint32_t MODER;    /* 0x00 */
    volatile uint32_t OTYPER;   /* 0x04 */
    volatile uint32_t OSPEEDR;  /* 0x08 */
    volatile uint32_t PUPDR;    /* 0x0C */
    const volatile uint32_t IDR;/* 0x10 input, read-only */
    volatile uint32_t ODR;      /* 0x14 output */
    volatile uint32_t BSRR;     /* 0x18 bit set/reset, write-only */
} gpio_regs;

#define GPIOA ((gpio_regs *)0x48000000u)
GPIOA->ODR |= (1u << 5);        /* set pin 5 (RMW, see below) */
```

### Layout Rules

- `volatile` goes on each member; `gpio_regs *` is an ordinary pointer to volatile data.
- Offsets must match the datasheet. Fill gaps with `volatile uint32_t reserved[N];` and pin them with `static_assert(offsetof(gpio_regs, ODR) == 0x14, "layout");`.
- `const volatile` on read-only registers turns an accidental write into a compile error.

## Access Width

Many peripherals require a specific access size; a byte write to a word register, or a word write split into bytes, can corrupt the device or bus-fault. The C type is the access width:

```c
*(volatile uint8_t  *)addr = v;   /* byte (strb) */
*(volatile uint16_t *)addr = v;   /* half-word (strh) */
*(volatile uint32_t *)addr = v;   /* word (str) */
```

Don't `memcpy` into a register region; it may use any width and split or merge accesses.

## Bit-Fields

Don't model registers with bit-fields: allocation order, straddling, padding, and the access width the compiler picks are implementation-defined, and it may read-modify-write the whole word at a size the datasheet doesn't allow. Use masks and shifts:

```c
#define MODE_Pos   1u
#define MODE_Msk   (0x3u << MODE_Pos)
reg = (reg & ~MODE_Msk) | ((val << MODE_Pos) & MODE_Msk);
```

## Read-Modify-Write and Atomicity

`reg |= BIT;` is read, OR, write. An ISR or other bus master touching the register in between loses its update; `volatile` makes each access happen but not the three indivisible. Options, in order of preference:

1. Set/clear registers (`BSRR`-style): one write changes one bit.
2. Bit-banding (Cortex-M3/M4): an alias region where each word maps to one bit.
3. A critical section around the RMW.

```c
GPIOA->BSRR = (1u << 5);          /* set pin 5, no RMW */
GPIOA->BSRR = (1u << (5 + 16));   /* clear pin 5 */
```

## Write-1-to-Clear and Read-to-Clear

- Write-1-to-clear (W1C): writing 1 clears the bit, 0 leaves it. `SR &= ~FLAG` writes 1s back to other pending flags and clears them too; write only the target bit: `SR = FLAG;`.
- Read-to-clear (RC): reading clears the flag. An extra read from a debugger watch or a log line consumes the event, so read once, deliberately.

## Ordering: volatile vs Memory Barriers

`volatile` orders volatile accesses as the compiler emits them, but issues no CPU barrier and does not order non-volatile memory. On a core with a write buffer or weak ordering, a peripheral write can still be in the store buffer when a later RAM write reaches DMA, and a just-enabled peripheral may not have latched yet.

```c
PERIPH->CR = ENABLE;
__DSB();        /* enable is complete before... */
start_dma();    /* ...DMA starts reading */
```

### ARM Barriers

- `__DMB()`: orders memory accesses before and after it.
- `__DSB()`: also waits for them to complete.
- `__ISB()`: flushes the pipeline after changes that affect instruction fetch (memory remap, enabling the FPU).

These are CMSIS intrinsics; other architectures have equivalents. `atomic_signal_fence` or `__asm__ volatile("" ::: "memory")` stops compiler reordering only and emits no hardware barrier, so you often need both.

## DMA and Cache Coherency

On parts with a data cache (Cortex-M7, application cores):

- Before DMA reads a CPU-written buffer, clean the cache lines.
- After DMA writes a buffer the CPU will read, invalidate them.
- Or put DMA buffers in a non-cacheable MPU region.

`volatile` does nothing for caches. Use the maintenance intrinsics (`SCB_CleanDCache_by_Addr`, `SCB_InvalidateDCache_by_Addr`) and align and size buffers to the cache line.

## Pitfalls

| Pitfall | Fix |
|---------|-----|
| Register access not `volatile` (polling hangs, writes vanish) | `volatile` on the register type |
| Bit-fields for a register map | Masks and shifts |
| `SR &= ~FLAG` on a W1C register | `SR = FLAG;` |
| Extra read of an RC register | Read once, no debug reads |
| RMW on a register an ISR also writes | Set/clear register, bit-band, or critical section |
| `volatile` relied on for ordering against RAM or DMA | `__DMB()`/`__DSB()` |
| Cacheable DMA buffer without maintenance | Clean/invalidate, or non-cacheable region |
| Wrong access width | C type matching the datasheet size |

Memory model behind the barriers: [c-concurrency-atomics](../../../c/modern-c/references/c-concurrency-atomics.md).
