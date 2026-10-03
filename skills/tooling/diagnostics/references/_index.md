# Diagnostics References Index

Deep-dive references for the [diagnostics](../SKILL.md) skill; start at its symptom router.

## References

| File | Covers | Read when |
|------|--------|-----------|
| `sanitizers.md` | ASan/UBSan/TSan/LSan/MSan flags, `*_OPTIONS`, suppression files, combination rules, CI recipes, annotated use-after-free report | Reading a sanitizer report, or wiring sanitized builds into CI |
| `gdb-lldb.md` | gdb <-> lldb translation, TUI, breakpoint scripting, pretty-printers, core dumps, attaching, rr, Python + native | Stepping through code or opening a core dump |
| `profiling-tools.md` | perf + flamegraphs, sample, py-spy vs cProfile, massif/heaptrack/tracemalloc, hyperfine, microbenchmarks, measure -> fix -> re-measure | A program is too slow or uses too much memory |

## Quick Links by Problem

- Read an ASan use-after-free report -> `sanitizers.md` (annotated report)
- Silence a leak from a third-party library -> `sanitizers.md` (suppression files)
- Run sanitizers in CI -> `sanitizers.md` (CI recipes)
- gdb command, but on macOS -> `gdb-lldb.md` (translation table)
- Open a core dump -> `gdb-lldb.md` (core-dump workflow)
- Record a flaky crash and replay it -> `gdb-lldb.md` (rr)
- Debug a C extension called from Python -> `gdb-lldb.md` (Python + native)
- Find the CPU hot path -> `profiling-tools.md` (perf, py-spy)
- Find what allocates the most memory -> `profiling-tools.md` (heap profiling)
- Prove an optimization helped -> `profiling-tools.md` (hyperfine)
