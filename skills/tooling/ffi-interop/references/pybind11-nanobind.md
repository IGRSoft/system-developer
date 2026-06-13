# pybind11 & nanobind: Compiled C++ Bindings

Use this when:

- You are exposing C++ functions, classes, or `std::` types to Python.
- You are choosing or comparing nanobind and pybind11 for a project.
- You need to get ownership (`return_value_policy`) right so nothing double-frees.
- You must release the GIL around heavy native work, or target `python3.14t`.
- You are packaging a native extension into a wheel with scikit-build-core.
- You need `.pyi` stubs so type checkers and IDEs see your extension.

Skip if:

- You are binding a **C** library with no C++ types → use ctypes/cffi against a
  stable C ABI; see [c-api-boundaries.md](c-api-boundaries.md).
- You only need to pick a tool → start at [../SKILL.md](../SKILL.md).
- You need the boundary-design rules (opaque handles, no exceptions across
  `extern "C"`) → those are in [c-api-boundaries.md](c-api-boundaries.md).

Jump to:

- nanobind vs pybind11
- Module Definition
- Binding Functions
- Binding Classes
- Return-Value Policies (Ownership)
- Buffers, NumPy, and the Buffer Protocol
- GIL Management
- Free-Threading (`python3.14t`)
- Exception Translation
- Packaging with scikit-build-core
- Stub Generation
- Diagnostics

> Baseline: **nanobind 2.x**, **pybind11 2.13+**, **CMake 3.15+**,
> **scikit-build-core 0.10+**, **CPython 3.14**. APIs across these move between
> minor releases — verify signatures against your installed versions and the
> upstream docs (fetch via Context7/Ref rather than trusting memory).

---

## nanobind vs pybind11

Same author, same mental model; nanobind is the modern rewrite.

| Aspect | nanobind | pybind11 |
|--------|----------|----------|
| Binary size | Much smaller | Larger |
| Compile time | Faster | Slower |
| Runtime overhead | Lower | Higher |
| Free-threading | First-class (`FREE_THREADED`, `ft_mutex`, `.lock()`) | Supported, more manual |
| C++ standard floor | C++17 | C++11 (older reach) |
| Maturity / examples | Growing | Very mature, huge corpus |
| Header namespace | `nanobind`, alias `nb` | `pybind11`, alias `py` |

**Default for new C++ bindings: nanobind.** Choose pybind11 when extending an
existing pybind11 codebase or when you genuinely need pre-C++17 support. The two
APIs are deliberately close — most snippets below show nanobind first with the
pybind11 equivalent noted.

The examples use `namespace nb = nanobind;` / `namespace py = pybind11;` and the
`_a` argument-literal (`using namespace nb::literals;`).

---

## Module Definition

The module name in the macro **must** equal the compiled target/file stem, or
import fails with "does not define module export function."

```cpp
// nanobind
#include <nanobind/nanobind.h>
namespace nb = nanobind;

NB_MODULE(example_ext, m) {           // -> example_ext.cpython-314-*.so
    m.doc() = "Example native extension";
    m.attr("__version__") = "0.1.0";
}
```

```cpp
// pybind11
#include <pybind11/pybind11.h>
namespace py = pybind11;

PYBIND11_MODULE(example_ext, m) {
    m.doc() = "Example native extension";
}
```

Submodules group related bindings:

```cpp
NB_MODULE(example_ext, m) {
    nb::module_ math = m.def_submodule("math", "Numeric helpers");
    math.def("add", [](int a, int b) { return a + b; });
}
```

---

## Binding Functions

```cpp
int add(int a, int b) { return a + b; }

NB_MODULE(example_ext, m) {
    // named args, docstring
    m.def("add", &add, "a"_a, "b"_a, "Add two integers");

    // default arguments
    m.def("scale", [](double x, double f = 2.0) { return x * f; },
          "x"_a, "f"_a = 2.0);

    // keyword-only after nb::kw_only()
    m.def("connect", &connect, "host"_a, nb::kw_only(), "timeout"_a = 30);
}
```

- Prefer **lambdas** for small adapters instead of writing C++ overloads just for
  binding shape.
- Overloads: bind each with `nb::overload_cast<...>` (nanobind) /
  `py::overload_cast<...>` (pybind11) to disambiguate.
- Free functions, member functions, and lambdas all bind the same way.

---

## Binding Classes

