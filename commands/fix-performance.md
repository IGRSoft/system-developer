---
description: Profile CPU, memory, or I/O hot paths or benchmark with hyperfine, then optionally apply the ranked fixes
argument-hint: [path or target (default .)] [--mode cpu|memory|io|bench] [--duration SECONDS] [--apply]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, Skill
estimated-cost:
  min-tokens: 2000
  max-tokens: 26000
  model-distribution:
    haiku: 25%
    sonnet: 60%
    opus: 15%
---

# Profile & Optimize Performance

Collect a CPU, memory, or I/O profile of a built target, or a `hyperfine` before/after benchmark, with the platform's native profiler. Hand the raw artifacts to `system-developer:sys-performance-engineer` for interpretation. The command collects; the engineer ranks hot paths.

Measure-only is the default: Phases 1-5 profile and report without touching source. With `--apply`, a checkpoint follows; only after the user approves does `system-developer:sys-code-fixer` apply the ranked fixes, followed by a build+test gate and a re-measure.

## Rules

### Measurement

- Profile only an optimized build with symbols (RelWithDebInfo, `-O2 -g`, unstripped). If a compiled target is Debug (`-O0`), stripped, or missing, print the rebuild instruction and stop. An `-O0` build moves the hot path and a stripped one has no symbols, so its profile is wrong.
- Don't interpret the trace yourself; the engineer produces the ranked findings.
- Save every artifact under `.context/logs/profile-<timestamp>/` (`$OUT`), plus a `meta.txt` with target, mode, platform, language, tool, and build flags. The engineer reads from there, not from scrollback.
- Use each profiler's own output and target flags instead of `cd` or `&&` chains; scoped Bash permissions don't match compound commands.
- Run the matrix commands as written. If a flag is rejected, check `man`/`--help` rather than guessing.

### Applying fixes

- Before the checkpoint the only writes are under `$OUT`. `Write`/`Edit` are allowed for the apply phase only.
- Apply needs both `--apply` and an explicit approval at the checkpoint. Approval of the findings is not approval to edit.
- `--mode bench` records only and never edits: there is no profile to derive a fix plan from.
- After applying, re-measure and report the delta honestly. If the numbers didn't improve, say so and offer to revert.
- A missing tool never hard-fails: print the install hint, skip that collection, and report the skip.

## Usage

```bash
/system-developer:fix-performance .                                # CPU profile of the primary built target
/system-developer:fix-performance build/parser --mode memory
/system-developer:fix-performance build/server --mode cpu --duration 15
/system-developer:fix-performance app/ingest.py --mode io
/system-developer:fix-performance "build/prog --new" --mode bench  # JSON baseline for before/after
/system-developer:fix-performance build/parser --mode cpu --apply  # profile, then apply after approval
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path or target` | `.` | A directory (detect the primary built target / Python entry point), a binary path, or, in `--mode bench`, a full command line to time. |
| `--mode cpu\|memory\|io\|bench` | `cpu` | `cpu` = where time goes; `memory` = allocations/leaks; `io` = syscall/I/O wait; `bench` = wall-clock before/after with hyperfine. |
| `--duration SECONDS` | tool default | Sampling length for attach modes (`sample <pid> <dur>`, `perf record -p <pid> -- sleep <dur>`, `py-spy record --pid`). Ignored for launch-and-exit runs and `--mode bench`. |
| `--apply` | off | Unlock the checkpoint-gated apply phase (Phases 6-8). Not valid with `--mode bench`. |

## Build Prerequisite Check (C/C++ only)

| Check | How |
|-------|-----|
| Has symbols, not stripped | `file <target>` says "not stripped"; `nm <target>` lists symbols (macOS: `.dSYM` alongside) |
| Optimized, not Debug | No `-O0`/`-Og` for the hot TUs in `compile_commands.json`; `CMAKE_BUILD_TYPE` is `RelWithDebInfo` (or `Release` with explicit `-g`) |

On failure print:

```bash
# CMake: optimized + symbols, unstripped
cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build
# For accurate Linux perf call graphs, keep frame pointers:
#   -DCMAKE_C_FLAGS_RELWITHDEBINFO="-O2 -g -fno-omit-frame-pointer"

# Meson: meson setup build --buildtype debugoptimized -Dstrip=false
# Make/autotools: make CFLAGS="-O2 -g -fno-omit-frame-pointer"  (and don't strip at install)
```

Python and Bash skip this check; for py-spy `--native` on a C extension, the extension still needs `-g`.

## Platform / Tool Matrix

Resolve the OS once with `uname -s`, then run the row for `--mode` + language, substituting target, pid, duration, and `$OUT`.

### C / C++

