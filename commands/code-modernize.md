---
description: Modernize C (17->23), C++ (17->20->23), Python (->3.14), or Bash to a newer standard one jump at a time, gating each migration class on a green build and test run
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
<!-- Updated: June 2026 -->

Move a C, C++, Python, or Bash codebase to a newer language standard incrementally and safely. Modernization is sequenced as a ledger of discrete *migration classes* (e.g. "concepts over SFINAE", "ruff UP autofixes", "strict-mode prologue"), and every class is verified by a full build + test run before its commit and before the next class begins. Mechanical rewrites are delegated to `system-developer:sys-code-fixer`; semantic migrations that need judgment go to `system-developer:cpp-developer` or `system-developer:python-developer`.

[Extended thinking: A standard jump is dozens of independent transforms with sharply different risk. Doing them all at once produces an un-reviewable diff and a build that is either green or broken with no way to bisect which transform broke it. This command instead builds an ordered ledger at `.context/.modernize/plan.md`, then walks it class by class — mechanical (clang-tidy `modernize-*`, `ruff --select UP`) first, then semantic — running `/system-developer:build-test` after each class and committing one class per commit. Crucially, it never skips a standard: C++17 modernizes to 20, *then* 20 to 23 — never 17 straight to 23, because each step's idioms (concepts, then `std::expected`) build on the last and the toolchain gates differ. `--dry-run` produces the ledger and stops, so you can review the plan before any edit. Mechanical-vs-semantic routing keeps cheap deterministic rewrites on haiku via the code-fixer and reserves the language developer for the rewrites that change shape, not just spelling.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **One standard jump at a time.** `--target cpp23` on a C++17 project means **17 -> 20, then 20 -> 23** — two ordered passes, each fully verified and committed before the next. Never skip a standard (never 17 -> 23 directly). Detect the current standard first (see Inventory) and refuse to jump more than one level without first completing the intermediate level.
2. **One migration class per commit.** Each ledger row is applied, verified, and committed on its own. Never batch unrelated classes into one diff. The commit subject names the class (e.g. `refactor: adopt std::span over pointer+size`).
3. **Verify after every class.** After applying a class, run `/system-developer:build-test` (build + tests). If it is not green, the class is NOT committed — revert or fix before moving on. A red build halts the run; report it and stop.
4. **`--dry-run` produces the ledger only.** In `--dry-run`, write `.context/.modernize/plan.md` and stop. Make ZERO source edits and ZERO commits. This is the review-the-plan mode.
5. **Mechanical vs semantic routing.** Pure mechanical rewrites (clang-tidy `modernize-*` fixes, `ruff check --select UP --fix`, `shfmt`) delegate to `system-developer:sys-code-fixer`. Rewrites needing judgment (SFINAE -> concepts where the constraint must be designed, error-code -> `std::expected` API changes, `#define` -> typed `constexpr`, free-threading readiness) delegate to `system-developer:c-developer` / `system-developer:cpp-developer` / `system-developer:python-developer`. Never hand a semantic migration to the code-fixer.
6. **Gate features on the toolchain, not the calendar.** Before adopting a standard's feature, confirm the project's compiler/CPython supports it (see `skill: version-feature-matrix`). Prefer feature-test macros (`__cpp_lib_*`, `__has_include`) over compiler-version checks. If the toolchain cannot guarantee the target standard, report the gap and stop — do not write code that will not compile.
7. **Single-command Bash invocations.** Use each tool's own path/recursion flags. Never `cd`-chain or `&&`-chain directory changes — scoped Bash patterns do not match compound commands.
8. **Tool-missing never hard-fails.** If a required tool is absent, print the install hint, skip that class (or language), and continue. Report what was skipped.
9. **Never enter plan mode.** This command IS the procedure — execute it (or, with `--dry-run`, produce the ledger and stop).

## Usage

```bash
# Preview the C++23 migration ledger without touching any source
/system-developer:code-modernize . --target cpp23 --dry-run

# Modernize a C17 project to C23 idioms (one jump)
/system-developer:code-modernize src/ --target c23

# Modernize a C++17 project to C++20 (one jump)
/system-developer:code-modernize src/ --target cpp20

# Bring Python sources up to 3.14 idioms
/system-developer:code-modernize . --target py314

# Harden shell scripts to the strict-mode baseline
/system-developer:code-modernize scripts/ --target bash
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path` | `.` | Directory or file to modernize. Inventory and detection are rooted here. |
| `--target c23\|cpp20\|cpp23\|py314\|bash` | required | The destination standard / hardening profile. For C++, the command auto-inserts the intermediate jump if the source is more than one level below the target. `cpp26` is a recognized future stub — see the note below. |
| `--dry-run` | off | Produce `.context/.modernize/plan.md` (the migration ledger) and stop. No edits, no commits. |

`--target` is required — there is no default standard, because the right destination depends on the deployment toolchain. `c23` modernizes a C17 codebase to C23 idioms (single jump — see the `--target c23` playbook). `cpp26` is recognized but **not yet a working profile** (C++26 is at DIS 2026 — not shipping); the command reports the stub and stops (see Error Handling). For C++26 features today, adopt them one-by-one behind `__cpp_*` feature-test macros via `system-developer:cpp-developer` rather than a bulk modernization pass.

## Inventory

Before building the ledger, establish the *current* standard so the jump count is correct.

| Language | Where the current standard lives | Read |
|----------|----------------------------------|------|
| C | `CMAKE_C_STANDARD` / `target_compile_features(... c_std_NN)` in `CMakeLists.txt`; `c_std=` in `meson.build`; `-std=c17`/`-std=c23`/`-std=c2x` in a `Makefile`/compile flags | the highest pinned `NN` (C17 is the safe baseline) |
| C++ | `CMAKE_CXX_STANDARD` / `target_compile_features(... cxx_std_NN)` in `CMakeLists.txt`; `cpp_std=` in `meson.build`; `-std=c++NN` in a `Makefile`/compile flags | the highest pinned `NN` |
| Python | `requires-python` in `pyproject.toml`; `python_requires` in `setup.py`; `.python-version` | the floor version; modernize to `--target` only if the floor allows it |
| Bash | shebangs (`#!/usr/bin/env bash` vs `#!/bin/sh`), presence of `set -euo pipefail`, `[[ ]]` vs `[ ]`, arrays | how far from the strict-mode baseline |

The marker -> language map is canonical in `skill: language-detection` — detect **per file/subtree** for mixed repos, do not fork the routing logic. Use `skill: version-feature-matrix` to translate the detected current standard and `--target` into the required compiler/CPython floor and the per-jump feature set.

**One-jump enforcement (C++):** if current is C++17 and `--target cpp23`, the ledger contains two sections — *Jump 1: C++17 -> C++20* and *Jump 2: C++20 -> C++23* — and the workflow completes Jump 1 (all classes built, tested, committed) before opening Jump 2. If current already meets or exceeds `--target`, report "already at or above target" and stop.

## The Migration Ledger

The inventory's output is `.context/.modernize/plan.md`: an ordered checklist of migration classes, mechanical-first within each jump. Template:

```markdown
# Modernization Ledger
Target: {c23|cpp20|cpp23|py314|bash} | Current: {detected} | Path: {path}
Toolchain gate: {compiler/CPython + min version from version-feature-matrix} — {PASS | GAP: ...}

## Jump 1: {from} -> {to}
| # | Migration class | Kind | Owner | Status |
|---|-----------------|------|-------|--------|
| 1 | clang-tidy modernize-* autofixes | mechanical | sys-code-fixer | pending |
| 2 | SFINAE -> concepts | semantic | cpp-developer | pending |
| 3 | pointer+size -> std::span | semantic | cpp-developer | pending |
| ... | ... | ... | ... | ... |

## Jump 2: {from} -> {to}   <!-- only when target is >1 level above current -->
| # | Migration class | Kind | Owner | Status |
| ... |
```

Status transitions per row: `pending -> applied -> verified -> committed` (or `reverted` on a red build). The ledger is the source of truth across resumes — read it, do not rely on context-window memory.

## Per-Target Playbooks

Each playbook is an ordered list of migration classes. Mechanical classes lead (cheap, deterministic, low-risk); semantic classes follow. Every feature claim carries a standard marker and a fallback row from `skill: version-feature-matrix`.

### `--target c23` (from C17)

Toolchain gate: `-std=c23` is the canonical spelling from **GCC 14 / Clang 18** (older toolchains use `-std=c2x`); newest stable mid-2026 is **GCC 15.x / Clang 20-21.x**. GCC 15 defaults to `-std=gnu23` for C — always pin `-std`. Treat MSVC as C17-only unless a feature is verified. Per `skill: version-feature-matrix` (C section). Gate each feature with `__has_include`/`__STDC_VERSION__ >= 202311L` or a feature probe, never a bare compiler version. Single jump — C17->C23 has no intermediate standard.

C17->C23 ledger (mechanical-first):

| Order | Class | Kind | Notes |
|-------|-------|------|-------|
| 1 | `clang-tidy -checks='modernize-*,readability-*' -fix` (C pass) | mechanical | Picks up C-applicable modernize/readability fixes. Delegate to `sys-code-fixer`. |
| 2 | `NULL` -> **`nullptr`** | mechanical | C23 `nullptr` (and `nullptr_t`); type-safe null pointer constant. |
| 3 | `K&R` / empty `()` prototypes -> **`(void)`** semantics | mechanical-ish | In C23 an empty `()` now means `(void)` (no args), not "unspecified args" — audit declarations that relied on the old meaning before relying on it. |
| 4 | macro/enum constants -> **`constexpr` objects** | semantic | C23 `constexpr` for object definitions; replace `#define`d numeric constants where a typed `constexpr` reads better. Route to `c-developer` for judgment. |
| 5 | hand-rolled overflow checks -> **`<stdckdint.h>`** (`ckd_add`/`ckd_sub`/`ckd_mul`) | semantic | Checked integer arithmetic; replaces error-prone manual overflow guards. |
| 6 | embedded binary blobs -> **`#embed`** | semantic | `#embed` resource inclusion — **GCC 15+ / Clang 19+** (verify against your toolchain; keep the xxd/objcopy fallback where the toolchain lags). |
| 7 | `typeof` / `typeof_unqual` | mechanical-ish | C23 standardizes `typeof`; replace GNU `__typeof__` reliance where portability now allows. |
| 8 | wide-fixed-width arithmetic -> **`_BitInt(N)`** | semantic | Precise-width integers; adopt only where a fixed bit width is a real requirement. |
| 9 | diagnostics/attributes -> **`[[nodiscard]]` / `[[maybe_unused]]` / `[[deprecated]]`** | mechanical-ish | C23 standard attribute syntax (was compiler-specific `__attribute__`); apply on APIs whose return must be checked or that are being retired. |

Hardening cross-ref: pair the jump with `-fhardened` (GCC 14+) and `-ftrivial-auto-var-init=zero` where appropriate (`skill: secure-coding`). Adopt features one-by-one behind a feature probe; if the toolchain cannot reach C23, keep `-std=c17` as the safe baseline and report the gap.

### `--target cpp20` (from C++17)

Toolchain gate: confirm GCC 10+ / Clang with usable ranges & concepts (verify against your toolchain) per `skill: version-feature-matrix`. Gate each feature with `__cpp_concepts`, `__cpp_lib_ranges`, `__cpp_lib_span`, etc.

| Order | Class | Kind | Notes |
|-------|-------|------|-------|
| 1 | `clang-tidy -checks='modernize-*' -fix` | mechanical | `modernize-use-nullptr`, `-use-override`, `-use-using`, `-loop-convert`, etc. Delegate to `sys-code-fixer`. |
| 2 | SFINAE / `enable_if` -> **concepts** | semantic | Replace `template<class T, enable_if_t<...>>` with `template<Concept T>` / `requires`. Constraints must be *designed*, not transliterated. |
| 3 | hand-written ranges -> **`<ranges>`** views/algorithms | semantic | `views::filter`/`transform`/`take`; prefer lazy views over eager copies. Fallback: range-v3 if the deployment toolchain lags. |
| 4 | pointer + length params -> **`std::span`** | semantic | Replace `(T* p, size_t n)` signatures; watch the lifetime trap (span is non-owning, like `string_view`). |
| 5 | positional aggregate init -> **designated initializers** | mechanical-ish | `Config{.timeout = 5, .retries = 3}` for clarity; verify the aggregate stays an aggregate. |
| 6 | hand-rolled comparison operators -> **`<=>`** (spaceship) | semantic | `auto operator<=>(const T&) const = default;` where defaulted ordering is correct. |

### `--target cpp23` (from C++20)

Toolchain gate: C++23 support is partial across compilers (GCC 13+, Clang 17+ partial, deducing-this Clang 18+ — verify against your toolchain) per `skill: version-feature-matrix`. **Availability-check every feature** with `__cpp_lib_expected`, `__cpp_lib_print`, `__cpp_explicit_this_parameter` before adopting; if unavailable, keep the fallback and skip the class.

| Order | Class | Kind | Notes |
|-------|-------|------|-------|
| 1 | `clang-tidy -checks='modernize-*' -fix` (C++23 pass) | mechanical | Picks up newly-available `modernize-*` checks. Delegate to `sys-code-fixer`. |
| 2 | error codes / out-params -> **`std::expected<T, E>`** | semantic | Convert functions returning `bool`+out-param or sentinel error codes. API-shape change — route to `cpp-developer`. Fallback: `tl::expected`. |
| 3 | `printf` / `iostream` formatting -> **`std::print` / `std::println`** | semantic | Cleaner, type-safe. Fallback: `fmt::print` (fmtlib). Gate on `__cpp_lib_print`. |
| 4 | CRTP / explicit-`this` boilerplate -> **deducing this** | semantic | `template<class Self> auto f(this Self&& self)`; deduplicates const/non-const & ref-qualified overloads. Gate on `__cpp_explicit_this_parameter`. |

### `--target py314`

Toolchain gate: `requires-python` must allow 3.14; otherwise this is a *version-bump* decision (raise the floor) before idiom modernization. Per `skill: version-feature-matrix`.

| Order | Class | Kind | Notes |
|-------|-------|------|-------|
| 1 | `ruff check --select UP --target-version py314 --fix` | mechanical | The headline first pass — `pyupgrade` rules rewrite legacy idioms (old typing imports, `super()` args, f-string conversions, ...). Delegate to `sys-code-fixer`. |
| 2 | generics -> **PEP 695 type parameters** | semantic | `def f[T](x: T) -> T` and `class Box[T]`; `type Alias[T] = ...`. Drop `TypeVar`/`Generic` boilerplate where the rewrite is clean. Route to `python-developer`. |
| 3 | removed-deprecation sweep | semantic | Remove uses of APIs removed/deprecated by 3.14 (verify the exact list against your toolchain / the 3.14 "What's New" via Context7/Ref). |
| 4 | drop `from __future__ import annotations` | mechanical-ish | On 3.14, PEP 649 deferred annotations are default; the future import forces older string semantics — remove it (see `skill: version-feature-matrix` fallback row). |
| 5 | free-threading readiness notes (C extensions) | semantic / advisory | For projects shipping C extensions: audit for `Py_mod_gil` declaration and thread-safety; emit readiness notes rather than auto-rewriting native code. Route to `python-developer`. |

### `--target bash`

Toolchain gate: none beyond the gate trio (`shellcheck`, `shfmt`). Exit criterion for every script is **shellcheck-clean**. Mind the macOS `/bin/bash` 3.2 caveat (`skill: version-feature-matrix`) — prefer `#!/usr/bin/env bash` + a version guard over 4.x/5.x-only features in portable scripts.

| Order | Class | Kind | Notes |
|-------|-------|------|-------|
| 1 | strict-mode prologue -> **`set -Eeuo pipefail`** | semantic | Add the prologue; audit each script for places `set -e` silently misbehaves (honest caveat matrix in `skill: bash-scripting`). |
| 2 | cleanup -> **`trap ... EXIT`** | semantic | Replace ad-hoc cleanup with a `trap cleanup EXIT` (and `ERR`/`INT` where apt); idempotent temp-file/lock removal. |
| 3 | `[ ]` -> **`[[ ]]`**; quoting fixes | mechanical | `[[ ]]` for tests; quote all expansions (clears SC2086/SC2046). Delegate to `sys-code-fixer`. |
| 4 | undeclared vars -> **`local`**; lists -> **arrays** | semantic | Function-scope with `local`; replace word-split string lists with real arrays (`"${arr[@]}"`). |
| 5 | `shfmt -w` formatting | mechanical | Normalize indentation/style last, after logic changes. Delegate to `sys-code-fixer`. |

## Workflow

### Phase 1: Inventory & Ledger (Bash + Read)

1. Confirm `path` exists; if not, emit the Error Handling "path not found" message and stop.
2. If `--target cpp26`, emit the "C++26 future stub" message and stop (Error Handling).
3. Validate `--target` is one of `c23|cpp20|cpp23|py314|bash`; if missing/invalid, emit the "missing target" message and stop.
4. Detect the current standard per the Inventory table (read `CMAKE_CXX_STANDARD`/`cxx_std_NN`, `requires-python`, shebangs). Resolve the toolchain gate via `skill: version-feature-matrix`. If the gate is a GAP (toolchain cannot reach `--target`), report it and stop (Rule 6).
5. If current already meets/exceeds `--target`, report "already at or above target" and stop.
6. For C++: if `--target` is more than one level above current, split the ledger into ordered Jumps (Rule 1).
7. Write `.context/.modernize/plan.md` from the matching playbook(s), all rows `pending`.
8. **If `--dry-run`: stop here.** Report the ledger path and the planned classes. Make no edits, no commits.

### Phase 2: Apply Classes In Order (delegated)

Walk the ledger top-down, one row at a time. For each `pending` row:

1. **Mark `applied`** in the ledger as you start it.
2. **Delegate by kind:**
   - **mechanical** ->
     **Use Task tool with subagent_type="system-developer:sys-code-fixer"**
     Prompt: "Apply ONLY the migration class **{class}** for `{path}` (target {target}, jump {from}->{to}). Run the exact mechanical transform: {e.g. `clang-tidy -p {path}/build -checks='modernize-*' -fix {files}` / `ruff check --select UP --target-version py314 --fix {path}` / `shfmt -w {files}`}. Do NOT apply any other class. Make minimal, deterministic edits. Report every file and rule/check touched. Do not run the test suite."
   - **semantic (C)** ->
     **Use Task tool with subagent_type="system-developer:c-developer"**
     Prompt: "Perform ONLY the migration class **{class}** for `{path}` (C17->C23). {e.g. Replace `#define`d constants with typed `constexpr` objects / convert hand-rolled overflow checks to `<stdckdint.h>` ckd_* / adopt `#embed` for binary blobs with an xxd/objcopy fallback / introduce `_BitInt(N)` only where a fixed width is required}. Gate every adopted feature with `__STDC_VERSION__ >= 202311L`/`__has_include`/a feature probe; if a feature is unavailable on the project toolchain (e.g. `#embed` needs GCC 15+/Clang 19+), keep the fallback and report it. Do not touch other classes. Return the diff and the feature-probe rationale."
   - **semantic (C++)** ->
     **Use Task tool with subagent_type="system-developer:cpp-developer"**
     Prompt: "Perform ONLY the migration class **{class}** for `{path}` ({from}->{to}). {e.g. Replace SFINAE/enable_if constraints with designed concepts / convert pointer+size signatures to std::span watching lifetime / convert error-code returns to std::expected}. Gate every adopted feature with the relevant `__cpp_*`/`__cpp_lib_*` macro; if a feature is unavailable on the project toolchain, keep the fallback and report it. Do not touch other classes. Return the diff and the feature-test rationale."
   - **semantic (Python)** ->
     **Use Task tool with subagent_type="system-developer:python-developer"**
     Prompt: "Perform ONLY the migration class **{class}** for `{path}` (target 3.14). {e.g. Rewrite TypeVar/Generic to PEP 695 type parameters / sweep removed-deprecations / audit C-extension free-threading readiness and emit notes}. Verify 3.14 behavior against the toolchain (Context7/Ref) where a detail is volatile. Do not touch other classes. Return the diff (and readiness notes for advisory classes)."
3. **Mark `verified`** only after the build+test gate (Phase 3) is green for this class.

### Phase 3: Verify After Every Class (per class)

After each applied class, run the build + test gate by invoking the project's canonical sequence (the same one `/system-developer:build-test` resolves):

1. Run `/system-developer:build-test {path}` (or equivalently its detected configure/build/test commands). Tee output to `.context/logs/`.
2. **Green** -> mark the row `verified`, proceed to commit (Phase 4).
3. **Red** -> the class did NOT pass:
   - For a mechanical class, revert it (the fix-agent's diff) and report — mechanical fixes should never break a green build; a red one is a real signal.
   - For a semantic class, hand the failing build/test excerpt back to the same language agent for a corrective pass (bounded — one corrective cycle, then stop and report).
   - If still red, **halt the run**, mark the row `reverted`, and report (Rule 3). Do not proceed to later classes on a broken build.

### Phase 4: Commit One Class Per Migration (per class)

After a class is `verified`:

1. Stage only the files that class touched.
2. Commit with a conventional subject naming the class, e.g.:
   - `refactor: replace SFINAE with concepts (C++17->20)`
   - `refactor: adopt std::expected for parser errors (C++20->23)`
   - `refactor: ruff pyupgrade pass for Python 3.14`
   - `refactor: add strict-mode prologue and trap cleanup`
3. Mark the row `committed` in the ledger.
4. Move to the next `pending` row. When a Jump's rows are all `committed`, open the next Jump (C++ multi-jump only).

> Per the user's git conventions: no `--no-verify`, no AI-attribution footers, and follow the repo's commit format. If the repo is mid-feature on a protected branch, branch first.

### Phase 5: Report

Emit the Output Format. Summarize classes applied/verified/committed/skipped per Jump, and the ledger path for the audit trail.

## Tool Availability

Confirm each class's tool before delegating. Missing -> print the hint, skip that class, continue, and note the skip in the ledger and report.

| Missing tool | Install hint |
|--------------|--------------|
| `clang-tidy` / `clang-format` (C++ modernize-* / format) | `brew install llvm` |
| `cmake` / `ctest` (build+test gate, `compile_commands.json` for clang-tidy) | `brew install cmake ninja` |
| `ruff` (Python UP pass) | `uv tool install ruff` |
| `uv` (Python build+test gate) | `curl -LsSf https://astral.sh/uv/install.sh \| sh` (verify against your toolchain) |
| `shellcheck` (Bash exit criterion) | `brew install shellcheck` |
| `shfmt` (Bash formatting class) | `brew install shfmt` |

Exact flag spellings vary across tool releases — verify against your toolchain when a flag is rejected. Never hard-fail on a missing tool: print the hint, skip the class/language, continue, and report the skip.

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
Suggestion: Pass a directory or file that exists, e.g. /system-developer:code-modernize . --target cpp20 --dry-run
```

### Missing or invalid --target
```
Error: --target is required and must be one of: c23, cpp20, cpp23, py314, bash.
Suggestion: /system-developer:code-modernize . --target cpp23 --dry-run
```

### C++26 requested (future stub)
```
Note: --target cpp26 is not yet a working profile — C++26 is at DIS 2026
(not shipping). Adopt C++26 features one-by-one behind __cpp_* feature-test
macros via system-developer:cpp-developer rather than a bulk modernization
pass. Re-run with --target cpp23 for a supported jump.
```
See `skill: version-feature-matrix` (C++ section) for the C++26 emerging row and the feature-test-macro gating guidance.

### C source modernization
```
Note: C17->C23 modernization is the --target c23 profile (nullptr, constexpr
objects, <stdckdint.h>, #embed, typeof, _BitInt(N), () means (void),
[[nodiscard]]/[[maybe_unused]]/[[deprecated]]). Semantic classes route through
system-developer:c-developer; pin -std=c17 as the safe baseline if the
toolchain cannot reach C23.
```
See `skill: version-feature-matrix` (C section) for the C23 feature/fallback table.

### More than one standard jump requested
Not an error — the command auto-inserts the intermediate jump (C++17 + `--target cpp23` -> two ordered Jumps). It will complete Jump 1 (built, tested, committed) before opening Jump 2 (Rule 1).

### Already at or above target
```
Note: {path} is already at or above {target} (detected: {current}).
Nothing to modernize. Suggestion: target a higher standard or a different path.
```

### Toolchain gate failure
```
Error: Toolchain cannot guarantee {target}.
{compiler/CPython} {detected version} < required {min version}
(see skill: version-feature-matrix).
Suggestion: upgrade the toolchain, or modernize to the highest supported standard.
```
Stop — do not write code that will not compile (Rule 6).

### Build red after a class
Halt the run (Rule 3). Mark the row `reverted`, report the first error and log path, and do NOT attempt later classes. For a semantic class, one bounded corrective cycle with the owning agent is allowed before the halt.

### Tool missing
Print the install hint from Tool Availability, skip the class (or language), continue, and note the skip. Only when no class can run does the command report HALTED with aggregated hints.

## See Also

- `skill: version-feature-matrix` — canonical standard/version -> toolchain-floor + feature/fallback tables (gate every adopted feature here).
- `skill: language-detection` — marker -> language -> agent routing (keep per-file detection in sync).
- `skill: modern-c` — C17/C23 standard selection, the C23 quick-wins ledger (nullptr, constexpr objects, `<stdckdint.h>`, `#embed`, `typeof`, `_BitInt(N)`, attributes), and hygiene flags.
- `skill: modern-cpp` — RAII/Rule-of-Zero, vocabulary types, the constexpr spectrum, and the version-ref playbooks (`cpp17/20/23-features`, ranges, error-handling).
- `skill: modern-python` — t-strings, PEP 649 deferred annotations, the `from __future__` removal, except*/add_note.
- `skill: bash-scripting` — strict-mode prologue, the honest `set -e` caveat matrix, portability and version guards.
- `/system-developer:build-test` — the build + test gate run after every migration class.
- `/system-developer:lint-fix` — the shallow mechanical pass (`clang-tidy modernize-*`, `ruff --select UP`) for a single language; this command sequences those plus semantic migrations across standard jumps.
- `/system-developer:code-review` — review the modernized diff for behavioral drift once the ledger is complete.
