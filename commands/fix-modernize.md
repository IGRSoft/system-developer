---
description: Modernize C, C++, Python, or Bash one standard jump at a time, gating each migration class on a green build and tests
argument-hint: [path (default .)] --target c23|cpp20|cpp23|py314|bash [--dry-run]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
estimated-cost:
  min-tokens: 4000
  max-tokens: 30000
  model-distribution:
    haiku: 30%
    sonnet: 55%
    opus: 15%
---

# Code Modernize

Move a C, C++, Python, or Bash codebase to a newer language standard incrementally. The work is an ordered ledger of discrete *migration classes* (e.g. "concepts over SFINAE", "ruff UP autofixes", "strict-mode prologue"), mechanical first, then semantic. Each class is applied, verified by a full build + test run, and committed on its own, so a red build points at exactly one transform. Mechanical rewrites go to `system-developer:sys-code-fixer`; migrations that need judgment go to the language developer.

## Rules

- One standard jump at a time. `--target cpp23` on a C++17 project runs *17 -> 20*, then *20 -> 23*, each fully verified and committed before the next, because each step's idioms build on the last and the toolchain gates differ.
- One migration class per commit, with a subject naming the class. Don't batch unrelated classes.
- Run the build + test gate after every class. A class that isn't green isn't committed; a red build halts the run.
- `--dry-run` writes the ledger and stops: no source edits, no commits.
- Mechanical rewrites (clang-tidy `modernize-*` fixes, `ruff check --select UP --fix`, `shfmt`) go to `sys-code-fixer`. Anything needing judgment (designing concepts, `std::expected` API changes, typed `constexpr`, free-threading readiness, `set -e` audits) goes to the language developer, never the code-fixer.
- Gate features on the toolchain, not the calendar. For C/C++ prefer feature-test macros (`__cpp_lib_*`, `__STDC_VERSION__`, `__has_include`) over compiler-version checks; for Python gate on `sys.version_info` or a capability probe; for Bash on `BASH_VERSINFO`. If the toolchain can't reach the target, report the gap and stop rather than write code that won't compile.
- Use each tool's own path/recursion flags instead of `cd` or `&&` chains; scoped Bash permissions don't match compound commands.
- A missing tool never hard-fails: print its install hint, skip that class (or language), continue, and report the skip.

## Usage

```bash
/system-developer:fix-modernize . --target cpp23 --dry-run   # preview the ledger only
/system-developer:fix-modernize src/ --target c23            # C17 -> C23
/system-developer:fix-modernize src/ --target cpp20          # C++17 -> C++20
/system-developer:fix-modernize . --target py314             # Python 3.14 idioms
/system-developer:fix-modernize scripts/ --target bash       # strict-mode baseline
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | Directory or file to modernize. Inventory and detection are rooted here. |
| `--target c23\|cpp20\|cpp23\|py314\|bash` | required | Destination standard or hardening profile. For C++, the intermediate jump is inserted automatically when the source is more than one level below. |
| `--dry-run` | off | Write `.context/.modernize/plan.md` and stop. |

`--target` has no default because the right destination depends on the deployment toolchain. `cpp26` is recognized but has no bulk profile; the command prints the C++26 note and stops (see Error Handling).

## Inventory

Detect the current standard so the jump count is right. In mixed repos, detect per file or subtree.

| Language | Where the current standard lives | Read |
|----------|----------------------------------|------|
| C | `CMAKE_C_STANDARD` / `target_compile_features(... c_std_NN)`; `c_std=` in `meson.build`; `-std=c17`/`c23`/`c2x` in a Makefile or flags | highest pinned `NN` (C17 is the safe baseline) |
| C++ | `CMAKE_CXX_STANDARD` / `target_compile_features(... cxx_std_NN)`; `cpp_std=` in `meson.build`; `-std=c++NN` in a Makefile or flags | highest pinned `NN` |
| Python | `requires-python` in `pyproject.toml`; `python_requires` in `setup.py`; `.python-version` | the floor; modernize only if the floor allows the target |
| Bash | shebangs (`#!/usr/bin/env bash` vs `#!/bin/sh`), `set -euo pipefail`, `[[ ]]` vs `[ ]`, arrays | distance from the strict-mode baseline |

If current already meets or exceeds `--target`, report "already at or above target" and stop.

## The Migration Ledger

`.context/.modernize/plan.md` is the source of truth across resumes; read it rather than relying on context memory.

