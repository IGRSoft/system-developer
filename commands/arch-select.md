---
description: Select the structural, concurrency, and ownership pattern for a C, C++, Python, or Bash module or project
argument-hint: <feature, module, or path> [--lang c|cpp|python|bash] [--pattern NAME] [--deep] [--abi-stable] [--no-write]
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
estimated-cost:
  min-tokens: 3000
  max-tokens: 18000
  model-distribution:
    haiku: 10%
    sonnet: 55%
    opus: 35%
---

# Architecture Selection

Pick the architecture for a new feature, module, or project, or validate one the user already has in mind. You capture the real constraints (language mix, build system, workload shape, lifetime shape, published surface, toolchain floor); `system-developer:system-architector` resolves them onto three separate axes: one structural pattern, one concurrency model, one ownership model. They are chosen independently because "hexagonal" says nothing about who owns the buffer, and "thread pool" says nothing about whether the public header is an ABI promise.

The output is a concrete target/module layout with named public boundaries, a version marker plus fallback for every pick, and the ABI/API impact stated up front. Nothing is implemented.

## Rules

### Selection rules

- Resolve scope, language, and toolchain floor once, before delegating, and pass that context to the architector so it doesn't re-derive it.
- Answer all three axes every time. If no concurrency is needed, say "single-threaded" rather than omitting the axis.
- Every pick carries its required standard/version and a fallback. Don't recommend a feature the probed toolchain can't build.
- Smallest structure wins. No pattern switch for a change the current structure still fits, and no new runtime or build dependency (plugin loader, DI framework, new package manager) unless the constraints accept it or the repo already uses it. A detected pattern that still fits is a valid answer: "keep current structure".

### Scope and output rules

- Flag any change to a public struct layout, exported symbol, function signature, `enum` value, or documented Python surface as a potential break with a semver-major plan.
- Quick Recommendation by default; Deep Refactor only with `--deep` or when a migration, mixed patterns, an ABI/API break, or a module-boundary change is in scope. No migration artifacts for a single-module greenfield pick.
- Write only `.context/arch-selection.md`. Create or edit no source, header, build file, or manifest.

## Usage

