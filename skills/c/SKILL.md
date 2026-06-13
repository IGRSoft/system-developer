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

Modern C development: C17 baseline, C23 adoption, memory discipline, concurrency.

## Skill Selection Guide

| I need to... | Use this skill |
|--------------|----------------|
| Pick C17 vs C23, adopt C23 features | [modern-c](modern-c/SKILL.md) |
| Full C23 feature catalog with per-feature fallbacks | [modern-c/references/c23-features.md](modern-c/references/c23-features.md) |
| Threads, `_Atomic`, memory orders, TLS | [modern-c/references/c-concurrency-atomics.md](modern-c/references/c-concurrency-atomics.md) |
| Design ownership/lifetime conventions | [c-memory-ownership](c-memory-ownership/SKILL.md) |
| Triage a crash or undefined behavior | [c-memory-ownership/references/undefined-behavior-catalog.md](c-memory-ownership/references/undefined-behavior-catalog.md) |
| Custom allocators, arenas, pools | [c-memory-ownership/references/allocators-and-arenas.md](c-memory-ownership/references/allocators-and-arenas.md) |
| Sanitizers, gdb/lldb, valgrind workflow | [diagnostics](${CLAUDE_SKILL_DIR}/tooling/diagnostics/SKILL.md) |
| Input validation, command execution safety | [secure-coding](${CLAUDE_SKILL_DIR}/_shared/secure-coding/SKILL.md) |
| Cross-language C/C++ or Python bindings | [ffi-interop](${CLAUDE_SKILL_DIR}/tooling/ffi-interop/SKILL.md) |

## Decision Tree

```
C task?
├── Language level / new features
│   ├── Which standard to target → modern-c/SKILL.md (selection table)
│   ├── Specific C23 feature + C17 fallback → modern-c/references/c23-features.md
│   └── Shared headers with C++ → ${CLAUDE_SKILL_DIR}/cpp/SKILL.md + ffi-interop
├── Memory
│   ├── Ownership/lifetime design → c-memory-ownership/SKILL.md
│   ├── Custom allocation strategy → c-memory-ownership/references/allocators-and-arenas.md
│   └── Crash, leak, or UB triage → undefined-behavior-catalog.md + tooling/diagnostics
├── Concurrency
│   ├── <threads.h>, _Atomic, memory orders → modern-c/references/c-concurrency-atomics.md
│   └── Data race triage → TSan via ${CLAUDE_SKILL_DIR}/tooling/diagnostics/SKILL.md
└── Build, lint, package → ${CLAUDE_SKILL_DIR}/tooling/build-systems/SKILL.md
```

## Standard Flags Quick Reference

```sh
-std=c17    # Baseline: GCC 8+, Clang 6+, MSVC /std:c17 (VS 2019 16.8+)
-std=c23    # GCC 14+, Clang 18+
-std=c2x    # Pre-ratification spelling for GCC 9-13, Clang 9-17
```

**C23 in one line**: core features (`nullptr`, `constexpr` objects, `typeof`,
`auto`, `<stdckdint.h>`, `_BitInt`) are usable from **GCC 13+ / Clang 16+** in
`-std=c2x`/`-std=c23` mode; `#embed` needs **GCC 15+ / Clang 19+**.
Per-feature minimums: [c23-features.md](modern-c/references/c23-features.md).

GCC 15 defaults to `-std=gnu23` when no flag is given — always pin `-std`
explicitly in the build system.

## File Overview

| Path | Purpose |
|------|---------|
| [_index.md](_index.md) | Full subtree navigation |
| [modern-c/SKILL.md](modern-c/SKILL.md) | C17 vs C23 selection, C23 quick wins, hygiene flags |
| [modern-c/references/c23-features.md](modern-c/references/c23-features.md) | Complete C23 catalog, compiler support, C17 fallbacks |
| [modern-c/references/c-concurrency-atomics.md](modern-c/references/c-concurrency-atomics.md) | `<threads.h>`, `_Atomic`, memory orders, TLS, pthreads boundary |
| [c-memory-ownership/SKILL.md](c-memory-ownership/SKILL.md) | Ownership conventions, cleanup patterns |

## Related Skills

- [cpp-skills](${CLAUDE_SKILL_DIR}/cpp/SKILL.md) — C++ standard selection and interop with C headers
- [version-feature-matrix](${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md) — canonical standard/toolchain minimums
- [diagnostics](${CLAUDE_SKILL_DIR}/tooling/diagnostics/SKILL.md) — sanitizers, debuggers, profilers
- [secure-coding](${CLAUDE_SKILL_DIR}/_shared/secure-coding/SKILL.md) — input validation and injection defense
