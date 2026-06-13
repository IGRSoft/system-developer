---
name: ffi-interop
description: >-
  Bind C and C++ to Python and design native ABI boundaries. Use when
  exposing a C/C++ library to Python, choosing between nanobind, pybind11,
  cffi, and ctypes, designing an extern "C" boundary, releasing the GIL
  around native calls, building wheels with scikit-build-core, or debugging
  a mixed Python/native stack.
---

# FFI & Interop

**Choosing a binding tool and getting the C ABI boundary right**

> Baseline: **CPython 3.14**, **C++17+** for binding libraries, **C17/C23** for
> the ABI layer. Tool versions move fast — confirm with `--version` and treat
> specific behaviors as "verify against your toolchain."

## When to Use

- Calling a C or C++ library from Python (or shipping a native extension).
- Picking a binding approach for a *new* project, or auditing an existing one.
- Designing the `extern "C"` surface a native library exposes to any consumer.
- A long native call is starving other Python threads (GIL not released).
- Targeting the free-threaded build (`python3.14t`) from a native extension.
- A crash lands half in Python frames and half in native frames.

## Tool Selection

Pick by what you are binding and what build cost you accept.

| Tool | Binds | Build step | Use when | Avoid when |
|------|-------|-----------|----------|------------|
| **nanobind** | C++ (rich types) | compile (CMake) | **New C++ bindings** — leaner/faster than pybind11, first-class free-threading | You need pre-C++17 support |
| **pybind11** | C++ (rich types) | compile (CMake) | Existing pybind11 codebase; widest examples/maturity | Greenfield where nanobind fits (prefer nanobind) |
| **cffi** | C only | optional (API mode compiles) | C ABI, want PyPy-friendly + ABI/API modes | You have C++ classes to expose |
| **ctypes** | C only | **none** (stdlib) | Quick call into an existing `.so`/`.dylib`, zero build, scripts | Hot loops (per-call overhead), C++ name-mangled symbols |

Rules of thumb:

- **New C++ project → nanobind.** Smaller binaries, faster compiles, free-threading built in.
- **C-only, no build tolerated → ctypes.** It is in the stdlib; nothing to ship.
- **C-only, want a real compiled shim and PyPy support → cffi.**
- **Exposing C++ classes / `std::` types / operator overloads → pybind11 or nanobind**, never ctypes/cffi.

See [references/pybind11-nanobind.md](references/pybind11-nanobind.md) for the compiled
C++ path and [references/c-api-boundaries.md](references/c-api-boundaries.md) for the
C-ABI design that ctypes/cffi consume.

## The C ABI Boundary Doctrine

Whatever crosses the language boundary should be a **stable, C-shaped surface** —
even when the implementation is C++. This is the single most important habit.

1. **`extern "C"` wrapper layer.** C++ implementation lives behind a thin C API.
   `extern "C"` disables name mangling so any consumer (Python, another C ABI, a
   different C++ compiler) can link.
2. **Opaque handles.** Hand out forward-declared pointers, not struct layouts.
   The caller never sees fields, so you can change internals without breaking the ABI.
3. **No exceptions across the boundary.** A C++ exception unwinding into C is
   undefined behavior. Wrap every entry point in a catch-all and convert to an
   error code.
4. **No STL types in signatures.** `std::string`, `std::vector`, iterators have no
   stable ABI. Pass `const char*` + length, `T* + size_t`, or opaque handles.
5. **Ownership documented per function.** Every pointer that crosses must state who
   frees it and with which function. Pair every `*_create` with a `*_destroy`.

```c
/* mylib.h — the only header a consumer needs */
#ifdef __cplusplus
extern "C" {
#endif

typedef struct ml_engine ml_engine;          /* opaque handle */

typedef enum { ML_OK = 0, ML_EINVAL = 1, ML_ENOMEM = 2, ML_ERUNTIME = 3 } ml_status;

ml_engine *ml_engine_create(const char *config, size_t config_len);  /* caller owns; free with ml_engine_destroy */
void       ml_engine_destroy(ml_engine *e);                          /* tolerates NULL */
ml_status  ml_engine_run(ml_engine *e, const double *in, size_t n, double *out);

#ifdef __cplusplus
}
#endif
```

