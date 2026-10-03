---
name: bash-testing
description: Test Bash scripts with bats-core and keep them lint-clean with ShellCheck and shfmt. Use when writing bats tests, designing sourceable/testable scripts, mocking commands via PATH stubs, or wiring shellcheck/shfmt into CI.
---

# Bash Testing, Linting, and Formatting

Make scripts sourceable, prove behavior with bats-core, and gate merges on
ShellCheck + shfmt. Version minimums for newer bats features are in
[bats-patterns.md](references/bats-patterns.md#installation-and-versions);
check with `bats --version`.

## Core Rules

| Rule | Why |
|------|-----|
| One behavior per `@test`, with a descriptive title | a failure names the broken contract |
| Source the script under test; call its functions | direct calls, inspectable state |
| Guard the entry point with the `BASH_SOURCE` main-guard | the file runs as a program and sources cleanly |
| Assert after `run`; it always returns 0 | results land in `$status`, `$output`, `${lines[@]}` |
| Mock via a PATH-prepended stub dir, never by editing the script | production code stays untouched |
| ShellCheck clean + `shfmt -d` clean is the merge gate | formatting is mechanical, not reviewed |
| Every inline `# shellcheck disable=` carries a one-line reason | silent disables hide real bugs |

## bats-core Essentials

```bash
#!/usr/bin/env bats

setup() {
    source "${BATS_TEST_DIRNAME}/../bin/greet.sh"   # dir of this .bats file
}

@test "greet prints a greeting for a name" {
    run greet "Ada"
    [ "$status" -eq 0 ]
    [ "$output" = "Hello, Ada" ]
}

@test "greet rejects an empty name" {
    run ! greet ""                 # asserts nonzero exit; use this, not bare `! cmd`
    [[ "$output" == *"name required"* ]]
}
```

- `$output` is stdout+stderr combined; `run --separate-stderr` splits it into `$stderr`.
- `${lines[@]}` drops empty lines unless `run --keep-empty-lines`.
- `run -N cmd` asserts exit code N inline (bats 1.5+; older: `[ "$status" -eq N ]`).
- `setup`/`teardown` run per test; `setup_file`/`teardown_file` once per file.
- Use `$BATS_TEST_TMPDIR` / `$BATS_FILE_TMPDIR` / `$BATS_SUITE_TMPDIR` instead of `mktemp -d`: bats creates and removes them.

## bats-assert / bats-support

For readable failure diffs, load the helpers per file (bats-support first):

```bash
setup() {
    bats_load_library bats-support
    bats_load_library bats-assert
}

@test "build emits the artifact path" {
    run build --target release
    assert_success
    assert_output --partial "artifacts/app"
    refute_output --partial "error"
}
```

`bats_load_library` searches `$BATS_LIB_PATH`; for vendored submodules use
`load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load"` or point
`BATS_LIB_PATH` at `test/test_helper`. Assertion list:
[bats-patterns.md](references/bats-patterns.md#helper-libraries).

## Designing Testable Scripts

Put each behavior in a function and guard the entry point so `source` doesn't run the program:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

greet() {
    local name="${1:?name required}"
    printf 'Hello, %s\n' "$name"
}

main() { greet "$@"; }

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then   # false when sourced
    main "$@"
fi
```

Take inputs as arguments rather than globals, write results to stdout and
diagnostics to stderr so each stream can be asserted.

## Mocking with PATH Stub Dirs

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
    run ! deploy --remote
}
```

Each test gets a fresh `$BATS_TEST_TMPDIR` and its own subshell, so stubs
don't leak. For builtins or functions PATH can't shadow, define a function and
`export -f` it.

## ShellCheck Workflow

```bash
shellcheck bin/*.sh                 # all findings
shellcheck --severity=warning *.sh  # gate: error + warning only
shellcheck -f gcc *.sh              # file:line:col for CI
```

SC2086 (unquoted `$var`) is `info` level, so a warning gate does not report
it; fix it anyway. Project settings go in `.shellcheckrc` at the
repo root. It takes `shell`, `enable`, `disable`, `external-sources`, and
`source-path`, but not `severity`: set that with `--severity` or
`SHELLCHECK_OPTS`.

```ini
shell=bash
enable=quote-safe-variables,require-variable-braces
# SC1091: sourced files not followed in CI sandbox
disable=SC1091
```

An inline directive applies to the next command; justify it, and scope it to
that line rather than the whole file:

```bash
# shellcheck disable=SC2086  # $flags is an intentional flag list
run_tool $flags "$input"
```

Common codes and fixes: [shellcheck-shfmt.md](references/shellcheck-shfmt.md).

## shfmt Formatting

The enforced flag set is `shfmt -i 2 -ci -bn` (2-space indent, indented `case`
arms, binary operators at line start):

```bash
shfmt -d -i 2 -ci -bn .            # diff; CI fails if non-empty
shfmt -w -i 2 -ci -bn .            # apply locally
```

Mirror the flags in `.editorconfig` so editors agree (shfmt reads it only when
no formatting flags are passed):

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
| `command not found` for your function in a test | script re-exec'd, not sourced; or no main-guard | `source` in `setup`; add the guard | Designing Testable Scripts |
| Sourcing a script runs the whole program | missing main-guard | wrap the entry in the `BASH_SOURCE` check | Designing Testable Scripts |
| `$output` empty though the command printed | called without `run` | prefix with `run` | bats-core Essentials |
| `bats_load_library: command not found` | bats older than 1.6 | upgrade, or `load .../bats-support/load` | bats-patterns.md |
| `bats_load_library` can't find a library | not on `$BATS_LIB_PATH` | set `BATS_LIB_PATH`, or `load` by path | bats-assert / bats-support |
| Mock never used; real command runs | stub dir not first on `PATH`, or not executable | prepend it; `chmod +x` | Mocking |
| Bats hangs | background child holds FD 3 | `long_cmd 3>&- &` | bats-patterns.md |
| `assert_output` undefined | bats-assert not loaded | load bats-support, then bats-assert | bats-assert / bats-support |
| SC2086 on `$var` | unquoted expansion | `"$var"`, or a justified one-line disable | shellcheck-shfmt.md |
| `shfmt -d` non-empty in CI | local formatting drifted | `shfmt -w -i 2 -ci -bn .` | shellcheck-shfmt.md |
| SC2148 (no shebang) | `.bats`/sourced file lacks a dialect | `#!/usr/bin/env bats` or `# shellcheck shell=bash` | shellcheck-shfmt.md |

## References

- [bats-patterns.md](references/bats-patterns.md): versions, layout, helper libraries, fixtures, argument-recording stubs, tags, parallel runs, reports, pitfalls, CI.
- [shellcheck-shfmt.md](references/shellcheck-shfmt.md): severity tuning, common SC codes, directives, `.shellcheckrc`, shfmt flags, pre-commit and CI.

## Related Skills

- [bash-scripting](../bash-scripting/SKILL.md): strict-mode prologue and defensive patterns the tests exercise
- [testing-principles](../../_shared/testing-principles.md): language-agnostic test design (AAA, isolation, naming)
- [diagnostics](../../tooling/diagnostics/SKILL.md): running tests and linters in the broader toolchain