```markdown
# Modernization Ledger
Target: {c23|cpp20|cpp23|py314|bash} | Current: {detected} | Path: {path}
Toolchain gate: {compiler/CPython + min version} — {PASS | GAP: ...}

## Jump 1: {from} -> {to}
| # | Migration class | Kind | Owner | Status |
|---|-----------------|------|-------|--------|
| 1 | clang-tidy modernize-* autofixes | mechanical | sys-code-fixer | pending |
| 2 | SFINAE -> concepts | semantic | cpp-developer | pending |
| ... | ... | ... | ... | ... |

## Jump 2: {from} -> {to}   <!-- only when target is >1 level above current -->
```

Row status: `pending -> applied -> verified -> committed`, or `reverted` on a red build.

## Per-Target Playbooks

Mechanical classes lead (cheap, deterministic); semantic classes follow.

### `--target c23` (from C17)

Toolchain gate: `-std=c23` from GCC 14 / Clang 18 (older toolchains spell it `-std=c2x`). GCC 15 defaults C to `-std=gnu23`, so always pin `-std`. Treat MSVC as C17-only unless a feature is verified. Gate features on `__STDC_VERSION__ >= 202311L`, `__has_include`, or a probe. Single jump. If the toolchain can't reach C23, keep `-std=c17` and report the gap.

| Order | Class | Kind | Notes |
|-------|-------|------|-------|
| 1 | `clang-tidy -checks='modernize-*,readability-*' -fix` (C pass) | mechanical | C-applicable modernize/readability fixes. |
| 2 | `NULL` -> `nullptr` | mechanical | C23 `nullptr` / `nullptr_t`. |
| 3 | K&R / empty `()` prototypes -> `(void)` semantics | mechanical-ish | In C23 empty `()` means no args; audit declarations that relied on "unspecified args". |
| 4 | macro/enum constants -> `constexpr` objects | semantic | Replace `#define`d numeric constants where a typed `constexpr` reads better. |
| 5 | hand-rolled overflow checks -> `<stdckdint.h>` (`ckd_add`/`ckd_sub`/`ckd_mul`) | semantic | Checked integer arithmetic. |
| 6 | embedded binary blobs -> `#embed` | semantic | GCC 15+ / Clang 19+; keep the xxd/objcopy fallback where the toolchain lags. |
| 7 | `typeof` / `typeof_unqual` | mechanical-ish | Replace GNU `__typeof__` where portability now allows. |
| 8 | wide fixed-width arithmetic -> `_BitInt(N)` | semantic | Only where a fixed bit width is a real requirement. |
| 9 | `__attribute__` -> `[[nodiscard]]` / `[[maybe_unused]]` / `[[deprecated]]` | mechanical-ish | On APIs whose return must be checked or that are being retired. |

Pair the jump with `-fhardened` (GCC 14+) and `-ftrivial-auto-var-init=zero` where appropriate.

### `--target cpp20` (from C++17)

Toolchain gate: GCC 10+ / Clang with usable ranges and concepts. Gate on `__cpp_concepts`, `__cpp_lib_ranges`, `__cpp_lib_span`, etc.

| Order | Class | Kind | Notes |
|-------|-------|------|-------|
| 1 | `clang-tidy -checks='modernize-*' -fix` | mechanical | `use-nullptr`, `use-override`, `use-using`, `loop-convert`, ... |
| 2 | SFINAE / `enable_if` -> concepts | semantic | `template<Concept T>` / `requires`. Constraints must be designed, not transliterated. |
| 3 | hand-written loops -> `<ranges>` views/algorithms | semantic | Prefer lazy views over eager copies. Fallback: range-v3. |
| 4 | pointer + length params -> `std::span` | semantic | Span is non-owning; watch lifetimes. |
| 5 | positional aggregate init -> designated initializers | mechanical-ish | Verify the type stays an aggregate. |
| 6 | hand-rolled comparisons -> `<=>` | semantic | `= default` where defaulted ordering is correct. |

### `--target cpp23` (from C++20)

Toolchain gate: C++23 support is partial (GCC 13+, Clang 17+ partial, deducing this Clang 18+). Check every feature with `__cpp_lib_expected`, `__cpp_lib_print`, `__cpp_explicit_this_parameter`; if unavailable, keep the fallback and skip the class.

