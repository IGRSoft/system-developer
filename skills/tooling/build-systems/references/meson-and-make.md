# Meson and Make Reference

Meson for clean C/C++ projects, when plain Make is still right, and when to migrate off
it. CMake, the default: [cmake-modern.md](cmake-modern.md).

## Meson 1.11 Setup / Compile / Test

Meson 1.11 is current: faster configure than CMake, terser syntax, Ninja backend, strict
by default.

```meson
# meson.build
project('app', 'cpp',
  version : '0.1.0',
  default_options : ['cpp_std=c++23', 'warning_level=3', 'werror=false'])

core = static_library('core', 'src/core.cpp',
  include_directories : include_directories('include'))

executable('app', 'src/main.cpp',
  link_with : core,
  include_directories : include_directories('include'))

test('unit', executable('unit', 'tests/unit.cpp', link_with : core))
```

```bash
meson setup build          # configure (out-of-source; Ninja backend by default)
meson compile -C build     # build
meson test -C build        # run the test suite
meson setup --reconfigure build   # re-run configure after changing options
```

### Options

- `meson setup build -Dcpp_std=c++20 --buildtype=debugoptimized` overrides options;
  `--buildtype` is `debug`, `debugoptimized` (the RelWithDebInfo equivalent, for
  profiling), or `release`.
- `compile_commands.json` is emitted automatically for clang-tidy and clangd.

## Meson Dependencies (subprojects / wrap)

`dependency()` uses the system/pkg-config copy first and falls back to a subproject from
a wrap file in `subprojects/`.

```meson
# Prefer a system/pkg-config copy, fall back to a wrap-provided subproject
fmt_dep = dependency('fmt', fallback : ['fmt', 'fmt_dep'], required : true)
executable('app', 'src/main.cpp', dependencies : fmt_dep)
```

```ini
# subprojects/fmt.wrap
[wrap-git]
url = https://github.com/fmtlib/fmt.git
revision = 11.0.2            # pin a tag/commit, never a moving branch
depth = 1

[provide]
fmt = fmt_dep               # the dependency variable the subproject exports
```

```bash
meson wrap install fmt      # fetch a wrap from WrapDB (the Meson package registry)
meson subprojects update    # refresh checked-in subprojects
```


## When Plain Make Is the Right Tool

Two cases:

1. An existing, working `Makefile` for a project that is not growing. Rewriting it is
   pure risk.
2. One simple single-language binary from a handful of files, no external packages, no
   cross-platform requirement.

Otherwise prefer CMake or Meson: Make has no dependency resolution, package-manager
integration, presets, or portable feature detection.

## A Minimal Correct Makefile

Out-of-tree objects, automatic header dependencies, phony targets:

```make
CC      := cc
CFLAGS  := -std=c23 -O2 -g -Wall -Wextra -MMD -MP
BUILD   := build
SRC     := $(wildcard src/*.c)
OBJ     := $(SRC:src/%.c=$(BUILD)/%.o)
BIN     := $(BUILD)/app

$(BIN): $(OBJ) | $(BUILD)
	$(CC) $(CFLAGS) $^ -o $@

$(BUILD)/%.o: src/%.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD):
	mkdir -p $@

-include $(OBJ:.o=.d)        # auto header deps from -MMD -MP

.PHONY: clean test
clean:
	rm -rf $(BUILD)
test: $(BIN)
	$(BIN) --self-test
```

- `-MMD -MP` + `-include *.d` rebuild on header changes, which hand-written Makefiles most
  often get wrong.
- `| $(BUILD)` is order-only: create the dir without relinking on its mtime.

This is GNU Make. BSD make differs (no `$(wildcard ...)`, different conditionals);
needing both is a migration signal.

## The Make → CMake/Meson Migration Signal

Migrate off plain Make when any of these become true:

| Signal | Why Make stops paying off |
|--------|---------------------------|
| You need an external package (fmt, Boost, OpenSSL, gtest) | Make has no dependency resolution — you hand-roll `pkg-config` calls and version checks. |
| It must build on more than one OS/compiler | GNU vs BSD make divergence; no portable feature detection. |
| You want IDE / clangd integration | No `compile_commands.json` without bolt-on tooling. |
| You add a second language or a shared library + tests + install | Link order, install rules, and export configs become error-prone by hand. |
| CI needs reproducible, cached dependency builds | No lockfile, no preset, no binary cache. |

Migrate to CMake for the broadest package-manager and IDE ecosystem, or Meson for a
fast, strict build with less boilerplate.

## Related References

- [package-managers.md](package-managers.md): dependency strategy across CMake, Meson, and uv
- [ci-pipelines.md](ci-pipelines.md): wiring Meson or Make builds into CI
- [version-feature-matrix](../../../_shared/version-feature-matrix.md): Meson and compiler version floors
