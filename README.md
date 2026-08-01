# System Developer Plugin

Claude Code plugin for systems and scripting development in **C**, **C++ (17/20/23/26-emerging)**, **Python 3.14**, and **Bash/POSIX shell**, with specialized agents, commands, and skills. Collaborates with the company-workflow plugin v4.0.0 for full 11-stage workflow orchestration (PL→AR→TL→DV→**DR**→SR→QA→DC→RE→FN→ST) including the handoff-protocol (planning-N.md, state.json ledger, frontmatter schema). Systems and CLI work defaults to `requires_screenshots: false`; when an evidence gate demands proof, agents attach `cli-fallback` terminal transcripts (build logs, test output, sanitizer reports) instead of screenshots.

**Version**: 1.6.0 | **company-workflow Compatibility**: v4.0.0 | **claude-code min version**: "2.1.170"

## What's new in 1.6.0

- **Cross-language correctness audit** — swept the plugin for one defect class: a rule true for a single language stated as universal in a document serving all four. The headline fix is the DV **Build Evidence** contract, which demanded a compiler line and a `-Wall -Wextra` warning count from *every* DV artifact and so was unsatisfiable for a pure Python or Bash change; it is now a per-language table.
- **Meson is executable, not just documented** — the shared agent base tells every language agent to build with `meson compile -C`, but no agent's scoped Bash allowlist granted the binary. `Bash(meson:*)` added to the four building agents, with matching Meson paths in `/sanitize-check`, `/gen-tests`, and `/fix-performance`, which had all hard-coded CMake.
- **Advertised flags now have code paths** — `/analyze-tech-debt --focus` is implemented rather than merely echoed, `/fix-modernize --target bash` has an owner for its semantic migration classes, `/sanitize-check` gained the missing `MSAN_OPTIONS` row, and `unity` joined the `/gen-tests --framework` set it was already resolvable from.
- **Python and Bash are no longer gated on C/C++ mechanics** — `/debug` no longer requires a debug rebuild for interpreted targets, `/fix-performance` has a real Bash collection path, and `/arch-select`'s ownership axis is answerable outside C and C++. See [`CHANGELOG.md`](CHANGELOG.md).

## What's new in 1.5.0

