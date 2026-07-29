---
description: Profile CPU, memory, or I/O hot paths or benchmark with hyperfine, then optionally apply the ranked fixes
argument-hint: [path or target (default .)] [--mode cpu|memory|io|bench] [--duration SECONDS] [--apply]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
estimated-cost:
  min-tokens: 2000
  max-tokens: 26000
  model-distribution:
    haiku: 25%
    sonnet: 60%
    opus: 15%
---

# Profile & Optimize Performance
<!-- Updated: July 2026 -->

Collect a CPU, memory, or I/O profile of a built target — or a `hyperfine` before/after benchmark — using the platform's native profiler, then hand the raw artifacts to `system-developer:sys-performance-engineer` for interpretation. Data collection is pure Bash; the agent is engaged only to read the profile and rank hot paths. The command never guesses at hotspots itself.

**Measure-only is the default.** Phases 1-5 read, profile, and report; they do not modify a single file. An optional apply phase (Phases 6-8) hands the engineer's ranked fix plan to `system-developer:sys-code-fixer`, but it is unreachable until you approve it at an explicit PHASE CHECKPOINT. Running without `--apply` behaves exactly like the old read-only profiler.

[Extended thinking: Profiling is a measure-first discipline, so this command's job is to produce *trustworthy* measurements, defer judgment, and only then — with the user's explicit consent — act on them. It is Darwin-first — `sample`/`xctrace`/`leaks`/`malloc_history` on macOS, `perf`/`valgrind`/`heaptrack` on Linux — because the same intent maps to different tools per OS; Python overlays py-spy/cProfile/tracemalloc on top. The single most common way profiling lies is a wrong build: an `-O0` build relocates the hot path and a stripped `Release` erases symbols, so the prerequisite check refuses anything but RelWithDebInfo-equivalent (`-O2 -g`, unstripped) and tells the user how to rebuild rather than profiling garbage. Every artifact lands under `.context/logs/profile-<timestamp>/` so the engineer (and the user) can re-open the trace. `--mode bench` is the comparison path: hyperfine `--warmup 3` with JSON baselines committed before and after a change, so the delta is evidence, not vibes. Interpretation — top-N hotspots with `file:line`, allocation churn, a fix plan ranked by effort/impact — is the agent's deliverable, not this command's. The apply phase exists because a ranked fix plan the user then has to re-paste into another command is a handoff tax, but optimization edits are exactly the kind of change that must not happen by surprise: the checkpoint makes consent explicit and the mandatory re-measure makes the result falsifiable, so an "optimization" that did not actually move the number gets reported as such instead of assumed.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **Profile a RelWithDebInfo build, never Debug, never stripped.** Before collecting any compiled-code profile, verify the target is built `-O2 -g` and unstripped (see Build Prerequisite Check). If it is `-O0`/Debug, stripped, or missing, STOP and emit the rebuild instruction — do NOT profile it. A wrong build produces wrong hot paths; reporting them is worse than not profiling.
2. **Collection is Bash-only; interpretation is the agent's.** This command runs the profiler and saves artifacts. It does NOT eyeball the trace and declare a winner. Hand the artifacts to `system-developer:sys-performance-engineer` and let it produce the ranked findings.
3. **Save every artifact under `.context/logs/profile-<timestamp>/`.** Create the directory once per run; write the trace/profile/JSON/leak-report and a `meta.txt` (target, mode, platform, tool, build flags) there. The directory is the single source of truth for interpretation — do not rely on terminal scrollback.
4. **Single-command Bash invocations.** Use each profiler's own flags for output paths and target selection. Never `cd`-chain or `&&`-chain directory changes — scoped Bash patterns do not match compound commands.
5. **Pick the platform tool, do not invent flags.** Resolve the OS once (`uname -s`), then run the matching tool from the Platform / Tool Matrix exactly as written. If a flag is rejected, consult `man`/`--help` or `skill: diagnostics` — never guess flag spellings.
6. **No mutation before the checkpoint.** Phases 1-5 are strictly read-only: they MUST NOT create, edit, or delete any source, build, or manifest file. The only writes are profiling artifacts under `.context/logs/profile-<timestamp>/`. `Write` and `Edit` are in `allowed-tools` solely for the apply phase; using them earlier is a failure.
7. **The apply phase requires BOTH `--apply` and an approved checkpoint.** Without `--apply`, stop after Phase 5 and report — never offer to edit. With `--apply`, stop at the PHASE CHECKPOINT and use the AskUserQuestion tool. Only an explicit approval unlocks Phase 6. Silence, ambiguity, or "looks good" about the *findings* is not approval to edit.
8. **`--mode bench` records, never optimizes.** Bench mode runs hyperfine and exports JSON baselines for before/after comparison. It is the measurement half of the loop; `--apply` is the other half. Bench mode never auto-edits, checkpoint or not — there is no profile to derive a fix plan from.
9. **Re-measure after applying, and report the delta honestly.** Phase 8 re-runs the same collection and compares. If the numbers did not improve, say so plainly and offer the rollback — do NOT describe an applied change as an optimization on the strength of the plan alone.
10. **Tool-missing never hard-fails.** If the platform profiler is absent, print the install hint, skip that collection, and report what was skipped. If no profiler is available at all, report the aggregated hints and stop without erroring out the session.
11. **Never enter plan mode.** This command IS the procedure — execute it.

## Usage

```bash
# CPU profile of the current project's primary built target
/system-developer:fix-performance .

# Memory profile of a specific binary
/system-developer:fix-performance build/parser --mode memory

# Sample a CPU profile for 15 seconds
/system-developer:fix-performance build/server --mode cpu --duration 15

# I/O profile a Python entry point
/system-developer:fix-performance app/ingest.py --mode io

# Benchmark two invocations and store a JSON baseline for before/after
/system-developer:fix-performance "build/prog --new" --mode bench

# Profile, then (after you approve at the checkpoint) apply the ranked fixes
/system-developer:fix-performance build/parser --mode cpu --apply
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `path or target` | `.` | A directory (detect the primary built target / Python entry point), a binary path, or — in `--mode bench` — a full command line to time. |
| `--mode cpu\|memory\|io\|bench` | `cpu` | `cpu` = where time goes; `memory` = where allocations/leaks are; `io` = syscall/I/O wait; `bench` = wall-clock before/after with hyperfine. |
| `--duration SECONDS` | tool default | For attach/sampling modes (`sample <pid> <dur>`, `perf record -p <pid> -- sleep <dur>`, `py-spy record` of a running process), how long to sample. Ignored for launch-and-exit runs and for `--mode bench` (hyperfine controls its own run count). |
| `--apply` | off | Unlock the optional apply phase. Even with it set, nothing is edited until you approve at the PHASE CHECKPOINT. Not valid with `--mode bench` (no profile to derive a fix plan from). |

`--mode` and `--duration` interact only for the sampling/attach paths; for a launch-and-exit target the program's own runtime bounds the profile.

**Without `--apply` this command is read-only.** It profiles, reports, and stops at Phase 5. `--apply` adds Phases 6-8 (checkpoint → fix → re-measure) and nothing else; the measurement half is byte-for-byte identical either way.

## Build Prerequisite Check (compiled targets)

Before any C/C++ collection, confirm the target is profilable. Run this and STOP with the rebuild hint if it fails:

| Check | How | Fail action |
|-------|-----|-------------|
| Built with debug info | `file <target>` reports "not stripped"; `nm <target>` lists symbols (macOS: `dsymutil`/`.dSYM` present alongside) | Emit "rebuild RelWithDebInfo" instruction; do not profile |
| Optimized (`-O2`), not Debug | No `-O0`/`-Og` in `compile_commands.json` for the hot TUs; CMake cache `CMAKE_BUILD_TYPE` is `RelWithDebInfo` (or `Release` + explicit `-g`) | Emit rebuild hint |
| Not stripped | `file <target>` does NOT say "stripped" | Emit rebuild hint |

Rebuild instruction to print on failure:

```bash
# CMake: a profilable build (optimized + symbols, unstripped)
cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build
# For accurate call graphs on Linux perf, also keep frame pointers:
#   -DCMAKE_C_FLAGS_RELWITHDEBINFO="-O2 -g -fno-omit-frame-pointer"

# Meson: meson setup build --buildtype debugoptimized -Dstrip=false
# Make/autotools: make CFLAGS="-O2 -g -fno-omit-frame-pointer"  (and do not strip at install)
```

`RelWithDebInfo` is `-O2 -g`: real optimization with symbols. Debug (`-O0`) relocates the hot path; stripped `Release` erases the symbols you need. See `skill: build-systems` for profilable presets. Python and Bash have no build step — skip this check for them (for py-spy `--native` on a C extension, the extension still needs `-g`).

## Platform / Tool Matrix

Resolve the OS once with `uname -s` (Darwin vs Linux), then pick the row for `--mode` + language. Run the command verbatim, substituting target, pid, duration, and output dir (`OUT=.context/logs/profile-<timestamp>`). The canonical flag reference is `skill: diagnostics` (profiling-tools) — keep this matrix in sync with it, do not fork the flag spellings.

### C / C++ — CPU (`--mode cpu`)

| Platform | Command |
|----------|---------|
| Darwin | `sample <pid> <duration> -file "$OUT/sample.txt"` (attach), or `xctrace record --template "Time Profiler" --output "$OUT/cpu.trace" --launch -- <target>` (launch, deeper) |
| Linux | `perf record -g --call-graph dwarf -o "$OUT/perf.data" -- <target>` then `perf report -i "$OUT/perf.data" --stdio > "$OUT/perf-report.txt"` |

### C / C++ — Memory (`--mode memory`)

| Platform | Command |
|----------|---------|
| Darwin | `leaks --atExit -- <target> 2>&1 \| tee "$OUT/leaks.txt"` (leaks at exit); `MallocStackLogging=1 <target>` then `malloc_history <pid> --all-by-size > "$OUT/malloc_history.txt"` (allocation backtraces) |
| Linux | `valgrind --tool=massif --massif-out-file="$OUT/massif.out" <target>` then `ms_print "$OUT/massif.out" > "$OUT/massif.txt"` (heap over time); `heaptrack -o "$OUT/heaptrack" <target>` (lower-overhead churn/leaks); `valgrind --leak-check=full --log-file="$OUT/memcheck.txt" <target>` (definite leaks) |

### C / C++ — I/O (`--mode io`)

| Platform | Command |
|----------|---------|
| Darwin | `fs_usage -w -f filesys <pid> 2>&1 \| tee "$OUT/fs_usage.txt"` (file-system syscalls; needs privilege), or an `xctrace` File Activity template |
| Linux | `perf record -e 'syscalls:sys_enter_*' -o "$OUT/io-perf.data" -- <target>` (or `strace -f -T -o "$OUT/strace.txt" <target>` for per-syscall timing) |

### Python (all platforms; native frames are Linux-only)

| Mode | Command |
|------|---------|
| `cpu` | `py-spy record --format speedscope -o "$OUT/pyspy.speedscope.json" -- python <entry>` (attach: `py-spy record --pid <pid> --format speedscope -o "$OUT/pyspy.speedscope.json"`); add `--native` for C-extension frames (Linux; extension built with `-g`); deterministic per-call counts: `python -m cProfile -o "$OUT/profile.prof" <entry>` |
| `memory` | `tracemalloc` snapshot in-process (top allocation sites by `lineno`); save the top-N dump to `"$OUT/tracemalloc.txt"` |
| `io` | `py-spy dump --pid <pid> > "$OUT/pyspy-dump.txt"` for a stuck/IO-waiting process; otherwise `strace`/`fs_usage` over the `python` process as in the C/C++ I/O row |

### Bash — all modes

There is no shell equivalent of `perf`/`py-spy`: a slow script waits on the processes it spawns. Do not report "no tool available" — collect this instead:

| Mode | Collection |
|------|-----------|
| `cpu` | Timestamped xtrace, ranked by the wall-clock gap between lines: `PS4='+ $EPOCHREALTIME ' BASH_XTRACEFD=3 bash -x <script> 3>"$OUT/xtrace.log"` (bash 5+; on macOS 3.2 use `PS4='+ $SECONDS '`). The hot spot is the slowest child command. |
| `memory` | Not measurable at the shell level. Identify the child that dominates `xtrace.log` and re-run against **that** target in its own language; report the redirection, not a null result. |
| `io` | `strace -f -e trace=file,read,write` (Linux) / `sudo dtruss -f` (macOS) — `-f` is required or the children doing the I/O are invisible. |

`--mode bench` is the primary evidence path for Bash; the xtrace only tells you *which* child to bench.

### `--mode bench` (all languages — wall-clock before/after)

| Step | Command |
|------|---------|
| Benchmark | `hyperfine --warmup 3 --export-json "$OUT/bench.json" '<command>'` |
| Compare A vs B | `hyperfine --warmup 3 --export-json "$OUT/bench-compare.json" '<command-old>' '<command-new>'` |
| Baseline for later diff | record `bench.json` *before* the change and again *after*; the delta between the two committed JSONs is the evidence |

Microbenchmarks (single function) are out of scope for this command's collection — Google Benchmark / pytest-benchmark belong in the test suite (`skill: diagnostics`).

## Workflow

### Phase 1: Resolve target & platform (Bash)

1. Confirm `path or target` exists (for `--mode bench`, the first token of the command must be runnable). If not, emit the Error Handling "target not found" message and stop.
2. Detect OS: `PLATFORM="$(uname -s)"` (`Darwin` or `Linux`).
3. Detect language of the target via `skill: language-detection` (binary vs `.py` entry vs `.sh`). For a directory, resolve the primary built target (e.g. the CMake executable under `build/`) or the Python entry point; if ambiguous, ask the user to pass an explicit target.
4. Create the artifact dir once: `TS="$(date +%Y%m%d-%H%M%S)"; OUT=".context/logs/profile-${TS}"; mkdir -p "$OUT"`.
5. Write `"$OUT/meta.txt"` with target, `--mode`, platform, language, chosen tool, and (for compiled targets) the detected build flags.

### Phase 2: Build prerequisite check (Bash — compiled targets only)

1. For C/C++ targets, run the Build Prerequisite Check. If it fails (Debug, stripped, or missing symbols), print the rebuild instruction and STOP — do not profile.
2. Skip this phase for Python and Bash (no compiled artifact). For py-spy `--native`, note in `meta.txt` whether the extension carries symbols.

### Phase 3: Collect (Bash)

1. Verify the platform tool exists (`command -v sample`/`xctrace`/`leaks`/`perf`/`valgrind`/`heaptrack`/`py-spy`/`hyperfine`). If missing, print the install hint (Tool Availability), skip the collection, note the skip, and stop after reporting (do not silently substitute a different tool/mode).
2. Run the matrix command for `PLATFORM` + `--mode` + language, writing artifacts into `"$OUT"`. For attach/sampling modes, honor `--duration`.
3. For `--mode bench`, run hyperfine `--warmup 3` and export the JSON baseline. If the user is comparing two commands, pass both and export the comparison JSON.
4. Capture exit status (`${PIPESTATUS[0]}` where piped through `tee`). If the profiler itself errors (e.g. `perf: Permission denied`, py-spy attach denied), record the message in `meta.txt` and surface it under Error Handling — these are environment issues, not target bugs.

### Phase 4: Interpret (delegate)

After artifacts are written, hand them to the performance engineer for the ranked analysis. This is the only delegation in the command.

- **Use Task tool with subagent_type="system-developer:sys-performance-engineer"**
  Prompt: "Interpret the {mode} profile of `{target}` ({language}, {platform}). Artifacts are in `{OUT}` (build flags and tool recorded in `{OUT}/meta.txt`). Read the profile/trace/JSON and produce: (1) the **top-N hotspots** as `file:line` with their share of time/allocations; (2) for `--mode memory`, the dominant **allocation churn / leak sites** and whether each is a leak vs retained/cached growth; (3) a **fix plan ranked by effort/impact** (algorithmic wins before micro-optimizations), each item naming the language agent that would implement it. Do NOT edit code — return the ranked analysis. For `--mode bench`, report the mean ± σ delta between the baselines and whether the change is a real regression/improvement beyond the noise."
- Expected output: ranked hotspot list with `file:line`, allocation/leak summary (memory mode), effort/impact-ranked fix plan, bench delta (bench mode).
- Context: reads only the artifacts in `{OUT}`; no code edits.
- Error handling: if the engineer cannot read an artifact, report the artifact path so the user can open it directly (e.g. `xctrace`/heaptrack GUIs); do not fabricate an analysis.

Model note: `sys-performance-engineer` defaults to sonnet/high; for a large or cross-language profile a caller may raise it to opus/xhigh — pass `model="opus"` on the Task call when the trace is complex enough to warrant it.

### Phase 5: Report (Bash)

Emit the Output Format summary, pointing at `{OUT}` and folding in the engineer's ranked findings (or the skip/error note when collection did not run).

**Without `--apply`, the command ends here.** The report is the deliverable; nothing on disk changed except `{OUT}`. Mention that `--apply` exists only if the engineer returned at least one actionable fix.

---

### PHASE CHECKPOINT (only when `--apply` is set)

**Completed:** Phases 1-5 — profile collected under `{OUT}`, interpreted by `sys-performance-engineer`, ranked fix plan produced. **No source file has been modified.**

**Next:** Phase 6 would delegate the ranked fix plan to `system-developer:sys-code-fixer`, which edits source files, followed by a build+test gate and a re-measure.

Stop here. Use the **AskUserQuestion** tool to present the ranked fix plan and ask which items to apply. Offer at minimum: apply the whole plan; apply only the high-impact / low-effort items; apply nothing (stop with the report). Do NOT proceed on an unanswered or ambiguous response — approval of the *findings* is not approval to edit code.

If the engineer returned no actionable fix, skip the checkpoint entirely, say so, and stop after Phase 5.

---

### Phase 6: Apply the approved fixes (delegate — post-checkpoint only)

Apply **only** the items the user approved, in the engineer's effort/impact order.

- **Use Task tool with subagent_type="system-developer:sys-code-fixer"**
  Prompt: "Apply these approved performance fixes from a {mode} profile of `{target}`: {approved_items as `{file, line, finding, proposed_fix, expected_effect}`}. Minimal-diff gate: change only what each item requires; do not refactor untouched code, reformat, or apply items outside this list. Preserve observable behavior — a faster program that computes something different is a defect, not an optimization. After each item, report `{file, line, item, change}`, and list any item you could NOT safely apply (needs API redesign, algorithmic rewrite, or human judgment)."
- Items needing design judgment (algorithm replacement, API/ABI change, threading model change) are **not** auto-applied — return them for manual handling with the engineer's rationale.
- Anything the fixer declines is reported, never forced.

### Phase 7: Build + Test Gate (BINDING)

Run `/system-developer:build-test` over the touched project. A red build or a failing test **blocks** the run: report the failing stage, offer to revert the applied diff, and do NOT proceed to the re-measure. A performance change that breaks correctness is a regression regardless of its numbers.

### Phase 8: Re-measure & compare (Bash)

1. Re-run the **same** collection from Phase 3 (same mode, same target, same duration) into a fresh `.context/logs/profile-<timestamp>/` directory. Same tool, same flags — a comparison against a differently-collected profile is not evidence.
2. Compare the new hotspot shares (or `hyperfine` means for a benchmarkable target) against the pre-fix run and record both artifact paths.
3. Report the delta in the Applied Fixes section of the Output Format. If the hot path did not move, or moved the wrong way, **say so** and offer to revert. Do not relabel a neutral result as a win.

## Tool Availability

Confirm the chosen profiler exists before collecting. If missing, print the hint, skip the collection, and report the skip.

| Missing tool | Platform | Install hint |
|--------------|----------|--------------|
| `perf` | Linux | install your distro's `linux-perf` / `linux-tools-$(uname -r)` package |
| `valgrind` | Linux | distro `valgrind` package (verify availability on your macOS toolchain — massif/memcheck are Linux-first) |
| `heaptrack` | Linux | distro `heaptrack` package |
| `sample` / `leaks` / `malloc_history` / `fs_usage` | Darwin | ship with macOS (Command Line Tools — `xcode-select --install`) |
| `xctrace` | Darwin | ships with the Command Line Tools / developer tools |
| `py-spy` | all | `uv tool install py-spy` (or `pipx install py-spy`) |
| `hyperfine` | all | `brew install hyperfine` (Linux: distro package, or `cargo install hyperfine`) |

Exact flag spellings vary across tool releases — verify against your toolchain when a flag is rejected. Never hard-fail on a missing tool: print the hint, skip the collection, continue, and report the skip.

## Output Format

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

| Step | Result | Notes |
|------|--------|-------|
| Build prerequisite | ✅ / ❌ rebuild / ⏭ N/A | {-O2 -g, unstripped — or rebuild hint} |
| Collection | ✅ / ❌ / ⏭ skipped | {tool, duration, or skip reason} |
| Interpretation | ✅ / ⏭ | {delegated to sys-performance-engineer} |
| Apply | ⏭ not requested / ⏭ declined at checkpoint / ✅ {n} applied | {approved scope} |
| Build+test gate | ⏭ N/A / ✅ / ❌ blocked | {only when fixes were applied} |
| Re-measure | ⏭ N/A / ✅ | {second profile path} |

### Top Hotspots
<!-- from sys-performance-engineer; cpu/io modes -->
| Rank | Location (file:line) | Share | Note |
|-----:|----------------------|------:|------|
| 1 | parse.cpp:142 | 38% | quadratic scan in inner loop |
| 2 | io.c:77 | 19% | unbuffered read per record |

### Allocation / Leak Summary
<!-- memory mode only -->
| Site (file:line) | Bytes / churn | Leak? | Note |
|------------------|--------------:|-------|------|
| arena.c:54 | 12 MB peak | no | retained cache, not a leak |
| node.cpp:88 | 4 MB | yes | missing free on error path |

### Benchmark Delta
<!-- bench mode only -->
| Command | Mean ± σ | vs baseline |
|---------|----------|-------------|
| old | 412 ms ± 9 ms | baseline |
| new | 268 ms ± 6 ms | −35% (beyond noise) |

### Ranked Fix Plan
<!-- from sys-performance-engineer; effort/impact order -->
1. {high-impact / low-effort fix} — implement via system-developer:{agent}
2. {next} — ...

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
- {tool}: {missing — install hint above} | {perf_event_paranoid too high} | {py-spy attach denied — run as process owner}
```

## Error Handling

### Target not found
```
Error: Target not found: {target}
Suggestion: Pass a built binary, a Python entry point, a directory to detect,
or (for --mode bench) a runnable command, e.g.
/system-developer:fix-performance build/prog --mode cpu
```

### Debug / stripped build (compiled target)
```
Error: {target} is a Debug or stripped build — profiling it yields wrong hot paths.
Rebuild RelWithDebInfo (optimized + symbols, unstripped):
  cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo && cmake --build build
Then re-run: /system-developer:fix-performance build/{target} --mode {mode}
```
This is a STOP, not a skip — do not profile an `-O0`/stripped build.

### perf permission denied (Linux)
```
Warning: perf could not read CPU counters (perf_event_paranoid too high).
Lower it with privilege (sysctl kernel.perf_event_paranoid) or run as the
process owner, then re-run. Artifacts (if any) are under {OUT}.
```

### py-spy attach denied
```
Warning: py-spy could not attach to pid {pid} (OS attach restriction).
Run as the target process's owner / with privilege, then re-run.
```

### Tool missing
Print the install hint from Tool Availability, skip the collection, continue. Only when *every* eligible profiler for the mode/platform is absent does the command report "no profiler available" with the aggregated hints (no hard failure).

### `--apply` with `--mode bench`
```
Error: --apply is not valid with --mode bench.
Bench mode measures wall-clock time; it produces no profile to derive a fix plan from.
Suggestion: profile first, then apply, e.g.
/system-developer:fix-performance build/prog --mode cpu --apply
```

### Build+test gate failed after applying
Not silent. Report the failing stage from `/system-developer:build-test`, offer to revert the applied diff, and route a code-level break plus the log excerpt to the owning language agent for a corrected patch before re-running the gate once. Never proceed to the re-measure over a red gate.

### Ambiguous target in a directory
```
Error: Could not resolve a single profilable target under {path}.
Suggestion: Pass the explicit binary or entry point, e.g.
/system-developer:fix-performance build/server --mode cpu
```

## See Also

- `skill: diagnostics` — canonical profiling-tools flag reference (perf/sample/py-spy/valgrind/heaptrack/hyperfine), the measure→fix→re-measure loop, and the symptom→tool table. Keep the Platform / Tool Matrix in sync with it.
- `skill: build-systems` — RelWithDebInfo presets and profilable build flags (`-O2 -g -fno-omit-frame-pointer`).
- `skill: language-detection` — target language resolution for the matrix.
- `/system-developer:build-test` — produce the profilable build first (`--type Release`/RelWithDebInfo) before profiling; also the binding gate `--apply` runs after editing.
- `/system-developer:fix-modernize` — for a ranked fix that is really a standard/idiom migration (too broad for the `--apply` minimal-diff gate).
- `/system-developer:review-code` — review the applied optimization diff for behavioral drift.
- `/system-developer:sanitize-check` — when the symptom is a *crash or corruption*, not slowness — correctness before performance.
