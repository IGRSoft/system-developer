---
description: Select the structural, concurrency, and ownership pattern for a C, C++, Python, or Bash module or project
argument-hint: <feature, module, or path> [--lang c|cpp|python|bash] [--pattern NAME] [--deep] [--abi-stable] [--no-write]
allowed-tools: Read, Write, Glob, Grep, Bash
estimated-cost:
  min-tokens: 3000
  max-tokens: 18000
  model-distribution:
    haiku: 10%
    sonnet: 55%
    opus: 35%
---

# Architecture Selection
<!-- Updated: July 2026 -->

Pick the architecture for a new feature, module, or project — or validate one you already have in mind. The command captures the real constraints (language mix, build system, workload shape, lifetime shape, published surface, toolchain floor), then resolves them onto three axes: one structural pattern, one concurrency model, one ownership model.

The output is a concrete target/module layout with named public boundaries, a version-and-portability marker plus fallback for every recommendation, and the ABI/API impact stated up front. Nothing is implemented — the report lands in `.context/arch-selection.md` and the next step is yours.

[Extended thinking: Systems architecture is not one choice, it is three semi-independent ones, and collapsing them is where designs go wrong — "hexagonal" says nothing about who owns the buffer, and "thread pool" says nothing about whether the public header is an ABI promise. This command therefore forces the constraints to resolve on each axis separately, then layers the structural pattern over the concurrency and ownership picks. It also refuses to recommend a feature the project's toolchain cannot compile: every marker (`std::jthread` needs C++20, free-threading needs CPython 3.14+, `nameref` needs Bash 4.3+ on a macOS that ships 3.2) is probed against the actual build flags and carries a fallback. Migration work is gated separately — a rewrite plan only appears when a real migration, mixed pattern, or ABI break is in scope, and each of its phases must stand alone behind a green `/system-developer:build-test`.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **Resolve scope, language, and toolchain floor before recommending.** Run detection once via `skill: language-detection`, read the actual `-std=`/`requires-python`/`CMAKE_*_STANDARD` settings, and pass that same resolved context to every delegation. Do NOT let the architect re-derive scope.
2. **Answer all three axes, every time.** One structural pattern, one concurrency model, one ownership model. A recommendation missing an axis is incomplete — say "single-threaded, no concurrency axis needed" explicitly rather than omitting it.
3. **Every recommendation carries a version marker and a fallback.** State the standard/version each pick requires and what to do when the toolchain is older. Never recommend a feature the probed toolchain cannot build.
4. **Smallest structure wins.** Do NOT propose a pattern switch for a change the current structure still fits, and do NOT introduce a new runtime or build dependency (plugin loader, DI framework, new package manager) unless the constraints explicitly accept that trade-off or the repo already uses it.
5. **ABI/API impact is mandatory output.** Any change to a public struct layout, exported symbol, function signature, `enum` value, or documented Python surface is flagged as a potential break and routed through a semver-major plan. Never hand-wave it.
6. **Quick by default, Deep only on triggers.** Produce a Quick Recommendation unless `--deep` is set or a Deep trigger applies (migration, mixed patterns, ABI/API break, module-boundary change). Do NOT emit migration artifacts for a single-module greenfield pick.
7. **Recommend, never implement.** This command writes exactly one file, `.context/arch-selection.md`. It creates and edits no source, header, build file, or manifest.
8. **Never enter plan mode.** This command IS the procedure — execute it.

## Usage

```bash
# Greenfield feature, described in prose
/system-developer:arch-select "streaming zstd decoder with a stable C API for external consumers"

# An existing tree — detect the current pattern, then recommend
/system-developer:arch-select src/ingest

# Validate a pattern you already chose
/system-developer:arch-select src/drivers --pattern plugin/registry

# Force the language when detection is ambiguous (extensionless scripts, bare headers)
/system-developer:arch-select tools/ --lang bash

# Migration scope: emit incremental phases, coexistence, and risk points
/system-developer:arch-select src/core --deep

# Library with external linkers/importers: force the full ABI/API section
/system-developer:arch-select libparse/ --abi-stable

# Print the report without writing .context/arch-selection.md
/system-developer:arch-select "per-request arena for the HTTP parser" --no-write
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `scope` | required | A prose description of the feature, or a path to an existing module/project. A path enables pattern detection and a real toolchain probe; prose does not. |
| `--lang c\|cpp\|python\|bash` | auto | Force the language instead of detecting. Use for extensionless scripts, bare `.h` headers, or to narrow a mixed repo. |
| `--pattern NAME` | none | Validate a named pattern instead of recommending one. Output becomes fit/mismatch with reasons and, on mismatch, the closest fit and its trade-off. |
| `--deep` | off | Force Deep Refactor Mode: current-state assessment, target, incremental migration phases, coexistence strategy, risk points. Implied by migration/ABI-break scope. |
| `--abi-stable` | auto | Treat the module as publishing a C ABI or a Python public API. Forces the full API/ABI section and a semver plan. Auto-enabled when an installed header, SONAME, or `__all__` is detected. |
| `--no-write` | off | Print the report only; skip writing `.context/arch-selection.md`. |

## Constraint Capture

| Constraint | How to determine |
|-----------|-----------------|
| **Language mix & build system** | `skill: language-detection` over the scope: `CMakeLists.txt`/`meson.build`/`Makefile` → C/C++; `pyproject.toml`/`uv.lock` → Python; `*.sh`/`*.bats` → Bash; mixed → per-root |
| **Scope size** | Single library/module vs. multi-target vs. package boundary |
| **Workload shape** | I/O fan-out, CPU-bound, or mixed — drives the concurrency axis |
| **Lifetime shape** | Bulk/per-request, deterministic scope, shared graph, or crossing into Python — drives the ownership axis |
| **Published surface** | Does anything outside the repo link or import this? Installed headers, SONAME, `__all__`, entry points |
| **Extension needs** | Runtime-loadable drivers/codecs/entry points — a plugin/registry signal |
| **Dependency tolerance** | Existing `vcpkg.json` / `conanfile` / `[project.dependencies]` is the ceiling |
| **Toolchain floor** | `-std=` flags, `CMAKE_CXX_STANDARD`, `requires-python`, compiler version — caps what may be recommended |

If the scope is prose and a critical constraint is unknowable from the repo, ask the user before delegating. Do not invent constraints.

## Structural Patterns

| Pattern | Best for | Anchor |
|---------|----------|--------|
| **Layered libraries** | Default for C/C++; a public-header tier over implementation tiers with acyclic deps | `skill: build-systems` (targets, `PUBLIC`/`PRIVATE` link scope) |
| **Hexagonal / ports-adapters** | Isolating I/O, OS, and device boundaries behind interfaces for testability | `skill: ffi-interop` (boundary doctrine) |
| **Plugin / registry** | Runtime-extensible tools, codec/driver tables, `dlopen` modules, Python entry points | `skill: build-systems` (shared libs, visibility) |
| **Pipeline / dataflow** | Stream processors, compilers, ETL, filter chains with backpressure | `skill: python-concurrency`, `skill: cpp-concurrency` |

Pick one. The structural pattern layers **over** the two axes below — it does not imply either of them.

## Orthogonal Axes

Concurrency and ownership are chosen independently of each other and of the structural pattern.

### Concurrency Axis

| Model | Best for | Anchor |
|-------|----------|--------|
| **Event-loop** | I/O-bound, many connections — `asyncio`, `epoll`/`kqueue` reactors | `skill: python-concurrency § asyncio` |
| **Thread-pool** | CPU-bound work over shared memory — `std::jthread`, pthreads, 3.14 free-threading | `skill: cpp-concurrency`, `skill: c-memory-ownership` |
| **Process-pool** | Isolation, GIL avoidance on pre-3.14t, fault containment — `multiprocessing`, fork/exec | `skill: python-concurrency § subinterpreters` |

For C/C++, default to a thread pool for CPU work and a reactor for I/O fan-out. For Python, follow the decision table in `skill: python-concurrency`. Single-threaded is a valid answer — say so explicitly.

### Ownership Axis

| Model | Best for | Anchor |
|-------|----------|--------|
| **Arena / region** | Bulk-lifetime allocations, parsers, per-request scratch in C | `skill: c-memory-ownership § allocators-and-arenas` |
| **RAII / smart pointers** | Default for C++; deterministic cleanup, Rule of Zero | `skill: modern-cpp` |
| **Refcount** | Shared graphs with no single clear owner — `shared_ptr`, manual refcounts in C | `skill: c-memory-ownership` |
| **GC-boundary** | Python objects crossing into native code; who owns the `PyObject*` reference | `skill: ffi-interop § c-api-boundaries` |

State who frees, when, and on which error path — including the unwinding path.

## Version & Portability Markers

Every pick states its floor and a fallback. Probe the real toolchain in Phase 1; never assert.

| Feature | Requires | Fallback |
|---------|----------|----------|
| `std::jthread` / `stop_token` | C++20 | `std::thread` + atomic stop flag + explicit join |
| `std::expected` | C++23 | Error-code + out-param, or a vendored `expected` |
| Coroutine / `co_yield` pipeline stages | C++20 | Callback or explicit state machine |
| Free-threading (no GIL) | CPython 3.14+ (`3.14t`) | Process pool or `InterpreterPoolExecutor` |
| Subinterpreter pools | CPython 3.13+ | `multiprocessing` pool |
| C23 `constexpr`, `typeof`, `nullptr` | C23 (GCC 14+ / Clang 18+) | C17 equivalents (`enum`/macro, `__typeof__`, `NULL`) |
| `dlopen` plugin loading | POSIX (`LoadLibrary` on Windows) | Static registration table linked at build time |
| `epoll` / `kqueue` reactor | Linux / BSD-macOS respectively | Portable `poll(2)` layer behind the port interface |
| Bash `nameref`, assoc arrays | Bash 4.3+ (macOS ships 3.2) | POSIX-sh delimited data, or declare the 4.3+ requirement |

## API / ABI Impact

| Concern | Rule |
|---------|------|
| **Semver** | MAJOR on any source- or binary-incompatible change; MINOR additive; PATCH fixes. Shared libraries track a SONAME/ABI version separate from the marketing version. |
| **Symbol visibility** | Default-hidden (`-fvisibility=hidden`), export deliberately. A visible symbol is an ABI promise; an accidentally-exported internal is a future break. |
| **`extern "C"` boundaries** | Plain C types only, no exceptions or STL across the seam, opaque handles over exposed structs. |
| **Stable C ABI over C++** | Any library with external or cross-toolchain consumers gets a C facade — the C++ ABI is fragile across compilers and standard-library versions. |
| **Python public API** | The public surface is what `__all__` and the docs promise. Deprecate before removal; move `pyproject.toml` version and the API contract together. |

ABI breaks are silent at compile time and lethal at load time. Flag them; do not bury them in prose.

## Detecting an Existing Pattern

When the scope is a path, classify what is already there before proposing anything.

| Signal | Pattern |
|--------|---------|
| Public-header dir + acyclic targets, `PUBLIC`/`PRIVATE` link scope | Layered libraries |
| Interface headers / ABCs (`Protocol`, pure-virtual) wrapping I/O, OS, device calls | Hexagonal / ports-adapters |
| Registration tables, `dlopen`/`LoadLibrary`, `register_*` callbacks, entry-point groups | Plugin / registry |
| Stage structs chained by queues or generators; `yield`/`co_yield` producers | Pipeline / dataflow |
| `asyncio`/`epoll`/`kqueue`, single-threaded reactor, `await` fan-out | Event-loop |
| `std::jthread`/thread pool, pthreads, `ThreadPoolExecutor`, `Py_mod_gil` slots | Thread-pool |
| `multiprocessing`, `fork`/`exec`, `InterpreterPoolExecutor` | Process-pool |
| Arena/region/bump allocator, per-request scratch, bulk `free` | Arena / region |
| `unique_ptr`/`shared_ptr`, Rule of Zero, no naked `new`/`delete` | RAII |
| Manual `retain`/`release`, refcount fields, `Py_INCREF`/`Py_DECREF` at the seam | Refcount / GC-boundary |

A detected pattern that still fits is a valid recommendation — report "keep current structure" and stop.

## Workflow

### Phase 1: Resolve Scope, Language, and Toolchain

1. Decide whether `scope` is a path or prose. A path that does not exist → Error Handling.
2. For a path, detect languages and build system via `skill: language-detection`; `--lang` overrides. Exclude `build/`, `builddir/`, `.venv/`, vendored trees.
3. Probe the toolchain floor: grep the build files for `-std=`, `CMAKE_C_STANDARD`/`CMAKE_CXX_STANDARD`, `cpp_std`, and `requires-python`; run `cmake --version` / `python3 --version` / `bash --version` where a version is load-bearing. Record what is unknown as unknown.
4. Detect the published surface (installed headers, SONAME/`VERSION` target properties, `__all__`, entry points). If found, enable `--abi-stable`.
5. Print the resolved scope, languages, build system, and toolchain floor before delegating.

### Phase 2: Capture Constraints

Fill the Constraint Capture table from Phase 1 plus the argument. Ask the user for any critical constraint that is neither in the repo nor in the prose — workload shape and published surface are the two that most often change the answer. Decide the mode: Deep if `--deep`, a migration, mixed patterns, an ABI/API break, or a module-boundary change is in scope; Quick otherwise.

### Phase 3: Select the Pattern

**Use Task tool with subagent_type="system-developer:system-architector"**
Prompt: "Select the architecture for this scope. Scope: {resolved scope}. Languages: {languages}. Build system: {system}. Toolchain floor: {std flags / requires-python / compiler versions, or 'unknown'}. Constraints: {constraint table}. Mode: {Quick Recommendation | Deep Refactor}. {If --pattern: 'The user proposes {NAME} — validate fit and report fit/mismatch with 1-2 reasons; on mismatch give the closest fit and its trade-off.' Else: 'Recommend the best fit with 1-2 reasons.'} Answer all three axes: one structural pattern, one concurrency model, one ownership model — say 'single-threaded, no concurrency axis' if that is the answer. For each pick, state the version/portability marker and a fallback, verified against the toolchain floor above. Apply your Guardrails: smallest viable structure, no new runtime or build dependency unless the constraints accept it. Use Output Format 'For Architecture Selection'."

### Phase 4: Structure and Boundaries

**Use Task tool with subagent_type="system-developer:system-architector"**
Prompt: "For the selected architecture ({pattern} / {concurrency} / {ownership}) produce the concrete layout for: {scope}. Include the directory and build-target layout with project-specific names (libraries, public-header dir, packages, modules), the key types/interfaces/ports, the extension and injection points, symbol visibility, and the test seams the structure creates. Build system: {system}. State the public API/ABI surface explicitly and, if `--abi-stable`, the semver plan for any change to it. Do not write or edit any source, header, or build file — return the layout only."

### Phase 5: Migration Plan (Deep mode only)

Skip entirely in Quick mode.

**Use Task tool with subagent_type="system-developer:system-architector"**
Prompt: "Produce a migration plan from the detected current state ({detected pattern / axes}) to the target ({pattern} / {concurrency} / {ownership}) for {scope}. Use Output Format 'For Migration Planning': current→target map, ordered incremental phases where each phase is independently buildable and testable behind a green `/system-developer:build-test` run, a coexistence strategy (ABI shim or facade where a published interface must hold), and the risk points — ABI/API compatibility, lifetime/ownership transfer, concurrency invariants, build-graph cycles. Do not apply any change."

### Phase 6: Report

Emit the Output Format. Unless `--no-write`, write it to `.context/arch-selection.md` (create `.context/` if absent). Then offer — do not perform — the next step: scaffold the layout, or run `/system-developer:develop-feature` against it.

## Output Format

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
| Ownership | {arena / RAII / refcount / GC-boundary} | {1 reason} |

**Fit:** {fit | mismatch}{, on mismatch: closest fit + trade-off}
**Detected today:** {current pattern with file:line evidence, or "greenfield"}

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

### Missing critical constraint
Ask the user directly rather than guessing — name the constraint, why it changes the answer, and the two or three options. Do not delegate with an invented value.

### Published ABI with a breaking change in scope
```
Warning: {scope} publishes a {C ABI | Python public API} and the requested change is binary/source incompatible.
The recommendation includes a semver-MAJOR plan and a facade/shim option; it will not silently break consumers.
```

### Ambiguous language
Apply `skill: language-detection` tie-breaks (bare `.h` counts as C unless C++ markers exist; shebang decides extensionless scripts). If still ambiguous, route the selection through `system-developer:system-developer` and note the routing in the report.

## See Also

- `skill: language-detection` — canonical marker → language → agent routing used by Phase 1.
- `skill: build-systems` — target layout, `PUBLIC`/`PRIVATE` link scope, shared-library visibility.
- `skill: ffi-interop` — `extern "C"` seams, `PyObject*` ownership at the GC boundary.
- `skill: c-memory-ownership`, `skill: modern-cpp` — the ownership-axis playbooks.
- `skill: python-concurrency`, `skill: cpp-concurrency` — the concurrency-axis decision tables.
- `skill: version-feature-matrix` — which standard/runtime version gates each feature marker.
- `/system-developer:arch-review` — review an existing tree against the selected pattern.
- `/system-developer:build-test` — the green gate every migration phase must clear.
- `/system-developer:gen-tests` — build the test seams the chosen structure creates.
- `/system-developer:develop-feature` — implement against the selected architecture.

Recommend the smallest structure that fits. If the current one already fits, say so.
