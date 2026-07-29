---
description: Audit, upgrade, or add C, C++, and Python dependencies — CVE and license report, then gated one-at-a-time upgrades
argument-hint: audit|upgrade|add [package] [--manager vcpkg|conan|fetchcontent|uv]
allowed-tools: Read, Edit, Glob, Grep, Bash, WebSearch, WebFetch
estimated-cost:
  min-tokens: 3000
  max-tokens: 18000
  model-distribution:
    haiku: 30%
    sonnet: 60%
    opus: 10%
---

# Dependency Lifecycle (audit / upgrade / add)
<!-- Updated: July 2026 -->

Three subcommands select the operation from the first argument, across the four package managers this plugin supports — vcpkg, Conan 2, CMake `FetchContent`, and uv:

- **`deps audit [--manager M]`** — outdated-versions report, CVE lookup, and license inventory. Read-only; changes nothing. See **Subcommand: `audit`** below.
- **`deps upgrade <package> [--manager M]`** — advance exactly one dependency, pin an exact version, and re-run the build and tests before the next. See **Subcommand: `upgrade`** below.
- **`deps add <package> [--manager M]`** — introduce a new pinned dependency to the right manifest. See **Subcommand: `add`** below.

**Dispatch**: parse the first token of `$ARGUMENTS`. `audit` → the `audit` subcommand with the remaining args as scope; `upgrade` → the `upgrade` subcommand with the next token as the package; `add` → the `add` subcommand with the next token as the package. **If the first token is absent or is not one of the three, default to `audit`** — the read-only path is always the safe fallback. `upgrade` and `add` without a package name are an error (see Error Handling); never guess which dependency the user meant.

