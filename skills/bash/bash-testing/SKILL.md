---
name: bash-testing
description: Test Bash scripts with bats-core and keep them lint-clean with ShellCheck and shfmt. Use when writing bats tests, designing sourceable/testable scripts, mocking commands via PATH stubs, or wiring shellcheck/shfmt into CI.
---

# Bash Testing, Linting, and Formatting

**Make shell scripts testable, prove behavior with bats-core, and gate quality with ShellCheck + shfmt.**

## When to Use

Use this skill when:

- Writing or reviewing `*.bats` tests for shell scripts or CLI tools.
- Refactoring a script so it can be sourced and unit-tested (function-per-behavior).
- Mocking external commands without touching production code (PATH stub dirs).
- Configuring `.shellcheckrc`, ShellCheck directives, or `shfmt` flags.
- Wiring `bats`, `shellcheck`, and `shfmt` into pre-commit hooks and CI.

> Version note (verify against your toolchain): examples target **bats-core 1.10+**,
> **ShellCheck 0.9+**, and **shfmt 3.x**. Older bats lacks `bats_load_library`,
> `run -N`/`run !`, and tags; fall back to plain `load` and manual `$status` checks
> (see the fallback rows below).

## Core Rules

| Rule | Why |
|------|-----|
| One behavior per `@test`; descriptive title | Failures point at the exact contract broken. |
| Source the script under test, don't re-exec it per assertion | Lets you call functions directly and inspect state. |
| Guard execution with the `BASH_SOURCE` main-guard | File runs as a program *and* sources cleanly under test. |
| `run` puts results in `$status`, `$output`, `${lines[@]}` | `run` always returns 0, so assert *after* it. |
| Mock via a PATH-prepended stub dir, never edit the script | Keeps the unit isolated and production code untouched. |
| ShellCheck clean + `shfmt -d` clean is the merge gate | No new warnings; formatting is mechanical, not reviewed. |
| Inline `# shellcheck disable=` needs a one-line justification | Silencing without a reason hides real bugs. |

## bats-core Essentials

```bash
#!/usr/bin/env bats

setup() {
    # BATS_TEST_DIRNAME = dir of this .bats file. Source the script under test.
    source "${BATS_TEST_DIRNAME}/../bin/greet.sh"
    TMP="$BATS_TEST_TMPDIR"   # unique per-test temp dir, auto-cleaned by bats
}

@test "greet prints a greeting for a name" {
    run greet "Ada"
    [ "$status" -eq 0 ]
    [ "$output" = "Hello, Ada" ]
}

@test "greet rejects an empty name" {
    run greet ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"name required"* ]]
}
```

- `$status` — exit code of the run command.
- `$output` — combined stdout+stderr (use `run --separate-stderr` to split into `$stderr`).
- `${lines[@]}` — output split by line; empty lines dropped unless `run --keep-empty-lines`.
- `setup`/`teardown` run per test; `setup_file`/`teardown_file` run once per file.
- `$BATS_TEST_TMPDIR` (per test), `$BATS_FILE_TMPDIR` (per file), `$BATS_SUITE_TMPDIR` (per suite) are auto-created and auto-removed — prefer them over hand-rolled `mktemp -d` + manual cleanup.

**Modern status assertions (bats-core 1.5+):**

```bash
run -0 deploy --dry-run      # asserts exit 0 inline
run -2 validate bad-input    # asserts exit 2 inline
run ! parse malformed        # asserts nonzero exit (use this, not bare `! parse`)
```

> Fallback (bats < 1.5): drop the `-N`/`!` forms and assert `[ "$status" -eq N ]`.

## bats-assert / bats-support

These add readable failure diffs. Install once (git submodule, system package, or `npm i -g`), then load per file:

```bash
setup() {
    bats_load_library bats-support   # required by bats-assert
    bats_load_library bats-assert
}

@test "build emits the artifact path" {
    run build --target release
    assert_success
    assert_output --partial "artifacts/app"
    refute_output --partial "error"
}
```

Common assertions: `assert_success` / `assert_failure [N]`, `assert_output [--partial|--regexp]`, `refute_output`, `assert_line --index N`, `assert_equal "$a" "$b"`. See [references/bats-patterns.md](references/bats-patterns.md).

> Fallback (no `bats_load_library`): `load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load"`.

## Designing Testable Scripts

A script is testable when each behavior is a function and the entry point is guarded so `source` does not execute the program.

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# Behavior lives in functions — directly callable from bats.
greet() {
    local name="${1:?name required}"
    printf 'Hello, %s\n' "$name"
}

main() {
    greet "$@"
}

# Main-guard: runs only when executed directly, NOT when sourced under test.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

Under test you `source` the file (the guard is false, so `main` never fires) and call `greet` in isolation. Rules: keep functions small and single-purpose, take inputs as arguments (not globals), write results to stdout, and send diagnostics to stderr so `run --separate-stderr` can assert each stream.