```bash
/system-developer:arch-select "streaming zstd decoder with a stable C API for external consumers"  # greenfield, prose
/system-developer:arch-select src/ingest                          # detect current pattern, then recommend
/system-developer:arch-select src/drivers --pattern plugin/registry  # validate a chosen pattern
/system-developer:arch-select tools/ --lang bash                  # extensionless scripts
/system-developer:arch-select src/core --deep                     # migration phases, coexistence, risks
/system-developer:arch-select libparse/ --abi-stable              # force the full ABI/API section
/system-developer:arch-select "per-request arena for the HTTP parser" --no-write  # print only
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `scope` | required | Feature prose, or a path to an existing module/project. A path also enables pattern detection and a toolchain probe. |
| `--lang c\|cpp\|python\|bash` | auto | Force the language for extensionless scripts, bare `.h` headers, or a mixed repo. |
| `--pattern NAME` | none | Validate a named pattern: fit/mismatch with reasons, plus the closest fit and its trade-off on mismatch. Known: `layered`, `hexagonal` (ports-adapters), `plugin/registry`, `pipeline` (dataflow). |
| `--deep` | off | Force Deep Refactor (current state, target, migration phases, coexistence, risks). Implied by migration/ABI-break scope. |
| `--abi-stable` | auto | Treat the module as publishing a C ABI or Python public API: full API/ABI section plus a semver plan. Auto-on for a detected installed header, SONAME, or `__all__`. |
| `--no-write` | off | Print only; don't write `.context/arch-selection.md`. |

## Version Markers

Check every marker the architector returns against the probed floor. Common ones:

### C and C++

| Feature | Requires | Fallback |
|---------|----------|----------|
| `std::jthread` / `stop_token` | C++20 | `std::thread` + atomic stop flag + explicit join |
| `std::expected` | C++23 | Error code + out-param, or a vendored `expected` |
| Coroutine (`co_yield`) pipeline stages | C++20 | Callback or explicit state machine |

### Python, Bash, and platform

| Feature | Requires | Fallback |
|---------|----------|----------|
| Free-threading (no GIL) | CPython 3.14+ (`3.14t`) | Process pool or `InterpreterPoolExecutor` |
| Subinterpreter pools | CPython 3.13+ | `multiprocessing` pool |
| C23 `constexpr`, `typeof`, `nullptr` | C23 (GCC 14+ / Clang 18+) | C17 equivalents (`enum`/macro, `__typeof__`, `NULL`) |
| `dlopen` plugin loading | POSIX (`LoadLibrary` on Windows) | Static registration table linked at build time |
| `epoll` / `kqueue` reactor | Linux / BSD-macOS | Portable `poll(2)` layer behind the port interface |
| Bash `nameref`, assoc arrays | Bash 4.3+ (macOS ships 3.2) | POSIX-sh delimited data, or declare the 4.3+ requirement |

## Workflow

### Phase 1: Resolve scope, language, and toolchain

1. Decide whether `scope` is a path or prose. A missing path → Error Handling.
2. For a path, detect languages and build system from manifests, extensions, and shebangs (`--lang` overrides; a CMake/Meson tree with only `.c`/`.h` sources is C; a bare `.h` is C unless the tree has C++ sources or `CMAKE_CXX_STANDARD`). Exclude `build/`, `builddir/`, `.venv/`, and vendored trees.
3. Probe the toolchain floor: grep build files for `-std=`, `CMAKE_C_STANDARD`/`CMAKE_CXX_STANDARD`, `cpp_std`, `requires-python`; run `cmake --version` / `python3 --version` / `bash --version` where a version matters. Record unknowns as unknown.
4. Detect the published surface (installed headers, SONAME/`VERSION` target properties, `__all__`, entry points). If found, enable `--abi-stable`.
5. Print the resolved scope, languages, build system, and toolchain floor.

### Phase 2: Capture constraints

Fill in: language mix and build system; scope size (single module, multi-target, package boundary); workload shape (I/O fan-out, CPU-bound, mixed); lifetime shape (bulk/per-request, deterministic scope, shared graph, crossing into Python); published surface; extension needs (runtime-loadable drivers, codecs, entry points); dependency tolerance (existing `vcpkg.json`/`conanfile`/`[project.dependencies]` is the ceiling); toolchain floor.

If a constraint that changes the answer is neither in the repo nor in the prose (workload shape and published surface most often), ask the user: name it, why it matters, and the two or three options. Don't delegate with an invented value. Then set the mode (Quick or Deep, per Rules).

### Phase 3: Select and lay out

Use the Agent tool with `subagent_type="system-developer:system-architector"`. If language detection stayed ambiguous, route this through `system-developer:system-developer` instead and note the routing in the report.

#### Architector prompt

"Select the architecture for {scope}. Languages: {languages}. Build system: {system}. Toolchain floor: {std flags / requires-python / compiler versions, or 'unknown'}. Constraints: {constraints}. Mode: {Quick Recommendation | Deep Refactor}. Recommend the best fit with 1-2 reasons.
Answer all three axes: one structural pattern, one concurrency model (or 'single-threaded'), one ownership model. For C/C++ state who frees, when, and on which error path.
For each pick give the version marker and a fallback, verified against the floor above. Add no runtime or build dependency unless the constraints accept it.
Give the concrete directory and build-target layout with project-specific names, key types/interfaces/ports, extension and injection points, symbol visibility, and the test seams the structure creates. State the public API/ABI surface and break risk.
Use your 'For Architecture Selection' output format. Don't write or edit any file."

#### Prompt additions

- For a path scope, append to the first paragraph: "Detect the current pattern and axes with file:line evidence; if it still fits, recommend keeping it."
- With `--pattern`, replace "Recommend the best fit with 1-2 reasons." with: "The user proposes {NAME}; report fit/mismatch with 1-2 reasons and, on mismatch, the closest fit and its trade-off."
- When the module is ABI-stable, extend the break-risk sentence: "State the public API/ABI surface and break risk, and the semver plan (with SONAME) for any change to it — the module is ABI-stable."
- In Deep mode, append: "Also use your 'For Migration Planning' format: current→target map, ordered phases each independently buildable and testable behind a green `/system-developer:build-test`, coexistence strategy (ABI shim or facade where a published interface must hold), and risk points (ABI/API compatibility, ownership transfer, concurrency invariants, build-graph cycles). Don't apply any change."

### Phase 4: Report

Check the markers against the floor (Version Markers table), then emit the Output Format. Unless `--no-write`, write it to `.context/arch-selection.md` (create `.context/` if absent). Offer, but don't perform, the next step: scaffold the layout, or run `/system-developer:develop-feature` against it.

## Output Format

One report, shown in three parts.

```markdown
## Architecture Selection: {scope}

