# CI Pipelines Reference

Use this when:

- You are wiring build + test + sanitize + lint into CI for a C/C++/Python/Bash project.
- You need a matrix across OS/compiler/standard and want it cache-fast.
- You want an ASan/UBSan gate, a clang-tidy/ruff/shellcheck gate, and reproducible builds.

Skip if:

- You only need the local build recipe — that is [cmake-modern.md](cmake-modern.md).
- You are reading a sanitizer report, not wiring the job — see
  [sanitizers.md](../../diagnostics/references/sanitizers.md).

Jump to:

- Pipeline Shape
- Matrix Builds
- Dependency Caching
- The Sanitizer Gate (ASan + UBSan, TSan separate)
- Lint / Static-Analysis Gates
- Reproducible Builds
- Putting It Together

---

## Pipeline Shape

A systems-project pipeline runs these stages; a failure in any stage fails the build:

```
configure → build → test → sanitize → lint/static-analysis
```

- **configure/build/test** through CMake presets (or Meson verbs) so CI matches local.
- **sanitize** is a *separate build directory* — never the same binary as the release
  build. ASan+UBSan in one job; TSan in its own.
- **lint** (clang-tidy / clang-format-check / ruff / shellcheck / shfmt) is fast and
  should gate every PR.

Run independent stages as parallel jobs; only `test`/`sanitize` depend on `build`.

---

## Matrix Builds

Cover the OS/compiler/standard combinations you actually ship. Keep the matrix small and
meaningful — every cell costs minutes.

```yaml
# GitHub Actions
jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
        preset: [default]
        include:
          - { os: ubuntu-latest, cc: gcc-15,  cxx: g++-15 }
          - { os: ubuntu-latest, cc: clang-21, cxx: clang++-21 }
          - { os: macos-latest, cc: clang,    cxx: clang++ }
    runs-on: ${{ matrix.os }}
    env: { CC: ${{ matrix.cc }}, CXX: ${{ matrix.cxx }} }
    steps:
      - uses: actions/checkout@v4
      - run: cmake --preset ${{ matrix.preset }}
      - run: cmake --build --preset ${{ matrix.preset }}
      - run: ctest --preset ${{ matrix.preset }} --output-on-failure
```

- `fail-fast: false` so one failing cell does not cancel the rest — you want the full
  picture.
- Pin compiler versions in the matrix (GCC 15.x, Clang 20-21.x) rather than relying on the
  runner default; *verify the runner images ship them* or install explicitly.
- Add a `c++2c` cell only behind a feature-test-macro guard — C++26 is not shipping.

---

## Dependency Caching

Cache the dependency layer keyed on the manifest/lockfile hash so a no-change push does not
rebuild the world.

```yaml
      # vcpkg binary cache (manifest mode)
      - uses: actions/cache@v4
        with:
          path: ${{ github.workspace }}/vcpkg_installed
          key: vcpkg-${{ matrix.os }}-${{ hashFiles('vcpkg.json') }}

      # Conan cache
      - uses: actions/cache@v4
        with:
          path: ~/.conan2
          key: conan-${{ matrix.os }}-${{ hashFiles('conan.lock') }}

      # FetchContent build dir
      - uses: actions/cache@v4
        with:
          path: build/_deps
          key: deps-${{ matrix.os }}-${{ hashFiles('CMakeLists.txt') }}
```

Key on the file that *determines* the dependency set (`vcpkg.json`, `conan.lock`,
`uv.lock`/`pylock.toml`, or the `CMakeLists.txt` holding `GIT_TAG`s). A stale key silently
serves wrong binaries — hash the source of truth.

---

## The Sanitizer Gate (ASan + UBSan, TSan separate)

ASan+UBSan combine; TSan runs alone. Two jobs, two build dirs. Treat any report as a
failing build. (Per-sanitizer detail: [sanitizers.md](../../diagnostics/references/sanitizers.md).)