| Order | Class | Kind | Notes |
|-------|-------|------|-------|
| 1 | `clang-tidy -checks='modernize-*' -fix` (C++23 pass) | mechanical | Newly available `modernize-*` checks. |
| 2 | error codes / out-params -> `std::expected<T, E>` | semantic | API-shape change. Fallback: `tl::expected`. |
| 3 | `printf` / `iostream` -> `std::print` / `std::println` | semantic | Fallback: `fmt::print`. |
| 4 | CRTP / duplicated const overloads -> deducing this | semantic | `template<class Self> auto f(this Self&& self)`. |

### `--target py314`

Toolchain gate: `requires-python` must allow 3.14; otherwise raising the floor is a separate version-bump decision to make first.

| Order | Class | Kind | Notes |
|-------|-------|------|-------|
| 1 | `ruff check --select UP --target-version py314 --fix` | mechanical | pyupgrade rules (typing imports, `super()` args, f-strings, ...). |
| 2 | generics -> PEP 695 type parameters | semantic | `def f[T](x: T) -> T`, `class Box[T]`, `type Alias[T] = ...`; drop `TypeVar`/`Generic` where clean. |
| 3 | removed-deprecation sweep | semantic | Check the exact list against the 3.14 "What's New". |
| 4 | drop `from __future__ import annotations` | mechanical-ish | PEP 649 deferred annotations are the default on 3.14; the import forces the older string semantics. |
| 5 | free-threading readiness (C extensions) | semantic / advisory | Audit `Py_mod_gil` and thread safety; emit notes, don't rewrite native code. |

### `--target bash`

Toolchain gate: `shellcheck` and `shfmt`. Every script must end shellcheck-clean. macOS `/bin/bash` is 3.2, so prefer `#!/usr/bin/env bash` plus a version guard over 4.x/5.x-only features in portable scripts.

| Order | Class | Kind | Notes |
|-------|-------|------|-------|
| 1 | strict-mode prologue `set -Eeuo pipefail` | semantic | Audit each script for places `set -e` silently misbehaves. |
| 2 | ad-hoc cleanup -> `trap cleanup EXIT` | semantic | Add `ERR`/`INT` where apt; idempotent temp-file/lock removal. |
| 3 | `[ ]` -> `[[ ]]`; quote expansions | mechanical | Clears SC2086/SC2046. |
| 4 | undeclared vars -> `local`; word-split lists -> arrays | semantic | `"${arr[@]}"`. |
| 5 | `shfmt -w` | mechanical | Last, after logic changes. |

## Workflow

### 1. Inventory and ledger

1. Stop with the matching Error Handling message if `path` doesn't exist, `--target` is `cpp26`, or `--target` is missing or invalid.
2. Detect the current standard (Inventory) and resolve the toolchain gate. On a GAP, report it and stop. If already at or above target, stop.
3. For C++ more than one level below target, split the ledger into ordered Jumps.
4. Write `.context/.modernize/plan.md` from the matching playbook(s), all rows `pending`. Confirm each class's tool (Tool Availability); mark classes with a missing tool as skipped.
5. With `--dry-run`, report the ledger path and planned classes and stop.

### 2. Per class, top-down

For each `pending` row: mark it `applied`, delegate, verify, commit. When every row in a Jump is `committed`, open the next Jump.

**Delegate.** Agent tool with the owner from the row:

| Kind | `subagent_type` | Language-specific instruction |
|------|-----------------|-------------------------------|
| mechanical | `system-developer:sys-code-fixer` | Run the exact transform, e.g. `clang-tidy -p {path}/build -checks='modernize-*' -fix {files}`, `ruff check --select UP --target-version py314 --fix {path}`, `shfmt -w {files}`. Minimal, deterministic edits; don't run the test suite. |
| semantic (C) | `system-developer:c-developer` | Gate on `__STDC_VERSION__ >= 202311L` / `__has_include` / a probe; keep fallbacks (e.g. xxd/objcopy for `#embed`). |
| semantic (C++) | `system-developer:cpp-developer` | Gate on the relevant `__cpp_*` / `__cpp_lib_*` macro; keep fallbacks. |
| semantic (Python) | `system-developer:python-developer` | Check volatile 3.14 details against current docs; return readiness notes for advisory classes. |
| semantic (Bash) | `system-developer:bash-developer` | Assume the macOS bash 3.2 floor unless the shebang pins newer; guard 4.x/5.x features; end shellcheck-clean. |

Prompt:

```
Apply only the migration class **{class}** to `{path}` ({from} -> {to}).
{row notes from the playbook}
{language-specific instruction}
If a feature is unavailable on the project toolchain, keep the fallback and say so.
Don't touch any other class. Return every file changed, the checks/rules applied,
and the feature-gate or portability rationale.
```

