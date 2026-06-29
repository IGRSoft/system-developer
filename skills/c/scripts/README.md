# C skill scripts

Executable helpers for the `c/*` skills. Same conventions as
[`../../_shared/scripts/README.md`](../../_shared/scripts/README.md): `#!/usr/bin/env bash`,
`set -Eeuo pipefail`, macOS bash-3.2-safe, stdout by default, self-documenting
`--help`, no new runtime dependencies, shellcheck-clean, covered by a test under
`tests/`. SKILL.md files reference these by relative path, never symlink.

## Scripts

| Script | Purpose | Deps |
|--------|---------|------|
| `gen_checked_arithmetic.sh` | Emit a portable `checked_arithmetic.h` (C23 `ckd_*` with a GCC/Clang `__builtin_*_overflow` fallback). Mirrors `../modern-c/SKILL.md` § Checked Arithmetic. | bash, printf (emitted header needs C23 or GCC/Clang) |
