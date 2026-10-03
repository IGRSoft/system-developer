# Stable C ABI Boundaries

Designing the `extern "C"` surface a native library exposes, and consuming it from Python with ctypes or cffi. C++ has no stable ABI (mangling, vtable and `std::` layouts, and exception machinery vary by compiler and flags), so even a pure-C++ library exposes a thin C facade at a boundary. Binding C++ classes directly: [pybind11-nanobind.md](pybind11-nanobind.md).

## extern "C" Linkage

`extern "C"` makes a C++ compiler emit unmangled names, linkable as plain C.

```c
/* mylib.h — guarded so both C and C++ consumers include it */
#ifndef MYLIB_H
#define MYLIB_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ... declarations ... */

#ifdef __cplusplus
}
#endif

#endif /* MYLIB_H */
```

The implementation file is C++ but each exported function carries C linkage:

```cpp
// mylib.cpp
#include "mylib.h"
#include "engine.hpp"   // internal C++ — never in the public header

extern "C" int ml_add(int a, int b) {   // emitted as `ml_add`, not `_Z6ml_addii`
    return a + b;
}
```

### Rules

- No C++ types in signatures: no `std::` types, references, templates, overloads, or default arguments. Use C fundamentals, `<stdint.h>` ints, pointers, and your own structs.
- One symbol per name, so give distinct names (`ml_open_file`, `ml_open_socket`).
- The public header compiles as both C and C++ and includes no C++ headers.
- Write `(void)` for empty parameter lists; `()` means "no arguments" only from C23 on.

## Opaque Handles

Expose a forward-declared, incomplete struct pointer. Consumers hold and pass it but cannot depend on its fields, so the layout is not part of the ABI.

```c
/* public header */
typedef struct ml_engine ml_engine;

ml_engine *ml_engine_create(void);
void       ml_engine_destroy(ml_engine *e);
int        ml_engine_step(ml_engine *e);
```

```cpp
struct ml_engine {            // defined only in the .cpp
    Engine impl;
    std::vector<double> scratch;
};

extern "C" ml_engine *ml_engine_create(void) {
    try { return new ml_engine{}; }   // new and Engine() may throw
    catch (...) { return nullptr; }   // never let it cross the boundary
}
extern "C" void ml_engine_destroy(ml_engine *e) {
    delete e;                 // tolerate NULL: delete nullptr is safe
}
```

Prefer opaque handles; use a public struct only when consumers need its fields (see Versioned Structs).


## Ownership Across the Boundary

Every pointer that crosses states who frees it and with which function, in the header comment and in the binding. A free-function mismatch is the most common cross-language bug.

- Pair every constructor with a destructor from the same library: a consumer's `free` on a library `malloc` across different CRTs is undefined.
- Caller-allocates: caller passes buffer + capacity, the library fills it and reports the needed size. No cross-boundary free at all, the cleanest option.
- Library-allocates: return a pointer with a documented matching free function.
- Borrowed: say "borrowed; valid until the next call / until destroy" and offer no free function.
- Destroy/free functions accept NULL and no-op, like `free(NULL)`.

### Example

```c
/* ML_OK, or ML_ETOOSMALL with *needed set to the required length. */
ml_status ml_render(ml_engine *e, char *buf, size_t cap, size_t *needed);

char *ml_describe(ml_engine *e);   /* caller frees with ml_free_string */
void  ml_free_string(char *s);     /* tolerates NULL */
```

## Error Propagation

A C++ exception unwinding into a C frame is undefined behavior (typically `std::terminate`), so every entry point catches everything and returns a status.

```c
/* Append only; never renumber. 0 is success. */
typedef enum {
    ML_OK = 0, ML_EINVAL = 1, ML_ENOMEM = 2, ML_ETOOSMALL = 3, ML_ERUNTIME = 4
} ml_status;
const char *ml_status_str(ml_status s);   /* static storage */
```

```cpp
extern "C" ml_status ml_engine_step(ml_engine *e) {
    if (!e) return ML_EINVAL;
    try {
        e->impl.step();
        return ML_OK;
    } catch (const std::invalid_argument &) { return ML_EINVAL; }
      catch (const std::bad_alloc &)        { return ML_ENOMEM; }
      catch (...)                           { return ML_ERUNTIME; }
}
```

### Guidelines

- Return the status; results go through out-params.
- Adding codes is compatible; renumbering or removing one breaks the ABI.
- For message detail, `ml_last_error()` returns a `const char*` into thread-local storage, not a global string.
- Validate every pointer and length at the top; the boundary is a trust border ([secure-coding](../../../_shared/secure-coding/SKILL.md)).

