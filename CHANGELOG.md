# Changelog

All notable changes to the **system-developer** plugin are documented here. The
format follows [Keep a Changelog](https://keepachangelog.com/) and the project
adheres to [Semantic Versioning](https://semver.org/). Version strings move
together across `plugin.json`, `marketplace.json`, `README.md`, and `MEMORY.md`
per the igrsoft `/cc-update` convention.

## [1.2.0] — 2026-06-14

2026 best-practices currency refresh plus targeted structural fixes. All changes
are **additive** — existing C++17/20/23, Bash 5.2, and mypy/pyright guidance is
preserved.

### Added

- **C++26 emerging standard row** across the canonical surfaces — the
  `_shared/version-feature-matrix.md` hub, `cpp/SKILL.md` standard-selection
  table, the `cpp-developer` agent, `README.md`, and plugin keywords. Headline
  features cited: static reflection (P2996), contracts, `std::execution` /
  senders-receivers (P2300), `std::inplace_vector`, `std::hive`, hardened std lib /
  erroneous behavior, pack indexing, `_` placeholder, `std::optional<T&>`,
  `span::at`, `submdspan`. Carries the exact hedge: **C++26 (DIS 2026) — not
  shipping; gate on `-std=c++2c` + feature-test macros**.
- **`tooling/build-systems` skill created** — `skills/tooling/build-systems/SKILL.md`
  plus `references/cmake-modern.md` (Modern CMake target-based doctrine,
  CMakePresets v6, FetchContent vs vcpkg vs Conan 2.29 `CMakeConfigDeps`, CMake 4.x
  migration / `CMAKE_POLICY_VERSION_MINIMUM`, C++20 modules `FILE_SET CXX_MODULES` /
  `import std`, Meson 1.11, and Make positioning). This **resolves the phantom**
  build-systems reference (previously linked by ~22 files while absent from disk
  and `marketplace.json`) and makes the "25 SKILL.md across 7 domains" count true
  on disk (the build-systems skill is the 25th; HEAD already had 24 before it).
  Registered in `marketplace.json`.
- **Python `ty` (Astral, beta) and `pyrefly` (Meta, stable v1.0)** as emerging
  fast type checkers alongside the pyright/mypy gate; `Bash(ty:*)` added to the
  relevant agent allow-lists.
- **PEP 751 `pylock.toml`** as the standardized, interoperable lockfile (final),
  with `uv export --format pylock.toml` documented for export and supply-chain
  scanning.
- **`code-modernize` C23 target profile** — a C17→C23 ledger (`nullptr`,
  `constexpr` objects, `<stdckdint.h>`, `#embed`, `typeof`, `_BitInt(N)`, empty
  `()` means `(void)`, `[[nodiscard]]`/`[[maybe_unused]]`/`[[deprecated]]`) plus a
  `cpp26` future target stub marked `(not shipping — DIS 2026)`.
- **Python 3.15 forward line** (beta; GA 2026-10-01 per PEP 790 —
  free-threading-by-default is Phase III, not 3.15).
- **New plugin keywords** — `cpp26`, `ty`, `pyrefly`, `pylock`.

### Changed

- **Bash 5.3 de-hedged** — now described as current stable (widely shipped in
  distros and Homebrew by mid-2026); the "verify against your `bash --version`"
  hedge was dropped. The macOS `/bin/bash` 3.2.57 fallback row is retained.
- **Tool-version baselines refreshed** — GCC 15.x, Clang 20-21.x, `-std=c23`
  (GCC 14 / Clang 18), `-std=c++2c` partial, CMake 4.x (≈4.3.x), Meson 1.11,
  Conan 2.29 (`CMakeConfigDeps`), vcpkg manifest GA, clang-tidy/clang-format
  22.1.x, cppcheck 2.18, IWYU 0.26, GoogleTest 1.17 (C++17 minimum), Catch2 3.9,
  Unity 2.6, CMocka 1.1.8, shellcheck 0.11, shfmt 3.13, bats 1.13.
- **Free-threading story updated** — single-thread overhead ~5-10% on 3.14 (down
  from ~40% on 3.13); ~51% of top native-wheel packages now ship `cp314t` wheels
  (NumPy 2.3.4 included). The "verify your dependency tree before production"
  guidance is retained.
- **`uv_build` backend** promoted to Production/Stable (uv 0.11.x); the
  "evolves quickly / verify" hedge removed.
- **`marketplace.json` keywords** synced to a superset of `plugin.json` (added
  `c17`, `cpp17`, `cpp20`, `cpp26`, `free-threading`, `ffi-interop`, `hooks`,
  `ty`, `pyrefly`, `pylock`, and the remaining workflow keywords); descriptions
  aligned across `plugin.json` and `marketplace.json`.

### Fixed

- The SKILL.md count claim is now accurate on disk — reconciled to **25** across
  7 domains (HEAD already had 24 before the new build-systems skill, which is the
  25th). The build-systems skill that the count depends on has been created and
  registered.

## [1.1.0]

Prior release. Added the shared `skills/embedded/` domain (seventh domain) — an
entry skill (`embedded-skills`) and two leaf skills (`embedded-systems`,
`embedded-cpp`) with reference files, cross-linked from `c/SKILL.md` and
`cpp/SKILL.md`. Established the Bash 5.3 and Python 3.14 baselines and the
tiered-`maxTurns` / scoped-`Bash(cmd:*)` allow-list / plugin-scoped advisory-hooks
conventions on the igrsoft v3.17.0 / CC 2.1.169 baseline.