**Verify.** Run `/system-developer:build-test {path}` (or its detected configure/build/test commands), teeing output to `.context/logs/`.

- Green: mark `verified`.
- Red, mechanical class: revert that diff and halt; mechanical fixes shouldn't break a green build, so it's a real signal.
- Red, semantic class: give the failing excerpt back to the same agent for one corrective pass. Still red: revert, mark `reverted`, and halt. Later classes aren't attempted on a broken build.

**Commit.** Stage only the files the class touched and commit with a conventional subject naming the class, e.g. `refactor: replace SFINAE with concepts (C++17->20)`, `refactor: ruff pyupgrade pass for Python 3.14`. Follow the repo's commit format; no `--no-verify`, no AI-attribution trailers; branch first if on a protected branch. Mark the row `committed`.

Modernization rationale and before/after notes go in the commit or PR, not in source comments.

### 3. Report

Emit the Output Format with per-Jump status and the ledger path.

## Tool Availability

| Missing tool | Install hint |
|--------------|--------------|
| `clang-tidy` / `clang-format` | `brew install llvm` |
| `cmake` / `ctest` (build gate, `compile_commands.json` for clang-tidy) | `brew install cmake ninja` |
| `ruff` | `uv tool install ruff` |
| `uv` (Python build gate) | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| `shellcheck` | `brew install shellcheck` |
| `shfmt` | `brew install shfmt` |

Flag spellings vary across tool releases; check `--help` when a flag is rejected. Report HALTED with aggregated hints only when no class can run.

## Output Format

```markdown
## Code Modernization Report

**Target:** {c23 | cpp20 | cpp23 | py314 | bash}
**Current standard:** {detected}
**Path:** {path}
**Mode:** dry-run | apply
**Ledger:** .context/.modernize/plan.md
**Toolchain gate:** {compiler/CPython + min version} — {PASS | GAP}

<!-- dry-run: stop after the ledger -->
### Planned Migration Classes ({count})
{rendered ledger table(s), all rows pending}

<!-- apply mode -->
### Jump 1: {from} -> {to}
| # | Class | Kind | Owner | Status | Commit |
|---|-------|------|-------|--------|--------|
| 1 | clang-tidy modernize-* | mechanical | sys-code-fixer | committed | {sha/subject} |
| 2 | SFINAE -> concepts | semantic | cpp-developer | committed | {sha/subject} |
| 3 | pointer+size -> std::span | semantic | cpp-developer | reverted | (build red) |

<!-- Jump 2 only when target > 1 level above current -->
### Jump 2: {from} -> {to}
| ... |

**Result:** COMPLETE / PARTIAL / HALTED ({reason})
- Classes committed: {n} | verified-not-committed: {n} | reverted: {n} | skipped (tool missing): {n}

<!-- on a halt -->
### Halt
- **Class:** {class} ({jump})
- **Build/test:** RED — {one-line first error; full log in .context/logs/...}
- **Action:** row marked reverted; later classes not attempted.

<!-- on skipped classes/tools -->
### Skipped
- {class}: {missing tool} — install hint printed above.
```

## Error Handling

### Path not found
```
Error: Path not found: {path}
Suggestion: Pass a directory or file that exists, e.g. /system-developer:fix-modernize . --target cpp20 --dry-run
```

### Missing or invalid --target
```
Error: --target is required and must be one of: c23, cpp20, cpp23, py314, bash.
Suggestion: /system-developer:fix-modernize . --target cpp23 --dry-run
```

### C++26 requested
```
Note: --target cpp26 has no bulk modernization profile yet. Adopt C++26
features one by one behind __cpp_* feature-test macros via
system-developer:cpp-developer. Re-run with --target cpp23 for a supported jump.
```

### Already at or above target
```
Note: {path} is already at or above {target} (detected: {current}).
Nothing to modernize. Suggestion: target a higher standard or a different path.
```

### Toolchain gate failure
```
Error: Toolchain cannot guarantee {target}.
{compiler/CPython} {detected version} < required {min version}.
Suggestion: upgrade the toolchain, or modernize to the highest supported standard.
```

## See Also

- `/system-developer:fix-quick`: the shallow single-language mechanical pass; this command sequences it with semantic migrations across standard jumps.
- `/system-developer:review-code`: review the modernized diff for behavioral drift once the ledger is complete.
