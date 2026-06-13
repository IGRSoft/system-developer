# bats-core Patterns Reference

Use this when:

- You are building a real bats test suite (helper libraries, fixtures, mocking, parallelism).
- You need to wire bats into CI and parse its TAP output.
- You are debugging a hanging or flaky bats run.

Skip if:

- You only need the basics (`@test`, `run`, `$status`, `$output`, setup/teardown) — those are in [SKILL.md](../SKILL.md).
- Your question is about ShellCheck or shfmt — see [shellcheck-shfmt.md](shellcheck-shfmt.md).

Jump to:

- Installation and Versions
- Project Layout
- Test Anatomy and Special Variables
- Assertion Styles
- Helper Libraries (bats-support / bats-assert / bats-file)
- setup / teardown / setup_file / teardown_file
- Fixtures
- Mocking and Stubbing
- Tags and Filtering
- Parallel Execution
- TAP Output and Reports
- Pitfalls (FD 3, pipes, subshells)
- CI Integration

> Version markers throughout assume **bats-core 1.10+**. Where a feature needs a
> newer release the row notes it; verify against your toolchain with `bats --version`.

## Installation and Versions

```bash
# macOS
brew install bats-core

# Debian/Ubuntu (distro package may lag; prefer git for current features)
sudo apt-get install -y bats

# Pinned, reproducible (recommended for CI): vendor as a submodule
git submodule add https://github.com/bats-core/bats-core test/bats
git submodule add https://github.com/bats-core/bats-support test/test_helper/bats-support
git submodule add https://github.com/bats-core/bats-assert  test/test_helper/bats-assert
git submodule add https://github.com/bats-core/bats-file    test/test_helper/bats-file

bats --version
```

| Feature | Introduced | Fallback if older |
|---------|-----------|-------------------|
| `bats_load_library NAME` | 1.5.0 | `load "${BATS_TEST_DIRNAME}/test_helper/NAME/load"` |
| `run -N` / `run !` inline status | 1.5.0 | `[ "$status" -eq N ]` after `run` |
| `run --separate-stderr` | 1.5.0 | redirect manually: `run bash -c 'cmd 2>file'` |
| `run --keep-empty-lines` | 1.4.0 | accept that empty lines are dropped from `${lines[@]}` |
| Tags (`# bats test_tags=`) + `--filter-tags` | 1.8.0 | use `--filter` on test names |
| `$BATS_TEST_TMPDIR` family | 1.4.0 | `mktemp -d` in setup, `rm -rf` in teardown |
| `bats_pipe` | 1.11.0 | `run bash -c 'a | b'` |

## Project Layout

```
project/
├── bin/
│   ├── deploy.sh
│   └── lib.sh
├── test/
│   ├── deploy.bats
│   ├── lib.bats
│   ├── test_helper.bash          # shared setup/helpers, loaded via `load`
│   ├── test_helper/
│   │   ├── bats-support/          # submodule
│   │   ├── bats-assert/           # submodule
│   │   └── bats-file/             # submodule
│   └── fixtures/
│       ├── valid-config.ini
│       └── expected-output.txt
└── .editorconfig
```

Keep tests under `test/` (or `tests/`); run the whole suite with `bats test/` (add `-r` to recurse).

## Test Anatomy and Special Variables

```bash
#!/usr/bin/env bats

@test "descriptive sentence about one behavior" {
    run my_command --flag value
    [ "$status" -eq 0 ]
    [ "$output" = "expected" ]
}
```

Useful introspection variables (set by bats during each test):

| Variable | Meaning |
|----------|---------|
| `$BATS_TEST_DIRNAME` | Directory of the running `.bats` file (anchor relative paths here) |
| `$BATS_TEST_FILENAME` | Full path to the running `.bats` file |
| `$BATS_TEST_NAME` | Function name of the current test |
| `$BATS_TEST_DESCRIPTION` | The human-readable `@test` title |
| `$BATS_TEST_NUMBER` | 1-based index within the file |
| `$BATS_RUN_COMMAND` | The command string passed to the last `run` |
| `$BATS_TEST_TMPDIR` | Per-test temp dir, auto-created and auto-removed |
| `$BATS_FILE_TMPDIR` | Per-file temp dir |
| `$BATS_SUITE_TMPDIR` | Per-suite temp dir |
| `$BATS_VERSION` | Running bats version |

Two knobs worth knowing: `BATS_TEST_RETRIES=N` (retry a flaky test up to N extra times) and `BATS_TEST_TIMEOUT=SECONDS` (abort a hung test) — set them in `setup_file`.

