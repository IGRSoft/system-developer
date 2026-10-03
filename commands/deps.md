---
description: Audit, upgrade, or add C, C++, and Python dependencies — CVE and license report, then gated one-at-a-time upgrades
argument-hint: audit|upgrade|add [package] [--manager vcpkg|conan|fetchcontent|uv]
allowed-tools: Read, Edit, Glob, Grep, Bash, WebSearch, WebFetch, Agent, Skill
estimated-cost:
  min-tokens: 3000
  max-tokens: 18000
  model-distribution:
    haiku: 30%
    sonnet: 60%
    opus: 10%
---

# Dependency Lifecycle (audit / upgrade / add)

Assess or change dependencies across the four managers this plugin supports: vcpkg, Conan 2, CMake `FetchContent`, and uv. Dependency changes carry the widest blast radius in a systems project (one bump can change ABI, drop a symbol, or pull in a CVE), so read-only assessment is kept separate from mutation, and every mutation is one exact-pinned dependency behind a build+test gate. This command owns discovery, the gate, and the report; version-jump risk, breaking-change analysis, and manifest edits go to `system-developer:sys-dependency-manager`.

## Dispatch

Parse the first token of `$ARGUMENTS`:

- `audit [--manager M]`: outdated report, CVE lookup, license inventory. Read-only.
- `upgrade <package> [--manager M]`: advance one dependency one step, pin exact, run the gate.
- `add <package> [--manager M]`: add a new exact-pinned dependency.

An absent or unrecognized first token (empty, a bare path, a harmless word) defaults to `audit`, the safe path. Two exceptions stop with an error instead of falling back, because an audit result would read as "nothing to do" for work never attempted:

- `--upgrade` or `--add` anywhere in the arguments.
- `upgrade` or `add` without a package name. Don't guess which dependency the user meant.

## Rules

### Editing and pinning

- `audit` edits nothing: no manifest, lockfile, or source.
- One dependency per `upgrade` run. After the gate, report and stop; the user re-runs for the next. A failed gate stops the run.
- Every version written is exact: a vcpkg `overrides[]` version, Conan `pkg/x.y.z`, a FetchContent `GIT_TAG` release tag or full SHA, or a uv lockfile pin. Never `*`, `^`, `~`, `latest`, a branch, or an unpinned `GIT_TAG`.
- Use each tool's directory flag (`vcpkg --x-manifest-root=DIR`, `uv --project DIR`, a path argument for `conan`) instead of `cd` or `&&` chains; scoped Bash permissions don't match compound commands.

### Missing tools and reporting

- A missing manager or scanner never hard-fails: print its install hint, skip that pass, continue, and list it under Skipped. A missing `osv-scanner` means the osv.dev API fallback, not a skipped CVE pass. Report a hard FAIL only when every eligible pass was skipped.
- Phrase every vulnerability in SR terms: severity (Critical/High/Medium/Low from CVSS), advisory id (CVE-/GHSA-/OSV-), affected range, fixed-in version, remediation. Critical/High first.
- CLI flags and osv.dev coverage change between versions; where a command below is uncertain for the installed toolchain, check `--help` before relying on it.

## Usage

```bash
/system-developer:deps audit                          # all detected managers
/system-developer:deps audit --manager uv             # uv only
/system-developer:deps upgrade fmt --manager vcpkg    # one step, gated
/system-developer:deps add nlohmann-json --manager vcpkg
```

`--manager vcpkg|conan|fetchcontent|uv` restricts the run to one manager; without it, `audit` processes every discovered manager.

## Manifest Discovery

Scan the project root plus `cmake/`, `deps/`, `external/`. `audit` processes every manifest found; `upgrade`/`add` require `--manager` when more than one manager is present.

| Manager | Manifest(s) | Pin of record | Language |
|---------|-------------|---------------|----------|
| vcpkg | `vcpkg.json` (read `dependencies[]`, `builtin-baseline`, `overrides[]`) | baseline commit + `overrides[]` (and `vcpkg-configuration.json`) | C / C++ |
| Conan 2 | `conanfile.py` (`requires`/`requirements()`) or `conanfile.txt` (`[requires]`) | `conan.lock` | C / C++ |
| FetchContent | `FetchContent_Declare(...)` in `CMakeLists.txt` / `*.cmake` (parse `GIT_REPOSITORY` + `GIT_TAG`) | the `GIT_TAG` itself | C / C++ |
| uv | `pyproject.toml` (`[project].dependencies`, `[dependency-groups]`) | `uv.lock` | Python |

