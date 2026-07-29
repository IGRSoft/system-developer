---
description: Configure debugging workflows, or triage and root-cause a crash, hang, or wrong-value bug in C, C++, Python, or Bash
argument-hint: [configure|triage] [path, error text, stack trace, core file, or pid]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
estimated-cost:
  min-tokens: 2000
  max-tokens: 16000
  model-distribution:
    haiku: 15%
    sonnet: 70%
    opus: 15%
---

# Debug & Triage
<!-- Updated: July 2026 -->

Two jobs behind one entry point. **Configure mode** stands up debugging infrastructure for a project — a debug build that actually carries symbols, core dumps enabled, debugger init files, trace hooks, and a documented reproduction loop. **Triage mode** takes one concrete failure already in hand — a segfault, a hang, a `Traceback`, a core file, a wrong number — and drives it to a named root cause.

The first token of `$ARGUMENTS` picks the mode; everything else is the target. Both modes lean on `skill: diagnostics`, which is canonical for symptom→tool routing and the exact flag spellings — reference it, never restate it here.

[Extended thinking: The trap in a systems debugging command is reaching for gdb by reflex. A debugger shows you the aftermath — the frame where the process finally died — while the defect (the overflowing write, the unsynchronized store, the signed overflow the optimizer exploited) happened earlier and elsewhere. For memory corruption, UB, and races a sanitizer *names* the defect at its origin, so this command routes those symptoms to `/system-developer:sanitize-check` before any breakpoint is set, and reserves interactive debugging for logic bugs, hangs, and state inspection. The second trap is debugging an optimized binary: variables read `<optimized out>` and stacks are inlined away, which is why the `-O0 -g` prerequisite is enforced up front rather than discovered ten minutes in. Configure mode may write scaffolding; triage mode stays advisory and hands the fix to the owning language agent.]

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **Dispatch before anything else.** Resolve the mode from the first token of `$ARGUMENTS` (see Mode Dispatch), state which mode you chose and why, then execute only that mode's phases.
2. **Sanitizer before debugger.** For a crash/segfault, wrong-value, leak, or suspected-race symptom in C/C++, the first move is `/system-developer:sanitize-check`, not gdb. Only escalate to a debugger when the sanitizer is clean or the symptom is a logic bug/hang.
3. **Enforce the debug build.** Interactive debugging requires `-O0 -g` (plus `-fno-omit-frame-pointer`). If the target was built optimized, say so and rebuild before setting breakpoints — do not read values out of an optimized frame.
4. **Triage does not fix.** Triage mode produces a root cause with evidence. It MUST NOT edit source to "fix" the bug — route the fix to the owning language agent or `/system-developer:review-code --fix`.
5. **Capture to a log.** Every debugger, trace, and reproduction run tees to `.context/logs/debug-<timestamp>.log`. The log is the source of truth; do not rely on scrollback.
6. **Resolve the language before delegating.** Use `skill: language-detection` for the marker→language→agent map. Ambiguous trees go to `system-developer:system-developer` (router), never to a guessed language agent.
7. **Tool-missing never hard-fails.** If gdb/lldb/strace/ltrace/py-spy is unavailable, print the install hint, note the constraint (see Platform Constraints), and continue with the tools that are present.
8. **Grade severity as P0–P3** per `skill: severity-matrix`. No ad-hoc severity words.
9. **Never enter plan mode.** This command IS the procedure — execute it.

## Usage

```bash
# Configure debugging infrastructure for a project
/system-developer:debug configure .
/system-developer:debug configure services/parser

# Triage a specific failure
/system-developer:debug triage "Segmentation fault (core dumped)"
/system-developer:debug triage "TypeError: 'NoneType' object is not subscriptable at etl.py:88"
/system-developer:debug triage core /cores/core.44231

# Ambiguous first token -> configure (a bare path is a scope, not an error)
/system-developer:debug .

# A hung process: attach and dump stacks
/system-developer:debug triage --pid 44231
```

## Options

| Option | Default | Effect |
|--------|---------|--------|
| `configure` | default | Set up debugging infrastructure for the target path: `-O0 -g` build config, core dumps, debugger init file, trace/logging hooks, reproduction loop. |
| `triage` | — | Root-cause one specific failure. Requires an error string, stack trace, core file, or `--pid`. Advisory only (Rule 4). |
| `path` | `.` | Configure-mode scope; also the source tree used to resolve symbols in triage. |
| `--pid N` | none | Triage a live process: attach with gdb/lldb (`thread apply all bt`) or `py-spy dump` for Python. Implies `triage`. |
| `--core FILE` | none | Triage a core dump against the matching binary. Implies `triage`. |
| `--no-sanitize` | off | Skip the Rule 2 sanitizer step when the caller has already run it. Record why in the report. |

