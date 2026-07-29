# Test fixtures

Tiny sample projects used to smoke-test the `system-developer` commands and
agents. They are **not** registered in the plugin manifests and are **not**
shipped to users — they only exercise the tooling locally and in CI.

Each fixture builds/passes cleanly on its happy path and carries exactly one
**planted defect** so a command has something concrete to detect. Defects that
would break the happy build are gated behind a flag (`ENABLE_BUG`); defects that
a linter should catch statically are left live in a clearly marked file.

| Fixture | Build system | Happy path | Planted defect | How to trigger / detect |
|---|---|---|---|---|
| `cmake-cpp/` | CMake + FetchContent GoogleTest | `cmake -S . -B build && cmake --build build && ctest --test-dir build` | Heap-buffer-overflow in `RingBuffer::at` | Configure with `-DENABLE_BUG=ON`, build with ASan, run `ctest` — AddressSanitizer reports a heap-buffer-overflow with file:line |
| `c-make/` | GNU Make | `make && make run` | Memory leak (heap copy never freed) | Build `make ENABLE_BUG=1`, run under `valgrind --leak-check=full ./wordcount` or LeakSanitizer — "definitely lost", one allocation per word |
| `py-uv/` | uv + ruff + pytest (src layout) | `uv sync && uv run pytest` | ruff F401 (unused import) + pre-3.14 typing idiom (`Optional`/`List`) in `src/calc/legacy.py` | `uv run ruff check src/` reports F401 and UP rules; `ruff check --fix` rewrites the typing idioms |
| `bash/` | Bash + bats | `bats greet.bats` | ShellCheck SC2086 (unquoted `$name`) in `greet.sh` | `shellcheck greet.sh` reports SC2086; `/system-developer:fix-quick --fix` quotes the variable |

## Per-fixture detail

### `cmake-cpp/`

A 3-element integer ring buffer with a passing GoogleTest suite. The default
(`ENABLE_BUG=OFF`) `RingBuffer::at` clamps logical indices into the live region.
With `-DENABLE_BUG=ON` the same method indexes the backing store by the raw
logical index and skips bounds checking, so `at(size())` and beyond read past
the live region — visible under AddressSanitizer.

GoogleTest is fetched via `FetchContent` (tag `v1.15.2`, pinned; verify against
your toolchain). The first build needs network access to clone it.

### `c-make/`

`wordcount.c` heap-duplicates three words and sums their lengths. The default
target frees each copy; `make ENABLE_BUG=1` compiles the `#ifdef ENABLE_BUG`
branch that never frees, producing one leaked allocation per loop iteration.

### `py-uv/`

`src` layout, package `calc`. `core.py` is clean and fully covered by
`tests/test_core.py`. `legacy.py` is the defect file: it has an unused
`import os` (ruff **F401**) and uses `typing.Optional` / `typing.List`
instead of `int | None` / `list[int]` (ruff **UP** / pyupgrade). `pytest`
lives in the `test` dependency group, not in project dependencies.

### `bash/`

`greet.sh` prints a greeting. The greeting line uses an unquoted `$name`
(ShellCheck **SC2086**). Behavior is still correct for the single-word inputs
the bats suite passes, so `bats greet.bats` is green; only the static linter
flags the script.
