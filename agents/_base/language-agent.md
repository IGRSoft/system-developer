# Language Agent Base Template

Shared behavior for all language-specific agents (C, C++, Python, Bash) and the Tier-2 specialists that inherit from them.

## Constraints

- All C/C++ code must compile warning-clean under `-Wall -Wextra -Werror` (GCC/Clang); Python must pass `ruff check` with zero findings; shell scripts must be `shellcheck`-clean
- C targets the C17 baseline (C23 features gated per `skills/_shared/version-feature-matrix.md`); C++ targets the project's selected standard — C++17/20/23 per the standard-selection table in `cpp/SKILL.md`
- No undefined behavior: no out-of-bounds access, use-after-free, signed-overflow assumptions, or data races; sanitizer findings are build breaks, not warnings
- Check every return value: no ignored error returns (a `(void)` cast requires a justifying comment); check `errno` after failing POSIX calls; never swallow Python exceptions with bare `except`; Bash uses `set -euo pipefail` plus explicit checks where `set -e` is blind
- Code and scripts must run on both Linux and macOS — do not assume glibc, GNU coreutils, or `/bin/bash` ≥ 4 (macOS ships Bash 3.2; verify against your toolchain)
- **Single-command Bash invocations**: scoped `Bash(cmd:*)` permissions cannot match compound commands. Use `cmake --build build`, `ctest --test-dir build`, `make -C <dir>`, `uv run pytest` — never `cd X && ...` chains or `;`/`|`-joined command lines

## Mandatory Requirements (Always Enforce)

All code must comply with these skills:

| Skill | Rule |
|-------|------|
| `modern-c` / `modern-cpp` | Warning-clean builds (`-Wall -Wextra -Werror`); version-gated features carry a standard marker and a fallback |
| `python-tooling` | `ruff check` and `ruff format --check` pass; type-check touched files with pyright or mypy |
| `bash-scripting` | `shellcheck` clean (no inline disables without a justifying comment); `shfmt`-formatted |
| `_shared/secure-coding` | All external input validated; no command/path/format-string injection surfaces |

Violations must be flagged and corrected before code is complete.

## Code Comment Policy

| Comment kind | Rule |
|--------------|------|
| Doxygen `/** */` on public C/C++ APIs (exported functions, public types, header declarations) | **Required.** Concise; `@param`/`@return`/`@retval`, ownership and lifetime notes where non-trivial. |
| PEP 257 docstrings on public Python modules, classes, and functions | **Required.** One-line summary first; document raised exceptions. |
| shdoc-style headers (`# @description`, `# @arg`, `# @exitcode`) on shell scripts and non-trivial functions | **Required.** Script header states purpose, usage, and exit codes. |
| Inline body comments (`//`, `#`) | **Minimize.** Allowed only when the *why* is non-obvious: hidden constraint, subtle invariant, workaround for a specific bug, behavior that would surprise a reader. |
| Comments that restate what the code does (`// increment counter`, `# loop over items`) | **Forbidden.** Prefer better names over narration. |
| Section banners (`/* ===== */`, `# --- section ---`) | Allowed but use sparingly — only when a file has ≥3 logical sections. |
| `// TODO:` / `# FIXME:` | Allowed when leaving deliberate follow-ups; include a ticket reference or owner. |

Apply this policy in DV stage output and when responding to DR findings. Reviewers (DR, SR) should flag policy violations alongside other issues. This policy aligns with `skill: igrsoft:code-comment-standard` — comment the non-obvious *why* and the contract only; route rationale, history, and before/after narrative to the PR / `.context/development-N.md` / ADR, not to source comments.

## Tool Priority

1. **Build/Test/Run**: Always use the native toolchain via scoped Bash — `cmake --build`, `ctest --test-dir`, `make -C`, `meson compile -C`, `uv run`, `bats`. One command per invocation (see Constraints).
2. **Documentation**: Use Context7 (`resolve-library-id` → `query-docs`) or Ref (`ref_search_documentation`) for library, framework, and standard-library docs.
3. **Flag reference**: `man <tool>` or `<tool> --help` for exact flag syntax. **Never guess flags** — verify against your toolchain before invoking.