## Mocking with PATH Stub Dirs

Override an external command by placing a fake earlier on `PATH` — no edits to the script.

```bash
setup() {
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS"
    PATH="$STUBS:$PATH"
    source "${BATS_TEST_DIRNAME}/../bin/deploy.sh"
}

make_stub() {  # name, stdout, exit
    cat >"$STUBS/$1" <<EOF
#!/usr/bin/env bash
echo "$2"
exit "${3:-0}"
EOF
    chmod +x "$STUBS/$1"
}

@test "deploy fails when curl returns non-2xx" {
    make_stub curl "503 Service Unavailable" 1
    run deploy --remote
    [ "$status" -ne 0 ]
}
```

Reset `PATH` per test (`setup` re-prepends from the real `PATH`, and `$BATS_TEST_TMPDIR` is fresh each test, so stubs don't leak). For builtins you can't shadow on PATH, define a shell function and `export -f` it instead.

## ShellCheck Workflow

```bash
shellcheck bin/*.sh                 # all warnings
shellcheck --severity=warning *.sh  # gate: error+warning only
shellcheck -f gcc *.sh              # CI-parseable file:line:col output
```

Pin project settings in `.shellcheckrc` at the repo root:

```ini
shell=bash
severity=warning
enable=quote-safe-variables,require-variable-braces
# SC1091: sourced files not followed in CI sandbox (justified)
disable=SC1091
```

Inline directives apply to the **next line**; always justify a disable:

```bash
# shellcheck disable=SC2086  # word-splitting is intentional: $flags is a flag list
run_tool $flags "$input"
```

Never blanket-disable at file top to dodge work — fix the finding or scope the disable to one line. See [references/shellcheck-shfmt.md](references/shellcheck-shfmt.md) for the top-20 codes and fixes.

## shfmt Formatting

The enforced flag set is **`shfmt -i 2 -ci -bn`** (2-space indent, switch-case indent, binary ops at line start):

```bash
shfmt -d -i 2 -ci -bn .            # diff mode — CI fails if non-empty
shfmt -w -i 2 -ci -bn .            # write — apply formatting locally
```

Put the flags in `.editorconfig` so editors and CI agree:

```ini
[*.{sh,bash,bats}]
indent_style = space
indent_size = 2
switch_case_indent = true
binary_next_line = true
```

## Diagnostic Table

| Symptom | Cause | Fix | Reference |
|---------|-------|-----|-----------|
| `command not found` for your function in a test | Script was re-exec'd, not sourced; or no main-guard | `source` the script in `setup`; add the `BASH_SOURCE` guard | This file — Designing Testable Scripts |
| Sourcing a script runs the whole program | Missing main-guard | Wrap entry in `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` | This file |
| `$output` empty though command printed | You called the command without `run` | Prefix with `run`; assert after it | This file — bats Essentials |
| `bats_load_library: command not found` | Old bats-core | Upgrade, or `load .../bats-support/load` | references/bats-patterns.md |
| Mock never used; real command runs | Stub dir not on `PATH` first, or not executable | Prepend stub dir; `chmod +x` the stub | This file — Mocking |
| Bats hangs forever | Background child inherited FD 3 | Close it: `long_cmd 3>&-` | references/bats-patterns.md |
| `assert_output` undefined | bats-assert not loaded (needs bats-support) | `bats_load_library bats-support` then `bats-assert` | This file — bats-assert |
| ShellCheck flags `$var` (SC2086) | Unquoted expansion → splitting/globbing | Quote it: `"$var"`; or scope a justified disable | references/shellcheck-shfmt.md |
| `shfmt -d` non-empty in CI | Local format drifted from flag set | Run `shfmt -w -i 2 -ci -bn .` | references/shellcheck-shfmt.md |
| ShellCheck warns SC2148 (no shebang) | `.bats`/sourced file lacks dialect hint | Add `#!/usr/bin/env bats` or `# shellcheck shell=bash` | references/shellcheck-shfmt.md |

## Deep-Dive References

- [references/bats-patterns.md](references/bats-patterns.md) — helper libraries, fixtures, advanced mocking, parallel runs, TAP output, CI integration.
- [references/shellcheck-shfmt.md](references/shellcheck-shfmt.md) — severity tuning, top-20 SC codes with fixes, directives, `.shellcheckrc`, shfmt flags, pre-commit + CI wiring.

## Related Skills

- [bash-scripting](../bash-scripting/SKILL.md) — strict-mode prologue, defensive patterns, and portability the tests exercise.
- [testing-principles](../../_shared/testing-principles.md) — language-agnostic test design (AAA, isolation, naming).
- [diagnostics](../../tooling/diagnostics/SKILL.md) — running tests and linters under the broader toolchain.
- [workflow-integration](../../_shared/workflow-integration/SKILL.md) — QA-gate expectation that bats + ShellCheck pass before handoff.
