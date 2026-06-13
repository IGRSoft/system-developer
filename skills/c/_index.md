# C Skills Index

Quick navigation for the `skills/c/` subtree. Start at [SKILL.md](SKILL.md) for
the guided entry with decision tree and `-std` flag quick reference.

## Skills

| Skill | Use it for |
|-------|------------|
| [modern-c/SKILL.md](modern-c/SKILL.md) | C17 vs C23 selection, C23 quick wins (`nullptr`, `constexpr` objects, `typeof`, `<stdckdint.h>`, `_BitInt`, `#embed`), hygiene flags |
| [c-memory-ownership/SKILL.md](c-memory-ownership/SKILL.md) | Ownership and lifetime conventions, cleanup patterns, allocator selection |

## References

| File | Use it for |
|------|------------|
| [modern-c/references/c23-features.md](modern-c/references/c23-features.md) | Complete C23 feature catalog: per-feature compiler support and C17 fallback for each |
| [modern-c/references/c-concurrency-atomics.md](modern-c/references/c-concurrency-atomics.md) | C11/C17 `<threads.h>`, `_Atomic`, memory orders, `atomic_flag`, TLS, when to use pthreads instead |
| [c-memory-ownership/references/undefined-behavior-catalog.md](c-memory-ownership/references/undefined-behavior-catalog.md) | UB classes (overflow, aliasing, lifetime), detection, and remediation |
| [c-memory-ownership/references/allocators-and-arenas.md](c-memory-ownership/references/allocators-and-arenas.md) | Arena, pool, and stack allocators; allocation failure policy |

## Cross-Tree

| Topic | Location |
|-------|----------|
| Toolchain minimums (canonical) | `${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md` |
| Sanitizers, gdb/lldb, valgrind | `${CLAUDE_SKILL_DIR}/tooling/diagnostics/SKILL.md` |
| CMake, Meson, Make | `${CLAUDE_SKILL_DIR}/tooling/build-systems/SKILL.md` |
| C/C++/Python boundaries | `${CLAUDE_SKILL_DIR}/tooling/ffi-interop/SKILL.md` |
| Input validation, injection defense | `${CLAUDE_SKILL_DIR}/_shared/secure-coding/SKILL.md` |