## Mode Dispatch

Read the first token of `$ARGUMENTS`:

- Literal `configure` → **Configure mode**. Remainder is the path.
- Literal `triage`, or `--pid` / `--core` anywhere in the arguments → **Triage mode**. Remainder is the failure evidence.
- Neither literal present → infer: text that looks like a **failure** (contains `error`, `Error`, `Traceback`, `Segmentation fault`, `Assertion`, `panic`, `core dumped`, `undefined behavior`, a `signal N`, or a `file:line` inside a stack frame) → Triage mode; a bare path, directory, or empty argument → Configure mode.
- **Default when still ambiguous: Configure mode.** Configure is non-destructive scaffolding; guessing triage on a scope argument wastes a reproduction cycle. State the inference and the default you fell back to.

## Symptom → Tool Routing

`skill: diagnostics` is canonical for this table and for every flag spelling below. This is the routing summary only.

| Symptom | First tool | Escalation |
|---------|-----------|------------|
| Crash / `SIGSEGV` / `SIGABRT` / heap corruption | `/system-developer:sanitize-check asan` | gdb/lldb on the core if ASan is clean |
| Wrong values, behavior changes with `-O2` | `/system-developer:sanitize-check ubsan` | debugger with `-O0 -g`; bisect the optimization level |
| Hang / deadlock (native) | attach + `thread apply all bt` | `/system-developer:sanitize-check tsan` for lock-order reports |
| Hang / stuck (Python) | `py-spy dump --pid N` | `faulthandler`, then `pdb` at the stuck call |
| Leak / unbounded growth | `/system-developer:sanitize-check lsan` | `valgrind --tool=massif` when recompiling is impossible |
| Data race / intermittent wrong results | `/system-developer:sanitize-check tsan` | debugger only to inspect the state TSan named |
| Slow, not wrong | `/system-developer:fix-performance` | not a debugging problem — profile, don't breakpoint |
| Syscall/env failure (`ENOENT`, bad path, missing fd) | `strace` / `dtruss` | `ltrace` for library-call level |

A sanitizer names the defect at its origin; a debugger only shows where the process finally died. That is why Rule 2 puts the sanitizer first for the top three rows.

## Debug Build Prerequisite

Interactive debugging and profiling want **different** builds — do not reuse one for the other:

| Purpose | Flags | Why |
|---------|-------|-----|
| Interactive debugging | `-O0 -g` | Locals stay live and addressable; no inlining, so frames match source. `-O1+` yields `<optimized out>` and merged frames. |
| Profiling / sanitizers | `-O2 -g` (`RelWithDebInfo`) | Real optimized timing and codegen, with symbols retained. |

Always add `-fno-omit-frame-pointer` so backtraces are reliable, and keep `llvm-symbolizer` on `PATH` or frames render as `??`.

The trade-off is explicit: `-O0` changes timing and can hide optimizer-sensitive bugs. If a bug only reproduces at `-O2`, do **not** force `-O0` — treat it as a UB candidate and run UBSan (`skill: diagnostics`).

## Debugger Quick Reference

gdb (Linux) and lldb (macOS) — full command translation lives in `skill: diagnostics` (gdb/lldb reference).

```bash
gdb --args ./prog arg1        # then: run, bt, frame N, info locals, print x
lldb -- ./prog arg1           # then: run, bt, frame select N, frame variable, p x
```

| Need | gdb | lldb |
|------|-----|------|
| All thread stacks (hangs) | `thread apply all bt` | `bt all` |
| Conditional breakpoint | `break f.c:42 if n > 10` | `b -f f.c -l 42 -c 'n > 10'` |
| Stop on value change | `watch obj->state` | `watchpoint set variable obj->state` |
| Attach to a live process | `gdb -p N` | `lldb -p N` |
| Open a core | `gdb ./prog core` | `lldb -c /cores/core.N ./prog` |

Pretty-printers make container state readable (libstdc++ ships gdb printers; lldb ships libc++ synthetics) — load them before inspecting `std::` types, and note in the report when raw internals were read instead.

## Core Dumps

Enable before reproducing, not after:

```bash
ulimit -c unlimited                  # this shell only
./prog                               # crash writes a core

coredumpctl list && coredumpctl debug   # Linux + systemd: newest crash under gdb
gdb ./prog core                          # Linux, manual core file

sudo sysctl -w kern.coredump=1           # macOS: cores land in /cores
lldb -c /cores/core.<pid> ./prog
```

Cores are only useful against the **same binary** that produced them, unstripped. If the binary was rebuilt since the crash, say so and re-reproduce rather than reading mismatched symbols.

## Syscall & Library Tracing

Use when the failure is at the boundary — a wrong path, a missing file, a permission denial, an unexpected `errno`:

```bash
strace -f -e trace=file,network -o trace.log ./prog     # Linux
ltrace -f ./prog                                        # Linux, library calls
sudo dtruss -f ./prog                                   # macOS
```

`strace -f` follows forks; narrow with `-e trace=` before reading, or the log is unusable. `ltrace` is Linux-first and unreliable against statically linked or heavily PLT-optimized binaries.

**macOS constraint:** `dtruss` needs `sudo` and is blocked by System Integrity Protection for Apple-signed and hardened-runtime binaries. Do not instruct the user to disable SIP. When `dtruss` is blocked, fall back to `lldb` breakpoints on the suspect libc entry points, or reproduce the failure on Linux under `strace`.

## Python & Bash Debugging

**Python** — sampling and interactive, no rebuild required:

```bash
py-spy dump --pid 44231                 # stack of a hung/stuck process, right now
py-spy record -o profile.svg --pid N    # sampled profile of a running process
python3 -X faulthandler -m mypkg        # dump all stacks on fatal signal
breakpoint()                            # in-source; honors PYTHONBREAKPOINT
python3 -m pdb -c continue script.py    # post-mortem at the exception
```

`py-spy` needs ptrace permission: `sudo` on macOS, and on Linux either `sudo` or a relaxed `kernel.yama.ptrace_scope`.

**Bash** — tracing is the debugger:

```bash
bash -x ./script.sh                                      # trace without editing
set -x; set +x                                           # scope a trace region
PS4='+ ${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]:-main}: '  # file:line:function per line
exec 9>trace.log; BASH_XTRACEFD=9                        # trace off stdout/stderr
trap 'echo "ERR line $LINENO: $BASH_COMMAND" >&2' ERR    # report the failing command
```

Pair `trap ERR` with `set -euo pipefail` — without strict mode the script sails past the failure it just reported.

## Workflow

### Phase 1: Dispatch & Detect (both modes)

1. Resolve the mode per **Mode Dispatch**; announce it and the inference used.
2. Resolve language and build system via `skill: language-detection`; record the owning language agent.
3. Create `.context/logs/`; set `LOG=".context/logs/debug-$(date +%Y%m%d-%H%M%S).log"`.
4. Probe available tooling (`command -v gdb lldb strace ltrace dtruss py-spy`); record what is missing (Rule 7) and any platform constraint that applies.

### Phase 2: Configure mode — scaffold