[Extended thinking: Dependency changes are the highest-blast-radius edits in a systems project — one transitive bump can silently change ABI, drop a symbol, or pull in a CVE. This command separates read-only assessment (audit) from mutation (upgrade/add) and forces upgrades through a one-dependency, pin-exact, build-and-test-gated loop. Manifest discovery is shared with `skill: language-detection`; CVE lookup prefers a local `osv-scanner` and falls back to the osv.dev API; license inventory is best-effort and never blocks. Security findings are phrased in `igrsoft:security-review-process` vocabulary so they flow cleanly into an SR stage. The heavy reasoning — version-jump risk, breaking-change analysis, manifest edits — is delegated to `system-developer:sys-dependency-manager`; this command owns discovery, the gate loop, and reporting.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **Audit is strictly read-only.** In `audit` mode, do NOT edit any manifest, lockfile, or source. Discovery, queries, and reporting only. If the user wants changes, they re-run with `upgrade` or `add`.
2. **Upgrade ONE dependency at a time.** Never batch upgrades. Pin the new version to an *exact* version (not a range), then run the build+test gate (`/system-developer:build-test`) before proposing the next dependency. A failed gate stops the loop — report and wait.
3. **Pin exact, never float.** Every version this command writes is exact: a concrete vcpkg version + updated baseline, a Conan `pkg/x.y.z`, a `FetchContent` `GIT_TAG` pinned to a release tag (plus `GIT_SHALLOW TRUE`), or a uv lockfile-resolved pin. Never introduce `*`, `^`, `~`, `latest`, `main`, or an unpinned `GIT_TAG`.
4. **Single-command Bash invocations.** Use each tool's own directory flags (`vcpkg --x-manifest-root=DIR`, `conan` from the project via `--`-scoped args, `uv --project DIR`). Never `cd`-chain or `&&`-chain directory changes — scoped Bash patterns do not match compound commands.
5. **Tool-missing never hard-fails.** If a package manager or scanner binary is absent, print the install hint, skip that manager's pass, and continue with the others. Report what was skipped. A missing `osv-scanner` falls back to the osv.dev API via WebFetch — never skip the CVE pass silently.
6. **Delegate the reasoning, own the loop.** Hand version-jump risk, breaking-change analysis, and manifest edits to `system-developer:sys-dependency-manager`. This command performs discovery, runs the build+test gate, and synthesizes the report.
7. **Security findings use SR vocabulary.** Phrase every CVE/advisory finding in `igrsoft:security-review-process` terms (severity, CVE/advisory id, affected version range, fixed-in version, remediation) so the output is consumable by an SR stage.
8. **Never enter plan mode.** This command IS the procedure — execute it.

## Usage

```bash
# Read-only audit of the current project (auto-detect all managers)
/system-developer:deps audit

# Audit only the uv-managed Python dependencies
/system-developer:deps audit --manager uv

# Upgrade a single dependency one step, with a build+test gate
/system-developer:deps upgrade fmt --manager vcpkg

# Add a new pinned dependency to the detected manifest
/system-developer:deps add nlohmann-json --manager vcpkg
```

If no subcommand is given, default to `audit`.

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `audit` | (default) | Read-only: outdated report + CVE lookup + license inventory. No edits. |
| `upgrade <package>` | — | Advance one dependency one step; pin exact; run the build+test gate. `<package>` is required. |
| `add <package>` | — | Add a new pinned dependency to the detected (or `--manager`-selected) manifest. |
| `--manager vcpkg\|conan\|fetchcontent\|uv` | auto | Restrict to one package manager. Without it, every discovered manager is processed. |

## Manifest Discovery

Scan the project root (and one level of obvious subdirs: `cmake/`, `deps/`, `external/`) and record every manifest found. A repo may carry more than one — process each in `audit`; require `--manager` to disambiguate `upgrade`/`add` when several are present. The marker → language → owning-agent mapping is canonical in `skill: language-detection`; keep this discovery list in sync with it.

| Manager | Manifest(s) | Lock/pin artifact | Owning language |
|---------|-------------|-------------------|-----------------|
| vcpkg | `vcpkg.json` | `builtin-baseline` field + `overrides[]` (and `vcpkg-configuration.json`) | C / C++ |
| Conan 2 | `conanfile.txt` / `conanfile.py` | `conan.lock` | C / C++ |
| FetchContent | `FetchContent_Declare(...)` blocks in `CMakeLists.txt` / `*.cmake` | the pinned `GIT_TAG` itself | C / C++ |
| uv | `pyproject.toml` | `uv.lock` | Python |

Discovery details:

- **vcpkg:** the presence of `vcpkg.json` is authoritative. Read `dependencies[]`, `builtin-baseline`, and any `overrides[]`. The baseline commit fixes the version set; pinning happens via `overrides[]` + baseline, not loose version strings.
- **Conan 2:** `conanfile.py` (with a `requires`/`requirements()` block) or `conanfile.txt` (`[requires]` section). A committed `conan.lock` is the pin of record.
- **FetchContent:** grep for `FetchContent_Declare(` and parse each block's `GIT_REPOSITORY` + `GIT_TAG`. A `GIT_TAG` that is a branch name (`main`, `master`) or a moving ref is an unpinned dependency — flag it in audit as a supply-chain finding and offer to pin it to a release tag with `GIT_SHALLOW TRUE`.
- **uv:** `pyproject.toml` `[project].dependencies` / `[dependency-groups]`; `uv.lock` is the resolved pin set.

Auxiliary `requirements*.txt` or `setup.py` without a `uv.lock` is a non-uv Python project — note it and recommend `uv` migration, but only operate on it under `--manager uv` after `uv lock` materializes a lockfile.

## Subcommand: `audit` (read-only)

Produces three sections per discovered manager: **Outdated**, **Vulnerabilities (CVE)**, **Licenses**. No edits.

### Phase 1: Discover

Run Manifest Discovery. If `--manager` is set, keep only that manager. If nothing is found, emit the "no manifests" error and stop.

### Phase 2: Outdated Report (Bash, per manager)

Run the manager's outdated query, teeing nothing (read-only). Capture each tool's exit status, not a pipe's.

| Manager | Outdated query | Notes |
|---------|----------------|-------|
| uv | `uv pip list --outdated --project <path>` | Lists only outdated packages with current → latest. (`uv pip list --outdated` is the reliable outdated filter; `uv tree` shows the graph, not an outdated diff — verify against your toolchain.) |
| vcpkg | `vcpkg update --x-manifest-root=<path>` | Lists ports upgradeable relative to the current baseline. `vcpkg x-update-baseline --dry-run` previews what a baseline bump would move. |
| Conan 2 | `conan graph info <path> --format=json` | Dump the dependency graph (names + versions); compare against `conan search "<pkg>/*" -r=conancenter` for newer releases. |
| FetchContent | (no tool) | For each `GIT_TAG`, query the upstream for newer release tags via WebSearch/WebFetch (`<repo>/releases`). Compare the pinned tag to the latest release. |

If a manager's binary is missing, print its install hint (see Tool Availability), skip its outdated pass, and continue.

### Phase 3: CVE Lookup

Prefer a locally installed scanner; fall back to the osv.dev API. **Never skip this pass silently** — a missing scanner means fall back, not omit.

1. **If `osv-scanner` is installed**, run it against the lockfile/manifest:
   - uv: `osv-scanner --lockfile=uv.lock` (point at `<path>/uv.lock`).
   - vcpkg: `osv-scanner --lockfile=vcpkg.json` (osv-scanner understands the vcpkg manifest format; verify against your toolchain).
   - Conan: `osv-scanner --lockfile=conan.lock` where present.
   - FetchContent: no lockfile — fall back to the API path for each `(name, version)` pair.
2. **Python extra check:** if uv is present, also run `uv audit --project <path>` (uv 0.10.12+ reads the lockfile and queries OSV — verify the version against your toolchain) or `uvx pip-audit` as a fallback. Reconcile its findings with osv-scanner's; report the union, de-duplicated by advisory id.
   - **Standardized lockfile for scanners (PEP 751):** to feed a scanner that does not understand `uv.lock` natively, export the resolved set to the interoperable `pylock.toml` with `uv export --format pylock.toml --project <path> -o pylock.toml`, then point the scanner at it (e.g. `osv-scanner --lockfile=pylock.toml`). `pylock.toml` is the standardized, tool-agnostic lockfile (PEP 751, final) — prefer it when bridging to scanners or CI systems outside the uv ecosystem.
3. **Fallback when no scanner is installed:** for each discovered `(ecosystem, name, version)`, POST to the osv.dev API via WebFetch:
   - URL: `https://api.osv.dev/v1/query`
   - Body shape: `{"package": {"ecosystem": "<PyPI|...>", "name": "<name>"}, "version": "<version>"}`
   - Map ecosystems: Python → `PyPI`; native C/C++ deps from vcpkg/Conan/FetchContent → query by upstream project (osv.dev coverage for native libs is partial; cross-check the NVD via WebSearch when osv.dev returns nothing for a well-known native CVE). Verify coverage against your toolchain.
4. **Normalize every finding into SR vocabulary** (per `igrsoft:security-review-process`): `severity` (Critical/High/Medium/Low from CVSS), `advisory id` (CVE-/GHSA-/OSV-), `affected range`, `fixed-in version`, `remediation` (upgrade target). Group Critical/High at the top.

### Phase 4: License Inventory (best-effort)

Best-effort; never blocks the audit.

- uv: `uv pip show <pkg>` per package, or read `License`/`Classifier` metadata; for a full pass, `uvx pip-licenses` if available.
- vcpkg/Conan: read the `license` field from each port's manifest / recipe where exposed (`vcpkg.json` `license`, Conan `license` attribute).
- FetchContent: note "license not declared in manifest — verify upstream `LICENSE`."

Flag any GPL/AGPL/SSPL or otherwise copyleft-incompatible license against a permissive project as a review item (not a hard failure) — phrase it as a supply-chain / license-compatibility finding for SR.

### Phase 5: Delegate analysis & report

Hand the raw discovery + queries to the dependency manager for risk framing:

- **Use Task tool with subagent_type="system-developer:sys-dependency-manager"**
  Prompt: "Audit-mode dependency analysis for the project at `{path}`. Discovered managers: {managers}. Outdated report:\n```\n{outdated_output}\n```\nCVE findings (raw):\n```\n{cve_output}\n```\nLicenses:\n```\n{license_output}\n```\nFor each outdated dependency, classify the version jump (patch/minor/major), note documented breaking changes, and assess upgrade risk. Normalize every vulnerability into `igrsoft:security-review-process` vocabulary (severity, advisory id, affected range, fixed-in, remediation). Produce a prioritized upgrade plan (security patches first, then patch/minor, then majors individually). Do NOT edit any files — this is read-only audit."
- Synthesize the agent's analysis into the Output Format report.

## Subcommand: `upgrade` (one dependency, gated)

Advances exactly one dependency one step. This is the ported incremental-upgrade discipline: prep, pin exact, build+test gate, then stop.

### Phase 1: Resolve target

1. Require `<package>`. Run Manifest Discovery; if multiple managers are present, require `--manager` to disambiguate.
2. Run the relevant Phase 2/3 audit queries scoped to `<package>` to learn current version, latest version, and any open CVE.

### Phase 2: Plan the single step (delegate)

- **Use Task tool with subagent_type="system-developer:sys-dependency-manager"**
  Prompt: "Plan a single-step upgrade of `{package}` ({manager}) in the project at `{path}` from `{current}` toward `{target}`. If the jump crosses a major version, advance only ONE major (v1→v2, never v1→v3) and identify the exact next version to pin. Summarize documented breaking changes between `{current}` and the chosen target, list the manifest edits required (vcpkg `overrides[]` + baseline, Conan `requires` + `conan.lock`, FetchContent `GIT_TAG` to a release tag with `GIT_SHALLOW TRUE`, or uv pin), and produce the exact-version pin to write. Return the edits as a concrete diff plan; do not apply yet."

### Phase 3: Apply the pinned edit

Apply the agent's edit, pinning exactly per manager:

| Manager | Pin mechanism |
|---------|---------------|
| vcpkg | Set/refresh `builtin-baseline` and add an exact `overrides[]` entry `{"name": "<pkg>", "version": "<x.y.z>"}`; run `vcpkg x-update-baseline --x-manifest-root=<path>` to reconcile. |
| Conan 2 | Set `requires` to `pkg/x.y.z` (exact), then `conan lock create <path>` to regenerate `conan.lock`. |
| FetchContent | Set `GIT_TAG <release-tag-or-sha>` (a tag or full SHA, never a branch) and ensure `GIT_SHALLOW TRUE` in the `FetchContent_Declare` block. |
| uv | `uv lock --upgrade-package <pkg>==<x.y.z> --project <path>` (or pin in `pyproject.toml` then `uv lock`), producing an updated `uv.lock`. |

### Phase 4: Build + Test Gate (BINDING)

Run the project's full build and test suite via the shared workhorse:

- Invoke `/system-developer:build-test <path>` (single dependency upgraded).
- **Gate decision:**
  - **PASS** (configure + build + test all green) → report the successful step. Do NOT auto-continue to another dependency; the user re-runs `upgrade` for the next.
  - **FAIL** → STOP. Report the failing stage and the build-test triage. Offer to roll back the single edit (revert the manifest/lockfile change) and, if the failure is a code-level break from the new version, hand the excerpt to the owning language agent (`c-developer`/`cpp-developer`/`python-developer`) for a migration patch — then re-run the gate once.

### Phase 5: Report the step

Emit the Output Format "Upgrade Step" block with from→to, the gate result, and the next recommended dependency (but do not start it).

> Lockfile/pin changes (vcpkg baseline + `overrides[]`, `conan.lock`, FetchContent `GIT_TAG`, `uv.lock`) feed the RE stage — leave them gate-ready (exact-pinned, build+test-green) for the FN finalization gate.

## Subcommand: `add` (new pinned dependency)

### Phase 1: Resolve manager & manifest

Require `<package>` and a single target manifest (auto-detect, or `--manager`). If no manifest exists for the chosen manager, offer to scaffold the minimal one (`vcpkg.json`, `conanfile.txt`, a `FetchContent_Declare` block, or a `[project].dependencies` entry).

### Phase 2: Resolve a pinnable version

Look up the latest stable release of `<package>` (manager registry query or upstream releases via WebSearch/WebFetch) and the CVE status of that version (Phase 3 CVE lookup, scoped). Do not add a version with an unremediated Critical/High advisory without flagging it.

### Phase 3: Add, pinned exact (delegate the edit)

- **Use Task tool with subagent_type="system-developer:sys-dependency-manager"**
  Prompt: "Add `{package}` at exact version `{version}` to the {manager} manifest at `{path}`. Write the minimal pinned entry (vcpkg `dependencies` + `overrides` + baseline, Conan `requires` + lock, FetchContent `GIT_REPOSITORY`/`GIT_TAG <tag>` + `GIT_SHALLOW TRUE`, or uv `pyproject.toml` + `uv lock`). Return the edit; do not add transitive duplicates already present."

### Phase 4: Build + Test Gate

Run `/system-developer:build-test <path>`. PASS → report the addition. FAIL → roll back the addition and report.

## Tool Availability

Confirm each manager/scanner before its pass. Missing → print hint, skip that pass, continue. Never hard-fail.

| Missing tool | Install hint |
|--------------|--------------|
| `uv` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` (verify against your toolchain) |
| `vcpkg` | Clone `https://github.com/microsoft/vcpkg` and bootstrap, or `brew install vcpkg` (verify against your toolchain) |
| `conan` | `uv tool install conan` (Conan 2) or `pipx install conan` |
| `osv-scanner` | `brew install osv-scanner` (or `go install github.com/google/osv-scanner/cmd/osv-scanner@latest`) — without it, this command falls back to the osv.dev API |
| `pip-audit` (uv-audit fallback) | `uv tool install pip-audit` (used when `uv audit` is unavailable) |
| CMake (for FetchContent build gate) | `brew install cmake ninja` |

A missing `osv-scanner` triggers the osv.dev API fallback (WebFetch), not a skipped CVE pass.

## Output Format

```markdown
## Dependency Audit Report

**Target:** {path}
**Mode:** {audit | upgrade | add}
**Managers:** {vcpkg, conan, fetchcontent, uv — as discovered}

### Outdated

| Manager | Package | Current | Latest | Jump | Risk |
|---------|---------|---------|--------|------|------|
| uv | requests | 2.31.0 | 2.34.0 | minor | low |
| vcpkg | fmt | 10.1.1 | 11.0.2 | major | review breaking changes |
| fetchcontent | googletest | release-1.12.1 | v1.15.2 | major | retag + GIT_SHALLOW |

### Vulnerabilities (SR vocabulary)

| Severity | Advisory | Package | Affected | Fixed in | Remediation |
|----------|----------|---------|----------|----------|-------------|
| High | GHSA-xxxx-xxxx | <pkg> | <range> | <x.y.z> | upgrade to <x.y.z> |
| Medium | CVE-2026-NNNN | <pkg> | <range> | <x.y.z> | upgrade / mitigate |

(If none: "No known vulnerabilities in the queried versions via {osv-scanner | osv.dev | uv audit}.")

### Licenses

| Package | License | Note |
|---------|---------|------|
| <pkg> | MIT | compatible |
| <pkg> | GPL-3.0 | copyleft — review compatibility (SR item) |

### Prioritized Upgrade Plan
1. **Security first:** {pkg} {cur}→{fixed} (advisory {id})
2. {pkg} {cur}→{tgt} (patch/minor)
3. {pkg} major upgrades — individually, one at a time

<!-- upgrade/add modes only -->
### Upgrade Step
- **Package:** {pkg} ({manager})
- **From → To:** {current} → {target} (exact pin)
- **Manifest edits:** {files changed}
- **Build + Test gate:** PASS / FAIL ({failing stage})
- **Next recommended:** {pkg} (run `/system-developer:deps upgrade {pkg}`)

### Skipped
- {manager}: {missing tool} — install hint printed above.
```

## Error Handling

### No manifests found
```
Error: No dependency manifests detected under {path}.
Looked for: vcpkg.json, conanfile.txt/.py, FetchContent_Declare(...) in CMake, pyproject.toml/uv.lock.
Suggestion: Run from the project root, or scaffold a manifest with `add <package> --manager <m>`.
```

### Subcommand given without a package
```
Error: `{upgrade|add}` requires a package name.
Suggestion: /system-developer:deps {upgrade|add} <package> [--manager <vcpkg|conan|fetchcontent|uv>]
           Run `/system-developer:deps audit` first to see what is declared and outdated.
```

### Multiple managers, ambiguous upgrade/add
```
Error: {N} package managers present ({list}). upgrade/add need one.
Suggestion: Re-run with --manager <vcpkg|conan|fetchcontent|uv>.
```

### Package not found in manifest (upgrade)
```
Error: {package} is not a declared dependency of the {manager} manifest.
Suggestion: Use `add {package}` to introduce it, or check the spelling against the manifest.
```

### Unpinned FetchContent tag
```
Warning: FetchContent_Declare({name}) pins GIT_TAG to a branch ({ref}) — not reproducible.
Suggestion: pin to a release tag or full SHA with GIT_SHALLOW TRUE. Offer to apply in upgrade mode.
```

### Build+test gate failed after upgrade
Not silent. Report the failing stage from `/system-developer:build-test`, offer to roll back the single manifest edit, and (for a code-level break) route the excerpt to the owning language agent for a migration patch before re-running the gate once.

### Tool missing
Print the install hint, skip that manager's pass, continue. A missing `osv-scanner` falls back to the osv.dev API. The command only reports a hard FAIL when *every* eligible pass was skipped.

## See Also

- `skill: language-detection` — canonical manifest → language → agent routing (keep discovery in sync).
- `skill: build-systems` — FetchContent vs vcpkg vs Conan 2 trade-offs, CMake preset flow, baseline/lockfile idioms.
- `skill: secure-coding` — supply-chain and dependency-trust rules that gate a diff.
- `/system-developer:build-test` — the build+test gate this command invokes after every upgrade/add.
- `/system-developer:sanitize-check` — run after a dependency upgrade to catch ABI/behavior regressions a new version introduces.
- `igrsoft:security-review-process` — SR-stage vocabulary used for every vulnerability finding here.