## Delegation Routing

| Need | Route To |
|------|----------|
| Architecture patterns, ownership models, API/ABI design | `system-developer:system-architector` |
| Cross-language work, FFI, C extensions, mixed builds | `system-developer:system-developer` |
| Test generation, coverage strategy | `system-developer:sys-test-generator` |
| Dependency manifests, updates, CVE scans | `system-developer:sys-dependency-manager` |
| Batch fixes from review findings | `system-developer:sys-code-fixer` |
| Profiling, benchmarks, performance regressions | `system-developer:sys-performance-engineer` |
| Security review, sanitizers, hardening flags | `system-developer:sys-security-auditor` |
| Build systems (CMake, Meson, Make) | Skill: `build-systems` |
| Sanitizer/debugger/profiler reference | Skill: `diagnostics` |
| Library documentation | Context7 or Ref MCP tools |
| Model / effort choice, opus+xhigh override | `skills/_shared/model-selection.md` |

## Standard Response Format

### For Implementation Tasks
1. **Approach**: Brief explanation of chosen approach and trade-offs
2. **Code**: Production-ready implementation following mandatory requirements
3. **Portability Notes**: Linux/macOS considerations, toolchain and standard-version constraints
4. **Testing**: Key test scenarios to verify

### For Review Tasks
1. **Summary**: Assessment with severity ratings (P0-P3)
2. **Issues**: Prioritized list with `file:line` references
3. **Recommendations**: Actionable fixes with code examples

## Workflow Stage Participation

Language agents participate in the igrsoft 11-stage workflow system (v3.33.0+; canonical spec: `company-workflow:skills/worktask/references/handoff-protocol.md`).

**Two human checkpoints** gate the pipeline: the **PL gate** (post-PL0 plan approval) and the **FN gate** (pre-finalization commit/push/PR). On a gate loopback, DV (and DR/QA) may re-run with `retry_count++` and a `run_index` bump — see `skill: workflow-integration § Human Checkpoints`.

### Handoff Contract (BINDING)

All cross-plugin invocations follow `skills/_shared/workflow-integration/SKILL.md`: plan-file resolution (`task.metadata.plan_file` → newest `.context/planning-*.md` glob), Required Inputs, pre-flight Verification, output frontmatter schema (≤30 lines, ≤200 tokens), state.json atomic write, and the per-stage required `metadata.*` matrix. See that skill for the per-stage recipes (AR consultation, DV, DR support) and the ≤500-token compressed return summary.

**state.json patching is REQUIRED before returning.** Atomic-patch `.context/state.json` with `stages.<CODE>` and `handoffs[FROM→TO]` using read → merge → temp → fsync → rename (handoff-protocol `#atomic-write`). If the patch fails, log the error and proceed — the SubagentStop hook repairs from frontmatter. But **frontmatter emission is unconditional**: an artifact without `handoff:` YAML breaks the entire three-layer safety net (agent → orchestrator fallback → SubagentStop hook).

**Artifact filenames use the numbered `<stage>-N.md` contract** (`N = run_index`, allocated by PL0 and propagated via `task.metadata.run_index`; e.g., `development-0.md`, `developer-review-0.md`) per `skill: workflow-integration § Artifact Filename Contract`. The basenames are canonical; only the `-N` suffix changes per run. Readers fall back to newest-glob (`<basename>-*.md`). **Emit `handoff:` frontmatter unconditionally** — it is the Layer-1/Layer-2 merge input *regardless of filename*. The SubagentStop hook's bare-name `artifact_for_stage()` map is a backward-compat fallback only; do not rename artifacts to satisfy it.

### DV Stage (Development) — Systems notes

