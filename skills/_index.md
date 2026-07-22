# Skills Index

Root index for all system-developer skills (C, C++, Python, Bash, embedded, and
shared tooling). **25 SKILL.md across 7 domains, plus shared references.** Start
at [`SKILL.md`](SKILL.md) for the routing entry point.

## Domains

| Directory | Index | Skills | Description |
|-----------|-------|--------|-------------|
| [_shared/](_shared/_index.md) | [`_index.md`](_shared/_index.md) | 2 + refs | Cross-cutting patterns: workflow integration, secure coding, versions, routing, severity, testing principles |
| [c/](c/SKILL.md) | [`_index.md`](c/_index.md) | 1 + 2 leaves | C17/C23 standard selection, C23 features, memory ownership, undefined behavior, C11/C17 concurrency |
| [cpp/](cpp/SKILL.md) | [`_index.md`](cpp/_index.md) | 1 + 2 leaves | C++17/20/23 standard selection (plus C++26 emerging — DIS 2026), RAII and modern idioms, ranges, concepts, coroutines, concurrency |
| [python/](python/SKILL.md) | [`_index.md`](python/_index.md) | 1 + 5 leaves | Python 3.12-3.14 features, typing, concurrency, uv/ruff tooling, pytest testing |
| [bash/](bash/SKILL.md) | [`_index.md`](bash/_index.md) | 1 + 2 leaves | Defensive Bash scripting, POSIX portability, bats/shellcheck/shfmt testing |
| [embedded/](embedded/SKILL.md) | [`_index.md`](embedded/_index.md) | 1 + 2 leaves | Bare-metal/freestanding C & C++: MMIO/registers, volatile, ISRs/startup, no-heap allocation, fixed-point, linker scripts, cross-compilation, embedded C++ subset |
| [tooling/](tooling/SKILL.md) | [`_index.md`](tooling/_index.md) | 1 + 3 leaves | Build systems, sanitizers, debuggers, profilers, FFI/interop |

## All Skills

### _shared

| Skill | Path | Description |
|-------|------|-------------|
| **secure-coding** | [`_shared/secure-coding/SKILL.md`](_shared/secure-coding/SKILL.md) | Non-negotiable security rules and bug-class defenses for C, C++, Python, and Bash — injection-safe process execution, memory-corruption sanitizer mapping, integer safety, path-traversal/TOCTOU resistance, secrets hygiene |
| **workflow-integration** | [`_shared/workflow-integration/SKILL.md`](_shared/workflow-integration/SKILL.md) | Guide for integrating with the igrsoft 11-stage workflow system (v3.36.0) |
| version-feature-matrix | [`_shared/version-feature-matrix.md`](_shared/version-feature-matrix.md) | Standards/versions → minimum toolchains and headline features (canonical lookup) |
| language-detection | [`_shared/language-detection.md`](_shared/language-detection.md) | Marker → language → agent routing table, detection priority, tie-breaking |
| model-selection | [`_shared/model-selection.md`](_shared/model-selection.md) | Per-agent model/effort/maxTurns assignments and opus+xhigh override paths |
| severity-matrix | [`_shared/severity-matrix.md`](_shared/severity-matrix.md) | Severity levels, P0-P3 review priorities, effort/impact quadrant, coverage requirements |
| testing-principles | [`_shared/testing-principles.md`](_shared/testing-principles.md) | Test pyramid, per-language framework matrix, quality gates, anti-patterns |

### c

| Skill | Path | Description |
|-------|------|-------------|
| **c** (entry) | [`c/SKILL.md`](c/SKILL.md) | C language skills navigation: C17/C23 selection, C23 adoption, memory ownership, UB, concurrency |
| **modern-c** | [`c/modern-c/SKILL.md`](c/modern-c/SKILL.md) | Modern C for C17 and C23: standard selection, C23 quick wins, checked integer arithmetic, hygiene flags |
| **c-memory-ownership** | [`c/c-memory-ownership/SKILL.md`](c/c-memory-ownership/SKILL.md) | Ownership conventions, cleanup patterns, allocator selection, sanitizer-first debugging |

### cpp

| Skill | Path | Description |
|-------|------|-------------|
| **cpp** (entry) | [`cpp/SKILL.md`](cpp/SKILL.md) | C++ skills navigation and the canonical standard-selection table for C++17/20/23 |
| **modern-cpp** | [`cpp/modern-cpp/SKILL.md`](cpp/modern-cpp/SKILL.md) | Core idioms: RAII, Rule of Zero, smart-pointer ownership, vocabulary types, constexpr family, deducing this, std::print |
| **cpp-concurrency** | [`cpp/cpp-concurrency/SKILL.md`](cpp/cpp-concurrency/SKILL.md) | jthread/stop_token, mutexes, atomics and memory ordering, latch/barrier/semaphore, coroutines, std::generator, TSan-first verification |

### python

