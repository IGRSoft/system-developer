# Diagnostics References Index

Deep-dive references for the [diagnostics](../SKILL.md) skill. Start at the
SKILL.md symptom router; come here for full flag tables, command translations,
and worked walkthroughs.

## References

| File | Covers | Read when |
|------|--------|-----------|
| `sanitizers.md` | Per-sanitizer flag reference (ASan/UBSan/TSan/LSan/MSan), `*_OPTIONS` env vars, suppression files, combination rules, CI recipes, an annotated use-after-free report walkthrough | You have a sanitizer report to read, or you are wiring sanitized builds into CI |
| `gdb-lldb.md` | gdb <-> lldb command translation, TUI, breakpoint scripting, pretty-printers, core-dump workflow (`ulimit`/`coredumpctl`), attaching to a live process, rr record/replay, debugging Python + native together | You are stepping through code interactively or opening a core dump |
| `profiling-tools.md` | perf record/report/annotate + flamegraphs, py-spy vs cProfile decision, massif/heaptrack heap profiling, hyperfine, the measure -> fix -> re-measure loop | A program is too slow or uses too much memory and you need to find where |

## Quick Links by Problem

- **Read an ASan use-after-free report** -> `sanitizers.md` (annotated walkthrough)
- **Silence a leak from a third-party library** -> `sanitizers.md` (suppression files)
- **Run sanitizers in CI** -> `sanitizers.md` (CI recipes)
- **`gdb` command, but I'm on macOS** -> `gdb-lldb.md` (translation table)
- **Open a core dump** -> `gdb-lldb.md` (core-dump workflow)
- **Record a flaky crash and replay it** -> `gdb-lldb.md` (rr)
- **Debug a C extension called from Python** -> `gdb-lldb.md` (Python + native)
- **Find the CPU hot path** -> `profiling-tools.md` (perf, py-spy)
- **Find what allocates the most memory** -> `profiling-tools.md` (massif/heaptrack)
- **Prove an optimization actually helped** -> `profiling-tools.md` (hyperfine)
