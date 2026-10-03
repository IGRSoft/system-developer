# bats-core Patterns Reference

Building a full bats suite, wiring it into CI, or debugging a hanging run.
Basics (`@test`, `run`, setup/teardown) are in [SKILL.md](../SKILL.md);
linting is in [shellcheck-shfmt.md](shellcheck-shfmt.md).

## Installation and Versions

```bash
brew install bats-core                    # macOS
sudo apt-get install -y bats              # Debian/Ubuntu (may lag)

# Pinned, reproducible (recommended for CI): vendor as submodules
git submodule add https://github.com/bats-core/bats-core test/bats
git submodule add https://github.com/bats-core/bats-support test/test_helper/bats-support
git submodule add https://github.com/bats-core/bats-assert  test/test_helper/bats-assert
git submodule add https://github.com/bats-core/bats-file    test/test_helper/bats-file
```

### Feature availability by version

| Feature | Since | Fallback if older |
|---------|-------|-------------------|
| `$BATS_TEST_TMPDIR` family | 1.4.0 | `mktemp -d` in setup, `rm -rf` in teardown |
| `run -N` / `run !`, `--separate-stderr`, `--keep-empty-lines` | 1.5.0 | `[ "$status" -eq N ]`; `run bash -c 'cmd 2>file'` |
| `bats_load_library` + `$BATS_LIB_PATH` | 1.6.0 | `load "${BATS_TEST_DIRNAME}/test_helper/NAME/load"` |
| Tags + `--filter-tags`, `BATS_TEST_RETRIES`, `BATS_TEST_TIMEOUT` | 1.8.0 | `--filter` on test names |
| `bats_pipe` | 1.10.0 | `run bash -c 'a | b'` |

## Project Layout

```
project/
├── bin/deploy.sh, lib.sh
└── test/
    ├── deploy.bats, lib.bats
    ├── test_helper.bash          # shared helpers, loaded via `load`
    ├── test_helper/              # bats-support, bats-assert, bats-file submodules
    └── fixtures/                 # inputs and golden outputs
```

Run the suite with `bats test/` (`-r` to recurse).

## Special Variables

| Variable | Meaning |
|----------|---------|
| `$BATS_TEST_DIRNAME` | directory of the running `.bats` file; anchor relative paths here |
| `$BATS_TEST_FILENAME` | full path to the running `.bats` file |
| `$BATS_TEST_NAME` / `$BATS_TEST_DESCRIPTION` | function name / `@test` title |
| `$BATS_TEST_NUMBER` | 1-based index within the file |
| `$BATS_RUN_COMMAND` | command passed to the last `run` |
| `$BATS_TEST_TMPDIR`, `$BATS_FILE_TMPDIR`, `$BATS_SUITE_TMPDIR` | per-test / file / suite temp dirs, auto-removed |
| `$BATS_VERSION` | running bats version |

Set `BATS_TEST_RETRIES=N` (retry a flaky test) or `BATS_TEST_TIMEOUT=SECONDS`
(abort a hung test) in `setup_file`.

## Assertion Styles

Plain conditionals need no dependencies. Use `[ ]` for POSIX comparisons and
`[[ ]]` for `==` globbing and `=~` regex:

```bash
@test "exit code, lines, and regex" {
    run printf 'one\n2024\n'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "one" ]
    [[ "${lines[1]}" =~ ^[0-9]{4}$ ]]
}

@test "rejects bad arg" { run -2 validate --nope; [[ "$output" == *"Usage:"* ]]; }
```

Assert failure with `run ! cmd`. Bash exempts a bare `! cmd` from `set -e`,
so it never fails the test.

## Helper Libraries

`bats-assert` depends on `bats-support`; load support first. Failures print a
structured diff instead of a bare `return 1`.

```bash
setup() {
    bats_load_library bats-support
    bats_load_library bats-assert
    bats_load_library bats-file
}
```

| Library | Key helpers |
|---------|-------------|
| bats-support | formatting used by the others; nothing to call directly |
| bats-assert | `assert_success`, `assert_failure [N]`, `assert_output [--partial\|--regexp]`, `refute_output`, `assert_line [--index N] [--partial]`, `refute_line`, `assert_equal` |
| bats-file | `assert_file_exists`, `assert_dir_exists`, `assert_file_executable`, `assert_file_contains`, `assert_symlink_to` |

```bash
@test "config validation reports the bad key" {
    run validate "$BATS_TEST_DIRNAME/fixtures/bad-config.ini"
    assert_failure
    assert_line --partial "unknown key: retries"
}
```

## setup_file / teardown_file

