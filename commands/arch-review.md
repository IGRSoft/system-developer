---
description: Review C/C++/Python/Bash architecture against its pattern, reporting violations with file:line and P0-P3 severity
argument-hint: [scope: dir/file (default .)] [--pattern layered|hexagonal|plugin|pipeline] [--lang c|cpp|python|bash] [--abi] [--trust-boundaries] [--deep]
allowed-tools: Read, Glob, Grep, Bash, Agent
estimated-cost:
  min-tokens: 5000
  max-tokens: 24000
  model-distribution:
    haiku: 10%
    sonnet: 60%
    opus: 30%
---

# Architecture Review

Review an existing C, C++, Python, or Bash codebase against the architecture pattern it actually implements, or the one named with `--pattern`. You sweep structural evidence (build graph, header tiers, registration tables, concurrency and ownership markers); `system-developer:system-architector` then detects the pattern, grades the codebase, and reports violations with `file:line` and P0-P3 severity. Most of these defects (target cycles, leaked internal headers, accidental exports) are invisible in a single-file read and obvious in the build graph, so the sweep comes first.

## Rules

- Read-only: write no file, not even a report. Print the findings and route remediation to `/system-developer:fix-refactor`.
- Detect before grading, and grade only against the detected pattern or `--pattern`. Grading against a pattern the code never adopted manufactures violations.
- Report detection confidence (`high`/`medium`/`low`) with evidence. At `low`, mark every violation provisional.
- Every violation has an anchor (`file:line`, or a target/module for build-graph findings) and a P0-P3 severity.
- Any fix touching a public struct layout, function signature, exported symbol, `enum` value, or Python public name states its ABI/API impact and needs a semver-major plan.
- A missing `nm`/`readelf`/`otool`/`cmake` never fails the run: print the install hint, note the reduced depth, and continue on source-level evidence.
- If the structure fits, say so. Don't pad with P3 preferences or recommend a wholesale pattern switch for a local mismatch.

## Usage

```bash
/system-developer:arch-review .                               # review as detected
/system-developer:arch-review src/codec/                      # one library subtree
/system-developer:arch-review . --pattern hexagonal           # grade against an expected pattern
/system-developer:arch-review . --abi                         # exported-symbol audit
/system-developer:arch-review scripts/ --lang bash            # extensionless scripts
/system-developer:arch-review . --trust-boundaries --deep     # boundary pass + migration outline
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `scope` | `.` | Directory (recursive) or file. A file is reviewed with its directory siblings and the build file that owns it. |
| `--pattern NAME` | detected | Grade against `layered`, `hexagonal`, `plugin`, or `pipeline`. Detection still runs; an expected-vs-detected mismatch is itself a finding. |
| `--lang c\|cpp\|python\|bash` | auto | Force the language. `--lang bash` grades only classes with a shell analogue (cyclic `source`, boundary bypass, library vs entry-point split) and always reports `low` confidence. |
| `--abi` | off | Add the exported-symbol audit (Phase 3) on an already-built shared library. |
| `--trust-boundaries` | off | Add a read-only trust-boundary pass by `system-developer:sys-security-auditor`. |
| `--deep` | off | Add the architector's Deep Refactor deliverables: current→target map, incremental migration path, coexistence strategy, risk points. Text only. |

## Violation Classes

### Structural and ABI classes

| Class | What it looks like |
|-------|--------------------|
| Cyclic dependency | Library targets or Python packages that import/link each other, directly or transitively |
| Leaked internal header | An `internal/`, `detail/`, or `_private` header reachable from the installed public tier or a public header's `#include` |
| Accidental ABI exposure | Default-visible symbols without `-fvisibility=hidden` plus an export macro; exposed public struct layout where an opaque handle was intended |

### Ownership, concurrency, and language-specific classes

| Class | What it looks like |
|-------|--------------------|
| Ownership ambiguity | A pointer whose owner is unnamed at the boundary: raw `T*` returned without a free contract, mixed arena/refcount lifetimes, unclear `PyObject*` ownership at an FFI seam |
| Concurrency mismatch | Blocking calls in an event loop, shared mutable state handed to a process pool, a thread pool bolted onto a single-threaded reactor |
| Boundary bypass | A caller reaching past a port/adapter or layer interface into the implementation tier |
| Public-API drift (Python) | `__all__`, the documented surface, and the importable names disagree; a removal shipped without deprecation |
| Cyclic `source` (Bash) | Shell libraries that `source` each other, or a library that sources an entry script |

## Severity

| Priority | Meaning |
|----------|---------|
| P0 | Structure broken or an ABI break shipping; also an accidental export of an internal struct layout or documented-private symbol |
| P1 | Fix before the next release. Every public API/ABI rule violation is at least P1 |
| P2 | Should fix |
| P3 | Nice to have |

## Workflow

### Phase 1: Scope and evidence sweep