```cpp
// mylib.cpp — exceptions stop at the boundary, never cross it
extern "C" ml_status ml_engine_run(ml_engine *e, const double *in, size_t n, double *out) {
    if (!e || (!in && n) || !out) return ML_EINVAL;
    try {
        reinterpret_cast<Engine *>(e)->run(in, n, out);   // C++ may throw
        return ML_OK;
    } catch (const std::bad_alloc &) { return ML_ENOMEM; }
      catch (...)                    { return ML_ERUNTIME; }  // catch-all is mandatory
}
```

Full treatment — versioned structs, callback safety, symbol visibility, and the
ctypes/cffi side — in [references/c-api-boundaries.md](references/c-api-boundaries.md).

## Minimal nanobind Module + Packaging

The standard 2026 path is a **CMake-driven wheel via scikit-build-core**. Same shape
for pybind11 (swap `nanobind` for `pybind11` in `CMakeLists.txt` and the build dep).

```cpp
// src/example_ext.cpp
#include <nanobind/nanobind.h>
namespace nb = nanobind;

int add(int a, int b) { return a + b; }

NB_MODULE(example_ext, m) {          // module name MUST match the built target
    m.def("add", &add, "a"_a, "b"_a, "Add two integers");
}
```

```cmake
# CMakeLists.txt
cmake_minimum_required(VERSION 3.15...3.30)
project(example LANGUAGES CXX)

find_package(Python 3.14 COMPONENTS Interpreter Development.Module REQUIRED)
find_package(nanobind CONFIG REQUIRED)

nanobind_add_module(example_ext STABLE_ABI src/example_ext.cpp)
install(TARGETS example_ext LIBRARY DESTINATION example)
```

```toml
# pyproject.toml — scikit-build-core turns CMake into a wheel
[build-system]
requires = ["scikit-build-core >=0.10", "nanobind >=2"]
build-backend = "scikit_build_core.build"

[project]
name = "example"
version = "0.1.0"
requires-python = ">=3.14"

[tool.scikit-build]
minimum-version = "build-system.requires"
build-dir = "build/{wheel_tag}"
```

Build with `uv build` (or `pip wheel .`). The full packaging story — stub
generation, editable installs, multi-platform wheels — is in
[references/pybind11-nanobind.md](references/pybind11-nanobind.md).

## GIL & Free-Threading

Two distinct concerns. Do not conflate them.

**Release the GIL around long native calls** so other Python threads run. This
applies on *every* build, GIL or free-threaded:

```cpp
// nanobind: release the GIL for the whole call
m.def("crunch", &crunch, nb::call_guard<nb::gil_scoped_release>());

// pybind11: same idea
m.def("crunch", &crunch, py::call_guard<py::gil_scoped_release>());
```

While the GIL is released, your code **must not touch any Python object** without
re-acquiring it. Only release around pure-native work.

**Free-threaded build (`python3.14t`)** needs *two* things, and the first without
the second is a trap:

1. **Declare it.** The module must opt in, or the interpreter re-enables the GIL at
   import and prints a warning.
   - nanobind: `nanobind_add_module(my_ext FREE_THREADED ...)` in CMake.
   - Raw C-API / pybind11: `Py_mod_gil` slot set to `Py_MOD_GIL_NOT_USED`.
2. **Actually be thread-safe.** Declaring `Py_MOD_GIL_NOT_USED` only suppresses the
   GIL — it does **not** make your code safe. Concurrent calls now run truly in
   parallel; shared native state needs locks (nanobind's `nb::ft_mutex`,
   `nb::arg().lock()`, or `std::atomic`). Declaring without protecting causes data
   races and corruption.

> PEP 779 made the free-threaded build officially supported in 3.14. Verify with
> `python3.14t -c "import sys; print(sys._is_gil_enabled())"` (expect `False`).

Details and the `Py_mod_gil` boilerplate are in
[references/pybind11-nanobind.md](references/pybind11-nanobind.md).

## Error Translation

Errors must change shape at each hop. Define the mapping once and keep it consistent.

| C layer | C++ layer | Python layer |
|---------|-----------|--------------|
| `return ML_EINVAL` | `throw std::invalid_argument` | `ValueError` |
| `return ML_ENOMEM` | `throw std::bad_alloc` | `MemoryError` |
| `errno`-style (e.g. `EACCES`) | `std::system_error` | `OSError` (with `errno`) |
| `return ML_ERUNTIME` | `throw std::runtime_error` | `RuntimeError` |
| out-of-range index | `throw std::out_of_range` | `IndexError` |
| (no exceptions across `extern "C"`) | catch-all → error code | binding re-raises from code |