## Assertion Styles

### Plain bash conditionals (no dependencies)

```bash
@test "exit code and exact output" {
    run printf 'one\ntwo\n'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "one" ]
    [ "${lines[1]}" = "two" ]
}

@test "substring and regex" {
    run date +%Y
    [[ "$output" == 2* ]]
    [[ "$output" =~ ^[0-9]{4}$ ]]
}
```

Use `[ ... ]` for POSIX comparisons and `[[ ... ]]` for `==` globbing and `=~` regex.

### Inline status checks (bats 1.5+)

```bash
@test "succeeds" { run -0 healthcheck; }
@test "rejects bad arg" { run -2 validate --nope; [[ "$output" == *"Usage:"* ]]; }
@test "any failure" { run ! parse /dev/null; }
```

Prefer `run ! cmd` over a bare `! cmd` for asserting failure — bash does not trigger `set -e` on `!`, so a bare negation in the middle of a test won't fail it.

## Helper Libraries

`bats-assert` depends on `bats-support`; load support first.

```bash
setup() {
    bats_load_library bats-support
    bats_load_library bats-assert
    bats_load_library bats-file
}
```

| Library | Key helpers |
|---------|-------------|
| bats-support | underpins the others (diff formatting); no direct API you call |
| bats-assert | `assert_success`, `assert_failure [N]`, `assert_output [--partial\|--regexp]`, `refute_output`, `assert_line --index N --partial ...`, `assert_equal`, `refute_line` |
| bats-file | `assert_file_exists`, `assert_dir_exists`, `assert_file_executable`, `assert_file_contains`, `assert_symlink_to` |

```bash
@test "build produces an executable artifact" {
    run build --release
    assert_success
    assert_output --partial "build complete"
    assert_file_executable "$BATS_TEST_TMPDIR/out/app"
}

@test "config validation reports the bad key" {
    run validate "$BATS_TEST_DIRNAME/fixtures/bad-config.ini"
    assert_failure
    assert_line --partial "unknown key: retries"
}
```

`bats-assert` prints a structured diff on failure, which is far more debuggable than a bare `[ ... ]` that just says `return 1`.

## setup / teardown / setup_file / teardown_file

```bash
# Once per file — expensive shared setup (build a binary, start a fixture server).
setup_file() {
    export BUILD_DIR="$BATS_FILE_TMPDIR/build"
    mkdir -p "$BUILD_DIR"
    make -C "$BATS_TEST_DIRNAME/.." build OUT="$BUILD_DIR" >&3
}

teardown_file() {
    : # $BATS_FILE_TMPDIR is auto-removed; only clean external resources here
}

# Per test — cheap, isolated state.
setup() {
    source "${BATS_TEST_DIRNAME}/../bin/lib.sh"
    cd "$BATS_TEST_TMPDIR"
}

teardown() {
    : # $BATS_TEST_TMPDIR auto-removed; stop per-test daemons here if any
}
```

`setup_file`/`teardown_file` must export anything tests need (each `@test` runs in its own subshell). Use `>&3` to print from `setup_file` so the message is visible (see FD 3 below).

## Fixtures

Store inputs and golden outputs under `test/fixtures/`; copy into a temp dir before mutating.

```bash
setup() {
    FIX="$BATS_TEST_DIRNAME/fixtures"
    cp "$FIX/input.csv" "$BATS_TEST_TMPDIR/input.csv"
}

@test "transform matches golden output" {
    run transform "$BATS_TEST_TMPDIR/input.csv"
    [ "$status" -eq 0 ]
    diff <(printf '%s\n' "$output") "$FIX/expected.txt"
}
```

For volume-dependent tests, generate fixtures on the fly:

```bash
generate_lines() {  # count, file
    seq 1 "$1" | sed 's/^/line /' >"$2"
}

@test "handles 10k-line input" {
    generate_lines 10000 "$BATS_TEST_TMPDIR/big.txt"
    run process "$BATS_TEST_TMPDIR/big.txt"
    [ "$status" -eq 0 ]
    [ "$(wc -l <"$BATS_TEST_TMPDIR/big.txt")" -eq 10000 ]
}
```

## Mocking and Stubbing

### PATH stub directory (preferred for external binaries)

```bash
setup() {
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS"
    PATH="$STUBS:$PATH"
    source "${BATS_TEST_DIRNAME}/../bin/deploy.sh"
}

stub() {  # name, exit_code, stdout...
    local name="$1" code="$2"; shift 2
    {
        echo '#!/usr/bin/env bash'
        printf 'echo %q\n' "$*"
        echo "exit $code"
    } >"$STUBS/$name"
    chmod +x "$STUBS/$name"
}

@test "deploy aborts when health check fails" {
    stub curl 22 "000"
    run deploy --remote prod
    [ "$status" -ne 0 ]
    [[ "$output" == *"health check failed"* ]]
}
```