### Unpinned and non-uv projects

- A FetchContent `GIT_TAG` naming a branch (`main`, `master`) or other moving ref is unpinned: report it as a supply-chain finding and offer to pin it in `upgrade` mode.
- `requirements*.txt` or `setup.py` without `uv.lock` is a non-uv Python project: note it, recommend migrating to uv, and operate on it only under `--manager uv` after `uv lock` creates a lockfile.

## Subcommand: `audit`

Run discovery (filtered by `--manager`); if nothing is found, emit the "no manifests" error. Then, per manager:

### Outdated

| Manager | Query |
|---------|-------|
| uv | `uv pip list --outdated --project <path>` |
| vcpkg | `vcpkg x-update-baseline --dry-run --x-manifest-root=<path>` (what a baseline bump would move) |
| Conan 2 | `conan graph info <path> --format=json`, then `conan search "<pkg>/*" -r=conancenter` for newer releases |
| FetchContent | No tool: compare each `GIT_TAG` to the upstream's latest release via WebSearch/WebFetch (`<repo>/releases`) |

### CVEs: scanners

1. With `osv-scanner` installed, scan the lockfile: `osv-scanner --lockfile=<path>/uv.lock` or `conan.lock`. osv-scanner doesn't read `vcpkg.json`, and FetchContent has no lockfile; use the API path for their `(name, version)` pairs.
2. For uv, also run `uv audit --project <path>` (fallback `uvx pip-audit`) and report the union, de-duplicated by advisory id. For a scanner that doesn't read `uv.lock`, export the PEP 751 lockfile with `uv export --format pylock.toml --project <path> -o pylock.toml` and scan that.
### CVEs: osv.dev API fallback

3. Without a scanner, POST each `(ecosystem, name, version)` to `https://api.osv.dev/v1/query` via WebFetch with body `{"package": {"ecosystem": "PyPI", "name": "<name>"}, "version": "<version>"}`. Native C/C++ deps: query by upstream project; osv.dev coverage is partial, so cross-check the NVD via WebSearch when it returns nothing for a well-known library.

### Licenses

Best-effort; never blocks.

- uv: `uv pip show <pkg>` or `License`/classifier metadata; `uvx pip-licenses` for a full pass.
- vcpkg / Conan: the port manifest `license` field or recipe `license` attribute.
- FetchContent: "license not declared in manifest; verify upstream `LICENSE`."

GPL/AGPL/SSPL or other copyleft against a permissive project is a license-compatibility review item, not a failure.

### Analysis

Send the raw results to the dependency manager via the Agent tool:

- `subagent_type: "system-developer:sys-dependency-manager"`, prompt: "Audit-mode dependency analysis for the project at `{path}`. Managers: {managers}. Outdated:\n```\n{outdated_output}\n```\nCVE findings (raw):\n```\n{cve_output}\n```\nLicenses:\n```\n{license_output}\n```\nClassify each outdated dependency's jump (patch/minor/major), note documented breaking changes, and rate upgrade risk. Normalize each vulnerability to severity, advisory id, affected range, fixed-in, remediation. Return a prioritized upgrade plan: security fixes first, then patch/minor, then each major on its own. Read-only: edit no files."

Synthesize the result into the Output Format report.

## Subcommand: `upgrade`

1. **Resolve.** Require `<package>` and a single manager. Run the audit's outdated and CVE queries scoped to `<package>` to get current version, latest version, and open advisories.
2. **Plan** via the Agent tool, `subagent_type: "system-developer:sys-dependency-manager"`, prompt: "Plan a single-step upgrade of `{package}` ({manager}) in `{path}` from `{current}` toward `{target}`. Across majors, advance only one major (v1→v2, not v1→v3) and name the exact version to pin. Summarize documented breaking changes between `{current}` and that version, and return the manifest edits as a concrete diff plan with the exact pin. Don't apply it."
### Apply the pin

