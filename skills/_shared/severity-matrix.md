# Severity Matrix Reference

Shared definitions for severity levels, finding priorities, and remediation order.

## Severity Levels

| Level | Description | Response Time | Systems Examples |
|-------|-------------|---------------|------------------|
| Critical | Security, data integrity, system down | Immediate | Heap overflow, use-after-free, command injection, data corruption on disk |
| High | Performance blockers, major functionality | Within sprint | Memory leak on a hot path, data race, unchecked allocation failure, deadlock |
| Medium | Code quality, minor performance | Quarterly | Swallowed errno, duplicated parsing logic, missing `set -euo pipefail` |
| Low | Style, nice-to-have | Opportunistic | Formatting drift, naming, missing docstring/Doxygen comment |

## Review Finding Priorities (P0-P3)

Used by the Implementation/Review response formats of all system-developer agents:

| Priority | Definition | Systems Examples |
|----------|------------|------------------|
| P0 | Must fix before merge — correctness/security broken | Buffer overflow, UAF, injection (`eval`, `shell=True`, format string), UB with observable impact, failing tests |
| P1 | Fix in this change — defect likely to bite | Leak on error path, race flagged by TSan, bare `except:`, unquoted Bash expansion on user input |
| P2 | Should fix — quality/maintainability | Missing error propagation, magic numbers, oversized function, weak test coverage on changed code |
| P3 | Nice to have — style | Formatting, naming, comment polish (auto-fixable via clang-format/ruff/shfmt) |

## Remediation Order (impact × effort)

For planning a backlog, not for review findings. These levels are named, not numbered, so they don't collide with the P0-P3 finding priorities above.

| Level | Impact | Effort | Action |
|-------|--------|--------|--------|
| Now | Critical | Any | Immediate remediation |
| Quick win | High | Low | Do first |
| Schedule | High | High | Plan and schedule |
| Batch | Medium | Low | Batch together |
| Defer | Low | High | Deprioritize or skip |

## Effort/Impact Quadrant

```
High Impact ┌──────────────┬──────────────┐
            │   SCHEDULE   │  QUICK WIN   │
            ├──────────────┼──────────────┤
            │    DEFER     │    BATCH     │
Low Impact  └──────────────┴──────────────┘
             High Effort    Low Effort
```

## Code Smell Indicators

| Smell | Thresholds | Impact |
|-------|------------|--------|
| Long function | >40 lines (C/C++), >30 (Python), >50 (Bash) | Hard to understand/test |
| Large translation unit / module | >500 lines | Difficult to maintain |
| Cyclomatic complexity | >10 | Error-prone |
| Nesting depth | >3 levels | Reduced readability |
| Parameters | >5 | Hard to use correctly |
| Code duplication | >5% | Maintenance burden |
| `#ifdef` density | >3 per function | Untestable combinatorics |

## Coverage Requirements

| Scope | Minimum | Target |
|-------|---------|--------|
| Critical paths (parsers, allocators, auth) | 90% | 95%+ |
| Business logic | 75% | 80%+ |
| Utilities | 60% | 70%+ |
| CLI surfaces / glue scripts | 50% | 60%+ |
