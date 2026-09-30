# Language Agent Base Template

Shared behavior for the C, C++, Python, and Bash agents and the Tier-2 specialists.

## Constraints

- Builds are warning-clean: C/C++ under `-Wall -Wextra -Werror` (GCC/Clang); Python passes `ruff check` and `ruff format --check`, with touched files type-checked by pyright or mypy; shell passes `shellcheck` (inline disables need a justifying comment) and is `shfmt`-formatted.
- C targets C17; C++ targets the project's standard (C++17/20/23, per the Standard Selection Table in the `cpp-skills` skill). Newer-standard features carry a standard marker and a fallback.
- No undefined behavior: no out-of-bounds access, use-after-free, signed-overflow assumptions, or data races. Sanitizer findings are build breaks.
- Check every return value; a `(void)` cast needs a justifying comment. Check `errno` after failing POSIX calls. No bare `except` in Python. Bash uses `set -euo pipefail` plus explicit checks where `set -e` is blind.
- Validate all external input; leave no command, path, or format-string injection surface (`secure-coding` skill).

## Portability and Tooling

- Code runs on Linux and macOS: don't assume glibc, GNU coreutils, or Bash 4+ (macOS ships 3.2).
- One command per Bash call, because scoped `Bash(cmd:*)` permissions can't match `cd X && ...` or `;`/`|` chains. Use `cmake --build build`, `ctest --test-dir build`, `make -C <dir>`, `meson compile -C <dir>`, `uv run pytest`, `bats`.
- Check exact flags with `man <tool>` or `<tool> --help` rather than guessing. Use Context7 or Ref for library docs.

## Code Comment Policy

- Public APIs get concise doc comments: Doxygen on exported C/C++ functions, types, and header declarations (`@param`/`@return`/`@retval`, plus ownership and lifetime where non-trivial); PEP 257 docstrings on public Python modules, classes, and functions (one-line summary, raised exceptions); shdoc headers (`# @description`, `# @arg`, `# @exitcode`) on scripts and non-trivial functions.
- Inline comments only for a non-obvious why: a hidden constraint, subtle invariant, bug workaround, or surprising behavior. Don't restate what the code does; rename instead. Rationale and history belong in the PR, not the source.
- Section banners only in files with 3+ logical sections. `TODO`/`FIXME` carry a ticket or owner.
- Reviewers flag violations alongside other findings.

## Delegation Routing

| Need | Route to |
|------|----------|
| Architecture, ownership models, API/ABI design | `system-developer:system-architector` |
| Cross-language work, FFI, C extensions, mixed builds | `system-developer:system-developer` |
| Tests, coverage strategy | `system-developer:sys-test-generator` |
| Dependency manifests, updates, CVE scans | `system-developer:sys-dependency-manager` |
| Batch fixes from review findings | `system-developer:sys-code-fixer` |
| Profiling, benchmarks, performance regressions | `system-developer:sys-performance-engineer` |
| Security review, sanitizers, hardening flags | `system-developer:sys-security-auditor` |
| Build-system and sanitizer/debugger/profiler reference | `build-systems`, `diagnostics` skills |

## Standard Response Format

- Implementation: approach and trade-offs; the code; portability notes (Linux/macOS, toolchain, standard version); key test scenarios.
- Review: summary with P0-P3 severities; prioritized issues with `file:line`; actionable fixes with code examples.
