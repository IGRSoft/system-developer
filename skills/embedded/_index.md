# Embedded Skills Index

Quick navigation for the `skills/embedded/` subtree. Start at
[SKILL.md](SKILL.md) for the selection tables, symptom router, and core flags.

## Skills

| Skill | Use it for |
|-------|------------|
| [embedded-systems/SKILL.md](embedded-systems/SKILL.md) | Language-agnostic embedded core: freestanding vs hosted, MMIO/register access, `volatile` semantics, ISRs and startup, no-heap allocation, fixed-point, linker scripts, cross-compilation |
| [embedded-cpp/SKILL.md](embedded-cpp/SKILL.md) | C++ subset for embedded: RAII without exceptions/RTTI (`-fno-exceptions -fno-rtti -ffreestanding`), freestanding stdlib subset, static/placement-new construction, `constexpr`/`constinit` ROM-able data, avoiding hidden allocations |

## embedded-systems References

| File | Use it for |
|------|------------|
| [mmio-and-registers.md](embedded-systems/references/mmio-and-registers.md) | `volatile` pointer/struct register maps, bit-field hazards, read-modify-write, write-1-to-clear, ordering vs caches/store buffers |
| [interrupts-and-startup.md](embedded-systems/references/interrupts-and-startup.md) | Vector tables, ISR rules and reentrancy, `volatile` + atomic ISR/`main` sharing, crt0 / Reset_Handler, `.data` copy and `.bss` zero |
| [linker-scripts-and-memory.md](embedded-systems/references/linker-scripts-and-memory.md) | `MEMORY`/`SECTIONS`/symbols, FLASH/RAM placement, `.noinit`, stack/heap sizing, cross toolchains (arm-none-eabi, triples, sysroot, newlib/newlib-nano, syscall stubs) |
| [fixed-point-and-no-float.md](embedded-systems/references/fixed-point-and-no-float.md) | Q-format, scaling and rounding, widening multiply/divide, saturation, software-float vs FPU cost, float-free `printf` |

## embedded-cpp References

| File | Use it for |
|------|------------|
| [freestanding-stdlib-subset.md](embedded-cpp/references/freestanding-stdlib-subset.md) | Which language/library features are available, unavailable, or costly under `-fno-exceptions -fno-rtti -ffreestanding`, and the replacement for each |

## Cross-Tree

| Topic | Location |
|-------|----------|
| Hosted-C baseline (`volatile`, UB, concurrency) | [c/SKILL.md](../c/SKILL.md) |
| Full C++ (the superset embedded-cpp constrains) | [cpp/SKILL.md](../cpp/SKILL.md) |
| Arena / pool allocators (reused with no heap) | [allocators-and-arenas.md](../c/c-memory-ownership/references/allocators-and-arenas.md) |
| Atomics / memory model (ISR and concurrency ordering) | [c-concurrency-atomics.md](../c/modern-c/references/c-concurrency-atomics.md) |
| Cross-compile toolchains in CMake/Meson | [build-systems](../tooling/build-systems/SKILL.md) |
| Toolchain/standard minimums (canonical) | [version-feature-matrix.md](../_shared/version-feature-matrix.md) |
