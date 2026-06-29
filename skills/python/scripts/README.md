# Python skill scripts

Executable helpers for the `python/*` skills. Same conventions as
[`../../_shared/scripts/README.md`](../../_shared/scripts/README.md): stdout by
default, self-documenting `--help`, no new runtime dependencies (bash 3.2+ /
Python 3.12+ stdlib), shellcheck/ruff clean, covered by a test under `tests/`.
SKILL.md files reference these by relative path, never symlink.

## Scripts

| Script | Lang | Purpose | Deps |
|--------|------|---------|------|
| `scaffold_pyproject.sh` | bash | Emit a PEP 621/735 `pyproject.toml` (`--package` library/CLI or `--app`) with a `[tool.ruff]` config. Mirrors `../python-tooling/SKILL.md`. | bash, printf |
| `ruff_modernize.sh` | bash | Run ruff's modernization set (`UP,B,SIM,C4,PIE,RUF`) at a target version; `--fix`. Mirrors `../python-tooling/SKILL.md` (ruff config). | bash, ruff |
| `scaffold_conftest.sh` | bash | Emit a pytest `conftest.py` skeleton (scoped fixtures; `--with-async` adds a pytest-asyncio fixture). Mirrors `../python-testing/SKILL.md`. | bash, printf |
