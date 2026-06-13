# Stable C ABI Boundaries

Use this when:

- You are designing the `extern "C"` surface a native library exposes to anyone.
- A C++ library must be callable from Python (via ctypes/cffi), another C ABI, or a
  different C++ compiler/toolchain.
- You need an ABI that survives internal refactors and library version bumps.
- You are deciding how errors, ownership, and callbacks cross the boundary.
- You are consuming a C library from Python with **ctypes** or **cffi**.
- You need to control which symbols a shared library exports.

Skip if:

- You are binding C++ classes/`std::` types to Python with a compiled binding tool →
  [pybind11-nanobind.md](pybind11-nanobind.md).
- You only need to pick an approach → start at [../SKILL.md](../SKILL.md).

Jump to:

- Why a C ABI
- extern "C" Linkage
- Opaque Handles
- Ownership Across the Boundary
- Error Propagation
- Versioned Structs
- Callback Safety
- Symbol Visibility
- Consuming from Python: ctypes
- Consuming from Python: cffi
- ABI Stability Checklist
- Diagnostics

> Baseline: **C17/C23** for the ABI header, **C++17+** for the implementation behind
> it, **CPython 3.14** consumers. Compiler/loader specifics differ across
> platforms — verify visibility and packaging behavior against your toolchain.

---

## Why a C ABI

C++ has no stable ABI: name mangling, vtable layout, `std::` type layout, and
exception machinery all vary by compiler, version, and flags. A C ABI is the lingua
franca every language and toolchain agrees on. So even a pure-C++ library exposes a
**thin C facade** when it needs to be consumed across a boundary.

The boundary has five jobs, each a section below:

1. Give symbols **C linkage** (`extern "C"`) so they are findable by plain name.
2. Hide data layout behind **opaque handles**.
3. Make **ownership** explicit and paired.
4. Convert all failure to **error codes** — never let exceptions cross.
5. Keep structs and the symbol set **versioned and stable**.

---

## extern "C" Linkage

`extern "C"` tells a C++ compiler to emit C-style, unmangled symbol names so the
function is linkable as plain C.

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

Rules:

- **No C++ types in `extern "C"` signatures.** No `std::string`, `std::vector`,
  references, templates, overloads, default arguments, or `bool`-via-`std::`. Use C
  fundamentals, fixed-width ints (`<stdint.h>`), pointers, and your own structs.
- **No overloading.** C linkage means one symbol per name. Give distinct names
  (`ml_open_file`, `ml_open_socket`).
- **Keep the public header C-clean.** It must compile as C *and* C++. Do not include
  C++ standard headers from it.
- C23 note: in C23 an empty parameter list `()` means `(void)` (no args), matching
  C++ — but write `(void)` explicitly for headers shared with older C.

---

## Opaque Handles

Expose a **forward-declared, incomplete struct pointer**. Consumers can hold and
pass it but cannot see or depend on its fields, so you can change internals freely.

```c
/* Public header: opaque — no fields visible. */
typedef struct ml_engine ml_engine;

ml_engine *ml_engine_create(void);
void       ml_engine_destroy(ml_engine *e);
int        ml_engine_step(ml_engine *e);
```

```cpp
// Implementation: the real type, hidden from consumers.
struct ml_engine {            // full definition lives only in the .cpp
    Engine impl;              // C++ members are fine here
    std::vector<double> scratch;
};

extern "C" ml_engine *ml_engine_create(void) {
    return new ml_engine{};   // C++ construction behind a C-shaped pointer
}
extern "C" void ml_engine_destroy(ml_engine *e) {
    delete e;                 // tolerate NULL: delete nullptr is safe
}
```

Benefits:

- The struct layout is **not** part of the ABI — add/remove/reorder members without
  breaking consumers.
- Encapsulation: consumers cannot poke at internals.
- `reinterpret_cast` between the opaque alias and the real type only happens inside
  the implementation.

If consumers genuinely need a value type with public fields, see **Versioned
Structs** — but prefer opaque handles whenever you can.

---

## Ownership Across the Boundary

Every pointer that crosses must answer: **who frees it, and with what function?**
Document it per function and never deviate.

Conventions that scale:

- **Pair every constructor with a destructor.** `ml_engine_create` ⇄
  `ml_engine_destroy`. The allocator and deallocator must come from the **same
  library** (mixing a `malloc` in the consumer with a `free` in the library across
  different CRTs is undefined).
- **Caller-allocates pattern.** Caller passes a buffer + capacity; library fills it
  and reports the needed size. No cross-boundary free at all — the cleanest option.

  ```c
  /* Returns ML_OK, or ML_ETOOSMALL with *needed set to required length. */
  ml_status ml_render(ml_engine *e, char *buf, size_t cap, size_t *needed);
  ```

- **Library-allocates pattern.** Library returns a pointer it owns; provide a
  matching free function and say so in the doc comment.

  ```c
  char *ml_describe(ml_engine *e);   /* caller must free with ml_free_string */
  void  ml_free_string(char *s);     /* tolerates NULL */
  ```

- **Borrowed pointers.** If the library keeps owning the memory (e.g. a pointer into
  an internal buffer), say *borrowed; valid until the next call / until destroy* and
  never hand the consumer a free function for it.

- **NULL tolerance.** Destroy/free functions should accept NULL and no-op. It makes
  consumer error paths simpler and matches `free(NULL)`.

State the contract in the header comment, in the doc, and in the binding. The most
common cross-language bug is a free-function mismatch.

---

## Error Propagation

**No exceptions cross `extern "C"`.** A C++ exception unwinding into a C frame is
undefined behavior (typically `std::terminate`). Every boundary entry point wraps
its body in a catch-all and returns a status code.

```c
/* Stable error enum — append only; never renumber existing values. */
typedef enum {
    ML_OK        = 0,
    ML_EINVAL    = 1,   /* bad argument */
    ML_ENOMEM    = 2,   /* allocation failed */
    ML_ETOOSMALL = 3,   /* caller buffer too small */
    ML_ERUNTIME  = 4    /* other failure */
} ml_status;

const char *ml_status_str(ml_status s);   /* human-readable, static storage */
```

```cpp
extern "C" ml_status ml_engine_step(ml_engine *e) {
    if (!e) return ML_EINVAL;             // validate first
    try {
        e->impl.step();                   // may throw
        return ML_OK;
    } catch (const std::invalid_argument &) { return ML_EINVAL; }
      catch (const std::bad_alloc &)        { return ML_ENOMEM; }
      catch (...)                           { return ML_ERUNTIME; }  // mandatory catch-all
}
```

Guidelines:

- **Return a status; use out-params for results.** `int *out`, `char *buf` — keep the
  return channel for the status.
- **Append-only enum.** Adding new codes is compatible; renumbering or removing is an
  ABS break. Reserve `0 == success`.
- **Thread-local last-error detail** if you need a message: a `ml_last_error()`
  returning a `const char*` into thread-local storage. Avoid a single global error
  string (not thread-safe).
- **Validate every pointer and length** at the top. The boundary is a trust border —
  treat all inputs as hostile. See [secure-coding](../../../_shared/secure-coding/SKILL.md).

