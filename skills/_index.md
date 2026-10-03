# Skills Index

Root index for all system-developer skills (C, C++, Python, Bash, embedded, and
shared tooling). [`SKILL.md`](SKILL.md) is the routing entry point.

## Domains

| Directory | Skills | Description |
|-----------|--------|-------------|
| [_shared/](_shared/_index.md) | 1 + refs | Secure coding, versions, routing, model selection, severity, testing principles |
| [c/](c/SKILL.md) | 1 + 2 leaves | C17/C23 selection, C23 features, memory ownership, UB, C11/C17 concurrency |
| [cpp/](cpp/SKILL.md) | 1 + 2 leaves | C++17/20/23 selection (C++26 emerging), RAII, ranges, concepts, coroutines, concurrency |
| [python/](python/SKILL.md) | 1 + 5 leaves | Python 3.12-3.14 features, typing, concurrency, uv/ruff tooling, pytest testing |
| [bash/](bash/SKILL.md) | 1 + 2 leaves | Defensive Bash scripting, POSIX portability, bats/shellcheck/shfmt testing |
| [embedded/](embedded/SKILL.md) | 1 + 2 leaves | Bare-metal C & C++: MMIO, volatile, ISRs/startup, no-heap, fixed-point, linker scripts, cross-compilation, C++ subset |
| [tooling/](tooling/SKILL.md) | 1 + 3 leaves | Build systems, sanitizers, debuggers, profilers, FFI/interop |

## All Skills

### _shared

| Skill | Description |
|-------|-------------|
| [**secure-coding**](_shared/secure-coding/SKILL.md) | Security rules for C, C++, Python, and Bash: injection-safe execution, memory-corruption → sanitizer mapping, integer safety, path traversal/TOCTOU, secrets |
| [version-feature-matrix](_shared/version-feature-matrix.md) | Standards/versions → minimum toolchains and headline features |
| [language-detection](_shared/language-detection.md) | Marker → language → agent routing table, detection priority, tie-breaking |
| [model-selection](_shared/model-selection.md) | Per-agent model/effort/maxTurns assignments and opus override paths |
| [severity-matrix](_shared/severity-matrix.md) | Severity levels, P0-P3 review priorities, effort/impact quadrant, coverage requirements |
| [testing-principles](_shared/testing-principles.md) | Test pyramid, per-language framework matrix, quality gates, anti-patterns |

### c

| Skill | Description |
|-------|-------------|
| [**c**](c/SKILL.md) (entry) | C language skills navigation: C17/C23 selection, C23 adoption, memory ownership, UB, concurrency |
| [**modern-c**](c/modern-c/SKILL.md) | Modern C for C17 and C23: standard selection, C23 quick wins, checked integer arithmetic, hygiene flags |
| [**c-memory-ownership**](c/c-memory-ownership/SKILL.md) | Ownership conventions, cleanup patterns, allocator selection, sanitizer-first debugging |

### cpp

| Skill | Description |
|-------|-------------|
| [**cpp**](cpp/SKILL.md) (entry) | C++ skills navigation and the canonical standard-selection table for C++17/20/23 |
| [**modern-cpp**](cpp/modern-cpp/SKILL.md) | Core idioms: RAII, Rule of Zero, smart-pointer ownership, vocabulary types, constexpr family, deducing this, std::print |
| [**cpp-concurrency**](cpp/cpp-concurrency/SKILL.md) | jthread/stop_token, mutexes, atomics and memory ordering, latch/barrier/semaphore, coroutines, std::generator, TSan-first verification |

### python

| Skill | Description |
|-------|-------------|
| [**python**](python/SKILL.md) (entry) | Navigation for Python 3.12-3.14: features, typing, concurrency, tooling, testing |
| [**modern-python**](python/modern-python/SKILL.md) | 3.12-3.14 features with version gates: t-strings, deferred annotations, except*, PEP 695, zstd, PEP 765 |
| [**python-typing**](python/python-typing/SKILL.md) | Static typing: PEP 695 generics, protocols over ABCs, TypedDict/Literal/overload/ParamSpec, strict pyright/mypy |
| [**python-concurrency**](python/python-concurrency/SKILL.md) | Pick and implement a 3.14 concurrency model: asyncio, threads, free-threading, subinterpreters, multiprocessing |
| [**python-tooling**](python/python-tooling/SKILL.md) | uv + ruff, pyproject.toml as single source of truth; dependencies, lockfiles, CI, src/ layout |
| [**python-testing**](python/python-testing/SKILL.md) | pytest: plain-assert tests, fixtures, parametrization, async, mocking, coverage, Hypothesis |

