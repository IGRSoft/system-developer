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

Pick the binding tool, keep the boundary C-shaped, and get ownership, errors, and the GIL right at each hop. Compiled C++ bindings are in [pybind11-nanobind.md](references/pybind11-nanobind.md); the `extern "C"` ABI and its ctypes/cffi consumers are in [c-api-boundaries.md](references/c-api-boundaries.md).

## Tool Selection

| Tool | Binds | Build step | Use when | Avoid when |
|------|-------|-----------|----------|------------|
| nanobind | C++ (rich types) | compile (CMake) | New C++ bindings: leaner and faster than pybind11, first-class free-threading | You need pre-C++17 |
| pybind11 | C++ (rich types) | compile (CMake) | Existing pybind11 codebase; most examples | Greenfield where nanobind fits |
| cffi | C only | optional (API mode compiles) | C ABI with a compiled shim, PyPy support | C++ classes to expose |
| ctypes | C only | none (stdlib) | Quick calls into an existing `.so`/`.dylib`, scripts | Hot loops (per-call overhead), mangled C++ symbols |

C++ classes, `std::` types, and operator overloads need pybind11 or nanobind; ctypes and cffi only see C linkage.

## The C ABI Boundary Doctrine

Whatever crosses the language boundary is a stable, C-shaped surface, even when the implementation is C++:

1. `extern "C"` wrapper layer, so symbols are unmangled and any consumer can link.
2. Opaque handles (forward-declared struct pointers), so internals can change without breaking the ABI.
3. No exceptions across the boundary: unwinding into C is undefined behavior. Catch-all at every entry point, return an error code.
4. No STL types in signatures: pass `const char*` + length, `T*` + `size_t`, or handles.
5. Ownership documented per function; every `*_create` has a `*_destroy`.

### Example header

```c
/* mylib.h — the only header a consumer needs */
#ifdef __cplusplus
extern "C" {
#endif
typedef struct ml_engine ml_engine;          /* opaque handle */
typedef enum { ML_OK = 0, ML_EINVAL = 1, ML_ENOMEM = 2, ML_ERUNTIME = 3 } ml_status;

ml_engine *ml_engine_create(const char *config, size_t config_len);  /* free with ml_engine_destroy */
void       ml_engine_destroy(ml_engine *e);                          /* tolerates NULL */
ml_status  ml_engine_run(ml_engine *e, const double *in, size_t n, double *out);
#ifdef __cplusplus
}
#endif
```

### Example implementation

```cpp
// mylib.cpp — struct ml_engine { Engine impl; }; is defined only here
extern "C" ml_status ml_engine_run(ml_engine *e, const double *in, size_t n, double *out) {
    if (!e || (!in && n) || !out) return ML_EINVAL;
    try {
        e->impl.run(in, n, out);             // C++ may throw
        return ML_OK;
    } catch (const std::bad_alloc &) { return ML_ENOMEM; }
      catch (...)                    { return ML_ERUNTIME; }
}
```

## Minimal nanobind Module + Packaging

A CMake build wrapped as a wheel by scikit-build-core. For pybind11, swap the package name in `requires` and use `pybind11_add_module`.

```cpp
// src/example_ext.cpp
#include <nanobind/nanobind.h>
namespace nb = nanobind;
using namespace nb::literals;

int add(int a, int b) { return a + b; }

NB_MODULE(example_ext, m) {          // name must match the built target
    m.def("add", &add, "a"_a, "b"_a, "Add two integers");
}
```

### Build files

```cmake
cmake_minimum_required(VERSION 3.15...3.30)
project(example LANGUAGES CXX)
find_package(Python 3.14 COMPONENTS Interpreter Development.Module REQUIRED)
find_package(nanobind CONFIG REQUIRED)
nanobind_add_module(example_ext src/example_ext.cpp)
install(TARGETS example_ext LIBRARY DESTINATION example)
```

```toml
[build-system]
requires = ["scikit-build-core >=0.10", "nanobind >=2"]
build-backend = "scikit_build_core.build"

[project]
name = "example"
version = "0.1.0"
requires-python = ">=3.14"
```

