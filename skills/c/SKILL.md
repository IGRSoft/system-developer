---
name: c-skills
description: >-
  C language skills navigation covering C17/C23 standard selection, C23
  feature adoption, memory ownership, undefined behavior, and C11/C17
  concurrency. Use when writing or reviewing C code, choosing -std flags,
  adopting C23 features, designing memory ownership, or using <threads.h>,
  _Atomic, and memory orders.
---

# C Language Skills

Routes C work to the right leaf skill or reference: C17 baseline, C23 adoption, memory discipline, concurrency.

## Skill Selection

| I need to... | Go to |
|--------------|-------|
| Pick C17 vs C23, adopt C23 features | [modern-c](modern-c/SKILL.md) |
| A specific C23 feature, its compiler minimum, and C17 fallback | [c23-features.md](modern-c/references/c23-features.md) |
| Threads, `_Atomic`, memory orders, TLS | [c-concurrency-atomics.md](modern-c/references/c-concurrency-atomics.md) |
| Design ownership/lifetime conventions | [c-memory-ownership](c-memory-ownership/SKILL.md) |
| Triage a crash, leak, or undefined behavior | [undefined-behavior-catalog.md](c-memory-ownership/references/undefined-behavior-catalog.md) |
| Custom allocators, arenas, pools | [allocators-and-arenas.md](c-memory-ownership/references/allocators-and-arenas.md) |

## Related Skills

| I need to... | Go to |
|--------------|-------|
| Sanitizers (incl. TSan for data races), gdb/lldb, valgrind | [diagnostics](../tooling/diagnostics/SKILL.md) |
| Build, lint, package | [build-systems](../tooling/build-systems/SKILL.md) |
| Bare-metal/freestanding: registers, ISRs, `volatile` vs atomics, no-heap, linker scripts | [embedded-skills](../embedded/SKILL.md) |
| Input validation, command execution safety, hardening flags | [secure-coding](../_shared/secure-coding/SKILL.md) |
| Headers shared with C++, or Python bindings | [cpp-skills](../cpp/SKILL.md), [ffi-interop](../tooling/ffi-interop/SKILL.md) |

## Standard Flags

```sh
-std=c17    # Baseline: GCC 8+, Clang 6+, MSVC /std:c17 (VS 2019 16.8+)
-std=c23    # GCC 14+, Clang 18+
-std=c2x    # Pre-ratification spelling for GCC 9-13, Clang 9-17
```

C23 features arrive per compiler release (Clang lags on `constexpr`; `#embed` needs GCC 15+ / Clang 19+); check [c23-features.md](modern-c/references/c23-features.md) or the [version-feature-matrix](../_shared/version-feature-matrix.md) before adopting one.

GCC 15 defaults to `-std=gnu23` when no flag is given, so pin `-std` in the build system.

For release hardening, GCC 14+ bundles the recommended set (`_FORTIFY_SOURCE=3`, stack protector, PIE/RELRO, `-ftrivial-auto-var-init=zero`, and more) behind `-fhardened`; flag details are in [secure-coding](../_shared/secure-coding/SKILL.md).
