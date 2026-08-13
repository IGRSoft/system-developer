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

Apply this policy in DV stage output and when responding to DR findings. Reviewers (DR, SR) should flag policy violations alongside other issues. This policy aligns with `skill: corpflow:code-comment-standard` — comment the non-obvious *why* and the contract only; route rationale, history, and before/after narrative to the PR / `.context/development-N.md` / ADR, not to source comments.

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