| Mode | Darwin | Linux |
|------|--------|-------|
| `cpu` | `sample <pid> <duration> -file "$OUT/sample.txt"` (attach), or `xctrace record --template "Time Profiler" --output "$OUT/cpu.trace" --launch -- <target>` (launch, deeper) | `perf record -g --call-graph dwarf -o "$OUT/perf.data" -- <target>` then `perf report -i "$OUT/perf.data" --stdio > "$OUT/perf-report.txt"` |

#### C / C++: memory and I/O

| Mode | Darwin | Linux |
|------|--------|-------|
| `memory` | `leaks --atExit -- <target> 2>&1 \| tee "$OUT/leaks.txt"` (leaks at exit); `MallocStackLogging=1 <target>` then `malloc_history <pid> --all-by-size > "$OUT/malloc_history.txt"` (allocation backtraces) | `valgrind --tool=massif --massif-out-file="$OUT/massif.out" <target>` then `ms_print "$OUT/massif.out" > "$OUT/massif.txt"` (heap over time); `heaptrack -o "$OUT/heaptrack" <target>` (lower-overhead churn/leaks); `valgrind --leak-check=full --log-file="$OUT/memcheck.txt" <target>` (definite leaks) |
| `io` | `fs_usage -w -f filesys <pid> 2>&1 \| tee "$OUT/fs_usage.txt"` (needs privilege), or an `xctrace` File Activity template | `perf record -e 'syscalls:sys_enter_*' -o "$OUT/io-perf.data" -- <target>`, or `strace -f -T -o "$OUT/strace.txt" <target>` for per-syscall timing |

### Python (native frames Linux-only)

| Mode | Command |
|------|---------|
| `cpu` | `py-spy record --format speedscope -o "$OUT/pyspy.speedscope.json" -- python <entry>` (attach: `--pid <pid>`); `--native` for C-extension frames (Linux, extension built with `-g`); per-call counts: `python -m cProfile -o "$OUT/profile.prof" <entry>` |
| `memory` | Write the runner below to `"$OUT/trace_mem.py"`, then `python -X tracemalloc=25 "$OUT/trace_mem.py" <entry> [args]`; top allocation sites by `lineno` land in `"$OUT/tracemalloc.txt"`. The target's source is not touched. |
| `io` | `py-spy dump --pid <pid> > "$OUT/pyspy-dump.txt"` for a stuck/IO-waiting process; otherwise `strace`/`fs_usage` on the `python` process as for C/C++ |

#### tracemalloc runner

```python
# trace_mem.py: run <entry> under tracemalloc (enabled by -X tracemalloc) and save the top sites.
import os, runpy, sys, tracemalloc
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tracemalloc.txt")
entry, sys.argv = sys.argv[1], sys.argv[1:]
kept = None  # holds the script's globals so what it retained is still live at snapshot time
try:
    kept = runpy.run_path(entry, run_name="__main__")
finally:
    snap = tracemalloc.take_snapshot().filter_traces(
        [tracemalloc.Filter(False, "<frozen importlib._bootstrap*>"), tracemalloc.Filter(False, __file__)])
    current, peak = tracemalloc.get_traced_memory()
    with open(out, "w") as f:
        f.write(f"current={current} B peak={peak} B\n")
        f.writelines(f"{s}\n" for s in snap.statistics("lineno")[:30])
```

### Bash

A slow script waits on the processes it spawns, so there's no `perf` equivalent; collect this instead of reporting "no tool":

| Mode | Collection |
|------|-----------|
| `cpu` | `PS4='+ $EPOCHREALTIME ' BASH_XTRACEFD=3 bash -x <script> 3>"$OUT/xtrace.log"` (bash 5+; macOS bash 3.2: `PS4='+ $SECONDS '`). Rank by the wall-clock gap between lines; the hot spot is the slowest child command. |
| `memory` | Not measurable at the shell level. Find the child that dominates `xtrace.log` and re-run against that target in its own language; report the redirection. |
| `io` | `strace -f -e trace=file,read,write` (Linux) / `sudo dtruss -f` (macOS). `-f` is required or the children doing the I/O are invisible. |

`--mode bench` is the main evidence path for Bash; the xtrace tells you which child to bench.

### `--mode bench` (all languages)

- Single: `hyperfine --warmup 3 --export-json "$OUT/bench.json" '<command>'`
- A vs B: `hyperfine --warmup 3 --export-json "$OUT/bench-compare.json" '<command-old>' '<command-new>'`
- Baseline: record `bench.json` before the change and again after; the delta between them is the evidence.

Single-function microbenchmarks (Google Benchmark, pytest-benchmark) belong in the test suite, not here.

### Install hints

