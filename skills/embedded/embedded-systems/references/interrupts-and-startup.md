# Interrupts and Startup (ISRs, Vector Tables, crt0)

Use this when:

- You are writing an interrupt service routine or placing a vector table.
- An ISR and `main` disagree on a shared value, or a value tears.
- Globals are garbage at `main` entry, or startup code needs writing.

Skip this file if:

- Your question is register access mechanics. Use
  [mmio-and-registers.md](mmio-and-registers.md).
- You need the atomics/memory-order rules themselves. Use
  [c-concurrency-atomics](${CLAUDE_SKILL_DIR}/c/modern-c/references/c-concurrency-atomics.md).

Jump to:

- Vector Table
- ISR Rules
- Reentrancy
- Sharing State with main: volatile + Atomic
- The Critical-Section Alternative
- Startup: Reset Handler / crt0
- .data, .bss, and What the Standard Promises
- C++ Static Constructors
- Pitfalls

## Vector Table

The vector table is an array of handler addresses (and the initial stack
pointer) at a fixed location the core reads on reset and on each exception. On
Cortex-M it begins at the start of the image: entry 0 is the initial `MSP`,
entry 1 is the reset handler, then the system and peripheral handlers.

```c
extern uint32_t _estack;        /* top of stack, from the linker script */
void Reset_Handler(void);
void Default_Handler(void);
void SysTick_Handler(void);

/* Placed by the linker script into .isr_vector at the image base. */
__attribute__((section(".isr_vector"), used))
void (* const vector_table[])(void) = {
    (void (*)(void))&_estack,   /* 0x00: initial stack pointer */
    Reset_Handler,              /* 0x04: reset */
    NMI_Handler,                /* 0x08 */
    HardFault_Handler,          /* 0x0C */
    /* ... core exceptions ... */
    SysTick_Handler,            /* SysTick */
    /* ... peripheral IRQs ... */
};
```

- The table must be placed at the address the core expects (the linker script
  puts `.isr_vector` first in FLASH) and aligned per the architecture.
- Unused entries point at a `Default_Handler` (often an infinite loop, or one
  that records the active exception number) so a stray interrupt is debuggable,
  not a jump to garbage.
- Handler names are conventionally `weak` aliases of `Default_Handler`; defining
  a function with the same name overrides the weak default — a missing handler
  silently falls back instead of failing to link.

## ISR Rules

- **Short and non-blocking.** Acknowledge the hardware, move the minimum data,
  set a flag or push to a queue, return. Defer real work to `main`/a task.
- **No `malloc`, no `printf`, no blocking calls.** They are slow, may not be
  reentrant, and can deadlock if `main` holds a related lock.
- **Acknowledge the interrupt source** (clear the peripheral flag, often
  write-1-to-clear) or it re-fires immediately on exit.
- **Match the ABI**: on most Cortex-M toolchains a plain C function works as an
  ISR because the core saves caller-saved registers; on other architectures an
  ISR needs a compiler attribute (`__attribute__((interrupt))`) to emit the
  correct prologue/epilogue and return instruction. Know your target's rule.

## Reentrancy

If interrupts can nest (a higher-priority IRQ preempts a lower one) or the same
handler can re-enter, every function reachable from the ISR must be **reentrant**:
no reliance on shared mutable `static`/global state that another invocation
could be midway through modifying, and no non-reentrant library calls. A
function that uses only its arguments and locals is reentrant; one that touches
a shared buffer is not unless that access is itself protected.

## Sharing State with main: volatile + Atomic

This is the defining correctness problem of bare-metal C/C++. An ISR and `main`
share a variable. Three things must hold:

1. **`main` must re-read the variable** the ISR may change — otherwise the
   compiler caches it in a register and never sees the update. This needs
   `volatile` (or an atomic load, which implies it).
2. **The access must not tear.** A 32-bit load/store is single-instruction and
   indivisible on a 32-bit core; a 64-bit value, a struct, or a misaligned
   access can be split, and an interrupt landing mid-access yields a half-updated
   value. This needs **atomicity**, which `volatile` does **not** provide.
