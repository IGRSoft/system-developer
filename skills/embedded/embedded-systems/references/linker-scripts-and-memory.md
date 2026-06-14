# Linker Scripts, Memory, and Cross-Compilation

Use this when:

- You are writing or reading a linker script (memory regions, sections, symbols).
- A link fails with a region overflow or a missing newlib syscall stub.
- You are bringing up a cross-compiler (arm-none-eabi, triple, sysroot, newlib).

Skip this file if:

- Your question is what startup code *does* with these symbols. Use
  [interrupts-and-startup.md](interrupts-and-startup.md).
- You want the CMake/Meson wiring for a cross toolchain. Use
  [build-systems](${CLAUDE_SKILL_DIR}/tooling/build-systems/SKILL.md).

Jump to:

- What the Linker Script Decides
- MEMORY: Physical Regions
- SECTIONS: Placing Code and Data
- LMA vs VMA: Why .data Has Two Addresses
- Exported Symbols Startup Needs
- Stack, Heap, and .noinit
- Reducing Image Size
- Cross-Compilation Toolchains
- newlib vs newlib-nano and Syscall Stubs
- Pitfalls

## What the Linker Script Decides

On a hosted OS the linker uses a default script and the loader maps everything.
Bare metal has neither: the linker script is **the** description of the chip's
memory and where each section goes. It answers three questions:

1. **Where is memory?** (`MEMORY`: FLASH at one address, RAM at another, sizes.)
2. **Where does each section live?** (`SECTIONS`: `.text` in FLASH, `.bss` in
   RAM, etc.)
3. **What addresses does startup code need?** (exported symbols for the `.data`
   copy and `.bss` zero loops, the stack top.)

## MEMORY: Physical Regions

```ld
MEMORY
{
  FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 256K   /* read + execute */
  RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 64K    /* read + write + execute */
}
```

`ORIGIN`/`LENGTH` come straight from the datasheet's memory map. The attributes
(`r`/`w`/`x`) are advisory documentation in GNU ld; the real protection, if any,
is the MPU. Multiple FLASH/RAM banks (CCM RAM, backup SRAM, external PSRAM) each
get their own region.

## SECTIONS: Placing Code and Data

```ld
SECTIONS
{
  .isr_vector : { KEEP(*(.isr_vector)) } > FLASH   /* must be first, at image base */
  .text   : { *(.text*) *(.rodata*) } > FLASH       /* code + const data in FLASH */

  .data : {
    _sdata = .;                                      /* RAM start of .data (VMA) */
    *(.data*)
    _edata = .;                                      /* RAM end of .data */
  } > RAM AT > FLASH                                 /* VMA in RAM, LMA in FLASH */
  _sidata = LOADADDR(.data);                         /* FLASH source of .data */

  .bss : {
    _sbss = .;
    *(.bss*) *(COMMON)
    _ebss = .;
  } > RAM
}
```

- `KEEP(...)` stops `--gc-sections` from discarding the vector table (nothing
  "calls" it, so it looks unused).
- `*(.text*)` collects every input `.text*` section; with
  `-ffunction-sections`/`-fdata-sections` each function/object is its own
  section, so `--gc-sections` can drop unused ones.
- The order inside FLASH matters: vectors first (the core reads them at the
  image base on reset).

## LMA vs VMA: Why .data Has Two Addresses

Every section has a **VMA** (virtual/run address — where it executes/lives at
runtime) and an **LMA** (load address — where it is stored in the image).

- `.text`, `.rodata`: VMA == LMA, both in FLASH. Executed/read in place.
- `.data`: **VMA in RAM, LMA in FLASH** (`> RAM AT > FLASH`). The initial values
  ship in FLASH; the variables live in RAM. Startup copies LMA→VMA. `LOADADDR()`
  gives the LMA so startup knows the FLASH source (`_sidata`).
- `.bss`: VMA in RAM, **no LMA** — it occupies no image space; startup just
  zeroes the RAM range.

This split is the entire reason startup has a `.data` copy loop and a `.bss`
zero loop — see [interrupts-and-startup.md](interrupts-and-startup.md).

## Exported Symbols Startup Needs

The linker script defines symbols (addresses, used via `extern uint32_t name;`
and `&name` in C) that startup code consumes:

| Symbol | Meaning | Used for |
|--------|---------|----------|
| `_sdata` / `_edata` | RAM start/end of `.data` | `.data` copy loop bounds |
| `_sidata` | FLASH load address of `.data` | `.data` copy source |
| `_sbss` / `_ebss` | RAM start/end of `.bss` | `.bss` zero loop bounds |
| `_estack` | Top of RAM / initial SP | vector table entry 0 |
| `_sheap`/`end` / `_eheap` | Heap bounds | `_sbrk` for `malloc`, if used |

A symbol *value* is an address; in C you take `&_sdata`, not `_sdata`.

## Stack, Heap, and .noinit

```ld
_estack = ORIGIN(RAM) + LENGTH(RAM);     /* stack grows down from the top */
_Min_Heap_Size  = 0x400;
_Min_Stack_Size = 0x800;
```

- **Stack**: grows downward from `_estack`. Size it for worst-case call depth +
  ISR nesting; overflow silently corrupts whatever is below (often `.bss`).
  Fill RAM with a sentinel pattern at startup and check the high-water mark to
  measure real usage.
- **Heap**: only if you use `malloc`. Give it an explicit bounded region; newlib
  `_sbrk` carves from it. A heap and a downward stack in the same RAM can
  collide — `_sbrk` must check against the stack pointer and fail, not silently
  overrun.