```yaml
  asan-ubsan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          cmake -S . -B build/asan -DCMAKE_BUILD_TYPE=Debug \
            -DCMAKE_C_FLAGS="-g -fno-omit-frame-pointer -fsanitize=address,undefined" \
            -DCMAKE_CXX_FLAGS="-g -fno-omit-frame-pointer -fsanitize=address,undefined" \
            -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined"
          cmake --build build/asan
      - env:
          ASAN_OPTIONS: abort_on_error=1:exitcode=1
          UBSAN_OPTIONS: halt_on_error=1:print_stacktrace=1:exitcode=1
        run: ctest --test-dir build/asan --output-on-failure

  tsan:
    runs-on: ubuntu-latest          # separate job — TSan never combines with ASan
    steps:
      - uses: actions/checkout@v4
      - run: |
          cmake -S . -B build/tsan -DCMAKE_BUILD_TYPE=Debug \
            -DCMAKE_C_FLAGS="-g -fno-omit-frame-pointer -fsanitize=thread" \
            -DCMAKE_CXX_FLAGS="-g -fno-omit-frame-pointer -fsanitize=thread" \
            -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=thread"
          cmake --build build/tsan
      - env: { TSAN_OPTIONS: halt_on_error=1:exitcode=1 }
        run: ctest --test-dir build/tsan --output-on-failure
```

- The `exitcode=1` options force a non-zero exit so a swallowed error still fails the job.
- Keep these out of the release matrix — sanitized binaries are slow and not what you ship.

---

## Lint / Static-Analysis Gates

Fast checks that should gate every PR. Run in report-or-fail mode; do not auto-fix in CI.

```yaml
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # C/C++ — needs compile_commands.json from a configure step
      - run: cmake --preset default -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
      - run: clang-tidy -p build/default $(git ls-files '*.c' '*.cpp')
      - run: clang-format --dry-run --Werror $(git ls-files '*.c' '*.cpp' '*.h' '*.hpp')

      # Python (ruff lint + format check; ty is report-only, beta — not yet a gate)
      - run: ruff check .
      - run: ruff format --check .

      # Bash
      - run: shellcheck $(git ls-files '*.sh')
      - run: shfmt -d $(git ls-files '*.sh')
```

| Tool | Gate role | Note |
|------|-----------|------|
| **clang-tidy / clang-format** (20-21.x) | C/C++ lint + format gate | clang-tidy needs `compile_commands.json` (`-p build/...`). |
| **ruff** | Python lint + format gate | Single fast tool for both. |
| **ty** (Astral, beta) | Python type check — **report-only** | Fast, no stable API yet; surface findings, do not block on it. Keep pyright/mypy as the gate. |
| **shellcheck** (0.11) / **shfmt** (3.13) | Bash lint + format gate | `shfmt -d` diffs; `shellcheck` catches quoting/injection classes. |

---

## Reproducible Builds

Same source + same toolchain → byte-identical (or at least behavior-identical) artifacts.
What to pin and strip:

- **Pin the toolchain** in the matrix (exact GCC/Clang/CMake versions) — not the runner
  default, which drifts.
- **Pin dependencies** with a lockfile/baseline (`vcpkg.json` baseline, `conan.lock`,
  `uv.lock`/`pylock.toml`) and cache keyed on its hash.
- **Strip nondeterminism** from binaries: pass `-ffile-prefix-map=$PWD=.` to remove
  absolute build paths; set `SOURCE_DATE_EPOCH` for timestamp-stable archives; sort inputs
  (globs are filesystem-order-dependent — prefer explicit file lists).
- **Out-of-source builds** so the build dir is reproducibly clean (`rm -rf build` is the
  full reset).

```bash
# Strip the build-path from debug info / __FILE__ for path-independent output
cmake -S . -B build -DCMAKE_CXX_FLAGS="-ffile-prefix-map=$PWD=."
```

These make CI failures reproducible locally and prevent "works on the runner, not on my
machine" drift.

---

## Putting It Together

A complete pipeline runs these jobs, gating the merge on all of them:

1. **build matrix** — OS × compiler × standard, deps cached, `ctest`/`meson test`.
2. **asan-ubsan** — one Debug build, runs the full suite under ASan+UBSan.
3. **tsan** — separate Debug build, runs threaded tests under TSan.
4. **lint** — clang-tidy + clang-format + ruff (+ ty report-only) + shellcheck + shfmt.

Keep them parallel where possible (lint and sanitize do not depend on the release matrix).
Cache the dependency layer in every job. Treat every sanitizer report and every lint
finding (except report-only `ty`) as a failing build.

## Related References

- [build-systems SKILL.md](../SKILL.md) — build-system selection and linking diagnostics
- [cmake-modern.md](cmake-modern.md) — presets that make CI configure match local exactly
- [package-managers.md](package-managers.md) — what to hash for the dependency cache key
- [sanitizers.md](../../diagnostics/references/sanitizers.md) — per-sanitizer flags, options, suppressions, report triage
- [version-feature-matrix](../../../_shared/version-feature-matrix.md) — pin matrix versions to the toolchain floors
- [secure-coding](../../../_shared/secure-coding/SKILL.md) — hardening flags to add to the release build
