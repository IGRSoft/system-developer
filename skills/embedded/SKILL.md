---
name: embedded-skills
description: >-
  Embedded and bare-metal systems skills navigation for C and C++:
  freestanding vs hosted, memory-mapped I/O and register access, volatile
  semantics, interrupts and startup, no-heap allocation, fixed-point math,
  linker scripts, cross-compilation, and the embedded C++ subset
  (-fno-exceptions -fno-rtti). Use when targeting microcontrollers or
  bare-metal, accessing hardware registers, writing ISRs, removing the
  heap, or constraining C++ for flash- and RAM-limited devices.
---

# Embedded Skills

**Bare-metal and freestanding development for C and C++ on constrained targets**

Thin router. Pick a leaf from the tables below; the leaf skills teach. The core
is language-agnostic; the C++ subset is a thin layer on top of it.

## Skill Selection Guide

| I need to... | Use this skill |
|--------------|----------------|
| Build freestanding (`-ffreestanding`, no libc/OS), or know what's gone | [embedded-systems](embedded-systems/SKILL.md) |
| Read/write a hardware register, lay out an MMIO struct correctly | [embedded-systems/references/mmio-and-registers.md](embedded-systems/references/mmio-and-registers.md) |
| Get `volatile` right (and know why it is NOT atomicity) | [embedded-systems](embedded-systems/SKILL.md) > volatile |
| Write an ISR, place a vector table, understand crt0/`.data`/`.bss` | [embedded-systems/references/interrupts-and-startup.md](embedded-systems/references/interrupts-and-startup.md) |
| Run with no heap: static, arena, or pool allocation | [embedded-systems](embedded-systems/SKILL.md) > No-Heap Allocation |
| Replace `float` with fixed-point arithmetic | [embedded-systems/references/fixed-point-and-no-float.md](embedded-systems/references/fixed-point-and-no-float.md) |
| Write or read a linker script (memory regions, sections, symbols) | [embedded-systems/references/linker-scripts-and-memory.md](embedded-systems/references/linker-scripts-and-memory.md) |
| Set up a cross-compiler (arm-none-eabi, triples, newlib/newlib-nano, sysroot) | [embedded-systems/references/linker-scripts-and-memory.md](embedded-systems/references/linker-scripts-and-memory.md) > Toolchains |
| Use C++ on a microcontroller (`-fno-exceptions -fno-rtti -ffreestanding`) | [embedded-cpp](embedded-cpp/SKILL.md) |
| RAII without exceptions; static/placement-new construction; ROM-able data | [embedded-cpp](embedded-cpp/SKILL.md) |
| Know which standard-library/language features are unavailable or costly | [embedded-cpp/references/freestanding-stdlib-subset.md](embedded-cpp/references/freestanding-stdlib-subset.md) |

## Decision Tree

```
Embedded / bare-metal task?
├── Language-agnostic core (C, or the C subset of C++) → embedded-systems/SKILL.md
│   ├── Freestanding vs hosted, what libc/OS you lose → embedded-systems/SKILL.md
│   ├── Register access / MMIO struct layout → references/mmio-and-registers.md
│   ├── `volatile` correctness (NOT concurrency) → embedded-systems/SKILL.md > volatile
│   ├── ISR / vector table / startup / .data / .bss → references/interrupts-and-startup.md
│   ├── No heap: static / arena / pool → embedded-systems/SKILL.md > No-Heap Allocation
│   ├── Fixed-point instead of float → references/fixed-point-and-no-float.md
│   └── Linker script / memory regions / cross-compiler → references/linker-scripts-and-memory.md
└── C++ specifically on the target → embedded-cpp/SKILL.md
    ├── RAII without exceptions/RTTI, the flag set → embedded-cpp/SKILL.md
    ├── Which stdlib/language features survive freestanding → references/freestanding-stdlib-subset.md
    └── constexpr/constinit ROM-able data, placement-new lifetime → embedded-cpp/SKILL.md
```

## Symptom Router

Start here when you have a behavior, not a topic name.

| Symptom | Likely cause | Go to |
|---------|--------------|-------|
| Register write "does nothing" / reads stale | missing `volatile`, or wrong width/offset | [mmio-and-registers.md](embedded-systems/references/mmio-and-registers.md) |
| ISR and `main` disagree on a shared value | shared state not `volatile` + not atomic | [interrupts-and-startup.md](embedded-systems/references/interrupts-and-startup.md) |
| Globals are garbage at startup (not zeroed/initialized) | `.bss`/`.data` not set up by crt0 | [interrupts-and-startup.md](embedded-systems/references/interrupts-and-startup.md) |
| Link fails: `undefined reference to '_sbrk'`, `_write`, `_exit` | newlib syscall stubs missing | [linker-scripts-and-memory.md](embedded-systems/references/linker-scripts-and-memory.md) > Toolchains |
| `region 'FLASH' overflowed` / `RAM overflowed` | section sizes exceed memory regions | [linker-scripts-and-memory.md](embedded-systems/references/linker-scripts-and-memory.md) |
| Image is huge / pulls in printf float code | `<iostream>`, `malloc`, exceptions, or float `printf` linked | [embedded-cpp](embedded-cpp/SKILL.md) + [fixed-point-and-no-float.md](embedded-systems/references/fixed-point-and-no-float.md) |
| C++ binary throws `std::terminate` on error | code throws but built `-fno-exceptions` | [embedded-cpp](embedded-cpp/SKILL.md) |
| Math drifts / overflows on an FPU-less part | software float or fixed-point scaling wrong | [fixed-point-and-no-float.md](embedded-systems/references/fixed-point-and-no-float.md) |

## Core Flags Quick Reference

```sh
# Freestanding C, no hosted-environment assumptions:
-ffreestanding -fno-builtin -nostdlib

# Bare-metal C++ adds (see embedded-cpp):
-fno-exceptions -fno-rtti -fno-threadsafe-statics

# Typical Cortex-M cross-compile (verify part/ABI against your datasheet):
arm-none-eabi-gcc -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16 \
    -ffreestanding -ffunction-sections -fdata-sections \
    -T link.ld -Wl,--gc-sections -nostartfiles
```

Toolchain/standard minimums live in
[version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md);
ARM-specific flags are part- and ABI-dependent — verify against the datasheet
and your compiler.

## File Overview

| Path | Purpose |
|------|---------|
| [_index.md](_index.md) | Full subtree navigation |
| [embedded-systems/SKILL.md](embedded-systems/SKILL.md) | Language-agnostic core: freestanding, MMIO, volatile, ISRs, no-heap, fixed-point, linkers |
| [embedded-cpp/SKILL.md](embedded-cpp/SKILL.md) | C++ subset for embedded: RAII without exceptions/RTTI, freestanding stdlib, ROM-able data |

## Related Skills

- [c-skills](${CLAUDE_SKILL_DIR}/c/SKILL.md) — hosted-C baseline; `volatile`, UB, and concurrency the embedded core builds on
- [cpp-skills](${CLAUDE_SKILL_DIR}/cpp/SKILL.md) — full C++; embedded-cpp is the constrained subset of it
- [c-memory-ownership](${CLAUDE_SKILL_DIR}/c/c-memory-ownership/SKILL.md) — arena/pool allocators reused on no-heap targets
- [build-systems](${CLAUDE_SKILL_DIR}/tooling/build-systems/SKILL.md) — expressing cross-compile toolchains and `-T` linker flags in CMake/Meson
- [version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md) — canonical standard/toolchain minimums
```