```cpp
struct Vec2 {
    double x, y;
    Vec2(double x, double y) : x(x), y(y) {}
    double norm() const { return std::hypot(x, y); }
    Vec2 operator+(const Vec2 &o) const { return {x + o.x, y + o.y}; }
};

NB_MODULE(example_ext, m) {
    nb::class_<Vec2>(m, "Vec2")
        .def(nb::init<double, double>(), "x"_a, "y"_a)
        .def_rw("x", &Vec2::x)            // read-write field (pybind11: def_readwrite)
        .def_rw("y", &Vec2::y)
        .def("norm", &Vec2::norm)
        .def(nb::self + nb::self)          // operator overload
        .def("__repr__", [](const Vec2 &v) {
            return nb::str("Vec2({}, {})").format(v.x, v.y);
        });
}
```

Field/property bindings (nanobind → pybind11):

| nanobind | pybind11 | Meaning |
|----------|----------|---------|
| `def_rw` | `def_readwrite` | mutable field |
| `def_ro` | `def_readonly` | read-only field |
| `def_prop_rw` | `def_property` | getter + setter |
| `def_prop_ro` | `def_property_readonly` | getter only |
| `def_static` | `def_static` | static method |

Inheritance: declare the base as a template parameter so Python sees the hierarchy.

```cpp
nb::class_<Animal>(m, "Animal").def("speak", &Animal::speak);
nb::class_<Dog, Animal>(m, "Dog").def(nb::init<>());  // Dog -> Animal
```

Enums:

```cpp
nb::enum_<Color>(m, "Color")
    .value("Red", Color::Red)
    .value("Green", Color::Green)
    .export_values();
```

---

## Return-Value Policies (Ownership)

The single biggest source of crashes. A policy declares **who owns the C++ object**
the Python wrapper points at. Get it wrong → double-free or dangling pointer.

| Policy | Python owns? | Use when returning... |
|--------|--------------|------------------------|
| `take_ownership` | yes (Python deletes) | a `new`'d object the caller must free |
| `copy` | yes (its own copy) | a value you want duplicated |
| `move` | yes (moved-from) | a movable temporary |
| `reference` | **no** | a pointer to something C++ keeps owning |
| `reference_internal` | no (tied to parent) | a pointer into `self` (member/field) |
| `automatic` (default) | depends | pointer→take_ownership; ref/value→copy |

```cpp
// Returns a borrowed pointer into the engine; lifetime tied to the engine.
// reference_internal keeps `self` alive as long as the result lives.
nb::class_<Engine>(m, "Engine")
    .def("buffer", &Engine::buffer, nb::rv_policy::reference_internal);

// Factory hands ownership to Python.
m.def("make_engine", []() { return new Engine(); },
      nb::rv_policy::take_ownership);
```

nanobind spells policies `nb::rv_policy::...`; pybind11 uses
`py::return_value_policy::...` with the same names. **Decision rule:** if C++ still
owns the object after the call, use `reference`/`reference_internal`; if Python is
now responsible for freeing it, use `take_ownership`/`move`; if in doubt and the
object is cheap, `copy` is the safe choice.

For shared ownership, hold the class with `std::shared_ptr`:

```cpp
nb::class_<Widget>(m, "Widget");                 // default holder
// shared ownership: declare the holder
nb::class_<Node, std::shared_ptr<Node>>(m, "Node");
```

Returning a raw pointer you `new`'d with the default `automatic` policy makes
Python take ownership — usually what you want for factories, dangerous for
accessors. Be explicit.

---

## Buffers, NumPy, and the Buffer Protocol

Bind zero-copy array data with the typed array wrapper.

```cpp
#include <nanobind/ndarray.h>

// Accept a contiguous float64 array, no copy.
double sum(nb::ndarray<double, nb::ndim<1>, nb::c_contig> a) {
    double s = 0;
    for (size_t i = 0; i < a.shape(0); ++i) s += a(i);
    return s;
}

// Return a view that keeps the owner alive (see ownership below).
NB_MODULE(example_ext, m) {
    m.def("sum", &sum, "a"_a);
}
```

pybind11 uses `py::array_t<double>` and `py::buffer_protocol()` on classes that
expose raw memory. In both libraries:

- **Constrain dtype and layout** (`c_contig`, `ndim`) in the signature so a wrong
  array is rejected at the boundary, not deep in your loop.
- **Returning a view** of native memory must keep the owner alive — pass an owner
  capsule (nanobind) / set a base object (pybind11). A view into freed memory is a
  use-after-free that only shows up under load.
- For large data, prefer views over copies, but only when the owner's lifetime is
  clearly longer than the view's.

---

## GIL Management

The GIL serializes Python bytecode. Holding it during a long native call blocks
every other Python thread (including the UI thread).

**Release around pure-native work** so other threads proceed:

```cpp
// Whole-call release (most common, cleanest):
m.def("crunch", &crunch, nb::call_guard<nb::gil_scoped_release>());
// pybind11: py::call_guard<py::gil_scoped_release>()

// Scoped release inside a function:
m.def("process", [](Data &d) {
    nb::gil_scoped_release release;   // GIL dropped here
    d.heavy_compute();                // no Python objects touched
});                                   // GIL reacquired at scope exit
```

**Hard rule:** while the GIL is released you must not create, inspect, refcount, or
otherwise touch any Python object. If you need to call back into Python from a
worker, re-acquire first:

```cpp
{
    nb::gil_scoped_release release;
    // ... native work ...
    {
        nb::gil_scoped_acquire acquire;   // safe to touch Python again
        callback(result);
    }
}
```

Releasing the GIL is correct on **every** build — it is independent of
free-threading. A pybind11/nanobind callback invoked from a C++ thread you spawned
must acquire the GIL before touching Python.

---

## Free-Threading (`python3.14t`)

> PEP 779 made the free-threaded build officially supported in CPython 3.14
> (experimental in 3.13). Ecosystem support is still maturing — verify your
> dependencies and your own extension on `python3.14t` before relying on it.

Two independent requirements. **Doing only the first is a data-race trap.**

### 1. Declare GIL-not-used

nanobind, via CMake — the clean path:

```cmake
nanobind_add_module(my_ext FREE_THREADED src/my_ext.cpp)
```

Raw C-API / pybind11 — set the module slot:

```c
static PyModuleDef_Slot slots[] = {
    {Py_mod_gil, Py_MOD_GIL_NOT_USED},     // opt out of forcing the GIL
    {0, NULL}
};
```

Without this, importing into `python3.14t` makes the interpreter **re-enable the
GIL** and emit a `RuntimeWarning` — you silently lose all parallelism.

### 2. Actually be thread-safe

`Py_MOD_GIL_NOT_USED` only *suppresses* the GIL. It does **not** protect your data.
Once declared, multiple Python threads call your functions truly in parallel, so
every piece of shared native state needs synchronization.

```cpp
struct SharedBuffer {
    nb::ft_mutex mutex;                 // free-threading-aware mutex
    std::vector<int> data;
    void push(int v) { data.push_back(v); }   // body runs under the lock (below)
};

NB_MODULE(my_ext, m) {
    nb::class_<SharedBuffer>(m, "SharedBuffer")
        .def(nb::init<>())
        // .lock() acquires the object's ft_mutex for the duration of the call:
        .def("push", &SharedBuffer::push, nb::arg("v").lock());

    // For trivial counters, prefer atomics over a mutex:
    // std::atomic<int> with fetch_add(memory_order_relaxed)
}
```

- `nb::ft_mutex` — a mutex that is a no-op on the GIL build, real on `python3.14t`.
- `nb::arg("x").lock()` — auto-acquire an argument object's per-object lock for the call.
- `std::atomic<T>` — for counters/flags, cheaper than a lock.
- `nb::gil_scoped_release` in free-threaded extensions also temporarily releases
  argument locks held by the current thread — re-acquire before touching that state.

Verify you are actually free-threaded:

```bash
python3.14t -c "import sys; print(sys._is_gil_enabled())"   # expect: False
```

pybind11 has analogous mechanisms but they are more manual; for new free-threaded
work nanobind is the lower-friction choice.

---

## Exception Translation

Standard C++ exceptions auto-map to Python exceptions in both libraries:

| C++ exception | Python exception |
|---------------|------------------|
| `std::invalid_argument` | `ValueError` |
| `std::domain_error` | `ValueError` |
| `std::out_of_range` | `IndexError` |
| `std::range_error` | `ValueError` |
| `std::bad_alloc` | `MemoryError` |
| `std::runtime_error` | `RuntimeError` |
| `std::exception` (other) | `RuntimeError` |

Throw the right standard type and the binding raises the right Python type — no
glue needed. Register a custom mapping for your own exception type:

```cpp
// nanobind
nb::exception<MyError>(m, "MyError");   // MyError -> Python MyError

// pybind11
py::register_exception<MyError>(m, "MyError");
```

For full control, register a translator that inspects the C++ exception and calls
`PyErr_SetString` / sets a chosen Python exception. Do **not** let a C++ exception
escape into the interpreter without translation — it terminates the process.

---

## Packaging with scikit-build-core

The standard 2026 path: a CMake build wrapped as a wheel by scikit-build-core. This
replaces hand-written `setup.py`/`Extension` for compiled projects.

