# Bash Skills Index

Quick navigation for the `skills/bash/` subtree. Start at [SKILL.md](SKILL.md)
for the guided entry with the Bash-vs-POSIX choice, the "leave shell" rule, and
the version snapshot.

## Skills

| Skill | Use it for |
|-------|------------|
| [bash-scripting/SKILL.md](bash-scripting/SKILL.md) | Strict-mode prologue, quoting rules, `[[ ]]`/`local`/`readonly`, traps, `mktemp`, `printf`, when NOT to use Bash |
| [bash-testing/SKILL.md](bash-testing/SKILL.md) | bats-core test layout, shellcheck/shfmt gate, mocking commands |

## References

| File | Use it for |
|------|------------|
| [bash-scripting/references/defensive-patterns.md](bash-scripting/references/defensive-patterns.md) | `set -e` caveat matrix, trap/signal interplay, safe temp files, `flock` locking, retries/timeouts, structured logging, `getopts` parsing |
| [bash-scripting/references/bash-versions-and-portability.md](bash-scripting/references/bash-versions-and-portability.md) | 5.2/5.3 feature catalog, bashism→POSIX `sh` fallback table, macOS 3.2 reality, `checkbashisms`, GNU vs BSD coreutils (`sed -i`) |
| [bash-testing/references/bats-patterns.md](bash-testing/references/bats-patterns.md) | bats-core idioms, `setup`/`teardown`, fixtures, command stubbing |
| [bash-testing/references/shellcheck-shfmt.md](bash-testing/references/shellcheck-shfmt.md) | `.shellcheckrc`, directive comments, `shfmt` flags, CI wiring |

## Cross-Tree

| Topic | Location |
|-------|----------|
| Toolchain minimums (canonical) | `${CLAUDE_SKILL_DIR}/_shared/version-feature-matrix.md` |
| Input validation, injection defense | `${CLAUDE_SKILL_DIR}/_shared/secure-coding/SKILL.md` |
| When a script outgrows shell → Python | `${CLAUDE_SKILL_DIR}/python/python-tooling/SKILL.md` |
| CI pipelines invoking shell | `${CLAUDE_SKILL_DIR}/tooling/build-systems/SKILL.md` |