- **`.noinit`**: data that must survive a warm reset (a reset reason code, a
  bootloader handshake) — place it in its own section the startup `.bss` loop
  does **not** zero.

## Reducing Image Size

| Lever | Effect |
|-------|--------|
| `-Os` (or `-Oz` on Clang) | Optimize for size |
| `-ffunction-sections -fdata-sections` + `-Wl,--gc-sections` | Drop unreferenced functions/objects |
| `-flto` | Cross-TU inlining and dead-code elimination |
| `--specs=nano.specs` (newlib-nano) | Smaller libc; drops float `printf` by default |
| `-fno-exceptions -fno-rtti` (C++) | Removes unwind tables and type-info (see embedded-cpp) |
| `-Wl,-Map=out.map` + `arm-none-eabi-size`/`nm --size-sort` | Find what is actually taking space |

## Cross-Compilation Toolchains

A cross-compiler runs on your host and emits code for a different target. The
**target triple** names the target: `arm-none-eabi` = ARM architecture, `none`
(no OS / bare metal), `eabi` (the embedded ABI). Contrast
`arm-linux-gnueabihf` (Linux OS, glibc, hard-float) — a *hosted* toolchain.

```sh
arm-none-eabi-gcc \
  -mcpu=cortex-m4 -mthumb \
  -mfloat-abi=hard -mfpu=fpv4-sp-d16 \      # part- and ABI-specific: verify
  -ffreestanding -ffunction-sections -fdata-sections \
  -T stm32f4.ld -Wl,--gc-sections -nostartfiles \
  startup.c main.c -o firmware.elf
arm-none-eabi-objcopy -O binary firmware.elf firmware.bin
arm-none-eabi-size firmware.elf
```

- **`-mcpu`/`-mthumb`/`-mfloat-abi`/`-mfpu`** are part-specific; the wrong
  float-ABI links incompatible objects (`-mfloat-abi=hard` vs `soft` must match
  across all objects *and* the libc variant). Verify every flag against the
  datasheet and your toolchain.
- A **sysroot** (`--sysroot=...`) holds the target's headers and libraries so
  the cross-compiler does not pick up host `/usr/include`. Bare-metal toolchains
  bundle a newlib-based sysroot; you rarely set it by hand for arm-none-eabi but
  must for custom toolchains.
- Clang cross-compiles with `--target=arm-none-eabi` and a GCC sysroot rather
  than a separate per-target binary.

Toolchain/standard minimums are canonical in
[version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md);
do not restate compiler versions here.

## newlib vs newlib-nano and Syscall Stubs

**newlib** is the usual bare-metal C library; **newlib-nano**
(`--specs=nano.specs`) is a size-optimized variant that, among other trims,
ships a `printf`/`scanf` without floating-point support unless you opt back in
(`-u _printf_float`). Choose nano for flash-constrained parts.

newlib's higher-level functions call out to **syscall stubs** that only you can
implement, because there is no OS underneath. If `printf`, `malloc`, or
`exit` are linked, you will see:

```
undefined reference to `_sbrk'    /* malloc/sbrk heap growth */
undefined reference to `_write'   /* printf/fputs output */
undefined reference to `_read', `_close', `_lseek', `_fstat', `_isatty', `_exit'
```

Two ways to satisfy them:

- **`--specs=nosys.specs`** — links stubs that fail/return errors; fine if you
  truly use none of that functionality.
- **Implement minimal stubs** — `_sbrk` carving from the heap region, `_write`
  pushing bytes to a UART so `printf` works, `_exit` looping forever. This is
  the usual choice when you want `printf`-over-UART debugging.

```c
caddr_t _sbrk(int incr) {
    extern char _sheap, _eheap;            /* from the linker script */
    static char *brk = &_sheap;
    if (brk + incr > &_eheap) { errno = ENOMEM; return (caddr_t)-1; }
    char *prev = brk; brk += incr; return (caddr_t)prev;
}
int _write(int fd, const char *buf, int len) {
    for (int i = 0; i < len; i++) uart_putc(buf[i]);
    return len;
}
```

## Pitfalls

| Pitfall | Consequence | Fix |
|---------|-------------|-----|
| `region 'FLASH'/'RAM' overflowed by N` | Sections exceed the region | `-Os`/`--gc-sections`/LTO; nano libc; or resize the region |
| `.isr_vector` garbage-collected | No vectors at reset, hard fault | `KEEP(*(.isr_vector))` |
| `.data` placed `> RAM` without `AT > FLASH` | No FLASH copy of initial values | `> RAM AT > FLASH`, export `_sidata = LOADADDR(.data)` |
| Using `_sdata` instead of `&_sdata` in C | Reads memory at that address, not the address | Take the symbol's address |
| `undefined reference to '_sbrk'/'_write'` | newlib stubs missing | Implement stubs or `--specs=nosys.specs` |
| Mismatched `-mfloat-abi` across objects/libc | Link error or runtime corruption | One float-ABI everywhere, matching libc variant |
| Heap and stack collide | Silent corruption | Bounded heap region, `_sbrk` checks the limit |
| Stack overflow into `.bss` | Globals corrupted mid-run | Size the stack; sentinel + high-water check |
| Image bloated by float `printf` | Flash overflow | newlib-nano; convert math to fixed-point |

Cross-references: how startup uses these symbols in
[interrupts-and-startup.md](interrupts-and-startup.md); fixed-point to avoid the
float-`printf`/software-float bloat in
[fixed-point-and-no-float.md](fixed-point-and-no-float.md); CMake/Meson cross
toolchain files in
[build-systems](${CLAUDE_SKILL_DIR}/tooling/build-systems/SKILL.md).
