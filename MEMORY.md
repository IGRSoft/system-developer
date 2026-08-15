# system-developer Plugin Memory

## Version Tracking

| Field | Value |
|-------|-------|
| Plugin version | 1.6.2 |
| corpflow compatibility | v4.0.13 |
| Claude Code min required | 2.1.170 |
| Last updated | 2026-07-29 |

Version strings move together (plugin.json, marketplace.json metadata, README
header, this table) per the corpflow `/cc-update` convention.

## CC Features Adopted at 1.0.0

The plugin is born on the corpflow v3.27.1 / CC 2.1.170 baseline, so it adopts the
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
  (`corpflow:*`, `security-scanning:*`, etc.).
- **Scoped `Bash(cmd:*)` allowlists** — each agent's `tools:` enumerates only the
  toolchain binaries it needs (for example `c-developer`: gcc, clang, cc, make,
  cmake, ninja, ctest, clang-tidy, clang-format, gdb, lldb, valgrind, pkg-config,
  man, git). Because scoped patterns do not match compound commands, agents issue
  single-command invocations (`cmake --build`, `ctest --test-dir`, `make -C`)
  rather than `cd`-chains.
- **Plugin-scoped advisory hooks** — `hooks/{audit-tooluse,audit-subagent,
  precompact-checkpoint}.sh`, wired in `plugin.json` (PostToolUse / SubagentStop /
  PreCompact). All rows are advisory (`actor: "system-developer:hook:*"`,
  `metadata.advisory: true`) and share corpflow's `dedupe_key` / `dedupe_key_extended`
  shape so corpflow's `audit-dedup.sh` keeps the orchestrator row authoritative when
  system-developer runs nested. Each script has `--self-test`.

## Not Adopted (corpflow-owned infrastructure)

system-developer agents are invoked specialists; corpflow owns orchestration. The
following stay orchestrator-owned and are deliberately **not** implemented here:

- **`audit-dedup.sh`** — corpflow-owned. system-developer emits advisory rows with
  matching dedupe keys for corpflow's helper to reconcile; it does not reconcile
  them itself.
- **`state-merge.sh` / SubagentStop `state.json` merge** — orchestrator-owned.
  The hooks here read and checkpoint state but never merge it. Frontmatter
  emission is unconditional (it is the input corpflow's merge layer consumes).
- **Screenshot-gate ownership** — corpflow owns the evidence gate. system-developer
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
- **Shared verb-first command names (v1.5.0)** — commands use bare filenames
  (invoked as `/system-developer:<name>`) drawn from the naming standard shared
  across the corpflow plugin family, with `apple-developer` as the reference
  implementation: a `<verb>-<object>` shape grouped by verb (`review-`, `fix-`,
  `gen-`, `arch-`, `analyze-`). Supersedes the pre-1.5.0 ad-hoc names
  (`code-review`, `lint-fix`, `deps-audit`, …). The point is cross-plugin recall —
  the same intent resolves to the same name everywhere — so a new command here
  takes the standard name even when a locally more descriptive one exists.
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

## Refresh Log (v1.6.0 — 2026-07-29)

Cross-language correctness audit. Hunted exactly one defect class: a rule true for one
of the four languages, stated as universal in a document serving all four. Nothing was
added to the agent, skill, or command inventory.

- **Build Evidence was C/C++-only but declared "non-negotiable" for every DV artifact**
  (`skills/_shared/workflow-integration/SKILL.md`, `templates/dv-development.md`,
  `agents/_base/language-agent.md`). Now a per-language table. The DR and QA sections of
  the same file were already qualified — this was a missed spot, not a policy.
- **`Bash(meson:*)` was granted to no agent** while `_base/language-agent.md § Tool
  Priority` instructs every agent to run `meson compile -C` and `/build-test` detects
  Meson at priority 3. Added to `c-developer`, `cpp-developer`, `sys-code-fixer`,
  `sys-test-generator`. Treat the allowlist and the prose that names tools as one unit —
  when either moves, check the other.
- **Advertised-with-no-implementation**: `/analyze-tech-debt --focus` (echoed in the
  report header only), `/sanitize-check --preset`'s non-CMake warning and its missing
  `MSAN_OPTIONS` row, `/fix-modernize --target bash`'s semantic classes (no delegation
  route existed), `unity` missing from `/gen-tests --framework`.
- **CMake-as-the-only-build-system** leaked into `/sanitize-check`, `/gen-tests`, and
  `/fix-performance` despite all three deferring to `/build-test`'s detection, which
  admits Meson, Make, and autotools. Each now carries the non-CMake forms.
- **Pre-existing, deliberately untouched**: `section-lint` fails repo-wide (many
  sections over the 1000-char cap, predating this change), and `validate.sh --strict`
  exits 1 on two >8KB SKILL.md warnings (`skills/SKILL.md`,
  `skills/_shared/workflow-integration/SKILL.md`). Error count stays 0.

## Refresh Log (v1.5.0 — 2026-07-29)

Command-surface unification with the corpflow plugin family. The command set is the only
thing that moved — no agent, skill, or language guidance changed.

- **Six commands renamed** to the cross-plugin verb-first standard (`code-review` →
  `review-code`, `lint-fix` → `fix-quick`, `code-modernize` → `fix-modernize`,
  `profile-performance` → `fix-performance`, `generate-tests` → `gen-tests`, `deps-audit`
  → `deps`). Breaking: the old names no longer resolve. `build-test` and `sanitize-check`
  were already compliant. The full old → new map lives in `README.md § Migration`.