1. Ensure a debug build configuration exists with `-O0 -g -fno-omit-frame-pointer` (a CMake `Debug` config / preset, Meson `--buildtype debug`, or the Makefile's debug target). Verify it builds via `/system-developer:build-test . --type Debug`.
2. Enable core dumps for the platform (see Core Dumps) and document where cores land.
3. Write debugger scaffolding the project lacks: a `.gdbinit`/`.lldbinit` with the project's pretty-printers and common breakpoints, or a documented `py-spy`/`pdb` entry point.
4. Add the trace hooks the language warrants — `PS4` + `BASH_XTRACEFD` for shell entry points, `faulthandler` for Python services.
5. Document the reproduction loop: exact command, environment, expected vs actual. Stop here — configure mode does not hunt bugs.

### Phase 3: Triage mode — classify & reproduce

1. Parse the evidence: signal/exception type, top user-code frame, `file:line`, thread count, whether it is deterministic.
2. Assign a severity (P0–P3) per `skill: severity-matrix`.
3. Route the symptom through **Symptom → Tool Routing**. Unless `--no-sanitize`, run the indicated `/system-developer:sanitize-check` kind first and let it name the defect.
4. Establish the narrowest reliable reproduction, teeing to `$LOG`. If it is not reproducible, say so and continue from static evidence — do not fabricate a repro.

### Phase 4: Triage mode — root cause

1. If the sanitizer named the defect, that IS the root cause — go to Phase 5 with its report.
2. Otherwise gather debugger evidence: core or attach → `bt` / `thread apply all bt`, locals at the faulting frame, watchpoint on the suspect variable; `py-spy dump` for a stuck Python process; `strace`/`dtruss` when the boundary is a syscall.
3. State the causal chain from trigger to failure, with the evidence line for each link. Mark unproven links explicitly.
4. For a deep or stalled hunt, escalate: **Use Task tool with subagent_type="debugging-toolkit:debugging-toolkit-debugger"**
   Prompt: "Root-cause this failure. Symptom: {symptom}. Severity: {P0-P3}. Evidence gathered so far (log `{LOG}`):\n```\n{evidence}\n```\nSanitizer result: {clean | finding | skipped}. Produce a ranked hypothesis list with the smallest proof step for each. Read-only — do not modify source."

### Phase 5: Report & route the fix

1. Emit the Output Format for the active mode.
2. Route the fix to the owning language agent — never apply it here (Rule 4):
   - C tree: **Use Task tool with subagent_type="system-developer:c-developer"**
     Prompt: "Root cause identified for the C project at `{path}`: {root_cause}. Evidence in `{LOG}`; failing frame `{file:line}`. Propose the minimal correct fix and a regression test. Do not widen scope beyond this defect."
   - C++ tree → **subagent_type="system-developer:cpp-developer"** (same prompt shape).
   - Python → **subagent_type="system-developer:python-developer"** (same prompt shape).
   - Bash → **subagent_type="system-developer:bash-developer"** (same prompt shape).
   - Ambiguous or cross-language (FFI, native extension) → **subagent_type="system-developer:system-developer"** (router), with the detected markers.
3. If the root cause is a hot path rather than a defect, hand it to **subagent_type="system-developer:sys-performance-engineer"** instead and point at `/system-developer:fix-performance`.
4. Recommend a regression test via `/system-developer:gen-tests`, then verify with `/system-developer:build-test`.

## Output Format

```markdown
## Debug Report — {Configure | Triage}

**Target:** {path}
**Language:** {C | C++ | Python | Bash | mixed}
**Log:** .context/logs/debug-{timestamp}.log

<!-- Configure mode -->
### Debug Infrastructure

| Item | State | Detail |
|------|-------|--------|
| Debug build (`-O0 -g -fno-omit-frame-pointer`) | ✅ / ➕ added / ❌ | {config or preset name} |
| Core dumps | ✅ / ➕ / ⏭ | {ulimit -c / coredumpctl / /cores} |
| Debugger init | ✅ / ➕ / ⏭ | {.gdbinit / .lldbinit / pdb entry point} |
| Trace hooks | ✅ / ➕ / ⏭ | {PS4+BASH_XTRACEFD / faulthandler / none} |

**Reproduction loop:** {exact command, env, expected vs actual}

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

When no root cause was reached, say so plainly, list the surviving hypotheses with their smallest proof step, and stop — do not present a guess as a finding.

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
Print the install hint, note the constraint, continue with what is present.

| Missing tool | Install hint |
|--------------|--------------|
| `gdb` | `brew install gdb` (macOS needs codesigning) / distro `gdb` |
| `lldb` | `brew install llvm` / `xcode-select --install` |
| `strace` / `ltrace` | distro package (Linux-only; macOS uses `dtruss`) |
| `py-spy` | `uv tool install py-spy` |
| `valgrind` | distro package (Linux-first; limited on recent macOS) |

Only when *every* tool required by the chosen route is missing does the command report FAIL with the aggregated hints.

## See Also

- `skill: diagnostics` — canonical symptom→tool routing, exact sanitizer/gdb/lldb/perf flags, core-dump and rr workflows, report-headline→diagnosis table.
- `skill: language-detection` — marker→language→agent routing used by Phase 1.
- `skill: severity-matrix` — the P0–P3 vocabulary used for triage severity.
- `skill: cpp-concurrency`, `skill: python-concurrency` — deadlock and race semantics behind hang triage.
- `skill: bash-scripting` — strict mode, `trap ERR`, and the tracing idioms above.
- `/system-developer:sanitize-check` — run this FIRST for crash, UB, leak, and race symptoms (Rule 2).
- `/system-developer:build-test` — the build/test gate; use `--type Debug` for the `-O0 -g` build.
- `/system-developer:review-code` — `--fix` applies the remediation triage mode deliberately does not.
- `/system-developer:fix-performance` — when the program is slow rather than wrong.
- `/system-developer:gen-tests` — lock the root cause behind a regression test.
