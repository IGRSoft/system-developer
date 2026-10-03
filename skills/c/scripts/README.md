# C skill scripts

Executable helpers for the `c/*` skills, following the conventions in
[`../../_shared/scripts/README.md`](../../_shared/scripts/README.md).

## Scripts

| Script | Purpose | Deps |
|--------|---------|------|
| `gen_checked_arithmetic.sh` | Emit a portable `checked_arithmetic.h` (C23 `ckd_*` with a GCC/Clang `__builtin_*_overflow` fallback). Mirrors `../modern-c/SKILL.md` § Checked Arithmetic. | bash, printf (emitted header needs C23 or GCC/Clang) |
