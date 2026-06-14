# Meson and Make Reference

Use this when:

- You are starting a clean C/C++ project and want a faster, stricter build than CMake.
- You are deciding whether to keep a plain `Makefile` or move to a real build system.
- You inherited Make and need the signal for *when* migration is worth it.

Skip if:

- You want the default C/C++ build system (CMake) — that is [cmake-modern.md](cmake-modern.md).
- You only need to pick a package manager — see [package-managers.md](package-managers.md).
- The problem is runtime, not build — see [diagnostics](../../diagnostics/SKILL.md).

Jump to:

- Meson 1.11 Setup / Compile / Test
- Meson Dependencies (subprojects / wrap)
- When Plain Make Is the Right Tool
- A Minimal Correct Makefile
- The Make → CMake/Meson Migration Signal

---

## Meson 1.11 Setup / Compile / Test

Meson 1.11 is current. It is faster to configure than CMake, has terser syntax, defaults
to the Ninja backend, and is strict by default (warnings, unused deps). Good for
greenfield C/C++.

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

- **Out-of-source always** — `build/` is created by `meson setup`, never the source tree.
- `meson setup build -Dcpp_std=c++20 --buildtype=debugoptimized` overrides options at
  configure time; `--buildtype` values: `debug`, `debugoptimized` (the profiling
  equivalent of RelWithDebInfo), `release`.
- `compile_commands.json` is emitted automatically — clang-tidy / clangd just work.

---

## Meson Dependencies (subprojects / wrap)

Meson resolves dependencies via `dependency()`, falling back to a **subproject** when the
system copy is absent. Wrap files live in `subprojects/`.

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

- `dependency('x', fallback: [...])` uses pkg-config/system first, then builds the
  subproject — the single mechanism for both system and vendored deps.
- Pin `revision` to a tag or commit; a branch makes builds irreproducible.

---

## When Plain Make Is the Right Tool

Make is not obsolete — it is the right tool in two narrow cases:

1. **An existing, working `Makefile`** for a project that is not growing. Do not migrate a
   build that works and is not in your way; rewriting it is pure risk.
2. **One simple, single-language target** — a single binary from a handful of `.c`/`.cpp`
   files, no external packages, no cross-platform requirement. A 10-line Makefile beats a
   CMake project here.

Outside those cases, prefer CMake (the default) or Meson. Make has no dependency
resolution, no package-manager integration, no presets, and no portable feature
detection — you reimplement all of that by hand, badly.

---

## A Minimal Correct Makefile

If Make is genuinely the right call, write it correctly: out-of-tree objects, automatic
header dependencies, phony targets.

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

- `-MMD -MP` + `-include *.d` give you correct header-change rebuilds — the single most
  common thing hand-written Makefiles get wrong.
- `| $(BUILD)` is an order-only prerequisite (create the dir, don't relink on its mtime).
- Mark non-file targets `.PHONY`.

This is GNU Make syntax. BSD make differs (no `$(wildcard ...)`, different conditionals) —
if you need portability across both, that *is* the migration signal below.

---

## The Make → CMake/Meson Migration Signal

Migrate off plain Make when any of these become true:

| Signal | Why Make stops paying off |
|--------|---------------------------|
| You need an external package (fmt, Boost, OpenSSL, gtest) | Make has no dependency resolution — you hand-roll `pkg-config` calls and version checks. |
| It must build on more than one OS/compiler | GNU vs BSD make divergence; no portable feature detection. |
| You want IDE / clangd integration | No `compile_commands.json` without bolt-on tooling. |
| You add a second language or a shared library + tests + install | Link order, install rules, and export configs become error-prone by hand. |
| CI needs reproducible, cached dependency builds | No lockfile, no preset, no binary cache. |

When you migrate: **CMake** if you need the broadest package-manager/IDE ecosystem (the
default — [cmake-modern.md](cmake-modern.md)); **Meson** for a clean, fast, strict build
with less boilerplate. Both give you out-of-source builds, `compile_commands.json`, real
dependency handling, and test integration that Make cannot.

## Related References

- [build-systems SKILL.md](../SKILL.md) — build-system selection table
- [cmake-modern.md](cmake-modern.md) — the CMake target/preset/dependency doctrine
- [package-managers.md](package-managers.md) — dependency strategy across CMake/Meson/uv
- [ci-pipelines.md](ci-pipelines.md) — wiring Meson or Make builds into CI
- [version-feature-matrix](../../../_shared/version-feature-matrix.md) — Meson/compiler version floors