3. **Ordering must hold** if the shared value gates other data ("buffer ready,
   now read it"). This needs the acquire/release ordering atomics give and
   `volatile` does not.

```c
#include <stdatomic.h>
#include <stdint.h>

/* A single flag, single core: the one case volatile alone nearly suffices,
   but prefer atomic for documented ordering. */
static volatile sig_atomic_t data_ready;     /* sig_atomic_t: tear-free by spec */

/* A counter or multi-byte value shared with an ISR: atomic, not just volatile. */
static atomic_uint event_count;

void EXTI0_IRQHandler(void) {
    EXTI->PR = EXTI_PR_PR0;                   /* W1C: write ONLY this bit; writing
                                                 ~PR0 would clear every other pending
                                                 line too (see mmio-and-registers.md) */
    atomic_fetch_add_explicit(&event_count, 1, memory_order_relaxed);
    atomic_store_explicit(&data_ready, 1, memory_order_release);
}

void main_loop(void) {
    if (atomic_load_explicit(&data_ready, memory_order_acquire)) {
        unsigned n = atomic_load_explicit(&event_count, memory_order_relaxed);
        atomic_store_explicit(&data_ready, 0, memory_order_relaxed);
        handle(n);                            /* release/acquire orders this after the ISR's writes */
    }
}
```

On a single core, atomics compile to ordinary loads/stores plus the compiler
barriers that stop reordering — there is no lock and essentially no runtime
cost, so there is no reason to use bare `volatile` for shared compound state.
`volatile` remains correct and necessary only for true MMIO and for
`sig_atomic_t` flags. The full rule set, including why `seq_cst` is the safe
default and when relaxed is justified, is in
[c-concurrency-atomics](${CLAUDE_SKILL_DIR}/c/modern-c/references/c-concurrency-atomics.md)
(C) and
[atomics-and-memory-model](${CLAUDE_SKILL_DIR}/cpp/cpp-concurrency/references/atomics-and-memory-model.md)
(C++).

## The Critical-Section Alternative

When the shared operation is genuinely multi-step (update several fields
together, dequeue then mutate), atomics on one variable are not enough — briefly
mask the interrupt:

```c
uint32_t primask = __get_PRIMASK();
__disable_irq();                /* enter critical section */
/* multi-field update that the ISR must not split */
__set_PRIMASK(primask);         /* restore prior state — do NOT blindly enable */
```

- **Save and restore** the prior mask rather than unconditionally re-enabling;
  the caller may already be inside another critical section.
- **Keep it as short as possible** — interrupts are blocked, hurting latency.
- A single-producer/single-consumer **lock-free ring buffer** often removes the
  need for a critical section entirely (ISR produces, `main` consumes, head and
  tail are separate atomics).

## Startup: Reset Handler / crt0

Before `main`, the reset handler (the C runtime startup, historically `crt0`)
must construct the environment the C and C++ standards assume. A minimal
sequence:

```c
extern uint32_t _sdata, _edata, _sidata;   /* .data: RAM start/end, FLASH source */
extern uint32_t _sbss, _ebss;              /* .bss: RAM start/end */
extern int main(void);
extern void __libc_init_array(void);       /* runs C++ .init_array constructors */

void Reset_Handler(void) {
    /* 1. Copy .data from its load address (FLASH) to its run address (RAM). */
    for (uint32_t *src = &_sidata, *dst = &_sdata; dst < &_edata; )
        *dst++ = *src++;

    /* 2. Zero-initialize .bss. */
    for (uint32_t *p = &_sbss; p < &_ebss; )
        *p++ = 0;

    /* 3. Run C++ static constructors (and C __attribute__((constructor))). */
    __libc_init_array();

    /* 4. Hand off to the application. */
    main();

    for (;;) { }                /* main must not return on bare metal */
}
```

The symbols come from the linker script — see
[linker-scripts-and-memory.md](linker-scripts-and-memory.md).

## .data, .bss, and What the Standard Promises

The C standard guarantees that objects with static storage duration are
zero-initialized (or initialized to their initializer) **before `main`**. On a
hosted OS the loader does this. On bare metal there is no loader — *startup code
is what makes the guarantee true*:

- **`.data`** holds statics with a non-zero initializer (`static int x = 7;`).
  The initial values live in FLASH (the **load** address, LMA); they must be
  **copied** into RAM (the **run** address, VMA) at startup. Skip the copy and
  `x` is whatever FLASH-mirrored junk happens to be there.
- **`.bss`** holds statics initialized to zero (`static int y;`,
  `static int z = 0;`). It occupies no space in FLASH; startup must **zero** the
  RAM range. Skip the zeroing and `y` is uninitialized RAM — the classic bug
  where a global "is sometimes zero, sometimes not."
- **`.rodata`** (const data, string literals) stays in FLASH and is read in
  place — no copy needed.
- **`.noinit`** is an optional section for data that must survive a warm reset
  and therefore must *not* be zeroed by startup (place it deliberately; see the
  linker reference).

## C++ Static Constructors

C++ objects with static storage and non-trivial constructors register their
constructors in `.init_array`; `__libc_init_array()` (called from startup) runs
them in order before `main`. If you forget to call it, those objects are never
constructed and you use raw, unconstructed memory. The flip side — the **static
initialization order fiasco** across translation units, and using `constinit`
to force compile-time init that needs no runtime constructor at all — is in
[embedded-cpp](../../embedded-cpp/SKILL.md).

## Pitfalls

| Pitfall | Consequence | Fix |
|---------|-------------|-----|
| Shared var `volatile` but not atomic | Torn reads, lost updates across the ISR | Atomic access, or critical section |
| Shared var neither `volatile` nor atomic | `main` caches a stale value forever | Atomic (preferred) or at least `volatile` |
| Long work or `printf`/`malloc` in an ISR | Latency spikes, deadlock, non-reentrancy bugs | Defer to `main`; ISR sets a flag/queues |
| ISR does not ack the source | Interrupt re-fires immediately, livelock | Clear the peripheral flag (often W1C) |
| Startup skips `.bss` zeroing | Globals are nonzero garbage at `main` | Add the `.bss` zero loop |
| Startup skips `.data` copy | Initialized globals hold FLASH junk | Add the `.data` copy loop |
| `__libc_init_array()` not called (C++) | Static objects never constructed | Call it from `Reset_Handler` before `main` |
| `main` returns on bare metal | Falls off into undefined territory | End `Reset_Handler` in an infinite loop |
| Unconditional `__enable_irq()` to exit a critical section | Re-enables IRQs inside a nested critical section | Save/restore `PRIMASK` |

Cross-references: register acknowledge mechanics in
[mmio-and-registers.md](mmio-and-registers.md); the symbols and section
placement startup depends on in
[linker-scripts-and-memory.md](linker-scripts-and-memory.md); the full
memory-order rationale in
[c-concurrency-atomics](${CLAUDE_SKILL_DIR}/c/modern-c/references/c-concurrency-atomics.md).