- Implement features in C/C++/Python/Bash under the Constraints above.
- Run only the tests covering changed files — `ctest --test-dir build -R <pattern>`, `uv run pytest -k <expr>`, or `bats -f <regex>`. Full-suite regression belongs to QA.
- Include security-surface summary in `.context/development-N.md` for DR and SR.
- On retry, append narrative to `.context/errors/{agent-basename}.md`.
- **Evidence gate (replaces the UI screenshot gate)**: systems/CLI work defaults `requires_screenshots: false` — PL0 should set it explicitly, and DV writes the skip-rationale manifest (`> Skipped: metadata.requires_screenshots = false. Rationale: <one line>`). When gate metadata still demands evidence (`metadata.requires_screenshots: true`), capture terminal transcripts of the decisive runs (build, tests, sanitizers) as `source: cli-fallback` rows (manifest `Adapter` column: `cli_fallback`) in `.context/images/<worktask_id>/screenshots.md` **before returning** — render via the cli-fallback chain (`silicon` → ImageMagick → `.txt` placeholder; `company-workflow:skills/dv-screenshot-capture/references/cli-fallback.md`). If the manifest is missing while the gate is armed, igrsoft's `dv-screenshot-gate.sh` blocks `SubagentStop` with `hookSpecificOutput.additionalContext` and re-dispatches.
- **Consuming rework remediation**: on a re-dispatch after a failed DR/QA gate (`metadata.retry_count > 0`), read the prepended `REMEDIATION (from <DR|QA> gate…)` block plus `metadata.gate_from_stage` + `metadata.gate_blockers[]`, and fix those exact findings first (do not re-scope or re-infer). Keep the diff minimal; record per-blocker resolution in `.context/errors/{agent-basename}.md`. The orchestrator owns the injection — language agents only consume it. See `skill: workflow-integration § Gate-Feedback Contract`.

### DR Stage (Developer Review) - Provide Context

Technical-lead (`igrsoft:technical-lead`) reviews DV output against systems-specific criteria (memory safety, undefined behavior, error-handling discipline, unsafe constructs, build hygiene, Linux/macOS portability). Language agents support DR by:

- Flagging known trade-offs in `development-N.md` under "DR Focus" section
- Responding to DR findings by routing to `system-developer:sys-code-fixer` (minimal-diff application) or `system-developer:system-architector` (pattern consult)
- Re-running build/test via the native toolchain (single scoped command) after each fix group
- **Gate-feedback**: DR writes a `## blockers` list of concrete, individually-actionable strings; the orchestrator forwards it verbatim as `metadata.gate_blockers[]` (with `gate_from_stage: "DR"`) on the DV re-dispatch. Write blockers so a developer can act on each one without re-opening the review. See `skill: workflow-integration § Gate-Feedback Contract`.

See `skills/_shared/workflow-integration/templates/dr-review.md` for review criteria and output templates.

### SR Stage (Security Review) - Provide Context

Document systems-specific security concerns:

| Area | Documentation Required |
|------|------------------------|
| **Memory Safety** | Ownership/lifetime model for new allocations; bounds-checked APIs used; raw-pointer arithmetic or `memcpy` with justification |
| **Sanitizer Status** | ASan+UBSan results (TSan where threading changed); any suppressions added, with rationale |
| **Input Validation** | All external inputs (argv, env, files, network, subprocess output) parsed and bounds-checked; injection surfaces addressed |
| **Secrets Handling** | No secrets in code, logs, or command lines; credential sources (env, keychain, agent) documented |
| **Privilege Use** | Any elevated-privilege requirement (sudo, setuid, capabilities, raw sockets) with justification and drop strategy |

### RE Stage (Release Engineering) - Provide Context

| Item | Provide |
|------|---------|
| **Version** | Semver tag; SONAME/ABI version for shared libraries; `pyproject.toml` version for Python |
| **Distribution** | Package registry (PyPI / vcpkg / Conan / Homebrew), source tarball, or container image |
| **Platform Notes** | Linux/macOS release considerations, minimum toolchain versions |
| **What's New** | Language/toolchain-specific release notes |

### IR Stage (Emergency) - Hotfix Constraints

On the emergency (incident) pipeline (`/worktask --emergency`):
- **Minimal changes only** - Touch only necessary code
- **No new features** - Fix the issue, nothing else
- **Use feature flags** - Enable rollback where possible
- **Expedited review** - Available for P0/P1 (24-48h)
