---
name: bash-skills
description: >-
  Bash and POSIX shell skills navigation. Use when writing or reviewing
  shell scripts, choosing between Bash and POSIX sh, deciding when a task
  has outgrown shell, looking up a Bash 5.2/5.3 feature, or setting up
  shellcheck/shfmt/bats.
---

# Bash Skills

Routes shell work to the right leaf skill and settles two choices first: whether to use shell at all, and Bash or POSIX sh.

## When to Leave Shell

Shell is glue: launching processes, pipelines, filesystem plumbing, CI steps. Move to Python (`system-developer:python-developer` agent, [python-tooling](../python/python-tooling/SKILL.md)) when any of these holds:

- the script passes ~100 lines or grows nested state and data structures
- it parses or emits structured data (JSON, CSV, XML) or needs a grammar beyond `case`/`getopts`
- it needs floating-point math or statistics

## Bash vs POSIX sh

| Use | When |
|-----|------|
| Bash (`#!/usr/bin/env bash`) | Default when you control the interpreter; gives arrays, `[[ ]]`, `local`, `mapfile`, process substitution |
| POSIX sh (`#!/bin/sh`) | Init scripts, container entrypoints (BusyBox `ash`, Debian `dash`), `configure`-style portability |

Avoid `#!/bin/bash` in portable scripts: macOS `/bin/bash` is frozen at 3.2. Use `#!/usr/bin/env bash` plus a `BASH_VERSINFO` guard (in the [bash-scripting](bash-scripting/SKILL.md) prologue) so a 3.2 run fails loudly instead of misbehaving.

## Skill Selection

| I need to... | Go to |
|--------------|-------|
| Write or harden a script (strict mode, traps, quoting) | [bash-scripting](bash-scripting/SKILL.md) |
| `set -e` caveats, locking, retries, logging | [defensive-patterns.md](bash-scripting/references/defensive-patterns.md) |
| A Bash 5.2/5.3 feature, POSIX fallback, or GNU vs BSD tools | [bash-versions-and-portability.md](bash-scripting/references/bash-versions-and-portability.md) |
| Write or run tests | [bash-testing](bash-testing/SKILL.md) |
| Configure shellcheck / shfmt | [shellcheck-shfmt.md](bash-testing/references/shellcheck-shfmt.md) |
| Block injection (no `eval`, `--` separators, quoting untrusted input) | [secure-coding](../_shared/secure-coding/SKILL.md) |
| Migrate or modernize an existing script | `/system-developer:fix-modernize` |

## Version Snapshot

Bash 5.2 is on most current distros (`patsub_replacement`, `varredir_close`); 5.3 adds `${ cmd; }` no-fork command substitution and `GLOBSORT`; macOS `/bin/bash` stays at 3.2 with none of these. Minimums: [version-feature-matrix](../_shared/version-feature-matrix.md).