3. **Apply** the pin:

   | Manager | Pin mechanism |
   |---------|---------------|
   | vcpkg | Add or update an exact `overrides[]` entry `{"name": "<pkg>", "version": "<x.y.z>"}`. Leave `builtin-baseline` alone: bumping it moves every other port too. |
   | Conan 2 | Set `requires` to `pkg/x.y.z`, then `conan lock create <path>` to regenerate `conan.lock`. |
   | FetchContent | Set `GIT_TAG` to a release tag with `GIT_SHALLOW TRUE`, or to a full commit SHA without `GIT_SHALLOW` (shallow clones need a tag or branch). |
   | uv | `uv lock --upgrade-package <pkg>==<x.y.z> --project <path>` (or pin in `pyproject.toml` and run `uv lock`). |

### Gate and report

4. **Gate.** Run `/system-developer:build-test <path>`.
   - PASS: report the step and stop.
   - FAIL: report the failing stage and build-test's triage, and offer to revert the manifest/lockfile edit. If the new version broke code, send the excerpt to the owning language agent (`c-developer`, `cpp-developer`, `python-developer`) for a migration patch, then re-run the gate once.
5. **Report** the Upgrade Step block, naming the next recommended dependency without starting it.

## Subcommand: `add`

1. Require `<package>` and a single target manifest (auto-detected or `--manager`). If the manager has no manifest yet, offer to scaffold a minimal one (`vcpkg.json`, `conanfile.txt`, a `FetchContent_Declare` block, or a `[project].dependencies` entry).
2. Find the latest stable release (registry query or upstream releases via WebSearch/WebFetch) and run the CVE lookup for that version. Flag any unremediated Critical/High advisory before adding.
### Delegate and gate

3. Delegate the edit via the Agent tool, `subagent_type: "system-developer:sys-dependency-manager"`, prompt: "Add `{package}` at exact version `{version}` to the {manager} manifest at `{path}`: vcpkg `dependencies` + exact `overrides` entry, Conan `requires` + regenerated lock, FetchContent `GIT_REPOSITORY` + `GIT_TAG <tag>` + `GIT_SHALLOW TRUE`, or uv `pyproject.toml` + `uv lock`. Write the minimal pinned entry, skip transitive duplicates already present, and return the edit."
4. Run `/system-developer:build-test <path>`. PASS: report the addition. FAIL: revert the addition and report.

## Install Hints

| Tool | Hint |
|------|------|
| `uv` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| `vcpkg` | Clone `https://github.com/microsoft/vcpkg` and bootstrap, or `brew install vcpkg` |
| `conan` | `uv tool install conan` or `pipx install conan` |
| `osv-scanner` | `brew install osv-scanner` or `go install github.com/google/osv-scanner/cmd/osv-scanner@latest` (without it: osv.dev API) |
| `pip-audit` | `uv tool install pip-audit` (when `uv audit` is unavailable) |
| CMake (FetchContent gate) | `brew install cmake ninja` |

## Output Format

One report, shown in two parts.

```markdown
## Dependency Audit Report

**Target:** {path}
**Mode:** {audit | upgrade | add}
**Managers:** {vcpkg, conan, fetchcontent, uv — as discovered}

### Outdated

| Manager | Package | Current | Latest | Jump | Risk |
|---------|---------|---------|--------|------|------|
| vcpkg | fmt | 10.1.1 | 11.0.2 | major | review breaking changes |

### Vulnerabilities (SR vocabulary)

| Severity | Advisory | Package | Affected | Fixed in | Remediation |
|----------|----------|---------|----------|----------|-------------|
| High | GHSA-xxxx-xxxx | <pkg> | <range> | <x.y.z> | upgrade to <x.y.z> |

(If none: "No known vulnerabilities in the queried versions via {osv-scanner | osv.dev | uv audit}.")

### Licenses

| Package | License | Note |
|---------|---------|------|
| <pkg> | GPL-3.0 | copyleft — review compatibility (SR item) |
```

### Report: plan, upgrade step, and skips

```markdown
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

### Mutating mode passed as a flag
```
Error: `--upgrade` / `--add` is not a supported flag. Mutating modes are selected by the
first token only: `deps upgrade <package>` or `deps add <package>`.
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
Suggestion: pin to a release tag (with GIT_SHALLOW TRUE) or a full SHA. Offer to apply in upgrade mode.
```

## See Also

- `skill: build-systems`: FetchContent vs vcpkg vs Conan 2 trade-offs, baseline and lockfile idioms.
- `skill: secure-coding`: supply-chain and dependency-trust rules.
- `/system-developer:build-test`: the gate run after every upgrade/add.
- `/system-developer:sanitize-check`: catches ABI or behavior regressions a new version introduces.
