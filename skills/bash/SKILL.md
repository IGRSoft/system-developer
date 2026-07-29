---
name: bash-skills
description: >-
  Bash and POSIX shell skills navigation. Use when writing or reviewing
  shell scripts, choosing between Bash and POSIX sh, hardening a script
  with strict mode and traps, deciding when a task has outgrown shell,
  looking up a Bash 5.2/5.3 feature, or setting up shellcheck/shfmt/bats.
---

# Bash Skills

**Navigation and language-selection for Bash and POSIX shell scripting**

## When to Use Bash At All

Shell is glue: launching processes, wiring pipelines, filesystem plumbing, CI
steps. The moment a script grows past that, reach for a real language.

| Signal | Stay in shell | Leave shell |
|--------|---------------|-------------|
| Script length | < ~100 lines | > ~100 lines → consider Python |
| Data shape | lines, files, exit codes | structured data (JSON/CSV/nested) → Python |
| Arithmetic / floats | integer counters | floating point, stats → Python |
| Logic | linear, few branches | nested state, many data structures → Python |
| Parsing | `case`, `getopts`, field splitting | grammars, JSON, XML → Python (`json`, `argparse`) |
| Portability target | any Unix box, no runtime | needs a guaranteed interpreter → Python |

Rule of thumb: **a script over ~100 lines, or one that needs to parse or emit
structured data, should be Python** (`Task(system-developer:python-developer)`),
not Bash. Shell shines for orchestration; it is a poor data-processing language.

## Bash vs POSIX sh

| Use | When |
|-----|------|
| **Bash** (`#!/usr/bin/env bash`) | Default. You control the interpreter; want arrays, `[[ ]]`, `local`, `mapfile`, process substitution. |
| **POSIX sh** (`#!/bin/sh`) | Init scripts, container entrypoints (Alpine/BusyBox `ash`, Debian `dash`), `configure`-style portability, no Bash guaranteed. |

Never write `#!/bin/bash` for portable scripts: on macOS that is **Bash 3.2**
(frozen at the last GPLv2 release). Use `#!/usr/bin/env bash` plus a version
guard so the script finds a modern Bash (Homebrew installs 5.x to
`/opt/homebrew/bin`) and fails loudly on 3.2 instead of misbehaving silently.

```bash
#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 5)); then
  printf 'error: bash >= 5.0 required (found %s)\n' "$BASH_VERSION" >&2
  exit 1
fi
```

## Skill Selection Guide

| I need to... | Use this skill |
|--------------|----------------|
| Write or harden a script (strict mode, traps, quoting) | [bash-scripting/SKILL.md](bash-scripting/SKILL.md) |
| Look up `set -e` caveats, locking, retries, logging | [bash-scripting/references/defensive-patterns.md](bash-scripting/references/defensive-patterns.md) |
| Check a Bash 5.2/5.3 feature or write a POSIX fallback | [bash-scripting/references/bash-versions-and-portability.md](bash-scripting/references/bash-versions-and-portability.md) |
| Write or run tests | [bash-testing/SKILL.md](bash-testing/SKILL.md) |
| Configure shellcheck / shfmt | [bash-testing/references/shellcheck-shfmt.md](bash-testing/references/shellcheck-shfmt.md) |

## Decision Tree

```
Shell task?
├── Over ~100 lines or structured data? → STOP, use Python (system-developer:python-developer)
├── Writing/hardening a script → bash-scripting/SKILL.md
│   ├── Strict-mode / trap / locking details → references/defensive-patterns.md
│   └── Version feature or POSIX fallback → references/bash-versions-and-portability.md
├── Testing a script → bash-testing/SKILL.md
│   └── bats / shellcheck / shfmt → bash-testing/references/
└── Migrating / modernizing → /system-developer:fix-modernize
```

## Version Snapshot

| Version | Where | Headline |
|---------|-------|----------|
| 5.2 | most current Linux distros, Homebrew | `patsub_replacement` (`&` reuse in `${var/pat/rep}`), `varredir_close` |
| 5.3 | current stable — widely shipped in distros and Homebrew | `${ cmd; }` no-fork command substitution, `GLOBSORT` ordering control |
| 3.2 (fallback) | **macOS `/bin/bash`** (frozen) | none of the above — target POSIX sh or `#!/usr/bin/env bash` + version guard |

Canonical toolchain minimums: [version-feature-matrix](../_shared/version-feature-matrix.md).

## Related Skills

- [bash-scripting](bash-scripting/SKILL.md) — strict-mode prologue, quoting, traps, defensive patterns
- [bash-testing](bash-testing/SKILL.md) — bats-core, shellcheck, shfmt gate
- [secure-coding](../_shared/secure-coding/SKILL.md) — no-`eval`, `--` separators, command-injection defense
- [python-tooling](../python/python-tooling/SKILL.md) — when a script has outgrown shell
