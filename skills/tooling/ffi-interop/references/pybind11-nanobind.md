# pybind11 & nanobind: Compiled C++ Bindings

Exposing C++ functions, classes, and `std::` types to Python. Binding a C library with no C++ types goes through ctypes/cffi instead: [c-api-boundaries.md](c-api-boundaries.md).

## nanobind vs pybind11

Same author and model; nanobind is the modern rewrite.

| Aspect | nanobind | pybind11 |
|--------|----------|----------|
| Binary size / compile time / call overhead | smaller / faster / lower | larger / slower / higher |
| Free-threading | first-class (`FREE_THREADED`, `ft_mutex`, `.lock()`) | supported, more manual |
| C++ floor | C++17 | C++11 |
| Maturity | growing | very mature, huge corpus |
| Namespace alias | `nb` | `py` |

Default for new bindings: nanobind. Use pybind11 to extend an existing pybind11 codebase or for pre-C++17. Snippets show nanobind with the pybind11 spelling noted; they assume `namespace nb = nanobind;` and `using namespace nb::literals;` (for `_a`).

## Module Definition

The macro's module name must equal the compiled file stem, or import fails with "does not define module export function."

```cpp
#include <nanobind/nanobind.h>
namespace nb = nanobind;

NB_MODULE(example_ext, m) {           // -> example_ext.cpython-314-*.so
    m.doc() = "Example native extension";
    nb::module_ math = m.def_submodule("math", "Numeric helpers");
    math.def("add", [](int a, int b) { return a + b; });
}
// pybind11: #include <pybind11/pybind11.h>, PYBIND11_MODULE(example_ext, m) { ... }
```

## Binding Functions

```cpp
NB_MODULE(example_ext, m) {
    m.def("add", &add, "a"_a, "b"_a, "Add two integers");          // named args, docstring
    m.def("scale", [](double x, double f) { return x * f; },
          "x"_a, "f"_a = 2.0);                                    // default argument
    m.def("connect", &connect, "host"_a, nb::kw_only(), "timeout"_a = 30);
}
```

Use lambdas for small adapters rather than writing C++ overloads for binding shape. Disambiguate overloads with `nb::overload_cast<...>` / `py::overload_cast<...>`.

## Binding Classes

```cpp
nb::class_<Vec2>(m, "Vec2")
    .def(nb::init<double, double>(), "x"_a, "y"_a)
    .def_rw("x", &Vec2::x)
    .def("norm", &Vec2::norm)
    .def(nb::self + nb::self)                       // operator overload
    .def("__repr__", [](const Vec2 &v) {
        return nb::str("Vec2({}, {})").format(v.x, v.y);
    });

nb::class_<Dog, Animal>(m, "Dog").def(nb::init<>());   // base as template parameter
nb::enum_<Color>(m, "Color").value("Red", Color::Red).export_values();
```

### Member spellings

| nanobind | pybind11 | Meaning |
|----------|----------|---------|
| `def_rw` / `def_ro` | `def_readwrite` / `def_readonly` | field |
| `def_prop_rw` / `def_prop_ro` | `def_property` / `def_property_readonly` | getter (+ setter) |
| `def_static` | `def_static` | static method |

## Return-Value Policies (Ownership)

The biggest source of crashes: the policy says who owns the C++ object behind the Python wrapper. Wrong policy means a double free or a dangling pointer.

| Policy | Python owns? | Use when returning |
|--------|--------------|--------------------|
| `take_ownership` | yes, deletes it | a `new`'d object the caller must free |
| `copy` / `move` | yes, its own copy / moved-from | a value or movable temporary |
| `reference` | no | a pointer C++ keeps owning |
| `reference_internal` | no, keeps `self` alive | a pointer into `self` |
| `automatic` (default) | depends | pointer → take_ownership; ref/value → copy |

Spelled `nb::rv_policy::...` / `py::return_value_policy::...`. C++ still owns it → `reference`/`reference_internal`; Python must free it → `take_ownership`/`move`; cheap and unsure → `copy`. The default makes Python own a returned raw pointer: right for factories, wrong for accessors.

### Example

```cpp
nb::class_<Engine>(m, "Engine")
    .def("buffer", &Engine::buffer, nb::rv_policy::reference_internal);
m.def("make_engine", [] { return new Engine(); }, nb::rv_policy::take_ownership);
nb::class_<Node, std::shared_ptr<Node>>(m, "Node");   // shared ownership holder
```

## Buffers and NumPy

```cpp
#include <nanobind/ndarray.h>

double sum(nb::ndarray<double, nb::ndim<1>, nb::c_contig> a) {   // zero-copy
    double s = 0;
    for (size_t i = 0; i < a.shape(0); ++i) s += a(i);
    return s;
}
```

pybind11 uses `py::array_t<double>` and `py::buffer_protocol()`. In both:

- Constrain dtype and layout in the signature so a wrong array is rejected at the boundary.
- A returned view of native memory must keep its owner alive (owner capsule in nanobind, base object in pybind11); otherwise it is a use-after-free that shows up under load.

## GIL Management

Holding the GIL through a long native call blocks every other Python thread. Release it around pure-native work, on every build:

```cpp
m.def("crunch", &crunch, nb::call_guard<nb::gil_scoped_release>());  // whole call

m.def("process", [](Data &d) {
    nb::gil_scoped_release release;   // dropped here
    d.heavy_compute();                // no Python objects touched
});                                   // reacquired at scope exit
```

While released, do not create, inspect, or refcount any Python object. To call back into Python from a worker, or from a C++ thread you spawned, take `nb::gil_scoped_acquire` first.

## Free-Threading (`python3.14t`)