Build with `uv build`. Stable-ABI wheels, editable installs, and stubs: [pybind11-nanobind.md](references/pybind11-nanobind.md#packaging-with-scikit-build-core).

## GIL & Free-Threading

Two separate concerns.

Release the GIL around long pure-native calls so other Python threads run, on every build:

```cpp
m.def("crunch", &crunch, nb::call_guard<nb::gil_scoped_release>());   // pybind11: py::
```

While it is released, touch no Python object; re-acquire with `gil_scoped_acquire` first.

The free-threaded build (`python3.14t`) needs both of these:

1. Declare support, or the interpreter re-enables the GIL at import with a warning: `FREE_THREADED` in `nanobind_add_module`, `py::mod_gil_not_used()` in `PYBIND11_MODULE`, or the `Py_mod_gil` slot set to `Py_MOD_GIL_NOT_USED` in the raw C API.
2. Be thread-safe. The declaration only removes the GIL; concurrent calls now run in parallel, so shared native state needs `nb::ft_mutex`, `nb::arg().lock()`, or `std::atomic`.

Details: [pybind11-nanobind.md](references/pybind11-nanobind.md#free-threading-python314t).

## Error Translation

Errors change shape at each hop; define the mapping once.

| C layer | C++ layer | Python layer |
|---------|-----------|--------------|
| `return ML_EINVAL` | `throw std::invalid_argument` | `ValueError` |
| `return ML_ENOMEM` | `throw std::bad_alloc` | `MemoryError` |
| `return ML_ERUNTIME` | `throw std::runtime_error` | `RuntimeError` |
| out-of-range index | `throw std::out_of_range` | `IndexError` |
| `errno`-style (e.g. `EACCES`) | `std::system_error` | `OSError`, via a custom translator (default is `RuntimeError`) |

nanobind and pybind11 translate the standard exceptions above automatically. Through ctypes/cffi, check every return code and raise the matching Python exception yourself.

## Mixed-Stack Debugging

| Need | Invocation |
|------|-----------|
| Native stack of a running Python process | `py-spy dump --pid <pid> --native` |
| Step through the extension | `gdb --args python3 -X dev script.py` (lldb on macOS) |
| Memory bugs in the extension | ASan runtime preloaded into `python`, see [sanitizers.md](../diagnostics/references/sanitizers.md#python-c-extensions-under-sanitizers) |

Build the extension with `-g -Og` so native frames have symbols. Debugger workflows: [gdb-lldb.md](../diagnostics/references/gdb-lldb.md).

## Diagnostics

### Build and import

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ImportError: dynamic module does not define module export function` | module name ≠ built target | match `NB_MODULE`/`PyInit_` name to the `.so` stem |
| ctypes `undefined symbol: _Z3addii` | C++ mangled name | wrap in `extern "C"` |
| clang: `has C-linkage specified, but returns user-defined type` | STL type in an `extern "C"` signature | `const char*` + length or an opaque handle |
| Crash when a C++ exception reaches C | unwinding across `extern "C"` | catch-all at every entry, return a code |

### Runtime

| Symptom | Cause | Fix |
|---------|-------|-----|
| `RuntimeWarning: ... re-enabling the GIL` on `python3.14t` | no free-threading declaration | declare it and make the code thread-safe |
| Other threads freeze during a native call | GIL held | `call_guard<gil_scoped_release>()` |
| Segfault touching a Python object after release | GIL not held | `gil_scoped_acquire` first |
| Corruption only on `python3.14t` | shared native state unguarded | `nb::ft_mutex` / `.lock()` / `std::atomic` |
| Returned pointer freed twice or leaked | ownership undefined | explicit return-value policy; documented free function |

## Related Skills

| Skill | For |
|-------|-----|
| [build-systems](../build-systems/SKILL.md) | CMake behind the wheel |
| [diagnostics](../diagnostics/SKILL.md) | sanitizers and debuggers for the native side |
| [python-concurrency](../../python/python-concurrency/SKILL.md) | free-threading from the Python side |
| [c-memory-ownership](../../c/c-memory-ownership/SKILL.md) | ownership conventions the C ABI honors |
| [secure-coding](../../_shared/secure-coding/SKILL.md) | validating data crossing the trust boundary |
