# System Developer Plugin

Claude Code plugin for systems and scripting development in **C**, **C++ (17/20/23)**, **Python 3.14**, and **Bash/POSIX shell**, with specialized agents, commands, and skills. Collaborates with the igrsoft (company-workflow) plugin v3.17.0 for full 11-stage workflow orchestration (PL→AR→TL→DV→**DR**→SR→QA→DC→RE→FN→ST) including the handoff-protocol (planning-N.md, state.json ledger, frontmatter schema). Systems and CLI work defaults to `requires_screenshots: false`; when an evidence gate demands proof, agents attach `cli-fallback` terminal transcripts (build logs, test output, sanitizer reports) instead of screenshots.

**Version**: 1.1.0 | **igrsoft Compatibility**: v3.17.0 | **claude-code min version**: "2.1.169"

## What's in 1.1.0

- **11 agents** — a `system-developer` router, four language developers (`c-developer`, `cpp-developer`, `python-developer`, `bash-developer`), `system-architector`, and five Tier-2 specialists (`sys-test-generator`, `sys-performance-engineer`, `sys-security-auditor`, `sys-code-fixer`, `sys-dependency-manager`). All inherit `agents/_base/language-agent.md`.
- **8 commands** — language-aware review, build/test, test generation, sanitizer runs, lint/format, profiling, standard modernization, and dependency auditing, each with restrictive `allowed-tools` and an `estimated-cost` band.
- **Complete skills tree** — 24 `SKILL.md` skills across `_shared`, `c`, `cpp`, `python`, `bash`, `embedded`, and `tooling`, with deep reference files. Version-specificity is the product: every language feature carries a standard/version marker and a pre-version fallback. The C++ standard-selection table and `skills/_shared/version-feature-matrix.md` are canonical; everything else links to them.
- **Plugin-scoped advisory hooks** — `audit-tooluse`, `audit-subagent`, `precompact-checkpoint`, wired in `plugin.json` with igrsoft-compatible dedupe keys. Advisory only: never merges `state.json` (orchestrator-owned). See [`hooks/README.md`](hooks/README.md).
- **CC capabilities adopted** — tiered `maxTurns` runaway-loop backstops, `disallowed-tools: Write, Edit` on the two review-only auditors, fully-qualified `Task(system-developer:<agent>)` delegations, and scoped `Bash(cmd:*)` allowlists per toolchain.

## Agents (11)

| Agent | Model / Effort | Purpose |
|-------|----------------|---------|
| `system-developer` | sonnet / medium | Index + router. Routes by file extension and keyword to language developers and specialists; handles cross-language work (FFI, C extensions, mixed CMake+pyproject repos) directly. |
| `c-developer` | sonnet / high | Efficient, memory-safe C. C17 baseline plus C23, POSIX/errno discipline, pthreads, C11 atomics, warning-clean GCC/Clang builds. |
| `cpp-developer` | sonnet / high | Idiomatic, memory-safe C++17/20/23. RAII, smart pointers, ranges, concepts, coroutines, `std::expected`, Core Guidelines, standard-selection trade-offs. |
| `python-developer` | sonnet / high | Modern, type-safe Python 3.14. uv-managed environments, ruff-clean code, deferred annotations, free-threading, t-strings, subinterpreters, concurrency-model selection. |
| `bash-developer` | sonnet / high | Defensive, portable Bash and POSIX shell. Strict mode, GNU/BSD divergence, shellcheck/shfmt/bats gating, injection-safe scripting. |
| `system-architector` | opus / xhigh | Architecture pattern selection and migration planning — layered libraries, hexagonal, plugin/registry, pipeline, concurrency and ownership models, API/ABI design, semver. |
| `sys-test-generator` | sonnet / high | Test generation across GoogleTest/Catch2, Unity/CMocka, pytest/Hypothesis, bats-core. Uses the framework the repo already has; never introduces a second one. |
| `sys-performance-engineer` | sonnet / high (review-only) | Code-first performance review backed by perf, valgrind, py-spy, hyperfine, and native tracers. `disallowed-tools: Write, Edit`; fixes route to `sys-code-fixer`. |
| `sys-security-auditor` | sonnet / high (review-only) | Security audit — memory safety, injection, unsafe deserialization, secrets, supply-chain CVEs, hardening-flag verification, CWE mapping. `disallowed-tools: Write, Edit`. |
| `sys-code-fixer` | haiku / medium | Minimal-diff remediation for findings from review, `sys-security-auditor`, and `sys-performance-engineer`. Per-language quick-fix playbooks. |
| `sys-dependency-manager` | haiku / low | Manifests and lockfiles across vcpkg, Conan 2, CMake FetchContent, uv, and pip; CVE/license audit; safe one-at-a-time upgrades with a build+test gate. |