Supported in CPython 3.14 (PEP 779). Two independent requirements; declaring without protecting is a data-race trap.

### 1. Declare GIL-not-used

| Binding | Declaration |
|---------|-------------|
| nanobind | `nanobind_add_module(my_ext FREE_THREADED src/my_ext.cpp)` |
| pybind11 | `PYBIND11_MODULE(my_ext, m, py::mod_gil_not_used())` |
| raw C API | `{Py_mod_gil, Py_MOD_GIL_NOT_USED}` in the module's `PyModuleDef_Slot` array |

Without it, importing into `python3.14t` re-enables the GIL with a `RuntimeWarning` and all parallelism is lost.

### 2. Actually be thread-safe

The declaration only removes the GIL. Calls now run truly in parallel, so shared native state needs synchronization.

```cpp
struct SharedBuffer {
    nb::ft_mutex mutex;                 // no-op on the GIL build
    std::vector<int> data;
    void push(int v) { data.push_back(v); }
};

nb::class_<SharedBuffer>(m, "SharedBuffer")
    .def(nb::init<>())
    .def("push", &SharedBuffer::push, nb::arg("v").lock());  // locks the object for the call
```

- `std::atomic<T>` for counters and flags, cheaper than a lock.
- In free-threaded builds `nb::gil_scoped_release` also releases argument locks held by the thread; re-acquire before touching that state.
- After importing your extension, `python3.14t -c "import my_ext, sys; print(sys._is_gil_enabled())"` should print `False`.

## Exception Translation

Both libraries map standard exceptions automatically:

| C++ | Python |
|-----|--------|
| `std::invalid_argument`, `std::domain_error`, `std::length_error`, `std::range_error` | `ValueError` |
| `std::out_of_range` | `IndexError` |
| `std::overflow_error` | `OverflowError` |
| `std::bad_alloc` | `MemoryError` |
| other `std::exception` | `RuntimeError` |

Exceptions with no mapping lose their type (nanobind raises `SystemError`, pybind11 a generic `RuntimeError`). Register your own types: `nb::exception<MyError>(m, "MyError")` / `py::register_exception<MyError>(m, "MyError")`, or `register_exception_translator` for full control.

## Packaging with scikit-build-core

The minimal module and build files are in [../SKILL.md](../SKILL.md#minimal-nanobind-module--packaging). For a stable-ABI (abi3) wheel that covers later CPython minors:

```cmake
find_package(Python 3.14 COMPONENTS Interpreter Development.Module
             ${SKBUILD_SABI_COMPONENT} REQUIRED)      # SABIModule when py-api is set
find_package(nanobind CONFIG REQUIRED)
nanobind_add_module(example_ext STABLE_ABI src/example_ext.cpp)
install(TARGETS example_ext LIBRARY DESTINATION example)
```

```toml
[tool.scikit-build]
minimum-version = "build-system.requires"   # pin behavior to the requires line
build-dir = "build/{wheel_tag}"             # cache per-wheel build trees
wheel.py-api = "cp314"                       # abi3 tag, needs STABLE_ABI + SABI component
```

### Notes

- Without the SABI component nanobind cannot build against the limited API. Free-threaded builds have no stable ABI in 3.14, so `STABLE_ABI` is ignored there and can be combined with `FREE_THREADED`.
- pybind11: `requires = ["scikit-build-core>=0.10", "pybind11"]`, `find_package(pybind11 CONFIG REQUIRED)`, `pybind11_add_module(...)`.
- Editable installs recompile only with `editable.rebuild = true`, which needs `build-dir` set and `--no-build-isolation`.
- Build manylinux/macOS/Windows wheels in CI with cibuildwheel: [ci-pipelines.md](../../build-systems/references/ci-pipelines.md) > Python Wheels.

## Stub Generation

Compiled modules have no Python source, so ship `.pyi` stubs and a `py.typed` marker (PEP 561).

```cmake
nanobind_add_stub(example_stub
  MODULE example_ext
  OUTPUT src/example/example_ext.pyi
  PYTHON_PATH $<TARGET_FILE_DIR:example_ext>
  DEPENDS example_ext)
```

One-off: `python -m nanobind.stubgen -m example_ext -o src/example/example_ext.pyi`. pybind11 uses the third-party `pybind11-stubgen`. Generate in the build so stubs cannot drift from the bindings.

## Diagnostics

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ImportError: ... does not define module export function (PyInit_X)` | macro name ≠ `.so` stem | make them match |
| `TypeError: __init__(): incompatible constructor arguments` | missing or mismatched `nb::init<...>` | bind the right constructor |
| Double free / crash on GC | took ownership of a borrowed pointer | `reference` / `reference_internal` |
| Use-after-free from an array view | view outlived its owner | owner capsule / `reference_internal` |
| `SystemError` / generic `RuntimeError` | unmapped C++ exception | standard type or a translator |
| `find_package(nanobind)` fails in the wheel build | not in `build-system.requires` | add it |
| Wheel not tagged abi3 despite `STABLE_ABI` | no SABI component / `wheel.py-api` | add both |
| Type checker sees `Any` | no stubs / no `py.typed` | generate `.pyi`, add `py.typed` |

GIL and free-threading symptoms are in [../SKILL.md](../SKILL.md#runtime).

## Related

| Link | For |
|------|-----|
| [cmake-modern.md](../../build-systems/references/cmake-modern.md) | the CMake driving the wheel |
| [free-threading.md](../../../python/python-concurrency/references/free-threading.md) | free-threading from the Python side |
| [gdb-lldb.md](../../diagnostics/references/gdb-lldb.md) | debugging the native extension |