```
example/
├── CMakeLists.txt
├── pyproject.toml
└── src/
    ├── example_ext.cpp
    └── example/__init__.py
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
# pyproject.toml
[build-system]
requires = ["scikit-build-core >=0.10", "nanobind >=2"]
build-backend = "scikit_build_core.build"

[project]
name = "example"
version = "0.1.0"
requires-python = ">=3.14"

[tool.scikit-build]
minimum-version = "build-system.requires"   # pin behavior to the requires line
build-dir = "build/{wheel_tag}"             # cache per-wheel build trees
wheel.py-api = "cp314"                       # tag; STABLE_ABI can widen this
```

```bash
uv build              # or: python -m build  /  pip wheel .
uv pip install -e .   # editable install (rebuilds the extension on import — see below)
```

Notes:

- **`STABLE_ABI`** (nanobind) builds against the limited API so one wheel works
  across multiple CPython minors — fewer wheels to ship. Verify it covers the
  features you use.
- **pybind11 variant:** `requires = ["scikit-build-core>=0.10", "pybind11"]`,
  `find_package(pybind11 CONFIG REQUIRED)`, `pybind11_add_module(...)`.
- **Editable installs** with compiled code need scikit-build-core's editable
  support (`[tool.scikit-build] editable.rebuild = true` for auto-rebuild). A plain
  `pip install -e .` will not recompile on source changes without it.
- Use **cibuildwheel** in CI to produce manylinux/macOS/Windows wheels. See
  [build-systems/references/ci-pipelines.md](../../build-systems/references/ci-pipelines.md).

---

## Stub Generation

Compiled modules have no Python source, so type checkers and IDEs see nothing.
Ship `.pyi` stubs.

```bash
# nanobind: stubgen ships with nanobind
python -m nanobind.stubgen -m example_ext -o src/example/example_ext.pyi
```

```cmake
# Generate stubs at build time (nanobind CMake helper)
nanobind_add_stub(
  example_stub
  MODULE example_ext
  OUTPUT src/example/example_ext.pyi
  PYTHON_PATH $<TARGET_FILE_DIR:example_ext>
  DEPENDS example_ext)
```

- Add a `py.typed` marker file to the package so type checkers treat the stubs as
  authoritative (PEP 561).
- pybind11 has `pybind11-stubgen` (third-party) for the same purpose.
- Regenerate stubs whenever the binding surface changes; stale stubs are worse than
  none. Wire it into the build so it cannot drift.

---

## Diagnostics

| Error / symptom | Cause | Fix |
|-----------------|-------|-----|
| `ImportError: dynamic module does not define module export function (PyInit_X)` | `NB_MODULE`/`PYBIND11_MODULE` name ≠ built `.so` stem | rename so they match exactly |
| `TypeError: __init__(): incompatible constructor arguments` | bound ctor signature mismatch / missing `nb::init<...>` | bind the right `nb::init<Args...>`; check arg types |
| Double free / crash on GC | wrong `return_value_policy` (took ownership of a borrowed pointer) | use `reference`/`reference_internal` for non-owning returns |
| Use-after-free from a returned array view | view outlived its owner | tie lifetime via owner capsule / `reference_internal` |
| Hang / UI freeze during a native call | GIL held for the whole call | `call_guard<gil_scoped_release>()` around native work |
| Crash touching a Python object | accessed Python while GIL released | `gil_scoped_acquire` before the access |
| `RuntimeWarning: ... re-enabling the GIL` on `python3.14t` | missing GIL-not-used declaration | `FREE_THREADED` / `Py_MOD_GIL_NOT_USED` |
| Corruption only on `python3.14t` | declared GIL-free but shared state unguarded | `nb::ft_mutex` / `.lock()` / `std::atomic` |
| Process aborts with an uncaught C++ exception | non-standard exception not translated | throw a standard type or register a translator |
| `scikit_build_core ... CMake Error: find_package(nanobind)` | nanobind not in `build-system.requires` | add `nanobind`/`pybind11` to `requires` |
| Type checker sees `Any` for everything | no stubs / no `py.typed` | generate `.pyi`, add `py.typed` |

## Related Skills

- [c-api-boundaries](c-api-boundaries.md) — the stable C ABI underneath, ctypes/cffi consumption
- [../SKILL.md](../SKILL.md) — tool selection and the boundary doctrine
- [build-systems/references/cmake-modern.md](../../build-systems/references/cmake-modern.md) — the CMake driving the wheel
- [build-systems/references/ci-pipelines.md](../../build-systems/references/ci-pipelines.md) — multi-platform wheels in CI
- [python-concurrency/references/free-threading.md](../../../python/python-concurrency/references/free-threading.md) — free-threading from the Python side
- [diagnostics/references/gdb-lldb.md](../../diagnostics/references/gdb-lldb.md) — debugging the native extension
