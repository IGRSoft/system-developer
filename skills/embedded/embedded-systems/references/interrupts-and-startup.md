# Interrupts and Startup (ISRs, Vector Tables, crt0)

## Vector Table

An array of handler addresses the core reads on reset and on each exception. On Cortex-M it starts the image: entry 0 is the initial `MSP`, entry 1 the reset handler, then system and peripheral handlers.

```c
extern uint32_t _estack;        /* top of stack, from the linker script */
void Reset_Handler(void), NMI_Handler(void), HardFault_Handler(void);

__attribute__((section(".isr_vector"), used))
void (* const vector_table[])(void) = {
    (void (*)(void))&_estack,   /* 0x00: initial stack pointer */
    Reset_Handler,              /* 0x04 */
    NMI_Handler,                /* 0x08 */
    HardFault_Handler,          /* 0x0C */
    /* ... core exceptions, SysTick_Handler, peripheral IRQs ... */
};
```

### Placement and Defaults

- The linker script puts `.isr_vector` first in FLASH, aligned per the architecture.
- Handlers are usually `weak` aliases of a `Default_Handler` (an infinite loop, ideally recording the exception number), so a stray interrupt is debuggable. Defining a function with the same name overrides it; a misspelled handler silently falls back instead of failing to link.

## ISR Rules

- Acknowledge the source (clear the peripheral flag, often W1C) or it re-fires on exit.
- Move the minimum data, set a flag or queue, return; defer real work to `main`.
- No `malloc`, `printf`, or blocking calls: slow, often non-reentrant, and can deadlock against `main`.
- Cortex-M saves caller-saved registers in hardware, so a plain C function works as an ISR. Other architectures need an attribute such as `__attribute__((interrupt))` for the right prologue and return.

## Reentrancy

If interrupts nest or a handler can re-enter, every function reachable from it must be reentrant: no unprotected shared mutable `static`/global state and no non-reentrant library calls.

## Sharing State with main: volatile + Atomic

An ISR and `main` share a variable. Three things must hold:

1. `main` re-reads it instead of caching it in a register (`volatile` or an atomic load).
2. The access doesn't tear. A 32-bit aligned load/store is indivisible on a 32-bit core; a 64-bit value, a struct, or a misaligned access is not. Needs atomicity, which `volatile` lacks.
3. Ordering holds when the value gates other data ("buffer ready, now read it"). Needs acquire/release, which `volatile` lacks.

### Example

```c
#include <stdatomic.h>
#include <stdbool.h>

static atomic_bool data_ready;
static atomic_uint event_count;

void EXTI0_IRQHandler(void) {
    EXTI->PR = EXTI_PR_PR0;     /* W1C: write only this bit */
    atomic_fetch_add_explicit(&event_count, 1, memory_order_relaxed);
    atomic_store_explicit(&data_ready, true, memory_order_release);
}

void main_loop(void) {
    if (atomic_load_explicit(&data_ready, memory_order_acquire)) {
        unsigned n = atomic_load_explicit(&event_count, memory_order_relaxed);
        atomic_store_explicit(&data_ready, false, memory_order_relaxed);
        handle(n);              /* acquire orders this after the ISR's writes */
    }
}
```

### Why Atomics

On a single core these atomics are ordinary loads/stores plus compiler barriers, with no lock. A lone `volatile sig_atomic_t` flag also works on a single core but gives no ordering for other data, so prefer `atomic_bool`. Full rules: [c-concurrency-atomics](../../../c/modern-c/references/c-concurrency-atomics.md) (C), [atomics-and-memory-model](../../../cpp/cpp-concurrency/references/atomics-and-memory-model.md) (C++).

## The Critical-Section Alternative

When the shared operation is multi-step (several fields together, dequeue then mutate), mask the interrupt briefly:

```c
uint32_t primask = __get_PRIMASK();
__disable_irq();
/* multi-field update the ISR must not split */
__set_PRIMASK(primask);         /* restore, don't blindly enable */
```

Restore the saved mask because the caller may already be in a critical section, and keep it short since interrupts are blocked. A single-producer/single-consumer ring buffer with separate atomic head and tail often removes the need entirely.

## Startup: Reset Handler / crt0

```c
extern uint32_t _sdata, _edata, _sidata;   /* .data: RAM start/end, FLASH source */
extern uint32_t _sbss, _ebss;              /* .bss: RAM start/end */
extern int main(void);
extern void __libc_init_array(void);       /* runs .init_array constructors */

void Reset_Handler(void) {
    for (uint32_t *src = &_sidata, *dst = &_sdata; dst < &_edata; )
        *dst++ = *src++;                   /* 1. copy .data FLASH -> RAM */
    for (uint32_t *p = &_sbss; p < &_ebss; )
        *p++ = 0;                          /* 2. zero .bss */
    __libc_init_array();                   /* 3. C++/constructor-attribute init */
    main();                                /* 4. application */
    for (;;) { }                           /* main must not return */
}
```

The symbols come from the linker script ([linker-scripts-and-memory.md](linker-scripts-and-memory.md)).

## .data, .bss, and What the Standard Promises

C guarantees static-storage objects are initialized before `main`. A hosted loader does this; on bare metal startup code is what makes it true.

- `.data`: statics with a non-zero initializer. Values live in FLASH (LMA) and must be copied to RAM (VMA); skip it and they hold junk.
- `.bss`: zero-initialized statics. No FLASH space; startup zeroes the RAM range. Skip it and globals are "sometimes zero."
- `.rodata`: const data and string literals, read in place from FLASH.
- `.noinit`: data that must survive a warm reset, so startup must not zero it.

## C++ Static Constructors

Non-trivial static constructors are listed in `.init_array`; `__libc_init_array()` runs them before `main`. Skip the call and those objects are never constructed. Init-order issues and `constinit`: [embedded-cpp](../../embedded-cpp/SKILL.md).

## Pitfalls

| Pitfall | Fix |
|---------|-----|
| Shared var `volatile` but not atomic (tears, lost updates) | Atomics or critical section |
| Shared var neither (`main` caches a stale value) | Atomics |
| Long work, `printf`, or `malloc` in an ISR | Defer to `main` |
| Source not acknowledged (re-fires, livelock) | Clear the peripheral flag |
| `.bss` not zeroed / `.data` not copied | Add the startup loops |
| `__libc_init_array()` not called (C++) | Call it before `main` |
| `main` returns | End `Reset_Handler` in an infinite loop |
| `__enable_irq()` to leave a critical section | Save and restore `PRIMASK` |