- **Unified command names** — six commands were renamed to the cross-plugin verb-first scheme shared with `apple-developer`, so the same intent resolves to the same name in every plugin. See [Migration: old → new command names](#migration-old--new-command-names) for the full map.
- **Eight new commands** — `arch-select`, `arch-review`, `analyze-tech-debt`, `gen-docs`, `debug`, `analyze-accessibility`, `fix-refactor`, and `develop-feature` bring the set to 16, matching the shared command surface. Each was adapted to C/C++/Python/Bash toolchains and this plugin's agents and skills rather than transliterated.
- **`fix-performance` can now close the loop** — measure-only remains the default and the profiling phases stay strictly read-only, but `--apply` unlocks a phase checkpoint that must be approved before `sys-code-fixer` edits anything, followed by a binding build+test gate and a mandatory re-measure.
- **`deps` moved to subcommand form** — `deps audit | upgrade | add`, dispatched off the first argument, defaulting to the read-only audit path. See [`CHANGELOG.md`](CHANGELOG.md).

## What's new in 1.4.0

- **company-workflow v3.36.0 sync** — compatibility headline realigned v3.33.0 → v3.36.0 across the manifests, README, `MEMORY.md`, the `workflow-integration` skill, and the agent stage-participation headers; the PL0 stamp note now also names `metadata.test_mode` and `metadata.ui_visual_check` (the latter N/A for CLI work, left `false`), with the Dynamic Worktask Sizing table already current (DR0 at every tier).
- **state-patch pointer form** — the manual `read → merge → temp → fsync → rename` atomic-write prose is replaced by the two-mode `state-patch.sh --stage <CODE> --prev <PREV>` contract (run when its path is supplied, else silently skip; Layers 2/3 repair from the unconditional `handoff:` frontmatter).
- **CLI evidence-freshness rule** — every `cli-fallback` transcript must be produced this run from the actual build/test invocation, never reused; the systems analog of company-workflow's QA direct-read evidence-integrity check.
- **Output budgets + Complexity Triage** — benchmark-driven `Output Budget` blocks on the DV (`_base`), AR, DV-support, and DR-support agents (Build Evidence stays exempt), plus a `Complexity Triage` gate on `system-architector` that self-limits scope at Low complexity; `section-lint` and `desc-lint` are wired into `scripts/test.sh`. See [`CHANGELOG.md`](CHANGELOG.md).

## What's new in 1.3.0

- **Worktask refresh to company-workflow v3.27.1** — workflow integration realigned to the current company-workflow worktask behaviour: launch is `/worktask`-only (no message-prefix triggers), two human checkpoints (the PL plan gate and the FN finalization gate, both carried on `PL0.metadata` and independently bypassable), `/megatask` for dependency-ordered multi-issue batches, PL0 dynamic sizing that stamps `metadata.skipped_stages`, and SR/ET running on `opus` (xhigh) with Fable 5 available as the top reasoning tier. See [`CHANGELOG.md`](CHANGELOG.md).

## What's in 1.2.0

- **2026 currency refresh** — C++26 added as an emerging standard (DIS 2026, not shipping; gate on `-std=c++2c` + feature-test macros) across the canonical hub, `cpp-developer`, and `cpp/SKILL.md`; Python `ty` (beta) / `pyrefly` (stable v1.0) checkers and PEP 751 `pylock.toml` interop lockfile added; Bash 5.3 de-hedged to current stable; tool baselines bumped (CMake 4.x, Conan 2.29, GoogleTest 1.17, shellcheck 0.11, shfmt 3.13, bats 1.13); `code-modernize` gained a C23 target profile; the previously-phantom `tooling/build-systems` skill is now created and registered. See [`CHANGELOG.md`](CHANGELOG.md).

## What's in 1.1.0

- **11 agents** — a `system-developer` router, four language developers (`c-developer`, `cpp-developer`, `python-developer`, `bash-developer`), `system-architector`, and five Tier-2 specialists (`sys-test-generator`, `sys-performance-engineer`, `sys-security-auditor`, `sys-code-fixer`, `sys-dependency-manager`). All inherit `agents/_base/language-agent.md`.
- **8 commands** — language-aware review, build/test, test generation, sanitizer runs, lint/format, profiling, standard modernization, and dependency auditing, each with restrictive `allowed-tools` and an `estimated-cost` band.
- **Complete skills tree** — 25 `SKILL.md` skills across `_shared`, `c`, `cpp`, `python`, `bash`, `embedded`, and `tooling`, with deep reference files. Version-specificity is the product: every language feature carries a standard/version marker and a pre-version fallback. The C++ standard-selection table and `skills/_shared/version-feature-matrix.md` are canonical; everything else links to them.
- **Plugin-scoped advisory hooks** — `audit-tooluse`, `audit-subagent`, `precompact-checkpoint`, wired in `plugin.json` with company-workflow-compatible dedupe keys. Advisory only: never merges `state.json` (orchestrator-owned). See [`hooks/README.md`](hooks/README.md).
- **CC capabilities adopted** — tiered `maxTurns` runaway-loop backstops, `disallowed-tools: Write, Edit` on the two review-only auditors, fully-qualified `Task(system-developer:<agent>)` delegations, and scoped `Bash(cmd:*)` allowlists per toolchain.

## Agents (11)

| Agent | Model / Effort | Purpose |
|-------|----------------|---------|
| `system-developer` | sonnet / medium | Index + router. Routes by file extension and keyword to language developers and specialists; handles cross-language work (FFI, C extensions, mixed CMake+pyproject repos) directly. |
| `c-developer` | sonnet / high | Efficient, memory-safe C. C17 baseline plus C23, POSIX/errno discipline, pthreads, C11 atomics, warning-clean GCC/Clang builds. |
| `cpp-developer` | sonnet / high | Idiomatic, memory-safe C++17/20/23 (plus C++26 emerging — DIS 2026, not shipping; gate on `-std=c++2c` + feature-test macros). RAII, smart pointers, ranges, concepts, coroutines, `std::expected`, Core Guidelines, standard-selection trade-offs. |
| `python-developer` | sonnet / high | Modern, type-safe Python 3.14. uv-managed environments, ruff-clean code, deferred annotations, free-threading, t-strings, subinterpreters, concurrency-model selection. |
| `bash-developer` | sonnet / high | Defensive, portable Bash and POSIX shell. Strict mode, GNU/BSD divergence, shellcheck/shfmt/bats gating, injection-safe scripting. |
| `system-architector` | opus / xhigh | Architecture pattern selection and migration planning — layered libraries, hexagonal, plugin/registry, pipeline, concurrency and ownership models, API/ABI design, semver. |
| `sys-test-generator` | sonnet / high | Test generation across GoogleTest/Catch2, Unity/CMocka, pytest/Hypothesis, bats-core. Uses the framework the repo already has; never introduces a second one. |
| `sys-performance-engineer` | sonnet / high (review-only) | Code-first performance review backed by perf, valgrind, py-spy, hyperfine, and native tracers. `disallowed-tools: Write, Edit`; fixes route to `sys-code-fixer`. |
| `sys-security-auditor` | sonnet / high (review-only) | Security audit — memory safety, injection, unsafe deserialization, secrets, supply-chain CVEs, hardening-flag verification, CWE mapping. `disallowed-tools: Write, Edit`. |
| `sys-code-fixer` | haiku / medium | Minimal-diff remediation for findings from review, `sys-security-auditor`, and `sys-performance-engineer`. Per-language quick-fix playbooks. |
| `sys-dependency-manager` | haiku / low | Manifests and lockfiles across vcpkg, Conan 2, CMake FetchContent, uv, and pip; CVE/license audit; safe one-at-a-time upgrades with a build+test gate. |

> `sys-performance-engineer` and `sys-security-auditor` are review-only by default; callers may override them to `opus` + `xhigh` for the hardest analyses (Opus 4.8 honors `xhigh`; Sonnet falls back to `high`, so the model must be raised too).

## Commands (16)

### Build, test, and verify

| Command | Description |
|---------|-------------|
| `/system-developer:build-test` | Detect the build system, configure, build, and run the test suite. The gate every other command runs against. |
| `/system-developer:gen-tests` | Generate, register, and verify a runnable test suite using the project's existing framework. Supports `--coverage-gaps`. |
| `/system-developer:sanitize-check` | Build with sanitizers (ASan/UBSan/TSan/LSan/MSan), run tests under them, and triage the reports. Supports `--fix`. |
| `/system-developer:debug` | Configure a debugging workflow, or triage one crash, hang, or wrong-value bug across gdb/lldb, strace, py-spy, and shell xtrace. |

### Review and analyze (read-only)

| Command | Description |
|---------|-------------|
| `/system-developer:review-code` | Language-aware review — parallel per-language reviewers plus a security pass, synthesized into a P0-P3 report. Supports `--quick` and `--fix`. |
| `/system-developer:arch-review` | Review the codebase against its architecture pattern; violations reported with `file:line` and P0-P3 severity. |
| `/system-developer:analyze-tech-debt` | Inventory, quantify, and rank technical debt into a P0-P3 remediation plan, each item naming its owning agent and fix command. |
| `/system-developer:analyze-accessibility` | Audit a CLI program's terminal output: `NO_COLOR` honoring, contrast-safe ANSI, screen-reader-friendly output, `--help` clarity. |

### Change code

| Command | Description |
|---------|-------------|
| `/system-developer:fix-quick` | Run linters and formatters (clang-tidy/clang-format, ruff, mypy, shellcheck, shfmt) — check-only (`--check`) or auto-fix (`--fix`). |
| `/system-developer:fix-modernize` | Modernize C (17→23), C++ (17→20→23), Python (→3.14), or Bash one standard jump at a time, gating each migration class on a green build and test run. Supports `--dry-run`. |
| `/system-developer:fix-refactor` | Refactor for clean-code and SOLID structure — `system-architector` plans, `sys-code-fixer` applies, every class gated on a green build. |
| `/system-developer:fix-performance` | Profile CPU, memory, or I/O hot paths, or benchmark with hyperfine. Measure-only by default; `--apply` adds an approval checkpoint, a build+test gate, and a re-measure. |

### Design, document, and build features

| Command | Description |
|---------|-------------|
| `/system-developer:arch-select` | Select the structural pattern plus the orthogonal concurrency and ownership axes for a module or project. |
| `/system-developer:develop-feature` | End-to-end feature development: design → implementation → tests → sanitizers → security pass, with phase checkpoints and a resumable state file. |
| `/system-developer:gen-docs` | Generate or update Doxygen (C/C++), Sphinx docstrings (Python), and shell header comments, then verify with the real doc build. |
| `/system-developer:deps` | `deps audit \| upgrade \| add` — CVE and license report, then exact-pinned one-at-a-time upgrades behind a build+test gate. |

All commands degrade gracefully when a tool is missing: they print an install hint (for example `brew install llvm shellcheck shfmt hyperfine`, `uv tool install ruff`), skip that language, and never hard-fail.

## Migration: old → new command names

Six commands were renamed in 1.5.0 to match the naming standard shared across the company-workflow plugin family. The old names no longer resolve — update any scripts, aliases, or worktask payloads that reference them.

| Old name (≤1.4.0) | New name (1.5.0+) | Behavior change |
|-------------------|-------------------|-----------------|
| `/system-developer:code-review` | `/system-developer:review-code` | None — same flags, same output. |
| `/system-developer:lint-fix` | `/system-developer:fix-quick` | None. |
| `/system-developer:code-modernize` | `/system-developer:fix-modernize` | None. |
| `/system-developer:profile-performance` | `/system-developer:fix-performance` | Additive: default stays measure-only; new `--apply` unlocks a checkpoint-gated fix phase. |
| `/system-developer:generate-tests` | `/system-developer:gen-tests` | Log filenames moved from `generate-tests-*.log` to `gen-tests-*.log`. |
| `/system-developer:deps-audit` | `/system-developer:deps` | Restructured to subcommands. `deps-audit audit` → `deps audit`; a bare `deps` still defaults to the read-only audit. |

`build-test` and `sanitize-check` were already standard-compliant and are unchanged.

## Skills (25)

### Shared

| Skill | Description |
|-------|-------------|
| `secure-coding` | Non-negotiable security rules and bug-class defenses across all four languages — injection-safe process execution, sanitizer mapping, integer safety, path-traversal/TOCTOU resistance, secrets hygiene. |
| `workflow-integration` | Guide for integrating with the company-workflow 11-stage workflow system (v4.0.0), including the DV development contract and the `requires_screenshots: false` / cli-fallback norm. |

### C

| Skill | Description |
|-------|-------------|
| `c-skills` | C language navigation — C17/C23 standard selection, C23 adoption, memory ownership, undefined behavior, C11/C17 concurrency. |
| `modern-c` | C23 quick wins with min compiler versions: `nullptr`, `constexpr`, `typeof`, `_BitInt`, `#embed`, `<stdckdint.h>` checked arithmetic, hygiene flags. |
| `c-memory-ownership` | Ownership conventions, cleanup patterns, allocator selection (goto-cleanup vs arena), and AddressSanitizer-first debugging of leaks, double-frees, and use-after-free. |

### C++

| Skill | Description |
|-------|-------------|
| `cpp-skills` | C++ navigation and the canonical standard-selection table for C++17/20/23, including fallbacks for C++20/23 features. |
| `modern-cpp` | Core idioms — RAII, Rule of Zero, smart-pointer ownership, vocabulary types (`string_view`/`span` lifetime traps), the constexpr family, deducing this, `std::print`. |
| `cpp-concurrency` | `jthread`/`stop_token`, mutexes and `scoped_lock`, atomics and memory ordering, latch/barrier/semaphore, coroutines and `std::generator`, TSan-first verification. |

### Python

| Skill | Description |
|-------|-------------|
| `python-skills` | Python 3.12-3.14 navigation — modern features, typing, concurrency, uv/ruff tooling, pytest. |
| `modern-python` | Version-gated 3.12-3.14 features — t-strings (PEP 750), deferred annotations (PEP 649/749), exception groups/`except*`, PEP 758, `compression.zstd`, PEP 695 generics, PEP 765 finally warning. |
| `python-typing` | Static typing — PEP 695 generics, protocols over ABCs, TypedDict/Literal/overload/ParamSpec, strict pyright/mypy configuration. |
| `python-concurrency` | Choosing and implementing the right 3.14 concurrency model — asyncio, threads, free-threading (3.14t), subinterpreters, or multiprocessing. |
| `python-tooling` | uv as the single project tool plus ruff as linter/formatter, with `pyproject.toml` as the one source of truth. |
| `python-testing` | Pytest for 3.12-3.14 — plain-assert tests, fixtures/conftest scoping, parametrization, async testing, mocking, coverage, Hypothesis. |

### Bash

| Skill | Description |
|-------|-------------|
| `bash-skills` | Bash and POSIX shell navigation — Bash vs POSIX sh, strict mode and traps, when a task has outgrown shell, Bash 5.2/5.3 features, shellcheck/shfmt/bats. |
| `bash-scripting` | Defensive scripting — strict-mode prologue, quoting, arrays, traps, safe resource handling, and resolving shellcheck warnings. |
| `bash-testing` | Testing Bash with bats-core and keeping scripts lint-clean with ShellCheck and shfmt; sourceable/testable design, PATH-stub mocking, CI wiring. |

### Embedded

| Skill | Description |
|-------|-------------|
| `embedded-skills` | Embedded/bare-metal navigation — routes freestanding vs hosted, register access, ISRs, no-heap, fixed-point, linker scripts, cross-compilation, and the embedded C++ subset symptoms to exactly one target. |
| `embedded-systems` | Language-agnostic bare-metal core: freestanding (`-ffreestanding`, `__STDC_HOSTED__`), MMIO/register access, `volatile` (not atomicity, not ordering), ISRs/vector tables/startup/crt0, no-heap allocation, fixed-point arithmetic, linker scripts, cross-compilation toolchains (arm-none-eabi, newlib/newlib-nano). |
| `embedded-cpp` | C++ subset for embedded: RAII without exceptions/RTTI (`-fno-exceptions -fno-rtti -ffreestanding`), freestanding stdlib subset (available/unavailable/costly table), static/placement-new construction, `constexpr`/`constinit` ROM-able data, hidden-allocation and dynamic-dispatch avoidance. |

### Tooling

| Skill | Description |
|-------|-------------|
| `tooling-skills` | Build, diagnostics, and interop navigation — routes a "won't build", "crashes", "too slow", or "can't link" symptom to the right guide. |
| `build-systems` | Modern CMake doctrine, CMakePresets workflow, FetchContent vs vcpkg vs Conan dependency strategy, CMake 4.x migration, C++20 modules, CMake/Meson/Make selection. |
| `diagnostics` | Route a runtime symptom (crash, wrong values, race, leak, slow) to the right sanitizer, debugger, or profiler with the exact flags. |
| `ffi-interop` | Bind C/C++ to Python (nanobind, pybind11, cffi, ctypes), design `extern "C"` ABI boundaries, release the GIL, build wheels with scikit-build-core. |

## Model & Effort

`maxTurns` is a runaway-loop backstop. Only `system-architector` runs `opus`/`xhigh` by default; the language developers and `sys-` review/test agents run `sonnet`/`high` with a documented per-invocation `opus`+`xhigh` override path.

| Agent | Model | Effort | maxTurns |
|-------|-------|--------|----------|
| `system-developer` | sonnet | medium | 40 |
| `c-developer` | sonnet | high | 50 |
| `cpp-developer` | sonnet | high | 50 |
| `python-developer` | sonnet | high | 50 |
| `bash-developer` | sonnet | high | 50 |
| `system-architector` | opus | xhigh | 60 |
| `sys-test-generator` | sonnet | high | 50 |
| `sys-performance-engineer` | sonnet | high (review-only) | 50 |
| `sys-security-auditor` | sonnet | high (review-only) | 50 |
| `sys-code-fixer` | haiku | medium | 30 |
| `sys-dependency-manager` | haiku | low | 20 |

## Installation & Registration

### From Marketplace

```bash
claude plugins install system-developer@system-developer
```

### Manual registration in `~/.claude/settings.json`

Register the marketplace as a directory source and enable the plugin:

```jsonc
{
  "extraKnownMarketplaces": {
    "system-developer": {
      "source": {
        "source": "directory",
        "path": "/Users/korich/Projects/igrsoft/system-developer"
      },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "system-developer@system-developer": true
  }
}
```

After editing `settings.json`, run `/plugins` (or restart the session) to load the plugin.

## Workflow Integration (company-workflow v4.0.0)

This plugin collaborates with the **company-workflow** plugin v4.0.0 for 11-stage workflow orchestration. company-workflow owns orchestration, worktree isolation, and `state.json` merge; system-developer agents stay invoked specialists and follow the handoff-protocol (plan-file resolution, Required Inputs, `handoff:` frontmatter schema, `state.json` atomic write). During the DV stage, `company-workflow:developer` routes to the appropriate system-developer specialist based on file/marker detection.

**Two human checkpoints**: company-workflow worktasks stop at the **PL gate** (post-PL0 plan approval) and the **FN gate** (pre-finalization commit/push/PR). Both carriers live independently on `PL0.metadata` (`plan_gate` / `fn_gate`, default `checkpoint`) and are bypassed by `--auto-plan` / `--auto-finalization` respectively (and both by `--emergency`). system-developer agents run as invoked specialists *between* the gates and do not own gate logic, though DV/DR/QA may re-run on a gate loopback.

**Multi-issue batches**: `/megatask <milestone#>` (or `/megatask --issues 12,15,18`) orders many worktasks by a dependency/blocker DAG, each issue in its own isolated worktree.

**Reasoning tier**: the security-review (SR) and ethics-review (ET) stages run on `opus` at effort `xhigh`; Fable 5 is available as the top reasoning tier on CC ≥ 2.1.170, but the shipped company-workflow stage agents pin `opus`. system-developer's own agents keep their existing models.

| Stage | system-developer Role | Contribution |
|-------|----------------------|--------------|
| **DV** | Primary | Language-specific implementation; emits `development-N.md` with a Build Evidence section. |
| **DR** | Support | `sys-code-fixer` applies technical-lead findings (minimal-diff gate); `system-architector` consulted for structural concerns. |
| **SR** | Context Provider | `sys-security-auditor` supplies memory-safety, injection, secrets, and supply-chain context. |
| **QA** | Support | `sys-test-generator`; the QA gate is tests pass **and** ASan+UBSan clean. |
| **RE** | Context Provider | `sys-dependency-manager` supplies lockfile/CVE state for release readiness. |

**Evidence norm**: systems and CLI work defaults to `requires_screenshots: false`. When a gate demands evidence, agents attach `cli-fallback` terminal transcripts (build logs, `ctest`/`pytest`/`bats` output, sanitizer reports) rather than screenshots.

## Quick Start

```bash
# Detect the build system, configure, build, and run the tests
/system-developer:build-test .

# Language-aware review, then auto-apply minimal-diff fixes
/system-developer:review-code src/ --fix

# Build with AddressSanitizer, run the tests under it, and triage
/system-developer:sanitize-check asan .

# Plan a C++23 migration without touching files
/system-developer:fix-modernize . --target cpp23 --dry-run

# Use an agent directly, outside the workflow
Use the system-developer agent to design a plugin/registry architecture for a C++ codec library
```

## Development

Skills bundle small executable helpers under `skills/<domain>/scripts/` and
`skills/_shared/scripts/` (e.g. `detect_language.py`, `sanitizer_flags.sh`,
`scaffold_pyproject.sh`). They keep `SKILL.md` prose lean: the model runs the
script instead of reading and re-deriving the boilerplate it would otherwise
inline. Each is self-documenting (`<script> --help`), stdout-by-default, and adds
no runtime dependency beyond what the skill already assumes.

```bash
scripts/validate.sh            # release gate: manifests, frontmatter, link integrity
scripts/test.sh                # shellcheck + bats + pytest over the bundled scripts
scripts/test.sh --strict       # CI mode: a missing tool fails instead of skipping
```

`scripts/test.sh` degrades gracefully when `bats`/`pytest`/`shellcheck` are
absent (it SKIPs and prints an install hint); CI runs it `--strict` on Linux and
macOS via [`.github/workflows/test.yml`](.github/workflows/test.yml) to exercise
both the GNU and BSD coreutils paths.

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
