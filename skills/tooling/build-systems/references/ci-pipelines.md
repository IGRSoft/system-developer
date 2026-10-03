# CI Pipelines Reference

Wiring build, test, sanitize, and lint into CI for C/C++/Python/Bash projects. Local build
recipes: [cmake-modern.md](cmake-modern.md). Reading a sanitizer report:
[sanitizers.md](../../diagnostics/references/sanitizers.md).

## Pipeline Shape

Gate the merge on four parallel jobs; any failure fails the build:

1. build matrix: OS x compiler, deps cached, `ctest` or `meson test`, through presets or
   Meson verbs so CI matches local.
2. asan-ubsan: a separate Debug build running the full suite.
3. tsan: its own Debug build, since TSan cannot combine with ASan.
4. lint: clang-tidy, clang-format, ruff, shellcheck, shfmt (ty report-only).

Sanitized binaries get their own build dirs and stay out of the release matrix. Cache the
dependency layer in every job.

## Matrix Builds

Cover only the OS/compiler combinations you ship; every cell costs minutes.

```yaml
# GitHub Actions
jobs:
  build:
    strategy:
      fail-fast: false              # one failing cell doesn't cancel the rest
      matrix:
        include:                    # one job per entry
          - { os: ubuntu-latest, cc: gcc-15,   cxx: g++-15 }
          - { os: ubuntu-latest, cc: clang-21, cxx: clang++-21 }
          - { os: macos-latest,  cc: clang,    cxx: clang++ }
    runs-on: ${{ matrix.os }}
    env: { CC: ${{ matrix.cc }}, CXX: ${{ matrix.cxx }} }
    steps:
      - uses: actions/checkout@v4
      - run: cmake --preset default
      - run: cmake --build --preset default
      - run: ctest --preset default --output-on-failure
```

- Pin compiler versions rather than the runner default; install them if the image lacks them.
- Add a `c++2c` cell only behind a feature-test-macro guard; C++26 is not shipping.

## Dependency Caching

Key the cache on the file that determines the dependency set, so a stale key never serves
wrong binaries:

```yaml
      # vcpkg binary cache (default location on Linux/macOS)
      - uses: actions/cache@v4
        with:
          path: ~/.cache/vcpkg/archives
          key: vcpkg-${{ matrix.os }}-${{ hashFiles('vcpkg.json') }}

      # Conan cache
      - uses: actions/cache@v4
        with:
          path: ~/.conan2
          key: conan-${{ matrix.os }}-${{ hashFiles('conan.lock') }}

      # FetchContent sources/builds (preset binaryDir build/default)
      - uses: actions/cache@v4
        with:
          path: build/default/_deps
          key: deps-${{ matrix.os }}-${{ hashFiles('CMakeLists.txt') }}
```

For Python, key on `uv.lock` or `pylock.toml`.

## The Sanitizer Gate (ASan + UBSan, TSan separate)

Treat any report as a failing build. Per-sanitizer detail: [sanitizers.md](../../diagnostics/references/sanitizers.md).

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
```

### TSan job

The `tsan` job is the same with `build/tsan`, `-fsanitize=thread`, and
`TSAN_OPTIONS: halt_on_error=1:exitcode=1`. The `exitcode=1` options make a swallowed
report still fail the job.

## Lint / Static-Analysis Gates

Run in report-or-fail mode; don't auto-fix in CI.

```yaml
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # C/C++: clang-tidy needs compile_commands.json from a configure step
      - run: cmake --preset default -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
      - run: clang-tidy -p build/default $(git ls-files '*.c' '*.cpp')
      - run: clang-format --dry-run --Werror $(git ls-files '*.c' '*.cpp' '*.h' '*.hpp')
      # Python
      - run: ruff check .
      - run: ruff format --check .
      # Bash
      - run: shellcheck $(git ls-files '*.sh')
      - run: shfmt -d $(git ls-files '*.sh')
```

ty (Astral, beta) is report-only: surface its findings but keep pyright/mypy as the type
gate.

## Reproducible Builds

- Pin the toolchain (exact GCC/Clang/CMake versions) and dependencies (vcpkg baseline,
  `conan.lock`, `uv.lock`/`pylock.toml`), with caches keyed on those files.
- Strip nondeterminism: `-ffile-prefix-map=$PWD=.` removes absolute build paths,
  `SOURCE_DATE_EPOCH` stabilizes archive timestamps, and explicit file lists avoid
  filesystem-order globs.
- Build out of source so `rm -rf build` is a full reset.

```bash
cmake -S . -B build -DCMAKE_CXX_FLAGS="-ffile-prefix-map=$PWD=."
```

## Related References

- [package-managers.md](package-managers.md): what to hash for the dependency cache key
- [version-feature-matrix](../../../_shared/version-feature-matrix.md): pin matrix versions to the toolchain floors
- [secure-coding](../../../_shared/secure-coding/SKILL.md): hardening flags for the release build