**Mode:** {Quick Recommendation | Deep Refactor}
**Languages / build system:** {languages} / {system}
**Toolchain floor:** {std flags, requires-python, compiler versions, or "unknown — assumptions stated below"}

### Recommendation
| Axis | Choice | Why |
|------|--------|-----|
| Structure | {layered / hexagonal / plugin-registry / pipeline} | {1 reason} |
| Concurrency | {event-loop / thread-pool / process-pool / single-threaded} | {1 reason} |
| Ownership | {arena / RAII / refcount / GC-boundary / managed-runtime / process-scoped} | {1 reason} |

**Fit:** {fit | mismatch}{, on mismatch: closest fit + trade-off}
**Detected today:** {current pattern with file:line evidence, or "greenfield"}
```

### Report: layout and boundaries

```markdown
### Structure
{directory / build-target tree with real names}

### Key Boundaries
- **Public surface:** {headers, exported symbols, `__all__`, entry points}
- **Ports / interfaces:** {names and what they abstract}
- **Extension points:** {registration, injection}
- **Visibility:** {`-fvisibility=hidden` + export macro, or Python public/private split}

### Version & Portability Markers
| Pick | Requires | Fallback |
|------|----------|----------|
| {feature} | {standard/version} | {fallback} |

### API / ABI Impact
- **Break risk:** {none | source | binary} — {what changes}
- **Semver:** {MAJOR/MINOR/PATCH} {+ SONAME plan if a shared library}

### Test Seams
- {what the structure makes testable, and how to stub the ports}
```

### Report: migration and next steps

```markdown
<!-- Deep mode only: -->
### Migration
| Phase | Change | Green gate |
|-------|--------|-----------|
| 1 | {change} | /system-developer:build-test {path} |

**Coexistence:** {how old and new interoperate during transition}
**Risk points:** {ABI, ownership transfer, concurrency invariants, build cycles}

### Next Steps
1. {first step}
2. {second step}
3. {third step}
```

## Error Handling

### Path not found
```
Error: Path not found: {scope}
Suggestion: Pass an existing directory, or describe the feature in prose, e.g.
/system-developer:arch-select "streaming decoder with a stable C API"
```

### Prose scope — no toolchain to probe
```
Note: {scope} is a description, not a path — no build files to probe.
Toolchain floor is unknown; every version marker below is an assumption, stated explicitly.
Suggestion: re-run against the target directory once the project exists.
```

### No recognized sources under the path
```
Note: No C/C++/Python/Bash sources found under {scope}.
Treating this as greenfield. Pattern detection and toolchain probing are skipped.
Suggestion: pass --lang to pin the target language for the recommendation.
```

### Unknown `--pattern` value
```
Error: Unrecognized pattern: {NAME}
Known: layered, hexagonal (ports-adapters), plugin/registry, pipeline (dataflow);
axes: event-loop | thread-pool | process-pool, arena | raii | refcount | gc-boundary.
Suggestion: drop --pattern to get a recommendation instead.
```

### Published ABI with a breaking change in scope
```
Warning: {scope} publishes a {C ABI | Python public API} and the requested change is binary/source incompatible.
The recommendation includes a semver-MAJOR plan and a facade/shim option; it will not silently break consumers.
```

## See Also

- `/system-developer:arch-review` — review an existing tree against the selected pattern.
- `/system-developer:build-test` — the green gate every migration phase must clear.
- `/system-developer:gen-tests` — build the test seams the chosen structure creates.
- `/system-developer:develop-feature` — implement against the selected architecture.
