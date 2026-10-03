# Linker Scripts, Memory, and Cross-Compilation

## What the Linker Script Decides

Bare metal has no default script or loader; the linker script is the description of the chip's memory. It answers:

1. Where is memory? (`MEMORY`)
2. Where does each section live? (`SECTIONS`)
3. Which addresses does startup need? (exported symbols for the `.data` copy, `.bss` zero, stack top)

## MEMORY: Physical Regions

```ld
MEMORY
{
  FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 256K
  RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}
```

`ORIGIN`/`LENGTH` come from the datasheet memory map. In GNU ld the `r`/`w`/`x` attributes only steer where input sections without an explicit region go; they enforce nothing (the MPU does). Extra banks (CCM RAM, backup SRAM, external PSRAM) get their own regions.

## SECTIONS: Placing Code and Data

```ld
SECTIONS
{
  .isr_vector : { KEEP(*(.isr_vector)) } > FLASH   /* first, at image base */
  .text   : { *(.text*) *(.rodata*) } > FLASH

  .data : {
    _sdata = .;
    *(.data*)
    _edata = .;
  } > RAM AT > FLASH                                 /* VMA in RAM, LMA in FLASH */
  _sidata = LOADADDR(.data);

  .bss : {
    _sbss = .;
    *(.bss*) *(COMMON)
    _ebss = .;
  } > RAM
}
```

- `KEEP` stops `--gc-sections` from discarding the vector table, which nothing references.
- With `-ffunction-sections -fdata-sections`, each function and object gets its own input section, so `--gc-sections` can drop unused ones.
- Vectors go first because the core reads them at the image base on reset.

## LMA vs VMA: Why .data Has Two Addresses

Each section has a VMA (where it lives at run time) and an LMA (where it is stored in the image).

- `.text`, `.rodata`: VMA == LMA in FLASH, used in place.
- `.data`: VMA in RAM, LMA in FLASH (`> RAM AT > FLASH`). Startup copies LMA to VMA; `LOADADDR()` gives the source (`_sidata`).
- `.bss`: VMA in RAM, no image space; startup zeroes it.

## Exported Symbols Startup Needs

| Symbol | Meaning |
|--------|---------|
| `_sdata` / `_edata` | RAM bounds of `.data` |
| `_sidata` | FLASH load address of `.data` |
| `_sbss` / `_ebss` | RAM bounds of `.bss` |
| `_estack` | Initial SP (vector entry 0) |
| `_sheap` / `_eheap` | Heap bounds for `_sbrk`, if used |

A linker symbol's value is an address: declare `extern uint32_t _sdata;` and use `&_sdata`, not `_sdata`.

## Stack, Heap, and .noinit

```ld
_estack = ORIGIN(RAM) + LENGTH(RAM);     /* stack grows down from the top */
_Min_Heap_Size  = 0x400;
_Min_Stack_Size = 0x800;
```

- Stack: size for worst-case call depth plus ISR nesting; overflow silently corrupts what is below (often `.bss`). Fill RAM with a sentinel at startup and check the high-water mark.
- Heap: only if you use `malloc`. Give it a bounded region and make `_sbrk` fail at the limit rather than run into the stack.
- `.noinit`: data that survives a warm reset (reset reason, bootloader handshake), in its own section the `.bss` loop skips.

## Reducing Image Size

| Lever | Effect |
|-------|--------|
| `-Os` / `-Oz` | Optimize for size |
| `-ffunction-sections -fdata-sections -Wl,--gc-sections` | Drop unreferenced code and data |
| `-flto` | Cross-TU inlining and dead-code removal |
| `--specs=nano.specs` | Smaller libc, no float `printf` by default |
| `-fno-exceptions -fno-rtti` (C++) | No unwind tables or type info |
| `-Wl,-Map=out.map`, `arm-none-eabi-size`, `nm --size-sort` | Find what takes space |

## Cross-Compilation Toolchains

The target triple names the target: `arm-none-eabi` is ARM, no OS, embedded ABI. `arm-linux-gnueabihf` (Linux, glibc, hard-float) is a hosted toolchain.

```sh
arm-none-eabi-gcc \
  -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16 \
  -ffreestanding -ffunction-sections -fdata-sections \
  -T stm32f4.ld -Wl,--gc-sections -nostartfiles \
  startup.c main.c -o firmware.elf
arm-none-eabi-objcopy -O binary firmware.elf firmware.bin
arm-none-eabi-size firmware.elf
```

### Toolchain Notes

- `-mcpu`, `-mfloat-abi`, and `-mfpu` are part-specific; take them from the datasheet. `-mfloat-abi` must match across every object and the libc variant.
- A sysroot holds target headers and libraries so host `/usr/include` isn't used. arm-none-eabi bundles a newlib sysroot; custom toolchains need `--sysroot`.
- Clang cross-compiles with `--target=arm-none-eabi` plus a sysroot instead of a per-target binary.

## newlib vs newlib-nano and Syscall Stubs

newlib is the usual bare-metal libc. newlib-nano (`--specs=nano.specs`) is smaller and ships `printf`/`scanf` without float support unless you add `-u _printf_float`.

### Syscall Stubs

newlib calls OS hooks you must provide. Linking `printf`, `malloc`, or `exit` without them gives:

```
undefined reference to `_sbrk'    /* malloc heap growth */
undefined reference to `_write'   /* printf output */
undefined reference to `_read', `_close', `_lseek', `_fstat', `_isatty', `_exit'
```

Either link `--specs=nosys.specs` (stubs that return errors, fine if unused) or implement minimal ones, usually to get `printf` over a UART:

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

| Pitfall | Fix |
|---------|-----|
| `region 'FLASH'/'RAM' overflowed by N` | `-Os`, `--gc-sections`, LTO, nano libc, or resize |
| `.isr_vector` garbage-collected (hard fault at reset) | `KEEP(*(.isr_vector))` |
| `.data` `> RAM` without `AT > FLASH` | Add it and export `_sidata = LOADADDR(.data)` |
| `_sdata` used instead of `&_sdata` in C | Take the address |
| Mismatched `-mfloat-abi` | One float ABI everywhere, matching libc |
| Heap and stack collide | Bounded heap; `_sbrk` checks the limit |
| Stack overflows into `.bss` | Size the stack; sentinel high-water check |
| Float `printf` bloats flash | newlib-nano; fixed-point ([fixed-point-and-no-float.md](fixed-point-and-no-float.md)) |

CMake/Meson cross toolchain files: [build-systems](../../../tooling/build-systems/SKILL.md).
