---
name: embedded-skills
description: >-
  Embedded and bare-metal C/C++ skills navigation: freestanding vs hosted,
  memory-mapped registers and volatile, interrupts and startup, no-heap
  allocation, fixed-point math, linker scripts, cross-compilation, and the
  embedded C++ subset (-fno-exceptions -fno-rtti). Use when targeting
  microcontrollers or bare metal, writing ISRs, removing the heap, or fitting
  C/C++ into flash- and RAM-limited devices.
---

# Embedded Skills

Routes bare-metal work to a leaf skill or reference. The core is language-agnostic; embedded-cpp is a thin C++ layer on top of it.

## Skill Selection Guide

### Core (C, or the C subset of C++)

| I need to... | Go to |
|--------------|-------|
| Build freestanding (no libc/OS) and know what's gone | [embedded-systems](embedded-systems/SKILL.md) |
| Register access, MMIO struct layout | [mmio-and-registers.md](embedded-systems/references/mmio-and-registers.md) |
| `volatile` right (it is not atomicity) | [embedded-systems](embedded-systems/SKILL.md) > volatile |
| ISR, vector table, crt0, `.data`/`.bss` | [interrupts-and-startup.md](embedded-systems/references/interrupts-and-startup.md) |
| No heap: static, arena, or pool | [embedded-systems](embedded-systems/SKILL.md) > No-Heap Allocation |
| Fixed-point instead of `float` | [fixed-point-and-no-float.md](embedded-systems/references/fixed-point-and-no-float.md) |
| Linker script, memory regions, cross-compiler, newlib | [linker-scripts-and-memory.md](embedded-systems/references/linker-scripts-and-memory.md) |

### C++ on the target

| I need to... | Go to |
|--------------|-------|
| `-fno-exceptions -fno-rtti` flag set, RAII without exceptions | [embedded-cpp](embedded-cpp/SKILL.md) |
| Static/placement-new construction, `constexpr`/`constinit` ROM-able data | [embedded-cpp](embedded-cpp/SKILL.md) |
| Which stdlib/language features are unavailable or costly | [freestanding-stdlib-subset.md](embedded-cpp/references/freestanding-stdlib-subset.md) |

## Symptom Router

### Hardware and startup

| Symptom | Likely cause | Go to |
|---------|--------------|-------|
| Register write does nothing / reads stale | missing `volatile`, wrong width or offset | [mmio-and-registers.md](embedded-systems/references/mmio-and-registers.md) |
| ISR and `main` disagree on a shared value | shared state not `volatile` + atomic | [interrupts-and-startup.md](embedded-systems/references/interrupts-and-startup.md) |
| Globals are garbage at startup | crt0 didn't copy `.data` / zero `.bss` | [interrupts-and-startup.md](embedded-systems/references/interrupts-and-startup.md) |
| Math drifts or overflows on an FPU-less part | software float, or wrong fixed-point scaling | [fixed-point-and-no-float.md](embedded-systems/references/fixed-point-and-no-float.md) |

### Build and image size

| Symptom | Likely cause | Go to |
|---------|--------------|-------|
| `undefined reference to '_sbrk'` / `_write` / `_exit` | newlib syscall stubs missing | [linker-scripts-and-memory.md](embedded-systems/references/linker-scripts-and-memory.md) > Syscall Stubs |
| `region 'FLASH' overflowed` / `RAM overflowed` | sections exceed memory regions | [linker-scripts-and-memory.md](embedded-systems/references/linker-scripts-and-memory.md) |
| Image huge, pulls in float `printf` | `<iostream>`, `malloc`, exceptions, or float `printf` linked | [embedded-cpp](embedded-cpp/SKILL.md), [fixed-point-and-no-float.md](embedded-systems/references/fixed-point-and-no-float.md) |
| C++ binary hits `std::terminate` on error | code throws but built `-fno-exceptions` | [embedded-cpp](embedded-cpp/SKILL.md) |

## Core Flags Quick Reference

```sh
# Freestanding C (-ffreestanding implies -fno-builtin):
-ffreestanding -nostdlib

# Bare-metal C++ adds (see embedded-cpp):
-fno-exceptions -fno-rtti -fno-threadsafe-statics

# Typical Cortex-M cross-compile; -mcpu/-mfpu/-mfloat-abi depend on the part:
arm-none-eabi-gcc -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16 \
    -ffreestanding -ffunction-sections -fdata-sections \
    -T link.ld -Wl,--gc-sections -nostartfiles
```

## Related Skills

| I need to... | Go to |
|--------------|-------|
| Hosted-C baseline: `volatile`, UB, atomics | [c-skills](../c/SKILL.md) |
| Full C++ (embedded-cpp constrains it) | [cpp-skills](../cpp/SKILL.md) |
| Arena/pool allocators for no-heap targets | [c-memory-ownership](../c/c-memory-ownership/SKILL.md) |
| Cross-compile toolchains and `-T` in CMake/Meson | [build-systems](../tooling/build-systems/SKILL.md) |
| C/C++ standard minimums | [version-feature-matrix](../_shared/version-feature-matrix.md) |