### Recording call arguments

To assert *how* a command was invoked, have the stub log its argv:

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

### Mocking shell builtins / functions

PATH stubs can't shadow builtins (`cd`, `read`) or functions defined in the sourced script. Override with a function and export it for subshells:

```bash
@test "retry backs off using a faked sleep" {
    sleep() { :; }            # no-op so the test is instant
    export -f sleep
    run with_retries 3 false
    [ "$status" -ne 0 ]
}
```

## Tags and Filtering (bats 1.8+)

```bash
# bats file_tags=integration

# bats test_tags=slow,network
@test "uploads to the remote registry" { ... }

@test "parses a local manifest" { ... }   # only the file tag
```

```bash
bats --filter-tags integration test/        # only integration tests
bats --filter-tags '!slow' test/            # everything except slow
bats --filter-tags network,!slow test/      # network AND not slow
```

> Fallback (bats < 1.8): select by name with `bats --filter 'parses' test/`.

## Parallel Execution

```bash
bats --jobs 4 test/                 # run files/tests in parallel (needs GNU parallel)
bats --jobs 4 --no-parallelize-within-files test/
```

Parallelism is safe only when tests don't share mutable global state. Always write to per-test temp dirs (`$BATS_TEST_TMPDIR`), never a fixed `/tmp/myapp`. Opt a file out with `# bats file_tags=bats:serialize` patterns or `BATS_NO_PARALLELIZE_WITHIN_FILE=true` in `setup_file`.

## TAP Output and Reports

```bash
bats --formatter tap test/        # raw TAP (machine readable)
bats --formatter pretty test/     # default human formatter
bats --formatter junit test/      # JUnit XML for CI test reporting
bats --report-formatter junit --output ./reports test/
```

TAP example:

```
1..2
ok 1 parses a local manifest
not ok 2 uploads to the remote registry
# (in test file test/deploy.bats, line 14)
#   `[ "$status" -eq 0 ]' failed
```

Pipe TAP to any TAP consumer, or use `--report-formatter junit` to drop XML that CI dashboards ingest directly.

## Pitfalls

### File descriptor 3 (bats hangs)

bats reserves FD 3 for its TAP stream. A backgrounded child inherits FD 3, and bats blocks until that FD closes — so a background daemon makes bats appear to hang. Close FD 3 for long-running children:

```bash
start_server &              # ❌ bats may hang waiting on FD 3
start_server 3>&- &         # ✅ child no longer holds FD 3
```

Print intentional diagnostics to FD 3 (prefixed with `#` for TAP compliance):

```bash
echo "# building fixtures..." >&3
```

### `run` and pipes

`run` cannot see a pipe — bash parses `|` outside the `run` invocation:

```bash
run grep foo file | wc -l    # ❌ wc gets run's (empty) output; test is meaningless
run bats_pipe grep foo file \| wc -l   # ✅ pipe runs inside run (bats 1.11+)
run bash -c 'grep foo file | wc -l'    # ✅ portable fallback
```

### Subshell side effects

`run` executes in a subshell, so variable assignments and `cd` inside the run command do **not** persist. To test a function's side effect on a variable, call it directly (no `run`) and inspect after.

### `set -e` inside tests

bats runs each test under `set -e`, so the first failing command aborts the test. That is usually what you want, but it means a bare `! cmd` (which bash exempts from `set -e`) won't fail the test — use `run ! cmd`.

## CI Integration

### GitHub Actions

```yaml
name: shell-tests
on: [push, pull_request]
jobs:
  bats:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive       # pull vendored bats helpers
      - uses: bats-core/bats-action@3.0.0
      - name: Run bats
        run: bats --formatter junit --output reports test/
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: bats-reports
          path: reports/
```

### Makefile targets

```makefile
.PHONY: test test-parallel test-tap
test:
	bats test/

test-parallel:
	bats --jobs 4 test/

test-tap:
	bats --formatter tap test/ | tee reports/tests.tap
```

### Pre-commit (local gate)

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

- [SKILL.md](../SKILL.md) — entry: bats basics, testable-script design, the diagnostic table.
- [shellcheck-shfmt.md](shellcheck-shfmt.md) — linting and formatting the same scripts.
- [bash-scripting](../../bash-scripting/SKILL.md) — the script-side patterns these tests exercise.
