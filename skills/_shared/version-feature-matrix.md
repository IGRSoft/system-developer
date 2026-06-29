---
name: version-feature-matrix
description: Canonical lookup mapping language standards and versions (C17/C23, C++17/20/23/26-emerging, Python 3.12-3.15, Bash 5.2/5.3) to minimum toolchain versions and headline features. Reference before asserting feature availability or pinning a standard.
---

# Version & Feature Matrix

Canonical lookup for "which toolchain do I need for this standard, and what do I get". Every version-specific claim in this plugin's skills should link here rather than restate minimums. Compiler-support tables shift between minor releases — for entries marked *(verify)*, confirm against your toolchain (`gcc --version`, `clang --version`, `python3 -VV`, `bash --version`) and the vendor's C/C++ status pages before relying on a feature in CI.

Probe a specific feature instead of guessing: `scripts/check_feature_support.sh --feature NAME` (run `--list` for the names) checks the compiler's feature-test macro or compiles a probe for C/C++, and compares the interpreter version for Python/Bash — exit 0 = supported. It consolidates the per-feature availability checks below; keep its feature map in sync with these tables.

## C

| Standard | GCC | Clang | MSVC | What you get (one line) |
|----------|-----|-------|------|-------------------------|
| C17 | 8+ | 7+ | VS 2019 16.8+ (`/std:c17`) | Bugfix revision of C11 — the safe portability baseline; no new features |
| C23 | 13+ (core; `#embed` from 15 *(verify)*) | 16+ (core; `#embed` from 19 *(verify)*) | No complete `/std:c23` mode at time of writing *(verify)* | `nullptr`, `constexpr` objects, `typeof`, `<stdckdint.h>` checked arithmetic, `_BitInt(N)`, empty `()` means `(void)`, attributes |

**Fallback row**: if the toolchain cannot guarantee C23, pin `-std=c17` and emulate: `nullptr` → `NULL` with care, `<stdckdint.h>` → `__builtin_add_overflow` (GCC/Clang), `typeof` → `__typeof__` extension.

## C++

| Standard | GCC | Clang | MSVC | What you get (one line) |
|----------|-----|-------|------|-------------------------|
| C++17 | 7+ (complete incl. parallel algorithms ~9; `<filesystem>` needs `-lstdc++fs` before 9) | 5+ (libc++ 7+) | VS 2017 15.7+ | Structured bindings, `if constexpr`, `std::optional`/`variant`/`string_view`, `<filesystem>`, CTAD |
| C++20 | 10+ (substantially complete 11+) | concepts 10+, ranges/coroutines usable ~13-15 *(verify)*; `std::format` in libc++ from ~17 *(verify)* | VS 2019 16.10+ (`/std:c++20`) | Concepts, ranges, coroutines, three-way comparison, `std::span`, `constinit`/`consteval`, modules (build-system support varies — see `tooling/build-systems`) |
| C++23 | 13+ (more complete 14+ *(verify)*) | 17+ partial; deducing this from 18 *(verify)* | VS 2022 17.6+ partial (`/std:c++latest`) *(verify)* | `std::expected`, `std::print`/`println`, deducing this, `if consteval`, `std::mdspan`, `std::generator`, multidimensional `operator[]` |
| C++26 (emerging) | GCC 15.x partial (`-std=c++2c`) | Clang 20-21.x partial (`-std=c++2c`) | No (verify) | static reflection (P2996), contracts, `std::execution`/senders-receivers (P2300), `std::inplace_vector`, `std::hive`, hardened std lib / erroneous behavior, pack indexing, `_` placeholder, `std::optional<T&>`, `span::at`, `submdspan` — C++26 (DIS 2026) — not shipping; gate on `-std=c++2c` + feature-test macros |

**Fallback rows**:
- No C++26 → stay on C++23; adopt features one-by-one behind `__cpp_*` feature-test macros (never `-std=c++2c` blanket-enabled in production).
- No C++23 → `std::expected` ≈ `tl::expected` (header-only); `std::print` ≈ `fmt::print` (fmtlib is also the proving ground for `std::format`).
- No C++20 ranges/format on the deployment toolchain → range-v3 / fmtlib, or stay on C++17 idioms; gate with `__cpp_lib_*` feature-test macros, never compiler version alone.

## Python (CPython)