The C ↔ C++ ↔ Python mapping is in [../SKILL.md](../SKILL.md#error-translation).

## Versioned Structs

A struct passed by value (config, options) leads with a caller-set size so fields can be appended without breaking old callers.

```c
typedef struct {
    size_t   struct_size;   /* caller sets sizeof(ml_config) */
    uint32_t version;
    int      threads;       /* fields only ever appended */
    double   tolerance;
} ml_config;

void ml_config_init(ml_config *cfg);   /* fills defaults and struct_size */
```

```cpp
extern "C" ml_status ml_engine_configure(ml_engine *e, const ml_config *cfg) {
    if (!e || !cfg) return ML_EINVAL;
    if (cfg->struct_size >= offsetof(ml_config, threads) + sizeof(cfg->threads))
        e->impl.threads = cfg->threads;    // read a field only if the caller's struct has it
    return ML_OK;
}
```

Never reorder or retype an existing field.

## Callback Safety

```c
typedef int (*ml_progress_cb)(double fraction, void *user_data);
ml_status ml_engine_run(ml_engine *e, ml_progress_cb cb, void *user_data);
```

- Always pair the function pointer with `void *user_data`, passed back unchanged; it is how the consumer threads context (e.g. a Python object) through.
- On Windows x86, state the calling convention (`__cdecl` vs `__stdcall`) in the typedef.
- Callback shims catch everything and return an error code to abort; nothing throws through native frames.
- Calling a Python callback from a thread without the GIL: acquire it first ([pybind11-nanobind.md](pybind11-nanobind.md#gil-management)).
- Document whether the callback may re-enter the library and that `user_data` must outlive the call.

## Symbol Visibility

Build hidden-by-default and export only the public API, so only `ML_API` symbols are promised.

```c
#if defined(_WIN32)
#  define ML_API __declspec(dllexport)   /* dllimport when consuming */
#elif defined(__GNUC__)
#  define ML_API __attribute__((visibility("default")))
#else
#  define ML_API
#endif

ML_API ml_engine *ml_engine_create(void);
```

```cmake
set_target_properties(mylib PROPERTIES     # or -fvisibility=hidden by hand
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON)
```

On Linux a linker version script can pin the exported set further.

## Consuming from Python: ctypes

Stdlib, zero build; sees only C-linkage symbols.

```python
import ctypes
from ctypes import POINTER, c_double, c_int, c_size_t, c_void_p

lib = ctypes.CDLL("./libmylib.so")   # .dylib on macOS, .dll on Windows

# Without restype/argtypes ctypes assumes an int return: pointers truncate on 64-bit.
lib.ml_engine_create.restype = c_void_p
lib.ml_engine_create.argtypes = []
lib.ml_engine_destroy.restype = None
lib.ml_engine_destroy.argtypes = [c_void_p]
lib.ml_engine_run.restype = c_int
lib.ml_engine_run.argtypes = [c_void_p, POINTER(c_double), c_size_t, POINTER(c_double)]
```

### Wrapper

```python
class Engine:
    def __init__(self) -> None:
        self._h = lib.ml_engine_create()
        if not self._h:
            raise MemoryError("ml_engine_create failed")

    def run(self, data: list[float]) -> list[float]:
        n = len(data)
        out = (c_double * n)()
        status = lib.ml_engine_run(self._h, (c_double * n)(*data), n, out)
        if status != 0:
            raise RuntimeError(f"ml_engine_run failed: {status}")
        return list(out)

    def close(self) -> None:
        if self._h:
            lib.ml_engine_destroy(self._h)
            self._h = None

    def __enter__(self) -> "Engine":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()
```

Opaque handles stay `c_void_p`; never rebuild the struct in Python. Destroy deterministically (`with` or `close()`), not only in `__del__`.

## Consuming from Python: cffi

API mode compiles a shim against the real header, so signature drift fails at build time, per-call overhead is lower, and it works on PyPy. Prefer it over ctypes beyond a handful of calls. ABI mode (`ffi.dlopen`) works like ctypes.

```python
# build_mylib.py
from cffi import FFI

ffi = FFI()
ffi.cdef("""
    typedef struct ml_engine ml_engine;
    ml_engine *ml_engine_create(void);
    void       ml_engine_destroy(ml_engine *e);
    int        ml_engine_run(ml_engine *e, const double *in, size_t n, double *out);
""")
ffi.set_source("_mylib", '#include "mylib.h"', libraries=["mylib"])

if __name__ == "__main__":
    ffi.compile(verbose=True)
```

### Usage

```python
from _mylib import ffi, lib

h = lib.ml_engine_create()
if h == ffi.NULL:
    raise MemoryError
try:
    inp = ffi.new("double[]", [1.0, 2.0, 3.0])
    out = ffi.new("double[]", 3)
    if lib.ml_engine_run(h, inp, 3, out) != 0:
        raise RuntimeError("ml_engine_run failed")
    result = list(out)
finally:
    lib.ml_engine_destroy(h)
```

## Release Checks

Before publishing or bumping a native library, beyond the rules above:

- The public header compiles as both C and C++ (`-x c` and `-x c++`).
- Review the export table (`nm -D --defined-only` on Linux, `nm -gU` on macOS) for anything not marked `ML_API`.
- Bump the SONAME / version per semver: patch = no ABI change, minor = additive, major = breaking.

## Diagnostics

| Symptom | Cause | Fix |
|---------|-------|-----|
| `undefined symbol: _Z3addii` (mangled) | consumer expects a C name | `extern "C"` on the declaration |
| `OSError: ... cannot open shared object file` | loader can't find the library | rpath, absolute path, or a proper install |
| Garbage results / crash through ctypes | `restype`/`argtypes` unset | declare them for every function |
| Crash when a C++ exception reaches C | unwinding across `extern "C"` | catch-all at every entry |
| Heap corruption on free | wrong free function, or freed across CRTs | the library's matching destroy |
| New struct field broke old callers | no size guard | `struct_size`, gate new-field reads |
| Symbol clashes between two loaded libraries | everything exported | hidden visibility + `ML_API` |
| Crash when a callback runs on a worker thread | touched Python `user_data` without the GIL | acquire the GIL first |

## Related

| Link | For |
|------|-----|
| [c-memory-ownership](../../../c/c-memory-ownership/SKILL.md) | ownership conventions the ABI encodes |
| [cmake-modern.md](../../build-systems/references/cmake-modern.md#install--export-installtargets--export-) | install/export of the library |
| [gdb-lldb.md](../../diagnostics/references/gdb-lldb.md) | debugging across the boundary |
