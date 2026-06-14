# system-developer Plugin Memory

## Version Tracking

| Field | Value |
|-------|-------|
| Plugin version | 1.2.0 |
| igrsoft compatibility | v3.17.0 |
| Claude Code min required | 2.1.169 |
| Last updated | 2026-06-14 |

Version strings move together (plugin.json, marketplace.json metadata, README
header, this table) per the igrsoft `/cc-update` convention.

## CC Features Adopted at 1.0.0

The plugin is born on the igrsoft v3.17.0 / CC 2.1.169 baseline, so it adopts the
current capability set from the start rather than migrating into it:

- **Tiered `maxTurns`** — every agent declares a runaway-loop backstop sized to
  its role: haiku/low 20 (`sys-dependency-manager`), haiku/medium 30
  (`sys-code-fixer`), sonnet/medium 40 (`system-developer` router), sonnet/high 50
  (the four language developers, `sys-test-generator`, `sys-performance-engineer`,
  `sys-security-auditor`), opus/xhigh 60 (`system-architector`).
- **`disallowed-tools: Write, Edit`** — declared on the two review-only agents
  (`sys-performance-engineer`, `sys-security-auditor`) as defense-in-depth on top
  of their already Write/Edit-free `tools:` allow-lists. Fixes route to
  `sys-code-fixer`.
- **Fully-qualified `Task(plugin:agent)` references** — all delegations use the
  `Task(system-developer:<agent>)` / `subagent_type="system-developer:<agent>"`
  form; no bare agent names anywhere. Cross-plugin targets keep their own prefix
  (`igrsoft:*`, `security-scanning:*`, etc.).
- **Scoped `Bash(cmd:*)` allowlists** — each agent's `tools:` enumerates only the
  toolchain binaries it needs (for example `c-developer`: gcc, clang, cc, make,
  cmake, ninja, ctest, clang-tidy, clang-format, gdb, lldb, valgrind, pkg-config,
  man, git). Because scoped patterns do not match compound commands, agents issue
  single-command invocations (`cmake --build`, `ctest --test-dir`, `make -C`)
  rather than `cd`-chains.
- **Plugin-scoped advisory hooks** — `hooks/{audit-tooluse,audit-subagent,
  precompact-checkpoint}.sh`, wired in `plugin.json` (PostToolUse / SubagentStop /
  PreCompact). All rows are advisory (`actor: "system-developer:hook:*"`,
  `metadata.advisory: true`) and share igrsoft's `dedupe_key` / `dedupe_key_extended`
  shape so igrsoft's `audit-dedup.sh` keeps the orchestrator row authoritative when
  system-developer runs nested. Each script has `--self-test`.

## Not Adopted (igrsoft-owned infrastructure)

system-developer agents are invoked specialists; igrsoft owns orchestration. The
following stay orchestrator-owned and are deliberately **not** implemented here:

- **`audit-dedup.sh`** — igrsoft-owned. system-developer emits advisory rows with
  matching dedupe keys for igrsoft's helper to reconcile; it does not reconcile
  them itself.