| Version | Status anchor | What you get (one line) |
|---------|---------------|-------------------------|
| 3.12 | Released 2023-10 | PEP 695 `type` statement and class type parameters, f-string grammar formalized (PEP 701), per-interpreter GIL at C-API level (PEP 684), better error messages |
| 3.13 | Released 2024-10 | Experimental free-threaded build (PEP 703, separate `python3.13t` binary), experimental JIT, new REPL, `locals()` semantics (PEP 667) |
| 3.14 | Released 2025-10 | Free-threading officially supported (PEP 779, still a separate build), t-strings (PEP 750, `Template` objects — not str), deferred annotations by default (PEP 649/749), `concurrent.interpreters` (PEP 734), `compression.zstd` |
| 3.15 | Beta 2 (2026-06-02); GA 2026-10-01 (PEP 790); free-threading-by-default is Phase III — future, not 3.15 | *(beta — verify against release notes)* |

**Fallback rows**:
- Pre-3.14 t-strings: no backport — keep building safe DSLs with explicit escaping functions.
- Pre-3.14 deferred annotations: keep `from __future__ import annotations`; **on 3.14 stop adding it** (PEP 649 supersedes it; the future import forces the older string semantics).
- Pre-3.13/3.14 free-threading: use `multiprocessing` or C-extension GIL release for CPU parallelism.
- Minimums for tooling assumed by this plugin: `uv` and `ruff` are version-independent of CPython within 3.12-3.14; pin them in `pyproject.toml`/`uv.lock`, not prose.

## Bash

| Version | Where you find it | What you get (one line) |
|---------|-------------------|-------------------------|
| 5.2 | Most current Linux distros; Homebrew | `patsub_replacement` (`&` in `${var/pat/rep}`), `varredir_close`, improved `wait -p` |
| 5.3 | Current stable — widely shipped in distros and Homebrew by mid-2026 | `${ command; }` no-fork command substitution, `GLOBSORT`, plus smaller builtins/readline improvements |
| 3.2 (fallback row) | **macOS `/bin/bash`** (frozen for licensing reasons) | None of the above — no associative arrays, no `${var,,}`, no `mapfile`; target POSIX sh or require Homebrew bash via `#!/usr/bin/env bash` + a version guard |

Version guard snippet:

```bash
if ((BASH_VERSINFO[0] < 5)); then
  echo "error: bash >= 5.0 required (found ${BASH_VERSION})" >&2
  exit 1
fi
```

## Build / Toolchain Floor Quick Reference

Probe the local toolchain against these floors with
`scripts/check_toolchain_versions.sh` (relative to this file) — it prints an
`ok`/`below`/`missing` table and, with `--strict`, fails a CI image that is below
floor. The script mirrors this table; keep the two in sync.

| Tool | Floor assumed by this plugin | Reason |
|------|------------------------------|--------|
| CMake | 4.x (≈4.3.x); 3.28+ for `FILE_SET CXX_MODULES` (legacy modules floor) | `CMakePresets.json` workflow; C++20 modules; `CMAKE_POLICY_VERSION_MINIMUM` for legacy projects |
| Meson | 1.11 | Stable `meson setup`/`compile`/`test` verbs |
| Conan | 2.29 (`CMakeConfigDeps` generator) | Conan 2.x dependency integration (`CMakeConfigDeps` replaces `CMakeDeps`) |
| uv | current stable | Lockfile (`uv.lock`) + `uv run` workflows |
| ruff | current stable | Lint + format + `--select UP` modernization |
| cppcheck | 2.18 | Static analysis (MISRA addon) |
| IWYU (include-what-you-use) | 0.26 | Header hygiene |
| shellcheck / shfmt / bats-core | shellcheck 0.11 / shfmt 3.13 / bats 1.13 | Bash gate trio |
| GoogleTest / Catch2 | GoogleTest 1.17 (C++17 minimum; live at head) / Catch2 3.9 | CMake-native discovery (`gtest_discover_tests`, `catch_discover_tests`) |

## Usage Rules

1. **Feature-test before version-test** in C/C++: prefer `__has_include`, `__cpp_lib_*`, `__STDC_VERSION__` checks over compiler version comparisons.
2. **Every skill claim that names a standard links here** — do not restate minimum versions elsewhere; one table to update.
3. **Hedge volatile minutiae**: where this table says *(verify)*, the support landed across several minor releases — confirm on the actual CI image before pinning.

## Related Skills

- `cpp/SKILL.md` — standard-selection decision table (which standard to *choose*; this file is which standard you *can* use)
- `language-detection.md` — routing before version questions arise
- `tooling/build-systems` — expressing the chosen standard in CMake/Meson