The full C ↔ C++ ↔ Python error mapping table is in [../SKILL.md](../SKILL.md#error-translation).

---

## Versioned Structs

When you must expose a struct by value (config, options), make it forward-
compatible so adding fields does not break old callers.

**Size/version field pattern** — caller sets the size; library knows which fields
exist:

```c
typedef struct {
    size_t   struct_size;   /* set to sizeof(ml_config) by the caller */
    uint32_t version;       /* feature/layout version */
    int      threads;       /* fields added over time, only appended */
    double   tolerance;
} ml_config;

/* Initialize with current defaults and the right size. */
void ml_config_init(ml_config *cfg);
```

```cpp
extern "C" ml_status ml_engine_configure(ml_engine *e, const ml_config *cfg) {
    if (!e || !cfg) return ML_EINVAL;
    // Read `threads` only if the caller's struct is large enough to contain it.
    if (cfg->struct_size >= offsetof(ml_config, threads) + sizeof(cfg->threads))
        e->impl.threads = cfg->threads;
    return ML_OK;
}
```

Rules:

- **Append fields only**; never reorder or change the type of an existing field.
- **First member is `struct_size`** (or a `version`), set by the caller, checked by
  the library before reading newer fields.
- Provide an **`*_init`** that fills defaults so callers do not zero-init manually.
- Prefer **opaque handles** over public structs unless the consumer truly needs the
  fields — opaque sidesteps this entirely.

---

## Callback Safety

Callbacks let native code call back into the consumer. They are sharp.

```c
/* Always pair the function pointer with an opaque user-data pointer. */
typedef int (*ml_progress_cb)(double fraction, void *user_data);

ml_status ml_engine_run(ml_engine *e, ml_progress_cb cb, void *user_data);
```

Rules:

- **Always carry `void *user_data`.** A bare function pointer cannot capture state;
  the user-data pointer is how the consumer threads context (e.g. a Python object)
  through. Pass it back unchanged to every invocation.
- **Define the calling convention** if the platform has more than one (rare on
  64-bit Unix; matters on Windows — `__cdecl` vs `__stdcall`). Be explicit in the
  typedef.
- **Exceptions must not propagate through native frames.** A callback implemented in
  C++ (or a Python callback via a binding) must not throw across the native call
  stack. Catch at the callback shim; return an error code to abort the operation.
- **GIL when calling Python back.** If `user_data` is a Python object and you invoke
  the callback from a thread where the GIL is released, re-acquire it first (see
  [pybind11-nanobind.md](pybind11-nanobind.md#gil-management)).
- **Document re-entrancy and lifetime.** State whether the callback may call back
  into the library, and that `user_data` must outlive the call.

---

## Symbol Visibility

By default, shared libraries on some platforms export every non-static symbol,
bloating the export table and leaking internals. Export **only** the public API.

```c
/* visibility.h */
#if defined(_WIN32)
#  define ML_API __declspec(dllexport)   /* __declspec(dllimport) when consuming */
#elif defined(__GNUC__)
#  define ML_API __attribute__((visibility("default")))
#else
#  define ML_API
#endif
```

```c
ML_API ml_engine *ml_engine_create(void);   /* exported */
/* everything else: hidden */
```

Build the library hidden-by-default and mark only the API:

```bash
# GCC/Clang: hide everything, then ML_API re-exports the public symbols
cc -fvisibility=hidden -shared -o libmylib.so mylib.c
```

In CMake:

```cmake
set_target_properties(mylib PROPERTIES
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON)
```

Benefits: smaller/faster-loading libraries, a real ABI contract (only `ML_API`
symbols are promised), and no accidental dependence on internals. On Linux you can
additionally use a version script / linker map to pin the exported set; verify the
mechanism for your linker.

---

## Consuming from Python: ctypes

ctypes is stdlib — zero build, good for calling an existing `.so`/`.dylib`. It only
sees **C-linkage** symbols (hence the `extern "C"` layer).

```python
import ctypes
from ctypes import c_char_p, c_double, c_int, c_size_t, c_void_p, POINTER

lib = ctypes.CDLL("./libmylib.so")    # or .dylib on macOS, .dll on Windows

# Declare signatures — ctypes assumes int return otherwise (a classic bug source).
lib.ml_engine_create.restype = c_void_p
lib.ml_engine_create.argtypes = []

lib.ml_engine_destroy.restype = None
lib.ml_engine_destroy.argtypes = [c_void_p]

lib.ml_engine_run.restype = c_int          # ml_status
lib.ml_engine_run.argtypes = [c_void_p, POINTER(c_double), c_size_t, POINTER(c_double)]

class Engine:
    def __init__(self) -> None:
        self._h = lib.ml_engine_create()
        if not self._h:
            raise MemoryError("ml_engine_create failed")

    def run(self, data: list[float]) -> list[float]:
        n = len(data)
        buf = (c_double * n)(*data)
        out = (c_double * n)()
        status = lib.ml_engine_run(self._h, buf, n, out)
        if status != 0:                       # translate the C error code
            raise RuntimeError(f"ml_engine_run failed: {status}")
        return list(out)

    def close(self) -> None:
        if self._h:
            lib.ml_engine_destroy(self._h)    # pair create/destroy
            self._h = None

    def __del__(self) -> None:
        self.close()
```

Essentials:

- **Always set `restype` and `argtypes`.** Without them ctypes assumes `c_int`
  return and unchecked args — silent corruption on 64-bit pointers.
- **Opaque handle = `c_void_p`.** Never reconstruct the struct on the Python side.
- **Check the status and raise.** The C ABI cannot raise; the binding must.
- **Pair create/destroy** and call destroy deterministically (context manager or
  explicit `close`), not just in `__del__`.

---

## Consuming from Python: cffi

cffi is third-party but more robust than ctypes for non-trivial C, supports an
**API mode** (compiles a small shim, faster + safer) and an **ABI mode** (dlopen,
like ctypes), and works well on PyPy.

```python
# build_mylib.py — API mode: compiles against the real header
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

```python
# usage
from _mylib import ffi, lib

h = lib.ml_engine_create()
if h == ffi.NULL:
    raise MemoryError
try:
    n = 3
    inp = ffi.new("double[]", [1.0, 2.0, 3.0])
    out = ffi.new("double[]", n)
    if lib.ml_engine_run(h, inp, n, out) != 0:
        raise RuntimeError("ml_engine_run failed")
    result = list(out)
finally:
    lib.ml_engine_destroy(h)
```

ctypes vs cffi:

- **ctypes** — zero install, fine for a few calls, signatures declared in Python.
- **cffi API mode** — compiles against the actual header (catches signature drift at
  build time), lower per-call overhead, PyPy-friendly. Prefer it for anything beyond
  a handful of calls.
- Both consume the **same** `extern "C"` ABI — design the boundary once.

---

## ABI Stability Checklist

Before publishing or bumping a native library:

- [ ] Public header compiles clean as **both C and C++** (`-x c` and `-x c++`).
- [ ] No C++ types in any `extern "C"` signature.
- [ ] Every entry point validates pointers/lengths and has a **catch-all**.
- [ ] Every `*_create`/allocating function has a documented matching free function.
- [ ] Error enum is **append-only**; `0 == success`.
- [ ] Public structs lead with `struct_size`/`version`; fields appended only.
- [ ] Callbacks carry `void *user_data`; no exceptions escape callback shims.
- [ ] `-fvisibility=hidden` + explicit `ML_API` exports; export table reviewed.
- [ ] SONAME / version bumped per semver: patch = no ABI change, minor = additive,
      major = breaking. *(verify your platform's versioning mechanism)*

---

## Diagnostics

| Error / symptom | Cause | Fix |
|-----------------|-------|-----|
| `undefined symbol: _Z3addii` / `Undefined symbols for ...` (mangled) | C++ name mangling; consumer expects C name | wrap declaration in `extern "C"` |
| `OSError: ... cannot open shared object file` | loader can't find the `.so`/`.dylib` | set `LD_LIBRARY_PATH`/rpath, use absolute path, install correctly |
| Garbage results / crash through ctypes | `restype`/`argtypes` not set (assumed `int`) | declare them for every function |
| Crash when a C++ exception reaches C | exception unwinding across `extern "C"` | catch-all at every boundary entry → status code |
| Double free / heap corruption on free | freed across CRTs, or wrong free function | use the library's matching destroy; never `free` a library-owned pointer with the consumer CRT |
| Adding a struct field broke old callers | layout-dependent struct, no size guard | add `struct_size`/`version`, gate new-field reads |
| Callback can't access caller state | bare function pointer, no context | add `void *user_data`, pass it back unchanged |
| Symbol clashes between two loaded libraries | everything exported (no visibility control) | `-fvisibility=hidden` + `ML_API` on the public few |
| `python3.14t` corruption when callback runs from a worker thread | GIL released; touched a Python `user_data` | re-acquire the GIL before calling Python back |

## Related Skills

- [pybind11-nanobind](pybind11-nanobind.md) — compiled C++ bindings, GIL, free-threading, packaging
- [../SKILL.md](../SKILL.md) — tool selection, boundary doctrine, error-translation table
- [c-memory-ownership](../../../c/c-memory-ownership/SKILL.md) — ownership conventions the ABI encodes
- [secure-coding](../../../_shared/secure-coding/SKILL.md) — validating untrusted input at the boundary
- [build-systems/references/cmake-modern.md](../../build-systems/references/cmake-modern.md) — visibility presets, install/export, SONAME
- [diagnostics/references/gdb-lldb.md](../../diagnostics/references/gdb-lldb.md) — debugging across the native boundary
