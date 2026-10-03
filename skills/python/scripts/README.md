# Python skill scripts

Executable helpers for the `python/*` skills, following the conventions in
[`../../_shared/scripts/README.md`](../../_shared/scripts/README.md).

## Scripts

| Script | Purpose | Deps |
|--------|---------|------|
| `scaffold_pyproject.sh` | Emit a PEP 621/735 `pyproject.toml` (`--package` library/CLI or `--app`) with a `[tool.ruff]` config. Mirrors `../python-tooling/SKILL.md`. | bash, printf |
| `ruff_modernize.sh` | Run ruff's modernization set (`UP,B,SIM,C4,PIE,RUF`) at a target version; `--fix`. Mirrors `../python-tooling/SKILL.md` (ruff config). | bash, ruff |
| `scaffold_conftest.sh` | Emit a pytest `conftest.py` skeleton (scoped fixtures; `--with-async` adds a pytest-asyncio fixture). Mirrors `../python-testing/SKILL.md`. | bash, printf |