- **Eight commands added** — `arch-select`, `arch-review`, `analyze-tech-debt`,
  `gen-docs`, `debug`, `analyze-accessibility`, `fix-refactor`, `develop-feature` — for a
  16-command surface matching the standard set. Each was adapted from its
  `apple-developer` counterpart across three axes (tech stack, agent routing, skill
  references) rather than transliterated; every `skill:` reference was verified against
  `skills/_index.md`, and no apple skill name was carried over.
- **`fix-performance` gained `--apply`** — measure-only stays the default and the
  profiling phases stay strictly read-only; the apply phase is unreachable without both
  the flag and an approved `AskUserQuestion` PHASE CHECKPOINT, and is followed by a
  binding build+test gate and a mandatory re-measure.
- **`deps` moved to subcommand form** (`audit | upgrade | add`), defaulting to the
  read-only audit when the first token is absent or unrecognized.
- **Frontmatter standard enforced on all 16 commands** — verb-first `description` ≤120
  chars, no `name:` key, minimal `allowed-tools`, `estimated-cost` with a
  `model-distribution` summing to 100. Both `analyze-*` commands are read-only.
- **`scripts/validate.sh` fix** — a leading `${CLAUDE_SKILL_DIR}/` is now normalized
  before resolving backticked skill paths, clearing two false-positive warnings.
- **Known pre-existing debt (not introduced here)**: `validate.sh --strict` still exits 1
  on two >8KB `SKILL.md` files with no `references/` sibling (`skills/SKILL.md`,
  `skills/_shared/workflow-integration/SKILL.md`). Both predate 1.5.0 and splitting them
  is a skills refactor, not a command change.

## Refresh Log (v1.4.0 — 2026-07-22)

corpflow v3.36.0 port — three workflow-contract learnings plus repo-structure linters; no
C/C++/Python/Bash guidance changed.

- **Contract sync v3.33.0 → v3.36.0** — version headline realigned across `plugin.json`,
  `marketplace.json`, `README.md`, this file, the `workflow-integration` skill, and the agent
  stage-participation headers. The PL0 stamp note now also names `metadata.test_mode` and
  `metadata.ui_visual_check` (the latter **N/A** for systems/CLI work — left `false`), citing
  corpflow `estimation-methodology § PL0 Stage-Set`; the Dynamic Worktask Sizing table was
  already current (DR0 at every tier).
- **CLI evidence freshness** — `cli-fallback` transcripts must be produced this run from the
  actual build/test invocation, never reused; the systems analog of corpflow's ov151
  evidence-integrity gate (QA direct-reads evidence and cross-checks `### build-evidence` log
  paths, re-opening DV on a stale/duplicated transcript).
- **state-patch pointer form** — replaced the manual `read → merge → temp → fsync → rename`
  atomic-write prose with the two-mode `state-patch.sh --stage <CODE> --prev <PREV>` contract
  (run when its path is supplied, else silently skip; Layers 2/3 repair from frontmatter).
- **Benchmark-driven output budgets + architector Complexity Triage** — `Output Budget` blocks
  on DV/`_base`, AR, DV-support, and DR-support agents (Build Evidence exempt) and a
  `Complexity Triage` gate that self-limits `system-architector` at Low complexity.
- **Structure linters** — `section-lint.sh` + `desc-lint.sh` wired into `scripts/test.sh`.
  section-lint baseline: 491 sections over cap across 101 files (warn-only, burn-down tracked
  separately; scope includes references/).

Follow-ups: the skills `description` cap (600) is a regression brake, not a target — worst
today is 514 (`embedded-cpp`); tightening waits on eval evidence that a shorter description
still fires the right skill. The section-lint burn-down is tracked separately.

## Refresh Log (v1.3.1 — 2026-07-08)

- **corpflow compatibility refresh v3.27.1 → v3.33.0** — version-string realignment only; the
  `workflow-integration` content was already current (`/worktask`-only launch, two-gate model),
  so no agent/skill behavior changed. Bumped the compat headline across `plugin.json`,
  `marketplace.json`, `README.md`, the version table above, the `workflow-integration` skill
  contract headers, the skill-catalog descriptions, and the agent stage-participation headers
  (`system-developer`, `system-architector`, `sys-code-fixer`, `_base/language-agent`).
  Historical release notes below (the v3.17.0 → v3.27.1 baseline) are preserved unchanged.

## Refresh Log (v1.3.0 — 2026-06-23)

- **Worktask alignment to corpflow v3.27.1** — version co-move 1.2.0 → 1.3.0 and
  corpflow compatibility v3.17.0 → v3.27.1 (CC min 2.1.169 → 2.1.170) across
  plugin.json, marketplace.json, README, this file, and the skill-index labels.
  README Workflow Integration section refreshed: the two human checkpoints (PL plan
  gate + FN finalization gate, both on `PL0.metadata`, independently bypassable),
  `/megatask` dependency-DAG multi-issue batches, PL0 `metadata.skipped_stages`
  self-documentation, and SR/ET on `opus` (xhigh) with Fable 5 available. Keywords
  `fn-gate`, `fable-5`, `skipped-stages` added. No C/C++/Python/Bash guidance changed.