```bash
setup_file() {          # once per file: expensive shared setup
    export BUILD_DIR="$BATS_FILE_TMPDIR/build"
    mkdir -p "$BUILD_DIR"
    make -C "$BATS_TEST_DIRNAME/.." build OUT="$BUILD_DIR" >&3
}

setup() {               # per test: cheap, isolated state
    source "${BATS_TEST_DIRNAME}/../bin/lib.sh"
    cd "$BATS_TEST_TMPDIR"
}
```

Each `@test` runs in its own subshell, so `setup_file` must `export` what tests
need. Teardown hooks only need to clean external resources (daemons, remote
state); temp dirs are removed for you.

## Fixtures

Keep inputs and golden outputs under `test/fixtures/`; copy before mutating.
Generate large inputs on the fly (`seq 1 10000 >"$BATS_TEST_TMPDIR/big.txt"`).

```bash
@test "transform matches golden output" {
    cp "$BATS_TEST_DIRNAME/fixtures/input.csv" "$BATS_TEST_TMPDIR/"
    run transform "$BATS_TEST_TMPDIR/input.csv"
    [ "$status" -eq 0 ]
    diff <(printf '%s\n' "$output") "$BATS_TEST_DIRNAME/fixtures/expected.txt"
}
```

## Mocking and Stubbing

The basic PATH stub is in [SKILL.md](../SKILL.md#mocking-with-path-stub-dirs).
To assert how a command was called, have the stub log its argv:

```bash
stub_recording() {  # name
    local log="$STUBS/$1.calls"
    {
        echo '#!/usr/bin/env bash'
        printf 'printf "%%s\\n" "$*" >> %q\n' "$log"
    } >"$STUBS/$1"
    chmod +x "$STUBS/$1"
}

@test "rsync is called with --delete" {
    stub_recording rsync
    run sync_dir src dst
    grep -q -- '--delete' "$STUBS/rsync.calls"
}
```

PATH stubs can't shadow builtins or functions from the sourced script; override
with a function and export it:

```bash
@test "retry gives up without real sleeps" {
    sleep() { :; }
    export -f sleep
    run ! with_retries 3 false
}
```

## Tags and Filtering

```bash
# bats file_tags=integration

# bats test_tags=slow,network
@test "uploads to the remote registry" { ... }
```

```bash
bats --filter-tags integration test/        # only integration
bats --filter-tags '!slow' test/            # everything except slow
bats --filter-tags network,!slow test/      # network AND not slow
```

## Parallel Execution

```bash
bats --jobs 4 test/                                  # needs GNU parallel
bats --jobs 4 --no-parallelize-within-files test/
```

Parallel runs are safe only without shared mutable state: write to
`$BATS_TEST_TMPDIR`, never a fixed `/tmp/myapp`. Opt one file out with
`BATS_NO_PARALLELIZE_WITHIN_FILE=true` in `setup_file`.

## Reports

```bash
bats --formatter tap test/                              # TAP on stdout
bats --formatter junit test/ > reports/junit.xml        # JUnit on stdout
bats --report-formatter junit --output reports test/    # pretty console + JUnit file
```

A failing TAP line carries the file, line, and failed expression:

```
not ok 2 uploads to the remote registry
# (in test file test/deploy.bats, line 14)
#   `[ "$status" -eq 0 ]' failed
```

## Pitfalls

**FD 3 hangs.** bats reserves FD 3 for its output and waits until every holder
closes it, so a backgrounded daemon makes the run hang. Start it with
`start_server 3>&- &`. Print intentional diagnostics with
`echo "# building fixtures..." >&3`.

**`run` and pipes.** Bash parses `|` outside `run`, so `run grep foo file | wc -l`
pipes run's empty output. Use `run bats_pipe grep foo file \| wc -l` or
`run bash -c 'grep foo file | wc -l'`.

**Subshell side effects.** `run` uses a subshell, so assignments and `cd` don't
persist. To test a function's effect on a variable, call it without `run`.

## CI Integration

GitHub Actions:

```yaml
name: shell-tests
on: [push, pull_request]
jobs:
  bats:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive       # vendored bats helpers
      - uses: bats-core/bats-action@3.0.0
      - name: Run bats
        run: mkdir -p reports && bats --report-formatter junit --output reports test/
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: bats-reports
          path: reports/
```

Local pre-commit gate:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: bats
        name: bats
        entry: bats test/
        language: system
        pass_filenames: false
        files: '\.(sh|bash|bats)$'
```

## See Also

- [shellcheck-shfmt.md](shellcheck-shfmt.md): linting and formatting the same scripts
- [bash-scripting](../../bash-scripting/SKILL.md): the script-side patterns these tests exercise