| Skill | Path | Description |
|-------|------|-------------|
| **python** (entry) | [`python/SKILL.md`](python/SKILL.md) | Python skills navigation for 3.12-3.14: features, typing, concurrency, tooling, testing |
| **modern-python** | [`python/modern-python/SKILL.md`](python/modern-python/SKILL.md) | Language features for 3.12-3.14 with explicit version gates: t-strings, deferred annotations, except*, PEP 695, zstd, PEP 765 finally warning |
| **python-typing** | [`python/python-typing/SKILL.md`](python/python-typing/SKILL.md) | Static typing: PEP 695 generics, protocols over ABCs, TypedDict/Literal/overload/ParamSpec, strict pyright/mypy |
| **python-concurrency** | [`python/python-concurrency/SKILL.md`](python/python-concurrency/SKILL.md) | Choose and implement the right 3.14 concurrency model — asyncio, threads, free-threading, subinterpreters, multiprocessing |
| **python-tooling** | [`python/python-tooling/SKILL.md`](python/python-tooling/SKILL.md) | uv as the single tool plus ruff, with pyproject.toml as the one source of truth; dependencies, lockfiles, CI, src/ layout |
| **python-testing** | [`python/python-testing/SKILL.md`](python/python-testing/SKILL.md) | pytest for 3.12-3.14: plain-assert tests, fixtures, parametrization, async, mocking, coverage, Hypothesis |

### bash

| Skill | Path | Description |
|-------|------|-------------|
| **bash** (entry) | [`bash/SKILL.md`](bash/SKILL.md) | Bash and POSIX shell skills navigation: scripting, portability, when shell has outgrown the task, tooling |
| **bash-scripting** | [`bash/bash-scripting/SKILL.md`](bash/bash-scripting/SKILL.md) | Defensive scripting: strict-mode prologue, quoting, arrays, traps, safe resource handling |
| **bash-testing** | [`bash/bash-testing/SKILL.md`](bash/bash-testing/SKILL.md) | bats-core tests, sourceable/testable scripts, PATH stubs, shellcheck/shfmt in CI |

### embedded

| Skill | Path | Description |
|-------|------|-------------|
| **embedded** (entry) | [`embedded/SKILL.md`](embedded/SKILL.md) | Embedded/bare-metal skills navigation: freestanding vs hosted, registers, ISRs, no-heap, fixed-point, linkers, cross-compilation, the C++ subset |
| **embedded-systems** | [`embedded/embedded-systems/SKILL.md`](embedded/embedded-systems/SKILL.md) | Language-agnostic core: freestanding, MMIO/register access, `volatile` (and why it is not concurrency), ISRs/startup, no-heap allocation, fixed-point, linker scripts, cross-compilation |
| **embedded-cpp** | [`embedded/embedded-cpp/SKILL.md`](embedded/embedded-cpp/SKILL.md) | C++ subset for embedded: RAII without exceptions/RTTI (`-fno-exceptions -fno-rtti -ffreestanding`), freestanding stdlib subset, static/placement-new construction, `constexpr`/`constinit` ROM-able data |

### tooling

| Skill | Path | Description |
|-------|------|-------------|
| **tooling** (entry) | [`tooling/SKILL.md`](tooling/SKILL.md) | Build, diagnostics, and interop tooling navigation; routes "won't build", "crashes", "too slow", "can't link" symptoms |
| **build-systems** | [`tooling/build-systems/SKILL.md`](tooling/build-systems/SKILL.md) | Modern CMake doctrine, CMakePresets, FetchContent vs vcpkg vs Conan, CMake 4.x migration, C++ modules, Meson/Make |
| **diagnostics** | [`tooling/diagnostics/SKILL.md`](tooling/diagnostics/SKILL.md) | Route a runtime symptom (crash, wrong values, race, leak, slow) to the right sanitizer, debugger, or profiler with exact flags |
| **ffi-interop** | [`tooling/ffi-interop/SKILL.md`](tooling/ffi-interop/SKILL.md) | Bind C/C++ to Python and design native ABI boundaries: nanobind/pybind11/cffi/ctypes, extern "C", GIL release, scikit-build-core |

## Child Indexes

| Index Path | Contents |
|------------|----------|
| [`_shared/_index.md`](_shared/_index.md) | Shared skills: workflow, secure coding, versions, routing, severity, testing |
| [`c/_index.md`](c/_index.md) | C entry + modern-c + c-memory-ownership |
| [`cpp/_index.md`](cpp/_index.md) | C++ entry + modern-cpp + cpp-concurrency |
| [`cpp/modern-cpp/references/_index.md`](cpp/modern-cpp/references/_index.md) | modern-cpp deep-dive references (C++17/20/23 features, ranges, error handling) |
| [`python/_index.md`](python/_index.md) | Python entry + 5 leaf skills |
| [`python/python-concurrency/references/_index.md`](python/python-concurrency/references/_index.md) | Concurrency deep-dive references (asyncio, free-threading, subinterpreters) |
| [`bash/_index.md`](bash/_index.md) | Bash entry + bash-scripting + bash-testing |
| [`embedded/_index.md`](embedded/_index.md) | Embedded entry + embedded-systems + embedded-cpp (with references) |
| [`tooling/_index.md`](tooling/_index.md) | Tooling entry + build-systems + diagnostics + ffi-interop |
| [`tooling/diagnostics/references/_index.md`](tooling/diagnostics/references/_index.md) | diagnostics deep-dive references (sanitizers, gdb/lldb, profiling tools) |
