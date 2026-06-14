# Embedded Skills Index

Quick navigation for the `skills/embedded/` subtree. Start at
[SKILL.md](SKILL.md) for the guided entry with decision tree, symptom router,
and the core cross-compile flag quick reference.

## Skills

| Skill | Use it for |
|-------|------------|
| [embedded-systems/SKILL.md](embedded-systems/SKILL.md) | Language-agnostic embedded core: freestanding vs hosted, MMIO/register access, `volatile` semantics, ISRs and startup, no-heap allocation, fixed-point, linker scripts, cross-compilation |
| [embedded-cpp/SKILL.md](embedded-cpp/SKILL.md) | C++ subset for embedded: RAII without exceptions/RTTI (`-fno-exceptions -fno-rtti -ffreestanding`), freestanding stdlib subset, static/placement-new construction, `constexpr`/`constinit` ROM-able data, avoiding hidden allocations |

## References

| File | Use it for |
|------|------------|
| [embedded-systems/references/mmio-and-registers.md](embedded-systems/references/mmio-and-registers.md) | Memory-mapped I/O: correct `volatile` pointer/struct register maps, bit-field hazards, read-modify-write, write-1-to-clear, ordering vs caches/store buffers |
| [embedded-systems/references/interrupts-and-startup.md](embedded-systems/references/interrupts-and-startup.md) | Vector tables, ISR rules and reentrancy, `volatile` + atomic ISR/`main` sharing, crt0 / Reset_Handler, `.data` copy and `.bss` zero, C runtime init |
| [embedded-systems/references/linker-scripts-and-memory.md](embedded-systems/references/linker-scripts-and-memory.md) | Linker scripts (`MEMORY`/`SECTIONS`/symbols), placing sections in FLASH/RAM, `.noinit`, stack/heap sizing, cross-compilation toolchains (arm-none-eabi, triples, sysroot, newlib/newlib-nano, syscall stubs) |
| [embedded-systems/references/fixed-point-and-no-float.md](embedded-systems/references/fixed-point-and-no-float.md) | Q-format fixed-point, scaling and rounding, multiply/divide with widening, saturation, software-float vs FPU cost, float-free `printf` |
| [embedded-cpp/references/freestanding-stdlib-subset.md](embedded-cpp/references/freestanding-stdlib-subset.md) | Which language/library features are available, unavailable, or costly under `-fno-exceptions -fno-rtti -ffreestanding`, and the idiomatic replacement for each |

## Cross-Tree

| Topic | Location |
|-------|----------|
| Hosted-C baseline (`volatile`, UB, concurrency) | `${CLAUDE_SKILL_DIR}/c/SKILL.md` |
| Full C++ (the superset embedded-cpp constrains) | `${CLAUDE_SKILL_DIR}/cpp/SKILL.md` |
| Arena / pool allocators (reused with no heap) | `${CLAUDE_SKILL_DIR}/c/c-memory-ownership/references/allocators-and-arenas.md` |
| Atomics / memory model (ISR and concurrency ordering) | `${CLAUDE_SKILL_DIR}/c/modern-c/references/c-concurrency-atomics.md` |
| Cross-compile toolchains in CMake/Meson | `${CLAUDE_SKILL_DIR}/tooling/build-systems/SKILL.md` |
| Toolchain/standard minimums (canonical) | `${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md` |