> `sys-performance-engineer` and `sys-security-auditor` are review-only by default; callers may override them to `opus` + `xhigh` for the hardest analyses (Opus 4.8 honors `xhigh`; Sonnet falls back to `high`, so the model must be raised too).

## Commands (8)

| Command | Description |
|---------|-------------|
| `/system-developer:code-review` | Language-aware review — parallel per-language reviewers plus a security pass, synthesized into a P0-P3 report. Supports `--quick` and `--fix`. |
| `/system-developer:build-test` | Detect the build system, configure, build, and run the test suite for C, C++, Python, or Bash projects. |
| `/system-developer:generate-tests` | Generate, register, and verify a runnable test suite using the project's existing framework. Supports `--coverage-gaps`. |
| `/system-developer:sanitize-check` | Build with sanitizers (ASan/UBSan/TSan/LSan/MSan), run tests under them, and triage the reports. Supports `--fix`. |
| `/system-developer:lint-fix` | Run linters and formatters (clang-tidy/clang-format, ruff, mypy, shellcheck, shfmt) — check-only (`--check`) or auto-fix (`--fix`). |
| `/system-developer:profile-performance` | Profile CPU, memory, or I/O hot paths, or benchmark before/after with hyperfine, then route findings to `sys-performance-engineer`. |
| `/system-developer:code-modernize` | Modernize C++ (17→20→23), Python (→3.14), or Bash one standard jump at a time, gating each migration class on a green build and test run. Supports `--dry-run`. |
| `/system-developer:deps-audit` | Audit, upgrade, or add C/C++/Python dependencies — outdated report, CVE lookup, license inventory, and safe one-at-a-time upgrades with a build+test gate. |

All commands degrade gracefully when a tool is missing: they print an install hint (for example `brew install llvm shellcheck shfmt hyperfine`, `uv tool install ruff`), skip that language, and never hard-fail.

## Skills (24)

### Shared

| Skill | Description |
|-------|-------------|
| `secure-coding` | Non-negotiable security rules and bug-class defenses across all four languages — injection-safe process execution, sanitizer mapping, integer safety, path-traversal/TOCTOU resistance, secrets hygiene. |
| `workflow-integration` | Guide for integrating with the igrsoft 11-stage workflow system (v3.17.0), including the DV development contract and the `requires_screenshots: false` / cli-fallback norm. |

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

## Workflow Integration (igrsoft v3.17.0)

This plugin collaborates with the **igrsoft** (company-workflow) plugin v3.17.0 for 11-stage workflow orchestration. igrsoft owns orchestration, worktree isolation, and `state.json` merge; system-developer agents stay invoked specialists and follow the handoff-protocol (plan-file resolution, Required Inputs, `handoff:` frontmatter schema, `state.json` atomic write). During the DV stage, `igrsoft:developer` routes to the appropriate system-developer specialist based on file/marker detection.

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
/system-developer:code-review src/ --fix

# Build with AddressSanitizer, run the tests under it, and triage
/system-developer:sanitize-check asan .

# Plan a C++23 migration without touching files
/system-developer:code-modernize . --target cpp23 --dry-run

# Use an agent directly, outside the workflow
Use the system-developer agent to design a plugin/registry architecture for a C++ codec library
```

## License

MIT License — see [LICENSE](LICENSE) for details.