- **`state-merge.sh` / SubagentStop `state.json` merge** — orchestrator-owned.
  The hooks here read and checkpoint state but never merge it. Frontmatter
  emission is unconditional (it is the input igrsoft's merge layer consumes).
- **Screenshot-gate ownership** — igrsoft owns the evidence gate. system-developer
  work defaults to `requires_screenshots: false` and, when a gate demands proof,
  supplies `cli-fallback` terminal transcripts (build logs, ctest/pytest/bats
  output, sanitizer reports). It does not own or override the gate itself.

## Decisions Log

- **Single `bash-developer` absorbing POSIX** — rather than separate Bash and
  POSIX-shell agents, one `bash-developer` covers both, with POSIX handled as a
  "Portability Mode" section (GNU/BSD divergence, `dash`/`sh` targets). One agent,
  one mental model, no routing ambiguity for `.sh`/`.bash` files.
- **`sys-` prefix on the five colliding Tier-2 names** — `sys-test-generator`,
  `sys-performance-engineer`, `sys-security-auditor`, `sys-code-fixer`,
  `sys-dependency-manager` are prefixed because the bare names collide with
  apple-developer's Tier-2 agents. Non-colliding names stay plain
  (`system-developer`, `c-developer`, `cpp-developer`, `python-developer`,
  `bash-developer`, `system-architector`).
- **No localizator** — systems and scripting work has no String-Catalog / UI
  localization surface, so the apple-developer `localizator` role has no analog
  here and is intentionally omitted.
- **Review-only auditors** — `sys-performance-engineer` and `sys-security-auditor`
  carry `disallowed-tools: Write, Edit` and route all remediation to
  `sys-code-fixer`. Keeps the review/fix separation explicit and auditable.
- **Plain command names** — commands use bare filenames (invoked as
  `/system-developer:<name>`), mirroring apple-developer, rather than a verb prefix
  scheme.
- **Accepted `validate.sh` >8KB warnings on two entry SKILL.md files** —
  `skills/SKILL.md` (11KB navigation index) and
  `skills/_shared/workflow-integration/SKILL.md` (17KB cohesive handoff contract)
  exceed the 8KB references/-split heuristic. Left as-is: both are smaller than
  apple-developer's accepted equivalents (19KB and 21KB), and the workflow-integration
  contract is read whole by participating agents — fragmenting it across a references/
  dir would add a lookup hop on load-bearing handoff detail. The warnings are
  advisory (validator exits 0).
- **Shared `skills/embedded/` domain (v1.0.0 → 1.1.0 content addition)** — added a
  new seventh domain `skills/embedded/` with an entry skill (`embedded-skills`), two
  leaf skills (`embedded-systems`, `embedded-cpp`), and five reference files. Chosen
  as a shared domain (not sub-skills under `c/` or `cpp/`) because the bare-metal
  core (MMIO, volatile, ISRs, startup, no-heap, fixed-point, linker scripts,
  cross-compilation) is language-agnostic; the C++ subset leaf is C++-specific but
  cross-links cleanly from `cpp/SKILL.md`. Cross-linked from `c/SKILL.md` and
  `cpp/SKILL.md` selection tables, decision trees, and related-skills footers.
- **`tooling/build-systems/` skill created (v1.2.0)** — the pre-existing phantom
  link (previously referenced by ~22 files plugin-wide while absent from disk and
  `marketplace.json`) is now resolved: `skills/tooling/build-systems/SKILL.md` +
  `references/cmake-modern.md` were created (Modern CMake target-based doctrine,
  CMakePresets, FetchContent vs vcpkg vs Conan 2.29, CMake 4.x migration, C++20
  modules `FILE_SET CXX_MODULES` / `import std`, Meson 1.11, Make positioning) and
  registered in `marketplace.json`. Total SKILL.md count: 25 across 7 domains
  (build-systems skill created in v1.2.0, +1 over the prior 24). The count is
  accurate on disk.

## Refresh Log (v1.2.0 — 2026-06-14)

2026 best-practices currency refresh (additive only — no existing C++17/20/23,
Bash 5.2, or mypy/pyright guidance removed):

- **C++26 emerging row** added across the canonical hub
  (`_shared/version-feature-matrix.md`), `cpp/SKILL.md`, `cpp-developer`, README,
  and keywords — headline features (static reflection P2996, contracts,
  `std::execution`/senders P2300, `std::inplace_vector`, `std::optional<T&>`) with
  the exact hedge "C++26 (DIS 2026) — not shipping; gate on `-std=c++2c` +
  feature-test macros".
- **Python tooling currency** — `ty` (Astral, beta) and `pyrefly` (Meta, stable
  v1.0) added as emerging fast checkers alongside the pyright/mypy gate; PEP 751
  `pylock.toml` added as the standardized interop/export lockfile; `uv_build`
  promoted to Production/Stable; free-threading single-thread overhead updated to
  ~5-10% (3.14) from ~40% (3.13).
- **Bash 5.3 de-hedged** — now treated as current stable (macOS 3.2.57 fallback
  retained); tool baselines bumped (shellcheck 0.11, shfmt 3.13, bats 1.13).
- **Tool-version baseline refresh** — GCC 15.x, Clang 20-21.x, CMake 4.x,
  Conan 2.29 (CMakeConfigDeps), GoogleTest 1.17, Catch2 3.9, cppcheck 2.18,
  IWYU 0.26.
- **`code-modernize` C23 target profile** added (C17→C23 ledger) plus a `cpp26`
  future stub; **`marketplace.json` keyword sync** to a superset of `plugin.json`.
