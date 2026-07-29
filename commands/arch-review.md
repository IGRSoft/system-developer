---
description: Review C/C++/Python/Bash architecture against its pattern, reporting violations with file:line and P0-P3 severity
argument-hint: [scope: dir/file (default .)] [--pattern layered|hexagonal|plugin|pipeline] [--lang c|cpp|python|bash] [--abi] [--trust-boundaries] [--deep]
allowed-tools: Read, Glob, Grep, Bash
estimated-cost:
  min-tokens: 5000
  max-tokens: 24000
  model-distribution:
    haiku: 10%
    sonnet: 60%
    opus: 30%
---

# Architecture Review
<!-- Updated: July 2026 -->

Review an existing C, C++, Python, or Bash codebase against the architecture pattern it actually implements — or the one you name with `--pattern`. Detection runs from structural evidence (build graph, header tiers, registration tables, concurrency and ownership markers), then `system-developer:system-architector` grades the codebase and reports violations with `file:line` and a P0-P3 severity.

This command is **read-only**. It never edits a source file, a `CMakeLists.txt`, or a `pyproject.toml`. Remediation is a separate, explicit step: `/system-developer:fix-refactor`.

[Extended thinking: An architecture review of systems code fails in ways an app-layer review does not — a cycle between library targets, an internal header that leaked into the installed public tier, a default-visible symbol that silently became an ABI promise, an ownership model nobody can name, a thread-pool bolted onto an event-loop core, or a Python `__all__` that no longer matches what the docs promise. Every one of those is invisible in a single-file read and obvious in the build graph plus the exported symbol table, so this command sweeps that structural evidence first and hands the architector concrete anchors instead of asking it to infer a pattern from prose. Detection precedes judgment: grading a hexagonal codebase against a layered checklist manufactures violations that are not real. Keep the review honest — a codebase whose structure fits its constraints gets a short report saying so.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **Read-only, always.** This command MUST NOT write or edit any file — no sources, no build files, no report file. Findings are printed. Any remediation is routed to `/system-developer:fix-refactor` by name, never performed here.
2. **Detect before you grade.** Run the evidence sweep and the detection pass first. Grade only against the detected pattern (or an explicit `--pattern`). Do NOT evaluate a codebase against a pattern it never adopted.
3. **State detection confidence.** Report the detected pattern with `high`/`medium`/`low` confidence and its `file:line` evidence. At `low` confidence, say so in the report and treat every violation as provisional rather than asserting a pattern the evidence does not support.
4. **Every violation carries an anchor and a severity.** No finding ships without `file:line` (or a target/module name for build-graph findings) and a P0-P3 rating from `skill: severity-matrix`.
5. **State ABI/API impact per fix.** Any proposed change touching a public struct layout, function signature, exported symbol, `enum` value, or Python public name MUST be labelled with its ABI/API impact and routed through a semver-major plan.
6. **Tool-missing never hard-fails.** If `nm`, `readelf`, `otool`, or a build tool is unavailable, print the install hint, note the reduced depth for that check, and continue with source-level evidence.
7. **No manufactured violations.** If the structure fits, say so plainly. Do NOT pad the report with P3 preferences, and do NOT recommend a wholesale pattern switch for a local mismatch.
8. **Never enter plan mode.** This command IS the procedure — execute it.

## Usage

```bash
# Review the current project's architecture as-is
/system-developer:arch-review .

# Review one library subtree
/system-developer:arch-review src/codec/

# Grade against an expected pattern instead of the detected one
/system-developer:arch-review . --pattern hexagonal

# Audit exported symbols and public-header exposure for ABI risk
/system-developer:arch-review . --abi

# Force the language when detection is ambiguous
/system-developer:arch-review scripts/ --lang bash

# Add a trust-boundary pass and a migration outline for a big mismatch
/system-developer:arch-review . --trust-boundaries --deep
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `scope` | `.` | Directory or file to review. The evidence sweep is rooted here. |
| `--pattern NAME` | detected | Grade against an expected pattern (`layered`, `hexagonal`, `plugin`, `pipeline`) instead of the detected one. Detection still runs; a mismatch between expected and detected is itself reported as a finding. |
| `--lang c\|cpp\|python\|bash` | auto | Force the language instead of detecting. Use for extensionless scripts or to narrow a mixed repo. |
| `--abi` | off | Add the exported-symbol and public-header exposure audit (Phase 4). Off by default because it needs a built artifact. |
| `--trust-boundaries` | off | Add a read-only boundary/trust-zone pass from `system-developer:sys-security-auditor` alongside the architecture review. |
| `--deep` | off | Ask the architector for Deep Refactor Mode deliverables — current→target map, incremental migration path, coexistence strategy, risk points. Text only; nothing is applied. |

## Scope & Language Resolution

Resolve the review scope **once**, then pass that exact file list to every downstream pass.

1. **Explicit arg** — a directory (scan recursively) or a single file (read it plus its directory siblings and the build file that owns it).
2. **No arg** — the repository root (`.`).

Exclude vendored and generated trees from the list: `build/`, `builddir/`, `.venv/`, `node_modules/`, `third_party/`, `vendor/`, and any configured CMake/Meson output directory.

Detect the languages present using the canonical `skill: language-detection` marker table — do not fork its routing rules. Summary: `CMakeLists.txt`/`meson.build`/`Makefile` → C or C++ (tie-break on `.cpp`/`.cc`/`.hpp` sources, `project(x CXX)`, or `CMAKE_CXX_STANDARD`); `pyproject.toml`/`uv.lock` → Python; `*.sh`/`*.bats` → Bash. A mixed repo is reviewed per-root, and the roots are named in the report.

## Architecture Detection Signals

Infer the current pattern from evidence, mirroring the architector's signal table. Record a `file:line` (or target name) for every signal you match.

| Signal | Pattern |
|--------|---------|
| Public-header dir + acyclic library targets, `PUBLIC`/`PRIVATE` link scope | Layered libraries |
| Interface headers / ABCs (`Protocol`, pure-virtual) wrapping I/O, OS, or device calls | Hexagonal / ports-adapters |
| Registration tables, `dlopen`/`LoadLibrary`, `register_*` callbacks, entry-point groups | Plugin / registry |
| Stage structs/functions chained by queues or generators; `yield`/`co_yield` producers | Pipeline / dataflow |
| `asyncio`/`epoll`/`kqueue`, single-threaded reactor, `await` fan-out | Event-loop concurrency |
| `std::jthread`/`thread_pool`, pthreads, `ThreadPoolExecutor`, `Py_mod_gil` slots | Thread-pool concurrency |
| `multiprocessing`, `fork`/`exec`, `InterpreterPoolExecutor`, worker processes | Process-pool concurrency |
| Arena/region/bump allocator, per-request scratch, bulk `free` | Arena/region ownership |
| `unique_ptr`/`shared_ptr`, Rule of Zero, no naked `new`/`delete` | RAII ownership |
| Manual `retain`/`release`, refcount fields, `Py_INCREF`/`Py_DECREF` at the boundary | Refcount / GC-boundary ownership |

Concurrency and ownership are two orthogonal axes over a structural pattern — report all three, not one label.

## Violation Classes

The classes this review is responsible for finding. Each needs an anchor and a P0-P3 rating.

| Class | What it looks like |
|-------|--------------------|
| **Cyclic dependency** | Two library targets or Python packages that import/link each other, directly or transitively. Break the cycle or extract the shared tier. |
| **Leaked internal header** | An `internal/`, `detail/`, or `_private` header reachable from the installed public tier, or pulled in by a public header's `#include`. |
| **Accidental ABI exposure** | Default-visible symbols with no `-fvisibility=hidden` + explicit export macro; a public struct with exposed layout where an opaque handle was intended. |
| **Ownership ambiguity** | A pointer whose owner is unnamed at the boundary — raw `T*` returned without a documented free contract, mixed arena/refcount lifetimes, unclear `PyObject*` reference ownership at an FFI seam. |
| **Concurrency mismatch** | Blocking calls inside an event loop, shared mutable state handed to a process pool, a thread pool bolted onto a single-threaded reactor core. |
| **Boundary bypass** | A caller reaching past a port/adapter or layer interface into the implementation tier. |
| **Python public-API drift** | `__all__`, the documented surface, and the actually-importable names disagree; a removal shipped without a deprecation cycle. |

Anchors: `skill: build-systems` (targets, link scope, visibility), `skill: ffi-interop` (boundary and `PyObject*` ownership), `skill: c-memory-ownership`, `skill: modern-cpp`, `skill: cpp-concurrency`, `skill: python-concurrency`.

## API / ABI Rules Applied

Grade the public surface against these rules; every violation here is at least P1.

| Concern | Rule |
|---------|------|
| **Semver** | MAJOR on any source- or binary-incompatible change; MINOR additive; PATCH fixes. Shared libraries carry a SONAME/ABI version distinct from the marketing version. |
| **Symbol visibility** | Default-hidden (`-fvisibility=hidden`) with deliberate exports. A visible symbol is an ABI promise; an accidentally-exported internal is a future break. |
| **`extern "C"` boundaries** | Plain C types only across the seam — no exceptions or STL, opaque handles over exposed structs. |
| **Stable C ABI over C++** | Any library with external or cross-toolchain consumers should present a C facade; the C++ ABI is fragile across compilers and standard-library versions. |
| **Python public API** | The public surface is what `__all__` and the docs promise. Deprecate before removal; keep the `pyproject.toml` version and the API contract moving together. |

ABI breaks are silent at compile time and lethal at load time — flag any change to a public struct layout, function signature, exported symbol, or `enum` value as a potential break.

## Workflow

### Phase 1: Scope, Language, Evidence Sweep (read-only, no agent)

1. Resolve the scope and the language set (see Scope & Language Resolution). Print the roots and file count before delegating.
2. Sweep for structural evidence with Glob/Grep/Read, collecting `file:line` anchors:
   - **Build graph** — `target_link_libraries` scope keywords, `add_library` kinds (`STATIC`/`SHARED`/`OBJECT`/`INTERFACE`), Meson `declare_dependency`, Python intra-package imports.
   - **Header tiers** — `include/` public dirs vs `src/`, `internal/`, `detail/`; `install(FILES ...)`/`install(DIRECTORY ...)` lists.
   - **Visibility** — `-fvisibility=hidden`, `CXX_VISIBILITY_PRESET`, `VISIBILITY_INLINES_HIDDEN`, export macros, version scripts (`*.map`, `*.sym`).
   - **Extension/registry** — `dlopen`, `register_*`, static registration tables, `[project.entry-points]`.
   - **Concurrency & ownership** — the markers from the signal table.
   - **Python surface** — `__all__`, `__init__.py` re-exports, documented API pages.
3. If an already-configured build dir exists, optionally read its dependency graph (`cmake --graphviz` output, `meson introspect --targets`) for a precise target-level cycle check. Skip silently if absent — never configure a build here.

### Phase 2: Pattern Detection & Review

**Use Task tool with subagent_type="system-developer:system-architector"**

Prompt: "Read-only architecture review of `{scope}` (languages: {languages}; build system: {system}). Structural evidence already collected: {evidence anchors with file:line}. File list: {file_list}. Step 1 — detect the current structural pattern plus its ownership and concurrency axes, using your Architecture Detection signal table; report confidence (high/medium/low) with `file:line` evidence. {If --pattern: 'The expected pattern is `{pattern}` — report any mismatch with the detected pattern as its own finding.'} Step 2 — grade the codebase against that pattern and report violations in these classes: cyclic library/target or package dependencies, leaked internal headers, accidental ABI exposure (default-visible symbols, exposed public struct layout), ownership ambiguity, concurrency-model mismatch, boundary bypass, and Python public-API drift (`__all__` vs docs). Every violation needs `file:line` (or target/module name) and a P0-P3 severity. Step 3 — give a concrete fix per violation with its ABI/API impact stated; anything touching a public struct layout, signature, exported symbol, `enum` value, or Python public name must be routed through a semver-major plan. Step 4 — emit the pattern-specific PR checklist with pass/fail per item. Use your **For Architecture Review** output format. Do NOT edit any file. Prefer the smallest fix that resolves each violation; do not recommend a wholesale pattern switch unless the mismatch is severe. If the structure fits its constraints, say so directly."

Add when `--deep` is set: "Also run Deep Refactor Mode: current→target map, incremental migration path (each phase independently buildable and testable), coexistence strategy including any ABI shim or facade needed to hold a published interface, and the risk points. Text only — apply nothing."

### Phase 3: Exported-Symbol Audit (`--abi` only)

Run only when `--abi` is set and a built shared library exists. Never build one here — if no artifact is present, note the skip and rely on Phase 1's source-level visibility evidence.

1. List the dynamic symbol table of each built shared library, read-only:
   - Linux: `nm -D --defined-only <lib.so>` or `readelf --dyn-syms -W <lib.so>`
   - macOS: `nm -gU <lib.dylib>` or `otool -TV <lib.dylib>`
2. Diff the exported set against the deliberate export surface from Phase 1 (export macros, version script, public headers).
3. Every symbol exported but absent from the public surface is an **accidental ABI exposure** finding — P1 by default, P0 when it exposes an internal struct layout or a symbol the project already documents as private.
4. Feed the delta back to the architector output as evidence; do not re-run Phase 2.

### Phase 4: Trust-Boundary Pass (`--trust-boundaries` only)

**Use Task tool with subagent_type="system-developer:sys-security-auditor"**

Prompt: "Read-only trust-boundary review of `{scope}` (languages: {languages}). Detected architecture: {pattern + ownership + concurrency}. For each architectural boundary in this list — {ports/adapters, public API/ABI surface, FFI seams, plugin load points, process/IPC edges} — state which side is trusted, what crosses it, and whether the crossing data is validated at the boundary. Flag boundaries where untrusted input reaches a parser, a process spawn, a path operation, or a deserializer without validation. Do NOT edit any file. Return findings as `{file, line, boundary, severity (P0-P3), why, fix}`. If the boundaries are sound, say so directly."

Runs in parallel with Phase 2 when both are requested — it has no dependency on the detection result beyond the scope.

### Phase 5: Synthesis & Report

1. Merge the architector findings with the Phase 3 symbol delta and any Phase 4 boundary findings; deduplicate at the same `{file, line}`, keeping the higher severity and the clearer fix.
2. Normalize each survivor to `{anchor, class, severity, why, fix, abi_impact}` — severity per `skill: severity-matrix`.
3. Rank P0→P3 and emit the Output Format report. Print it; write nothing.
4. Point remediation at `/system-developer:fix-refactor`, and name `/system-developer:build-test` as the gate any applied fix must pass.

## Output Format

```markdown
## Architecture Review

**Scope:** {roots}
**Languages / build system:** {languages} / {system}
**Mode:** {as-detected | graded against --pattern {name}} {+ --abi} {+ --trust-boundaries} {+ --deep}

### Detected Pattern
- **Structure:** {layered | hexagonal | plugin/registry | pipeline} — confidence {high/medium/low}
- **Ownership:** {arena/region | RAII | refcount | GC-boundary}
- **Concurrency:** {event-loop | thread-pool | process-pool | none}
- **Evidence:** {file:line or target} — {signal matched}
{If --pattern and it differs from detected: **Expected vs detected mismatch:** {expected} vs {detected} — see findings.}

### Verdict
{PASS | WARN | FAIL} — {one or two sentences. If the structure fits: say so plainly.}

| Priority | Count |
|----------|-------|
| P0 (structure broken / ABI break shipping) | {n} |
| P1 (fix before the next release) | {n} |
| P2 (should fix) | {n} |
| P3 (nice to have) | {n} |

### Violations
| Anchor | Class | Severity | Why | Fix | ABI/API impact |
|--------|-------|----------|-----|-----|----------------|
| {file:line \| target} | {cyclic dep \| leaked internal header \| ABI exposure \| ownership ambiguity \| concurrency mismatch \| boundary bypass \| public-API drift} | P{n} | {what is broken} | {smallest fix} | {none \| additive (MINOR) \| breaking (MAJOR) — SONAME bump} |

### PR Checklist ({pattern})
- [ ] / [x] {pattern-specific item} — {pass/fail note}

<!-- With --abi: -->
### Exported-Symbol Delta
| Symbol | Library | Status |
|--------|---------|--------|
| {symbol} | {lib} | exported but not in public surface — accidental ABI exposure |

<!-- With --trust-boundaries: -->
### Trust Boundaries
| Boundary | Anchor | Severity | Finding |
|----------|--------|----------|---------|
| {boundary} | {file:line} | P{n} | {validation gap} |

<!-- With --deep: -->
### Migration Outline
- **Current → target:** {map}
- **Phases:** {ordered, each independently buildable and testable}
- **Coexistence:** {ABI shim / facade holding the published interface}
- **Risk points:** {ABI compat, ownership transfer, concurrency invariants, build-graph cycles}

### Next Step
Remediation is not applied by this command. Run `/system-developer:fix-refactor` on the P0/P1 findings, then gate on `/system-developer:build-test`.
```

## Error Handling

### No reviewable sources in scope
```
Note: No C/C++/Python/Bash sources found under {scope}.
Suggestion: Pass the directory that holds the sources, e.g. /system-developer:arch-review src/
```

### No build manifest (reduced depth)
```
Warning: No CMakeLists.txt / meson.build / Makefile / pyproject.toml under {scope}.
Effect: Target-graph, link-scope, and visibility checks are unavailable; the review
runs on source-level evidence only and detection confidence is capped at medium.
Suggestion: Run from the directory that owns the build manifest.
```

### Detection confidence low
```
Note: Architecture detection confidence is LOW — the evidence matched no signal cleanly.
Effect: Findings are reported as provisional, not as violations of a confirmed pattern.
Suggestion: Re-run with --pattern <name> to grade against the pattern you intended.
```

### `--abi` with no built artifact
```
Warning: --abi requested but no built shared library found under {scope}.
Effect: Symbol-table audit skipped; ABI findings come from source-level visibility
evidence (export macros, -fvisibility, version scripts) only.
Suggestion: Build first with /system-developer:build-test, then re-run with --abi.
```

### Symbol tool missing (reduced depth)
Print the hint, note the reduced depth in the report, and continue — never hard-fail:

| Missing tool | Install hint |
|--------------|--------------|
| `nm` / `readelf` / `objdump` | install binutils (`brew install binutils`, or your distro's `binutils`) |
| `otool` (macOS) | `xcode-select --install` |
| `cmake` (graph introspection) | `brew install cmake` |

### Ambiguous language
Apply the `skill: language-detection` shebang and tie-break rules. If still ambiguous, route the scope to `system-developer:system-developer` and note the routing in the report.

## See Also

- `skill: language-detection` — canonical marker → language → agent routing (keep the resolution section in sync).
- `skill: severity-matrix` — the P0-P3 definitions every violation is rated against.
- `skill: build-systems` — targets, `PUBLIC`/`PRIVATE` link scope, symbol visibility, version scripts.
- `skill: ffi-interop` — `extern "C"` boundary doctrine and `PyObject*` ownership at the C-API seam.
- `skill: c-memory-ownership`, `skill: modern-cpp` — arena/refcount and RAII ownership models.
- `skill: cpp-concurrency`, `skill: python-concurrency` — event-loop vs thread-pool vs process-pool decision tables.
- `/system-developer:arch-select` — pick the target pattern when this review reports a severe mismatch.
- `/system-developer:fix-refactor` — apply the remediation this command only recommends.
- `/system-developer:build-test` — the build/test gate every applied fix must pass.
- `/system-developer:review-code` — line-level correctness and security review, complementary to this structural pass.
- `/system-developer:analyze-tech-debt` — quantify and prioritize the debt these violations represent.