| Tool | Platform | Hint |
|------|----------|------|
| `perf` | Linux | distro `linux-perf` / `linux-tools-$(uname -r)` |
| `valgrind`, `heaptrack` | Linux | distro package (valgrind is Linux-first) |
| `sample`, `leaks`, `malloc_history`, `fs_usage`, `xctrace` | Darwin | Command Line Tools: `xcode-select --install` |
| `py-spy` | all | `uv tool install py-spy` (or `pipx install py-spy`) |
| `hyperfine` | all | `brew install hyperfine` (Linux: distro package or `cargo install hyperfine`) |

## Workflow

### Phase 1: Resolve target and platform

1. Confirm the target exists (for bench, that the command's first token is runnable); otherwise stop with "Target not found".
2. `PLATFORM="$(uname -s)"`.
3. Language: a binary is C/C++, `.py` is Python, `.sh` or a bash shebang is Bash. For a directory, resolve the primary built target (e.g. the CMake executable under `build/`) or the Python entry point; if ambiguous, stop and ask for an explicit target.
4. `TS="$(date +%Y%m%d-%H%M%S)"; OUT=".context/logs/profile-${TS}"; mkdir -p "$OUT"`, then write `meta.txt`.

### Phase 2: Build prerequisite check

C/C++ only: run the check above. On failure, print the rebuild instruction and stop.

### Phase 3: Collect

1. `command -v` the tool. If missing, print its install hint, skip, and report; don't substitute another tool or mode.
2. Run the matrix command into `$OUT`, honoring `--duration` for attach modes. For bench, run hyperfine and export the JSON (both commands when comparing).
3. When piping through `tee`, run with `set -o pipefail` so the profiler's exit status survives. Record profiler errors (`perf: Permission denied`, py-spy attach denied) in `meta.txt` and surface them under Error Handling; they are environment issues, not target bugs.

### Phase 4: Interpret (delegate)

Use the Agent tool with `subagent_type="system-developer:sys-performance-engineer"` (pass `model: "opus"` for a large or cross-language trace):

> Interpret the {mode} profile of `{target}` ({language}, {platform}). Artifacts are in `{OUT}`; build flags and tool are in `{OUT}/meta.txt`. Return: (1) the top-N hotspots as `file:line` with their share of time/allocations; (2) for memory mode, the dominant allocation churn / leak sites, each marked leak vs retained/cached growth; (3) a fix plan ranked by effort/impact, algorithmic wins first, each item naming the agent that would implement it; (4) for bench mode, the mean ± σ delta between baselines and whether it is beyond noise. Don't edit code. If you can't read an artifact, name its path instead of guessing.

### Phase 5: Report

Emit the Output Format with the engineer's findings (or the skip/error note). Without `--apply`, stop here; mention `--apply` only if the engineer returned at least one actionable fix.

### Checkpoint (`--apply` only)

If the engineer returned no actionable fix, say so and stop. Otherwise use AskUserQuestion to present the ranked plan and ask what to apply: the whole plan, only high-impact/low-effort items, or nothing. Don't proceed on an unanswered or ambiguous reply.

### Phase 6: Apply approved fixes (delegate)

Use the Agent tool with `subagent_type="system-developer:sys-code-fixer"`, passing only the approved items in the engineer's order:

> Apply these approved performance fixes from a {mode} profile of `{target}`: {approved items as `{file, line, finding, proposed_fix, expected_effect}`}. Change only what each item requires: no refactoring of untouched code, no reformatting, nothing outside this list. Preserve observable behavior; a faster program that computes something different is a defect. Report `{file, line, item, change}` per item, and list any item you could not safely apply (API redesign, algorithmic rewrite, threading-model change, or other judgment calls) with the reason.

Declined items are reported for manual handling, never forced.

### Phase 7: Build + test gate

Run `/system-developer:build-test` on the touched project. A red build or failing test blocks the run: report the failing stage, offer to revert the applied diff, and don't re-measure. For a code-level break, send the log excerpt to the owning language agent for a corrected patch, then re-run the gate once.

### Phase 8: Re-measure and compare

Re-run the same Phase 3 collection (same mode, target, duration, tool, flags) into a fresh `.context/logs/profile-<timestamp>/`; a differently collected profile is not a comparison. Compare hotspot shares (or hyperfine means), record both artifact paths, and fill in Applied Fixes. If the hot path didn't move or got worse, say so and offer to revert.

## Output Format

One report, shown in four parts.

```markdown
## Performance Profile Report

**Target:** {target}
**Mode:** cpu | memory | io | bench
**Platform:** Darwin | Linux
**Language:** C | C++ | Python | Bash
**Tool:** {sample | xctrace | perf | valgrind massif | heaptrack | leaks | py-spy | cProfile | tracemalloc | hyperfine}
**Build:** RelWithDebInfo ✅ | (bench/Python: N/A)
**Mutation:** read-only (no --apply) | applied {n} fixes after checkpoint approval
**Artifacts:** .context/logs/profile-{timestamp}/
```

### Report: step status

```markdown
| Step | Result | Notes |
|------|--------|-------|
| Build prerequisite | ✅ / ❌ rebuild / ⏭ N/A | {-O2 -g, unstripped — or rebuild hint} |
| Collection | ✅ / ❌ / ⏭ skipped | {tool, duration, or skip reason} |
| Interpretation | ✅ / ⏭ | {delegated to sys-performance-engineer} |
| Apply | ⏭ not requested / ⏭ declined at checkpoint / ✅ {n} applied | {approved scope} |
| Build+test gate | ⏭ N/A / ✅ / ❌ blocked | {only when fixes were applied} |
| Re-measure | ⏭ N/A / ✅ | {second profile path} |
```

### Report: findings by mode

```markdown
### Top Hotspots
<!-- cpu/io modes -->
| Rank | Location (file:line) | Share | Note |
|-----:|----------------------|------:|------|
| 1 | parse.cpp:142 | 38% | quadratic scan in inner loop |

### Allocation / Leak Summary
<!-- memory mode only -->
| Site (file:line) | Bytes / churn | Leak? | Note |
|------------------|--------------:|-------|------|
| node.cpp:88 | 4 MB | yes | missing free on error path |

### Benchmark Delta
<!-- bench mode only -->
| Command | Mean ± σ | vs baseline |
|---------|----------|-------------|
| old | 412 ms ± 9 ms | baseline |
| new | 268 ms ± 6 ms | −35% (beyond noise) |
```

### Report: fixes and skips

```markdown
### Ranked Fix Plan
<!-- effort/impact order -->
1. {high-impact / low-effort fix} — implement via system-developer:{agent}

### Applied Fixes
<!-- only after an approved --apply checkpoint -->
| File:Line | Item | Change | Effect (re-measured) |
|-----------|------|--------|----------------------|
| parse.cpp:142 | quadratic inner scan | hoisted lookup into a map | 38% → 6% of CPU time |

**Not applied (manual):** {items needing algorithmic/API judgment, or "none"}
**Before / after artifacts:** {OUT-before} → {OUT-after}
**Verdict:** improved / unchanged / regressed — {plain statement; offer rollback unless improved}

<!-- on skip/error only -->
### Skipped / Environment
- {tool}: {missing — install hint} | {perf_event_paranoid too high} | {py-spy attach denied — run as process owner}
```

## Error Handling

### Target and build errors

| Case | Message / action |
|------|------------------|
| Target not found | `Error: Target not found: {target}`. Suggest a built binary, Python entry point, directory, or (bench) a runnable command, e.g. `/system-developer:fix-performance build/prog --mode cpu`. |
| Ambiguous target in a directory | `Error: Could not resolve a single profilable target under {path}.` Suggest passing the explicit binary or entry point. |
| Debug / stripped build | `Error: {target} is a Debug or stripped build — profiling it yields wrong hot paths.` Print the rebuild instruction, then `Re-run: /system-developer:fix-performance build/{target} --mode {mode}`. This stops the run. |

### Environment and option errors

| Case | Message / action |
|------|------------------|
| perf permission denied (Linux) | `Warning: perf could not read CPU counters (perf_event_paranoid too high).` Lower `kernel.perf_event_paranoid` with privilege or run as the process owner; point at any artifacts in `{OUT}`. |
| py-spy attach denied | `Warning: py-spy could not attach to pid {pid} (OS attach restriction).` Run as the process owner or with privilege. |
| Tool missing | Print the install hint, skip, continue. Only when every eligible profiler for the mode/platform is absent, report "no profiler available" with the aggregated hints. |
| `--apply` with `--mode bench` | `Error: --apply is not valid with --mode bench.` Bench produces no profile to derive a fix plan from; suggest `/system-developer:fix-performance build/prog --mode cpu --apply`. |
| Build+test gate failed after applying | Handled in Phase 7. |

## See Also

- `skill: diagnostics` (`references/profiling-tools.md`): profiler flag reference, measure→fix→re-measure loop, symptom→tool table.
- `skill: build-systems`: profilable build presets.
- `/system-developer:build-test`: the gate after `--apply`. Its `--type` is Debug|Release only, so produce the RelWithDebInfo build with the rebuild instruction above.
- `/system-developer:fix-modernize`: when a ranked fix is really a standard/idiom migration, too broad for the minimal-diff apply.
- `/system-developer:review-code`: review the applied diff for behavioral drift.
- `/system-developer:sanitize-check`: when the symptom is a crash or corruption, not slowness.
