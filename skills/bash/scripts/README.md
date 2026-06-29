# Bash skill scripts

Executable helpers for the `bash/*` skills. Same conventions as
[`../../_shared/scripts/README.md`](../../_shared/scripts/README.md): `#!/usr/bin/env bash`,
`set -Eeuo pipefail`, macOS bash-3.2-safe, stdout by default, self-documenting
`--help`, no new runtime dependencies, shellcheck-clean, covered by a test under
`tests/`. SKILL.md files reference these by relative path, never symlink.

## Scripts

| Script | Purpose | Deps |
|--------|---------|------|
| `prologue_generator.sh` | Emit the defensive strict-mode prologue (optional version guard, INT/TERM traps, comments). Mirrors `bash-scripting/SKILL.md`. | bash, printf |
| `shellcheck_shfmt_scaffold.sh` | Emit `.shellcheckrc` / `.editorconfig` (and `--with-precommit` a pre-commit config) with the enforced flags. Mirrors `../bash-testing/references/shellcheck-shfmt.md`. | bash, printf |
| `probe_toolchain.sh` | Detect GNU vs BSD coreutils and emit portable shims (`sed_i`, `canonical`, epoch helpers). Mirrors `../bash-scripting/references/bash-versions-and-portability.md`. | bash, uname |
