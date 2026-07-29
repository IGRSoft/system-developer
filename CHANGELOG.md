# Changelog

All notable changes to the **system-developer** plugin are documented here. The
format follows [Keep a Changelog](https://keepachangelog.com/) and the project
adheres to [Semantic Versioning](https://semver.org/). Version strings move
together across `plugin.json`, `marketplace.json`, `README.md`, and `MEMORY.md`
per the igrsoft `/cc-update` convention.

## [1.6.0] — 2026-07-29

Cross-language correctness audit. This plugin serves four languages with genuinely
different toolchains, and the audit hunted one defect class: a rule true for **one**
language stated as though it were universal, in a document that serves all four. No
new agent, skill, or command was added; the fixes narrow over-broad claims, fill the
routing and permission holes those claims papered over, and implement one advertised
flag that had no code path.

### Fixed

- **DV Build Evidence demanded a C/C++ compiler line from every language.** The DV
  handoff contract (`skills/_shared/workflow-integration/SKILL.md § DV Contract for
  Systems Work`) declared a compiler/standard line and a `-Wall -Wextra` warning count
  "non-negotiable" for **all** DV artifacts, and `agents/_base/language-agent.md`
  echoed them as mandatory and never-trimmable to all four language agents. A pure
  Python or Bash change has neither, so the artifact was structurally incomplete or
  the agent had to fabricate a value. Build Evidence is now a per-language table
  (compiler + `-Wall -Wextra` for C/C++, interpreter + `ruff` for Python, shell
  version + `shellcheck` for Bash), with the same rule applied to the copy-paste
  template in `templates/dv-development.md`. The DR and QA sections of the same file
  were already language-qualified — the DV section had simply been missed.
- **No agent could run `meson`.** `agents/_base/language-agent.md § Tool Priority`
  instructs every language agent to build with `meson compile -C`, and Meson is a
  first-class detected build system in `/build-test` (priority 3), yet no agent's
  scoped `Bash(...)` allowlist granted the binary — the instruction silently could
  not execute. `Bash(meson:*)` added to `c-developer`, `cpp-developer`,
  `sys-code-fixer`, and `sys-test-generator`, plus the corresponding Meson command
  lines in the C and C++ agents' build sections.
- **`/fix-modernize --target bash` had no owner for its semantic classes.** The Bash
  playbook defines three `semantic` migration rows (strict-mode prologue, `trap`
  cleanup, `local`/arrays) but Phase 2 routed only mechanical, semantic-C, semantic-C++,
  and semantic-Python. A `semantic (Bash)` route to `bash-developer` was added, and
  Rule 5 now names it. Rule 6's "prefer feature-test macros (`__cpp_lib_*`,
  `__has_include`)" is qualified to C/C++, with the Python and Bash gating mechanisms
  (`sys.version_info`, `BASH_VERSINFO`) named.
- **`/analyze-tech-debt --focus` was advertised with no implementation.** The flag
  appeared in the frontmatter, the Options table, and two usage examples, but no phase
  consumed it; the only trace in execution was an echo in the report header. Phase 4
  now partitions findings by an explicit axis → taxonomy map and renders unfocused axes
  as one-line summaries, which is what the Options table always promised.
- **`/sanitize-check` gaps.** `msan` is an advertised kind and Rule 3 makes the
  matching `*_OPTIONS` mandatory, but the Runtime Options table had no `MSAN_OPTIONS`
  row. The `--preset` entry promised a warning on non-CMake projects that nothing
  emitted. Both added. The Build Flags block, which was CMake-only while Phase 1
  resolves the build system with `/build-test`'s priority order, now carries the Meson
  (`-Db_sanitize`, `-Db_lundef=false`) and Make/autotools equivalents.
- **`/debug` gated Python and Bash work on a debug rebuild.** Rule 3 ("Enforce the
  debug build", `-O0 -g`) sat unqualified in CRITICAL BEHAVIORAL RULES for a
  four-language command, Configure mode step 1 was unconditional, and the report's
  debug-build row was the only one with no skip state — forcing a ❌ on a pure Python
  or Bash project. All three qualified to C/C++ with an explicit `⏭ n/a` path. The
  Symptom → Tool Routing table, which every triage runs through, gained the two Bash
  rows it was missing.
- **`/gen-tests` assumed CMake and `uv`.** Registration, the mandatory verification
  gate, and the run table hard-coded `cmake`/`ctest` for C/C++ and `uv run pytest` for
  Python, despite Rule 1's own principle of honoring what the project already uses.
  Meson and Make registration/run forms added; the build step now takes its commands
  from the *detected* system; the pytest row no longer implies uv on a non-uv project.
  `unity` — resolvable by detection and used throughout the body — was missing from
  the advertised `--framework` set and is now listed.
- **`/arch-review --lang bash` and `/arch-select`'s ownership axis had no Bash
  content.** `arch-review` advertised `--lang bash` while every detection signal,
  violation class, and API/ABI rule was C/C++/Python; the Options entry now states the
  real coverage instead of implying parity, and the two genuinely applicable shell
  rows (sourced-library layering, cyclic `source`) were added. `arch-select` Rule 2
  mandates an ownership answer but the axis offered only memory models; `managed
  runtime` (Python) and `process-scoped` (Bash) rows added so the mandate is
  answerable in every language.
- **`/deps` silently downgraded a mutating request to a read-only audit.** The Dispatch
  rule at `commands/deps.md:23` defaults to `audit` when the first token "is not one of
  the three" — safe for an empty token or a bare path, but not for a flag that *names* a
  mutating mode. `deps --upgrade requests` fell through to the default and returned an
  audit for an upgrade the caller asked for, where "no action taken" reads as "nothing to
  do". `--upgrade` and `--add` anywhere in the arguments now stop with an explicit error
  instead of falling back. Same defect and same fix as `backend-developer`,
  `android-developer`, and `frontend-developer`; `apple-developer` was already safe
  because it asks rather than defaulting.
- **`/fix-performance` had no Bash collection path.** `--mode cpu|memory|io` is
  advertised for all four languages but the Platform/Tool Matrix covered only C/C++
  and Python, leaving a `.sh` target with no tool. A Bash section was added that says
  plainly there is no shell profiler and routes to timestamped xtrace, `strace -f`,
  and `--mode bench`. The CMake-only rebuild hint gained Meson and Make forms.

## [1.5.0] — 2026-07-29

Command-surface unification with the rest of the igrsoft plugin family. Six commands
are renamed to the shared verb-first scheme, eight new commands are added to match the
standard set, and two existing commands gain capability (`fix-performance` an optional
checkpoint-gated apply phase, `deps` a subcommand form). No C/C++/Python/Bash language
guidance changed, and no agent or skill was added or removed.

### Changed

- **BREAKING — six commands renamed** to the cross-plugin naming standard shared with
  `apple-developer`. The old names no longer resolve; update scripts, aliases, and
  worktask payloads that reference them.

  | Old | New |
  |-----|-----|
  | `code-review` | `review-code` |
  | `lint-fix` | `fix-quick` |
  | `code-modernize` | `fix-modernize` |
  | `profile-performance` | `fix-performance` |
  | `generate-tests` | `gen-tests` |
  | `deps-audit` | `deps` |

  `build-test` and `sanitize-check` were already compliant and are unchanged. Every
  in-body self-reference and cross-command reference across `commands/`, `agents/`,
  `skills/`, `tests/fixtures/`, and `README.md` was swept to the new names; historical
  release-note entries in this file, `MEMORY.md`, and the README's "What's in 1.2.0"
  section retain the names in use at that release.
- **`deps` restructured to subcommand form** — `deps audit | upgrade | add`, dispatched
  off the first token of `$ARGUMENTS`, defaulting to the read-only `audit` path when the
  token is absent or unrecognized. `upgrade`/`add` without a package name are now an
  explicit error rather than a guess. The three `Mode N:` sections are renamed
  `Subcommand:` accordingly.
- **`gen-tests` log filenames** moved from `.context/logs/generate-tests-<ts>.log` to
  `.context/logs/gen-tests-<ts>.log`.
- **Command frontmatter normalized** — verb-first `description` capped at 120 characters
  on every command (previously up to 162), minimal `allowed-tools`, and an
  `estimated-cost` band with a `model-distribution` summing to 100 on all 16.

### Added

- **`fix-performance --apply`** — an optional apply phase behind an explicit PHASE
  CHECKPOINT. Measure-only remains the default and Phases 1-5 stay strictly read-only
  (`Write`/`Edit` were added to `allowed-tools` solely for the new phase); `--apply`
  unlocks an `AskUserQuestion` checkpoint that must be approved before
  `sys-code-fixer` touches a file, followed by a binding `/system-developer:build-test`
  gate and a mandatory re-measure whose verdict is reported honestly (improved /
  unchanged / regressed, with a rollback offer unless improved). `--apply` is rejected
  with `--mode bench`, which produces no profile to derive a fix plan from.
- **Eight new commands**, each adapted from its `apple-developer` counterpart across
  three axes — tech stack (Swift/Xcode → C/C++/Python/Bash toolchains), agent routing,
  and skill references — with every referenced skill verified to exist in this plugin:

  | Command | Routes to | Notes |
  |---------|-----------|-------|
  | `arch-select` | `system-architector` | Structural pattern plus the orthogonal concurrency and ownership axes; every pick carries a version marker and a fallback. |
  | `arch-review` | `system-architector` | Read-only; cyclic deps, leaked internal headers, accidental ABI exposure, ownership ambiguity, concurrency mismatch. |
  | `analyze-tech-debt` | `system-architector` + language developers | Read-only; an absent tool marks a dimension unmeasured rather than guessing a number. |
  | `gen-docs` | language developers | Doxygen (C/C++), Sphinx docstrings (Python), shell header comments; verified by running the real doc build. |
  | `debug` | plugin router + `skill: diagnostics` | `configure`/`triage` dispatch; routes memory/UB/race symptoms to `sanitize-check` before a debugger. |
  | `analyze-accessibility` | plugin router | CLI output only — `NO_COLOR`, contrast-safe ANSI, screen-reader-friendly output, `--help` clarity. Read-only, `model: haiku`, and explicit that it makes no WCAG or GUI claim. |
  | `fix-refactor` | `system-architector` plans, `sys-code-fixer` applies | Requires a green baseline; a refactor on a red baseline is a rewrite. |
  | `develop-feature` | architect → language developers → `sys-test-generator` → `sys-security-auditor` | Phase checkpoints, sync points, and a resumable `.context/.feature-dev/state.json`. |

  Both `analyze-*` commands are read-only and carry no `Write`/`Edit`. The build gate in
  every new command is `/system-developer:build-test`.

### Fixed

- **`scripts/validate.sh`** — normalize a leading `${CLAUDE_SKILL_DIR}/` before resolving
  backticked skill reference paths, clearing two false "does not exist" warnings for
  `skills/embedded/_index.md` links whose targets are present on disk.

## [1.4.0] — 2026-07-22

igrsoft compatibility port to **v3.36.0** (from v3.33.0). Beyond the version-string
realignment, this release ports three igrsoft v3.36.0 workflow-contract learnings — the
`state-patch.sh` pointer form, a CLI evidence-freshness rule, and benchmark-driven output
budgets with an architector complexity gate — and wires two structure linters into the
test harness. No C/C++/Python/Bash language guidance changed.

### Changed

- **igrsoft compatibility → v3.36.0** across `plugin.json`, `marketplace.json`,
  `README.md`, `MEMORY.md`, the `workflow-integration` skill (invocation/contract headers
  + skill-catalog descriptions), and the agent stage-participation headers
  (`system-developer`, `system-architector`, `sys-code-fixer`, `_base/language-agent`).
  The Dynamic Worktask Sizing table was already current (DR0 at every tier); the PL0 stamp
  note now also names `metadata.test_mode` (`build-only`/`scoped`/`full`) and
  `metadata.ui_visual_check`, citing igrsoft `estimation-methodology § PL0 Stage-Set` as
  the source of truth.
- **state.json patching → `state-patch.sh` pointer form** — replaced the manual
  `read → merge → temp → fsync → rename` atomic-write prose in `_base/language-agent.md`,
  the `workflow-integration` skill (three-layer reconciliation), `system-architector.md`,
  and the DV template with the two-mode contract: run `state-patch.sh --stage <CODE> --prev
  <PREV>` when its path is supplied, else silently skip (never hand-roll a `jq`/manual
  merge) — Layers 2/3 repair the ledger from the unconditional `handoff:` frontmatter.

### Added

- **CLI evidence-freshness rule** — every `cli-fallback` transcript row must be produced
  *this run* from the actual build/test invocation; a stale or duplicated transcript
  re-opens DV. The systems analog of igrsoft's QA direct-read evidence-integrity check
  (`workflow-integration/SKILL.md § Screenshot Gate for CLI Work`). Also documents that
  `ui_visual_check` exists in the DV metadata contract but is **not applicable** to
  systems/CLI work (left `false`).
- **`Output Budget` blocks (benchmark-driven)** — added to DV (`_base/language-agent.md`),
  AR (`system-architector.md`), DV-support (`sys-test-generator.md`), and DR-support
  (`sys-code-fixer.md`): tighter artifact/return/tool-call caps *within* the existing
  ≤500-token return and ≤200-token frontmatter contract. **Build Evidence lines
  (compiler/standard, warning count, transcript path) are exempt from all caps.**
- **`Complexity Triage` (0–50)** — a gate on `system-architector` that self-limits scope
  at Low complexity (Quick Recommendation Mode mandatory, no Deep-Refactor artifacts);
  `model-selection.md` records the self-limit.
- **Structure linters** — `section-lint.sh` (≤1000-char section cap) and `desc-lint.sh`
  (two-tier frontmatter `description` cap) wired into `scripts/test.sh` alongside bats.

### Notes

- section-lint baseline: 491 sections over cap across 101 files — warn-only, burn-down
  tracked separately; scope includes references/.

## [1.3.1] — 2026-07-08

igrsoft compatibility refresh to **v3.33.0** (from v3.27.1); version-string realignment
only — the `workflow-integration` content was already current, so no agent/skill behavior
change.

### Changed
- **igrsoft compatibility → v3.33.0** across `plugin.json`, `marketplace.json`, `README.md`,
  `MEMORY.md`, the `workflow-integration` skill (invocation/contract headers), the skill
  catalog descriptions, and the agent stage-participation headers (`system-developer`,
  `system-architector`, `sys-code-fixer`, `_base/language-agent`). Historical release notes
  in this file and `MEMORY.md` describing the earlier v3.27.1 / v3.17.0 baseline are preserved
  unchanged.

## [1.3.0] — 2026-06-23

igrsoft worktask-behaviour currency refresh to v3.27.1; additive — existing
C/C++/Python/Bash guidance preserved.

### Changed

- **workflow-integration skill** — replaced the removed message-prefix trigger
  table (`micro:`/`quick:`/`worktask:`/`fworktask:`/`emergency:`) with the
  `/worktask` + flags invocation model; documented the two human checkpoints (PL
  & FN gates); added the `metadata.skipped_stages` note; bumped all v3.17.0
  labels to v3.27.1.
- **Corrected stage-model facts** — SR (`security-reviewer`) and ET
  (`ethics-reviewer`) run on opus at effort xhigh; Fable 5 (`fable`) noted as the
  available top tier (stage agents pin opus).
- **Base Code Comment Policy and agents** now cross-reference igrsoft's new
  compact code-documentation standard (`igrsoft:code-comment-standard`).
- **Refreshed igrsoft compatibility** to v3.27.1 / CC 2.1.170 across
  `plugin.json`, `marketplace.json`, `README.md`, `MEMORY.md`, and the 3
  skill-index labels.

### Notes

- The `requires_screenshots: false` / cli-fallback evidence norm and the
  DV/DR/QA handoff schema are unchanged.

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