Resolve the scope once and pass the same file list to every agent. Exclude `build/`, `builddir/`, `.venv/`, `node_modules/`, `third_party/`, `vendor/`, and configured CMake/Meson output directories. Detect languages from build manifests, extensions, and shebangs (`--lang` overrides; a bare `.h` is C unless the tree has C++ sources or `CMAKE_CXX_STANDARD`; helper scripts such as `scripts/*.sh` don't make a root a Bash root); review a mixed repo per root and name the roots. Print roots and file count.

#### Evidence anchors

Collect `file:line` anchors with Glob/Grep/Read:

- **Build graph**: `target_link_libraries` scope keywords, `add_library` kinds, Meson `declare_dependency`, Python intra-package imports.
- **Header tiers**: `include/` vs `src/`, `internal/`, `detail/`; `install(FILES|DIRECTORY ...)` lists.
- **Visibility**: `-fvisibility=hidden`, `CXX_VISIBILITY_PRESET`, `VISIBILITY_INLINES_HIDDEN`, export macros, version scripts (`*.map`, `*.sym`).
- **Extension points**: `dlopen`, `register_*`, static registration tables, `[project.entry-points]`.
- **Concurrency and ownership**: event loops (`asyncio`, `epoll`/`kqueue`), thread/process pools, arenas, smart pointers, refcounts, `Py_INCREF`/`Py_DECREF`.
- **Python surface**: `__all__`, `__init__.py` re-exports, documented API pages.
- **Bash**: sourced `lib*.sh`/`common.sh` libraries, thin entry scripts, `case`-based subcommand dispatch.

#### Build-graph cycle check

If a configured build directory already exists, read its target graph (`cmake --graphviz` output, `meson introspect --targets`) for an exact cycle check. Never configure a build.

### Phase 2: Review (parallel)

Launch the architector (`subagent_type="system-developer:system-architector"`) and, with `--trust-boundaries`, the auditor (`subagent_type="system-developer:sys-security-auditor"`) in one message with the Agent tool.

#### Architector

"Read-only architecture review of `{scope}` (languages: {languages}; build system: {system}). Evidence: {anchors}. File list: {file_list}.
1. Detect the structural pattern plus its ownership and concurrency axes; give confidence (high/medium/low) with `file:line` evidence.
2. Grade against that pattern. Classes: cyclic target/package dependencies, leaked internal headers, accidental ABI exposure, ownership ambiguity, concurrency mismatch, boundary bypass, Python public-API drift (`__all__` vs docs). Each needs `file:line` (or target/module) and a severity: P0 structure broken or ABI break shipping, P1 fix before next release (any public API/ABI violation is ≥ P1), P2 should fix, P3 nice to have.
3. Give the smallest fix per violation with its ABI/API impact (none / additive MINOR / breaking MAJOR with SONAME bump).
4. End with the pattern's PR checklist, pass/fail per item.
Use your Architecture Review format. Don't edit any file. If the structure fits, say so."

#### Architector additions

- With `--pattern`, append to step 1: "The expected pattern is `{pattern}`; report a mismatch with the detected pattern as its own finding."
- For a Bash root, append to step 1: "Sourced libraries with a thin entry script or `case` dispatch indicate layered or plugin-registry structure; confidence is low." Add "cyclic `source`" to step 2's classes.
- With `--deep`, append: "Also give Deep Refactor deliverables: current→target map, incremental migration path (each phase independently buildable and testable), coexistence strategy including any ABI shim or facade that holds a published interface, and risk points. Text only."

#### Auditor prompt (`--trust-boundaries` only)

"Read-only trust-boundary review of `{scope}` (languages: {languages}). Evidence: {anchors}. For each boundary (ports/adapters, public API/ABI surface, FFI seams, plugin load points, process/IPC edges), state which side is trusted, what crosses it, and whether crossing data is validated there. Flag untrusted input reaching a parser, process spawn, path operation, or deserializer without validation. Don't edit any file. Return `{file, line, boundary, severity (P0-P3), why, fix}`, or say the boundaries are sound."

### Phase 3: Exported-symbol audit (`--abi` only)

Needs an already-built shared library; never build one. Without an artifact, note the skip and rely on Phase 1 visibility evidence.

List each library's dynamic symbols (Linux: `nm -D --defined-only` or `readelf --dyn-syms -W`; macOS: `nm -gU` or `otool -TV`) and diff them against the deliberate export surface from Phase 1 (export macros, version script, public headers). Each symbol exported but not in that surface is an accidental ABI exposure: P1, or P0 when it exposes an internal struct layout or a documented-private symbol. This can run while Phase 2 agents work.

### Phase 4: Synthesis

Merge the architector findings, the symbol delta, and any boundary findings; deduplicate on `{file, line}`, keeping the higher severity and clearer fix. Normalize to `{anchor, class, severity, why, fix, abi_impact}`, rank P0→P3, and print the Output Format.

## Output Format

One report, shown in three parts.

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
```

### Report: violations and checklist

```markdown
### Violations
| Anchor | Class | Severity | Why | Fix | ABI/API impact |
|--------|-------|----------|-----|-----|----------------|
| {file:line \| target} | {cyclic dep \| leaked internal header \| ABI exposure \| ownership ambiguity \| concurrency mismatch \| boundary bypass \| public-API drift} | P{n} | {what is broken} | {smallest fix} | {none \| additive (MINOR) \| breaking (MAJOR) — SONAME bump} |

### PR Checklist ({pattern})
- [ ] / [x] {pattern-specific item} — {pass/fail note}
```

### Report: optional blocks and next step

```markdown
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

| Missing tool | Install hint |
|--------------|--------------|
| `nm` / `readelf` / `objdump` | install binutils (`brew install binutils`, or your distro's `binutils`) |
| `otool` (macOS) | `xcode-select --install` |
| `cmake` (graph introspection) | `brew install cmake` |

### Ambiguous language
Route a scope that detection can't place to `system-developer:system-developer` and note it in the report.

## See Also

- `/system-developer:arch-select` — pick a target pattern when this review reports a severe mismatch.
- `/system-developer:fix-refactor` — apply the remediation this command recommends.
- `/system-developer:build-test` — the gate every applied fix must pass.
- `/system-developer:review-code` — line-level correctness and security review.
- `/system-developer:analyze-tech-debt` — quantify and prioritize the debt these violations represent.
