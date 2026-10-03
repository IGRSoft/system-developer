---
description: Configure debugging workflows, or triage and root-cause a crash, hang, or wrong-value bug in C, C++, Python, or Bash
argument-hint: [configure|triage] [path, error text, stack trace, core file, or pid]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, Skill
estimated-cost:
  min-tokens: 2000
  max-tokens: 16000
  model-distribution:
    haiku: 15%
    sonnet: 70%
    opus: 15%
---

# Debug & Triage

Two jobs behind one entry point. **Configure mode** sets up debugging infrastructure for a project: a debug build that carries symbols, core dumps, debugger init files, trace hooks, and a documented reproduction loop. **Triage mode** takes one failure already in hand (a segfault, a hang, a `Traceback`, a core file, a wrong number) and drives it to a named root cause.

The `system-developer:diagnostics` skill holds the full symptom→tool routing, sanitizer flag sets, and gdb/lldb, core-dump, and rr references; load it when you need exact flags beyond what is here.

## Rules

### Order of work

- Resolve the mode first (Mode Dispatch), state which mode and why, then run only that mode's steps.
- **Sanitizer before debugger.** For a C/C++ crash, wrong value, leak, or suspected race, run `/system-developer:sanitize-check` first: it names the defect where it happened, while a debugger only shows where the process died. Use a debugger when the sanitizer is clean or the symptom is a logic bug or hang.
- **Debug build, C/C++ only.** Interactive debugging needs `-O0 -g -fno-omit-frame-pointer`; optimized frames read `<optimized out>`. If the target was built optimized, say so and rebuild before setting breakpoints. Python and Bash have no compiled artifact: don't gate `pdb`/`py-spy`/`bash -x` on a rebuild or report a missing debug build for them.

### Outputs, tools, and severity

- **Triage is advisory.** Triage produces a root cause with evidence and does not edit source; the fix goes to the owning language agent or `/system-developer:review-code --fix`. Configure mode may write scaffolding.
- Tee every debugger, trace, and reproduction run to `.context/logs/debug-<timestamp>.log`; the log is the source of truth, not scrollback.
- A missing gdb/lldb/strace/ltrace/py-spy never hard-fails: print the install hint (Error Handling), note the constraint, and continue with what is present.
- Grade triage severity P0–P3: **P0** correctness or security broken (memory corruption, UB with observable impact, crash in a shipped path); **P1** defect likely to bite (race, leak on an error path, wrong results under realistic input); **P2** failure limited to an edge case or non-critical path; **P3** cosmetic or diagnostic-only.

## Usage

