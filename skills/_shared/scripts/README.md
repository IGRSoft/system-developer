# Shared skill scripts

Executable helpers shared across more than one `system-developer` skill. Skills
reference them by relative path (e.g. `../../_shared/scripts/sanitizer_flags.sh`)
or `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/<name>` — **never** by symlink
(symlinks break in plugin packaging and on case-insensitive/Windows checkouts).

These exist for **token efficiency**: a `SKILL.md` body loads into context on
every trigger, but a `scripts/` file does not. Moving deterministic, copy-paste
content (flag sets, scaffolds, probes) into a script lets the model *run* it
instead of loading the prose and re-typing it. Each script's source-of-truth
prose is named in its header comment; keep the two in sync.

## Conventions

- `#!/usr/bin/env bash`, `set -Eeuo pipefail`, **macOS bash-3.2-safe** (no
  associative arrays / `mapfile`). Python helpers: 3.12+ **stdlib only**.
- **stdout by default**; writing a file is opt-in via `--output FILE`.
- **Self-documenting `-h`/`--help`** (NAME/USAGE/OPTIONS/EXAMPLES/EXIT CODES/
  DEPENDENCIES) so the source need never be read to invoke it.
- **No new runtime dependencies** beyond what the skill already assumes.
- shellcheck/`shfmt` clean (Bash) or ruff/mypy clean (Python); covered by a test
  under `tests/`.

## Scripts

| Script | Lang | Purpose | Deps |
|--------|------|---------|------|
| `sanitizer_flags.sh` | bash | Emit canonical ASan/UBSan/TSan/MSan compile + link flags, runtime `*_OPTIONS`, or a CMakePresets/Makefile fragment. Mirrors `tooling/diagnostics/SKILL.md` § Copy-Paste Flag Sets. | bash, printf |
| `detect_language.py` | python | Route a repo to a language agent (c/cpp/python/bash/router) via the marker/census rules. Mirrors `_shared/language-detection.md`. | python 3.12+ (stdlib), git (optional) |
| `injection_audit.sh` | bash | Heuristic scan for command-injection / dynamic-code-exec patterns in C/C++/Python/Bash. Exits non-zero on findings. Mirrors `_shared/secure-coding/references/command-execution-and-injection.md`. | bash, grep, git (optional) |
| `check_toolchain_versions.sh` | bash | Probe installed tool versions against the plugin's floors; `--strict` gates CI. Mirrors `version-feature-matrix.md` § Build/Toolchain Floor. | bash, awk, grep |
| `scaffold_cmake_preset.sh` | bash | Emit a CMakePresets.json v6 (configure/build/test, Ninja, export compile commands, C++ standard, optional `--vcpkg`). Mirrors `tooling/build-systems/SKILL.md`. | bash, printf |
| `check_feature_support.sh` | bash | Probe whether the toolchain supports a C/C++/Python/Bash feature (feature-test macro, compile probe, or version compare). `--list` for names. Mirrors `version-feature-matrix.md`. | bash, awk; a compiler/python3 for those probes |
| `wrap_lint_command.sh` | bash | Run a linter/formatter (ruff/ruff-format/mypy/shellcheck/shfmt/clang-format/clang-tidy) with the plugin's canonical flags; `--fix`/`--strict`. | bash + the chosen tool |