In nanobind/pybind11, standard C++ exceptions auto-translate to the Python types
above. When you consume a C ABI through ctypes/cffi, you check the return code and
`raise` the matching Python exception yourself. Never let a non-zero status pass
silently.

## Mixed-Stack Debugging

When a fault straddles Python and native frames, ordinary tools see only half.

| Need | Tool | Invocation |
|------|------|-----------|
| Native stack of a *running* Python process | `py-spy` | `py-spy dump --pid <pid> --native` |
| Step through the C/C++ extension | gdb / lldb | `gdb --args python3 -X dev script.py` → `break`, `run` |
| Memory bug inside the extension | ASan | `LD_PRELOAD=$(gcc -print-file-name=libasan.so) python3 script.py` (Linux) |
| Use-after-free / leak in the C ABI | ASan/LSan, valgrind | see [diagnostics](../diagnostics/SKILL.md) |

Build the extension with `-g` (and `-O0`/`-Og`) so native frames have symbols. On
macOS, prefer lldb and ASan via the compiler's runtime rather than `LD_PRELOAD`.
Debugger workflows live in [diagnostics/references/gdb-lldb.md](../diagnostics/references/gdb-lldb.md).

## Diagnostics

| Error / symptom | Cause | Fix | Reference |
|-----------------|-------|-----|-----------|
| `ImportError: dynamic module does not define module export function` | module name ≠ built target | match `NB_MODULE`/`PyInit_` name to the compiled `.so` stem | [pybind11-nanobind](references/pybind11-nanobind.md) |
| `undefined symbol: _Z3addii` from ctypes | C++ mangled name; ctypes needs C linkage | wrap in `extern "C"` | [c-api-boundaries](references/c-api-boundaries.md) |
| App crashes when a C++ exception reaches C | exception unwinding across `extern "C"` is UB | catch-all at every boundary entry → error code | [c-api-boundaries](references/c-api-boundaries.md) |
| `RuntimeWarning: ... re-enabling the GIL` on `python3.14t` | extension did not declare GIL-not-used | `FREE_THREADED` / `Py_MOD_GIL_NOT_USED` **and** make code thread-safe | [pybind11-nanobind](references/pybind11-nanobind.md) |
| GUI/other threads freeze during a native call | GIL held for the whole call | `nb::call_guard<nb::gil_scoped_release>()` around native work | [pybind11-nanobind](references/pybind11-nanobind.md) |
| Segfault touching a Python object after release | accessing Python while GIL released | re-acquire (`gil_scoped_acquire`) or don't release there | [pybind11-nanobind](references/pybind11-nanobind.md) |
| Data corruption only on `python3.14t` | declared GIL-free but native state unguarded | add `nb::ft_mutex` / `std::atomic` / `.lock()` | [pybind11-nanobind](references/pybind11-nanobind.md) |
| Returned pointer freed twice / leaked | ownership policy undefined | set `return_value_policy`; document free function | [pybind11-nanobind](references/pybind11-nanobind.md) |
| `error: no member named ... std::string` over the boundary | STL type in `extern "C"` signature | use `const char*` + length / opaque handle | [c-api-boundaries](references/c-api-boundaries.md) |

## Related Skills

- [pybind11-nanobind](references/pybind11-nanobind.md) — compiled C++ bindings, return-value policies, GIL, free-threading, scikit-build-core packaging, stubs
- [c-api-boundaries](references/c-api-boundaries.md) — stable `extern "C"` ABI, opaque handles, versioned structs, callbacks, ctypes/cffi consumption, symbol visibility
- [build-systems](../build-systems/SKILL.md) — CMake driving the native build behind the wheel
- [diagnostics](../diagnostics/SKILL.md) — sanitizers and debuggers for the native side
- [python-concurrency](../../python/python-concurrency/SKILL.md) — free-threading from the Python side
- [c-memory-ownership](../../c/c-memory-ownership/SKILL.md) — ownership conventions the C ABI must honor
- [secure-coding](../../_shared/secure-coding/SKILL.md) — validating data crossing the trust boundary