```bash
/system-developer:debug configure services/parser
/system-developer:debug triage "Segmentation fault (core dumped)"
/system-developer:debug triage "TypeError: 'NoneType' object is not subscriptable at etl.py:88"
/system-developer:debug triage --core /cores/core.44231
/system-developer:debug triage --pid 44231      # hung process: attach and dump stacks
/system-developer:debug .                       # bare path -> configure
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `configure` | default | Set up debugging infrastructure for the target path. |
| `triage` | — | Root-cause one failure. Needs an error string, stack trace, core file, or `--pid`. |
| `path` | `.` | Configure scope; in triage, the source tree used to resolve symbols. |
| `--pid N` | none | Triage a live process: gdb/lldb `thread apply all bt` / `bt all`, or `py-spy dump`. Implies `triage`. |
| `--core FILE` | none | Triage a core dump against the matching binary. Implies `triage`. |
| `--no-sanitize` | off | Skip the sanitizer first pass when the caller already ran it. Record why in the report. |

## Mode Dispatch

- First token `configure` → Configure; the rest is the path.
- First token `triage`, or `--pid`/`--core` anywhere → Triage; the rest is the evidence.
- Otherwise infer: failure-looking text (`error`, `Error`, `Traceback`, `Segmentation fault`, `Assertion`, `panic`, `core dumped`, `undefined behavior`, `signal N`, a `file:line` in a stack frame) → Triage; a bare path, directory, or nothing → Configure.
- Still ambiguous → Configure, because it is non-destructive and a wrong triage guess wastes a reproduction cycle. State the fallback.

## Symptom → Tool Routing

### Native crashes, hangs, leaks, and races

| Symptom | First tool | Escalation |
|---------|-----------|------------|
| Crash / `SIGSEGV` / `SIGABRT` / heap corruption | `/system-developer:sanitize-check asan` | gdb/lldb on the core if ASan is clean |
| Wrong values, behavior changes with `-O2` | `/system-developer:sanitize-check ubsan` | debugger at `-O0 -g`; bisect the optimization level |
| Hang / deadlock (native) | attach + `thread apply all bt` | `/system-developer:sanitize-check tsan` for lock-order reports |
| Leak / unbounded growth | `/system-developer:sanitize-check lsan` | `valgrind --tool=massif` when recompiling is impossible |
| Data race / intermittent wrong results | `/system-developer:sanitize-check tsan` | debugger only to inspect the state TSan named |

### Python hangs, performance, syscalls, and scripts

| Symptom | First tool | Escalation |
|---------|-----------|------------|
| Hang / stuck (Python) | `py-spy dump --pid N` | `faulthandler`, then `pdb` at the stuck call |
| Slow, not wrong | `/system-developer:fix-performance` | profile, don't breakpoint |
| Syscall/env failure (`ENOENT`, bad path, missing fd) | `strace` / `dtruss` | `ltrace` for library calls |
| Script exits early / wrong exit status (Bash) | `bash -x` (or `PS4` + `BASH_XTRACEFD` to a log) | `shellcheck` for what `set -e` misses |
| Unset variable / word-splitting surprise (Bash) | `set -u` + `bash -x` | `shellcheck` (SC2086/SC2154), then `bash-developer` |

## Platform Notes

### Native builds and cores

- **Builds:** debugging wants `-O0 -g`; profiling and sanitizers want `-O2 -g` (`RelWithDebInfo`). Keep `llvm-symbolizer` on `PATH` or frames render as `??`. If a bug reproduces only at `-O2`, don't force `-O0`: treat it as UB and run UBSan.
- **Core dumps:** enable before reproducing (`ulimit -c unlimited`; Linux+systemd `coredumpctl list`/`debug`; macOS `sudo sysctl -w kern.coredump=1`, cores in `/cores`). A core is only usable against the same unstripped binary; if it was rebuilt since, say so and re-reproduce.
- **Pretty-printers:** load libstdc++ gdb printers or lldb libc++ synthetics before inspecting `std::` types; note in the report when raw internals were read instead.

### Tracing

- **Tracing:** `strace -f -e trace=file,network -o trace.log` (narrow `-e trace=` first); `ltrace` is Linux-only and unreliable on static or PLT-optimized binaries. macOS `dtruss` needs `sudo` and SIP blocks it on Apple-signed and hardened-runtime binaries: don't tell the user to disable SIP; fall back to lldb breakpoints on the suspect libc calls or reproduce on Linux.

### Python and Bash

- **Python:** `py-spy dump --pid N` for a stuck process, `python3 -X faulthandler` for fatal signals, `python3 -m pdb -c continue script.py` for post-mortem. `py-spy` needs ptrace: `sudo` on macOS; `sudo` or a relaxed `kernel.yama.ptrace_scope` on Linux.
- **Bash:** tracing is the debugger. `PS4='+ ${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]:-main}: '`, `exec 9>trace.log; BASH_XTRACEFD=9`, and `trap 'echo "ERR line $LINENO: $BASH_COMMAND" >&2' ERR`. Pair `trap ERR` with `set -euo pipefail`, or the script runs past the failure it reported.

## Workflow

### Both modes: detect

1. Resolve the mode.
2. Resolve the language and its owning agent: only `.c`/`.h` sources → `c-developer`; any C++ source, `project(x CXX)`, or `CMAKE_CXX_STANDARD` → `cpp-developer`; `pyproject.toml`/`*.py` → `python-developer`; shell scripts only → `bash-developer`. Auxiliary `scripts/*.sh` don't make a project Bash. Mixed, FFI/native-extension, or unclear trees → `system-developer` (router), never a guessed language agent.
3. `mkdir -p .context/logs`; `LOG=".context/logs/debug-$(date +%Y%m%d-%H%M%S).log"`.
4. Probe tools (`command -v gdb lldb strace ltrace dtruss py-spy`); record what's missing and any platform constraint.

### Configure mode

1. C/C++: ensure a debug configuration with `-O0 -g -fno-omit-frame-pointer` (CMake `Debug` config or preset, Meson `--buildtype debug`, or a Makefile debug target) and verify it with `/system-developer:build-test <path> --type Debug`. Pure Python/Bash: record `⏭ n/a`.
2. Enable core dumps for the platform and document where they land.
3. Add missing debugger scaffolding: `.gdbinit`/`.lldbinit` with the project's pretty-printers and common breakpoints, or a documented `py-spy`/`pdb` entry point.
4. Add trace hooks the language warrants: `PS4` + `BASH_XTRACEFD` for shell entry points, `faulthandler` for Python services.
5. Document the reproduction loop (command, environment, expected vs actual) and stop; configure mode doesn't hunt bugs.

### Triage mode

1. Parse the evidence: signal or exception type, top user-code frame, `file:line`, thread count, determinism. Assign P0–P3.
2. Route through Symptom → Tool Routing. Unless `--no-sanitize`, run the indicated sanitize-check kind first. If it names the defect, that is the root cause; go to step 5.
3. Establish the narrowest reliable reproduction, teed to `$LOG`. If it doesn't reproduce, say so and work from static evidence; never invent a repro.
#### Gather evidence

4. Gather evidence: `bt` / `thread apply all bt` on the core or attached process, locals at the faulting frame, a watchpoint on the suspect variable; `py-spy dump` for stuck Python; `strace`/`dtruss` when the boundary is a syscall. Write the causal chain from trigger to failure with the evidence for each link, marking unproven links. For a deep or stalled hunt, escalate with the Agent tool to subagent_type="debugging-toolkit:debugging-toolkit-debugger":

   "Root-cause this failure. Symptom: {symptom}. Severity: {P0-P3}. Evidence so far (log `{LOG}`):
   ```
   {evidence}
   ```
   Sanitizer result: {clean | finding | skipped}. Return a ranked hypothesis list with the smallest proof step for each. Read-only: don't modify source."

#### Report and route the fix

5. Emit the report, then route the fix with the Agent tool to the owning agent from detect step 2 (`system-developer:c-developer`, `cpp-developer`, `python-developer`, `bash-developer`, or the `system-developer` router with the detected markers):

   "Root cause identified for the {language} project at `{path}`: {root_cause}. Evidence in `{LOG}`; failing frame `{file:line}`. Propose the minimal correct fix and a regression test. Don't widen scope beyond this defect."

   If the root cause is a hot path rather than a defect, send it to subagent_type="system-developer:sys-performance-engineer" instead and point at `/system-developer:fix-performance`.
6. Recommend a regression test via `/system-developer:gen-tests`, verified with `/system-developer:build-test`.

## Output Format

One report: the shared header plus the body for the active mode.

```markdown
## Debug Report — {Configure | Triage}

**Target:** {path}
**Language:** {C | C++ | Python | Bash | mixed}
**Log:** .context/logs/debug-{timestamp}.log

<!-- Configure mode -->
### Debug Infrastructure

| Item | State | Detail |
|------|-------|--------|
| Debug build (`-O0 -g -fno-omit-frame-pointer`) | ✅ / ➕ added / ❌ / ⏭ n/a | {config or preset name; `⏭ n/a` for pure Python/Bash} |
| Core dumps | ✅ / ➕ / ⏭ | {ulimit -c / coredumpctl / /cores} |
| Debugger init | ✅ / ➕ / ⏭ | {.gdbinit / .lldbinit / pdb entry point} |
| Trace hooks | ✅ / ➕ / ⏭ | {PS4+BASH_XTRACEFD / faulthandler / none} |

**Reproduction loop:** {exact command, env, expected vs actual}
```

### Report: triage-mode body

```markdown
<!-- Triage mode -->
### Failure

- **Symptom:** {signal / exception / wrong value}
- **Severity:** {P0 | P1 | P2 | P3}
- **Reproducible:** deterministic / intermittent / not reproduced
- **Sanitizer first pass:** {kind} → {finding | clean | skipped (--no-sanitize)}

### Root Cause

{One sentence. Then the causal chain, one line per link, each with its evidence
 (`file:line`, log line, or "unproven").}

### Evidence

| Source | Finding |
|--------|---------|
| {sanitize-check asan / bt / py-spy dump / strace} | {excerpt} |

### Routing

- **Fix owner:** system-developer:{agent} — not applied here (triage is advisory).
- **Regression test:** /system-developer:gen-tests {target}
- **Verify:** /system-developer:build-test {path}
```

When no root cause was reached, say so, list the surviving hypotheses with their smallest proof step, and stop; don't present a guess as a finding.

## Error Handling

### Optimized build — values unreadable
```
Warning: {binary} was built at -O{1|2|3}; locals read <optimized out> and frames are inlined.
Rebuild with -O0 -g -fno-omit-frame-pointer before setting breakpoints:
  /system-developer:build-test {path} --type Debug --clean
If the bug ONLY reproduces at -O2, do not force -O0 — treat it as UB and run
  /system-developer:sanitize-check ubsan {path}
```

### No core dump produced
```
Notice: The crash produced no core file.
Enable first, then reproduce:  ulimit -c unlimited
  Linux:  coredumpctl list          (systemd captures cores itself)
  macOS:  sudo sysctl -w kern.coredump=1   (cores land in /cores)
A core from a since-rebuilt binary is unusable — re-reproduce after enabling.
```

### dtruss blocked by SIP (macOS)
```
Notice: dtruss cannot trace this binary — System Integrity Protection blocks
DTrace against Apple-signed and hardened-runtime processes.
Do NOT disable SIP. Alternatives:
  - lldb breakpoints on the suspect libc entry points
  - reproduce on Linux under: strace -f -e trace=file ./prog
```

### py-spy cannot attach
```
Error: py-spy could not attach to pid {N} (permission denied).
  macOS: run under sudo.
  Linux: run under sudo, or lower kernel.yama.ptrace_scope for this session.
Fallback: python3 -X faulthandler, or send SIGABRT and inspect the traceback.
```

### Ambiguous mode
```
Notice: Could not classify "{first token}" as a failure or a scope.
Defaulting to configure mode over {path}.
Re-run with an explicit mode: /system-developer:debug triage "<error text>"
```

### Debugger missing

| Missing tool | Install hint |
|--------------|--------------|
| `gdb` | `brew install gdb` (macOS needs codesigning) / distro `gdb` |
| `lldb` | `brew install llvm` / `xcode-select --install` |
| `strace` / `ltrace` | distro package (Linux-only; macOS uses `dtruss`) |
| `py-spy` | `uv tool install py-spy` |
| `valgrind` | distro package (Linux-first; limited on recent macOS) |

Report FAIL with the aggregated hints only when every tool the chosen route needs is missing.

## See Also

- `system-developer:diagnostics` skill — full symptom→tool routing, sanitizer/gdb/lldb/perf flags, core-dump and rr workflows, sanitizer report→diagnosis table.
- `/system-developer:sanitize-check` — first pass for crash, UB, leak, and race symptoms.
- `/system-developer:build-test` — `--type Debug` for the `-O0 -g` build.
- `/system-developer:review-code --fix` — applies the fix triage doesn't.
- `/system-developer:fix-performance` — when the program is slow rather than wrong.
- `/system-developer:gen-tests` — lock the root cause behind a regression test.