### bash

| Skill | Description |
|-------|-------------|
| [**bash**](bash/SKILL.md) (entry) | Bash and POSIX shell skills navigation: scripting, portability, when shell has outgrown the task, tooling |
| [**bash-scripting**](bash/bash-scripting/SKILL.md) | Defensive scripting: strict-mode prologue, quoting, arrays, traps, safe resource handling |
| [**bash-testing**](bash/bash-testing/SKILL.md) | bats-core tests, sourceable/testable scripts, PATH stubs, shellcheck/shfmt in CI |

### embedded

| Skill | Description |
|-------|-------------|
| [**embedded**](embedded/SKILL.md) (entry) | Embedded/bare-metal skills navigation: freestanding vs hosted, registers, ISRs, no-heap, fixed-point, linkers, cross-compilation, the C++ subset |
| [**embedded-systems**](embedded/embedded-systems/SKILL.md) | Language-agnostic core: freestanding, MMIO/register access, `volatile` (and why it is not concurrency), ISRs/startup, no-heap allocation, fixed-point, linker scripts, cross-compilation |
| [**embedded-cpp**](embedded/embedded-cpp/SKILL.md) | C++ subset for embedded: RAII without exceptions/RTTI (`-fno-exceptions -fno-rtti -ffreestanding`), freestanding stdlib subset, static/placement-new construction, `constexpr`/`constinit` ROM-able data |

### tooling

| Skill | Description |
|-------|-------------|
| [**tooling**](tooling/SKILL.md) (entry) | Build, diagnostics, and interop tooling navigation; routes "won't build", "crashes", "too slow", "can't link" symptoms |
| [**build-systems**](tooling/build-systems/SKILL.md) | Modern CMake doctrine, CMakePresets, FetchContent vs vcpkg vs Conan, CMake 4.x migration, C++ modules, Meson/Make |
| [**diagnostics**](tooling/diagnostics/SKILL.md) | Route a runtime symptom (crash, wrong values, race, leak, slow) to the right sanitizer, debugger, or profiler with exact flags |
| [**ffi-interop**](tooling/ffi-interop/SKILL.md) | Bind C/C++ to Python and design native ABI boundaries: nanobind/pybind11/cffi/ctypes, extern "C", GIL release, scikit-build-core |

## Child Indexes

### Domain indexes

| Index Path | Contents |
|------------|----------|
| [`_shared/_index.md`](_shared/_index.md) | Shared: secure coding, versions, routing, model selection, severity, testing |
| [`c/_index.md`](c/_index.md) | C entry + modern-c + c-memory-ownership |
| [`cpp/_index.md`](cpp/_index.md) | C++ entry + modern-cpp + cpp-concurrency |
| [`python/_index.md`](python/_index.md) | Python entry + 5 leaf skills |
| [`bash/_index.md`](bash/_index.md) | Bash entry + bash-scripting + bash-testing |
| [`embedded/_index.md`](embedded/_index.md) | Embedded entry + embedded-systems + embedded-cpp (with references) |
| [`tooling/_index.md`](tooling/_index.md) | Tooling entry + build-systems + diagnostics + ffi-interop |

### Reference indexes

| Index Path | Contents |
|------------|----------|
| [`cpp/modern-cpp/references/_index.md`](cpp/modern-cpp/references/_index.md) | modern-cpp deep-dive references (C++17/20/23 features, ranges, error handling) |
| [`python/python-concurrency/references/_index.md`](python/python-concurrency/references/_index.md) | Concurrency deep-dive references (asyncio, free-threading, subinterpreters) |
| [`tooling/diagnostics/references/_index.md`](tooling/diagnostics/references/_index.md) | diagnostics deep-dive references (sanitizers, gdb/lldb, profiling tools) |
