---
name: testing-principles
description: Test pyramid, per-language framework matrix, coverage thresholds, and testing best practices for C, C++, Python, and Bash
---

# Testing Principles Reference

Shared testing patterns, framework selection, coverage requirements, and quality gates for systems work.

## Test Pyramid

```
         /\
        /  \      E2E Tests (5-10%)
       /────\     Full binaries/CLIs, critical user paths
      /      \
     /────────\   Integration Tests (20-30%)
    /          \  Component interactions, IPC, file/network boundaries
   /────────────\ Unit Tests (60-70%)
  /              \ Individual functions, classes, modules
```

## Framework Matrix

Detect the existing framework first — never introduce a second framework into a project that already has one.

| Language | Unit framework | Property / fuzz | Coverage tool | Focused run |
|----------|----------------|-----------------|---------------|-------------|
| C | Unity 2.6, CMocka 1.1.8 | libFuzzer, AFL++ | gcov + lcov | `ctest -R <regex>` |
| C++ | GoogleTest 1.17 (C++17 min), Catch2 3.9 | libFuzzer, rapidcheck | llvm-cov / gcovr | `ctest -R <regex>` |
| Python | pytest | Hypothesis | coverage.py (`pytest --cov`) | `pytest -k <expr>` |
| Bash | bats-core 1.13 | — | kcov | `bats -f <regex>` |

Versions are the floors this plugin assumes (mid-2026); confirm against your toolchain. GoogleTest 1.17 follows a "live at head" policy and requires C++17 as its minimum standard.

Registration is part of test generation: `add_test()`/`gtest_discover_tests()`/`catch_discover_tests()` (CMake), `conftest.py` discovery (pytest), `setup()`/`teardown()` files (bats). A test that is not registered does not exist.

## Coverage Targets

| Scope | Minimum | Target | Notes |
|-------|---------|--------|-------|
| Critical logic | 90% | 95%+ | Parsers, allocators, auth, data integrity |
| Core application code | 75% | 80%+ | Business rules, services |
| Utilities and helpers | 60% | 70%+ | Shared functions |
| CLI surfaces / glue scripts | 50% | 60%+ | Argument parsing, exit codes |
| Generated/config code | N/A | N/A | Excluded from coverage |

## Test Types

| Type | Purpose | Scope | Speed |
|------|---------|-------|-------|
| Unit | Verify isolated logic | Single function/class | <100ms |
| Integration | Verify interactions | Multiple components | <1s |
| E2E | Verify user journeys | Full binary/CLI | <30s |
| Sanitized | Catch memory/UB/race bugs | Unit+integration under ASan/UBSan/TSan | 2-20x slower |
| Property/fuzz | Explore input space | Parsers, codecs, boundaries | Varies |
| Performance | Verify speed/scale | Critical paths (hyperfine, Google Benchmark, pytest-benchmark) | Varies |

Sanitized runs are a first-class test type for C/C++: ASan+UBSan combine in one build; TSan requires its own build (see `tooling/diagnostics`).

## Testing Best Practices

### Naming Convention

```
test_[unit]_[scenario]_[expected]
test_parse_config_missing_file_returns_error
test_ring_buffer_wraparound_preserves_order
```

### AAA Pattern

```python
def test_parse_header_truncated_input_raises():
    # Arrange: set up test data and conditions
    data = VALID_HEADER[:4]

    # Act + Assert: execute and verify the expected outcome
    with pytest.raises(TruncatedInputError):
        parse_header(data)
```

```cpp
TEST(RingBuffer, WraparoundPreservesOrder) {
    RingBuffer<int> buf(2);          // Arrange
    buf.push(1); buf.push(2); buf.push(3);  // Act
    EXPECT_EQ(buf.front(), 2);       // Assert
}
```

### Test Independence

- Each test runs in isolation — no shared mutable state, no ordering assumptions
- Setup/teardown per test (fixtures in GoogleTest/pytest, `setup()`/`teardown()` in bats)
- Hermetic by default: temp dirs (`mktemp -d`, `tmp_path`), no network, no global config reads
- Deterministic: seed random sources; no sleeps as synchronization

## Quality Gates

| Gate | Threshold | Action on Failure |
|------|-----------|-------------------|
| Coverage | >80% new code | Block merge |
| Unit + integration tests | All pass | Block merge |
| ASan+UBSan on changed C/C++ components | 0 reports | Block merge (QA gate) |
| Flaky tests | <1% flakiness | Investigation |
| Test duration | <10 min total | Optimization |

## Anti-Patterns to Avoid

- Testing implementation details instead of observable behavior
- Excessive mocking (mock the boundary — filesystem, network, clock — not your own modules)
- Flaky tests (timing, network, real `$HOME`)
- Tests that assert nothing or duplicate the implementation
- Copy-paste test code instead of parameterized tests (`TEST_P`, `@pytest.mark.parametrize`)
- Missing edge cases: empty input, max sizes, EINTR/partial reads, non-UTF-8 paths
- Testing third-party code or the compiler

## Related Skills

- `severity-matrix.md` — coverage requirements and finding priorities
- `workflow-integration/SKILL.md` — QA gate definition for worktask runs
- `python/python-testing`, `bash/bash-testing` — per-language deep dives
