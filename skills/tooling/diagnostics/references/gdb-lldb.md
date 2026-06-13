# gdb / lldb Reference

Use this when:

- You are stepping through C/C++ code interactively and need the exact commands.
- You know the gdb command but you are on macOS (lldb), or vice versa.
- You are opening a core dump, attaching to a live process, or replaying with rr.
- You are debugging a C/C++ extension called from Python.

Skip if:

- You only need to pick a tool from a symptom. See the [diagnostics SKILL.md](../SKILL.md).
- The fault is a memory/race bug you have not characterized — run a sanitizer
  first ([sanitizers.md](sanitizers.md)); the debugger is for *after* you know roughly where.

Jump to:

- Which Debugger
- Launching and Basic Loop
- Command Translation Table
- Breakpoints and Watchpoints
- Inspecting State
- TUI Mode
- Breakpoint Scripting and Automation
- Pretty-Printers
- Core-Dump Workflow
- Attaching to a Live Process
- rr: Record and Replay (Linux)
- Debugging Python + Native Together
- Diagnostic Table

---

## Which Debugger

| Platform | Default | Notes |
|----------|---------|-------|
| Linux | **gdb** | Native; pairs with rr for reverse debugging |
| macOS | **lldb** | Ships with the command-line tools; gdb on macOS needs code-signing the binary and is rarely worth it |

Both attach to running processes, open core dumps, set conditional breakpoints,
and run scripts. The model is the same; the command spellings differ.

---

## Launching and Basic Loop

```bash
gdb --args ./prog arg1 arg2     # gdb (Linux)
lldb -- ./prog arg1 arg2        # lldb (macOS)
```

The minimal post-crash loop (commands shown gdb / lldb):

```
run            / run            # start the program
bt             / bt             # backtrace at the fault
frame 2        / frame select 2 # move to a stack frame
print var      / p var          # inspect a value
continue       / continue       # resume
quit           / quit           # exit
```

Build the program with `-g` (and `-O0` or `-Og` for faithful stepping; at `-O2`
variables get optimized out and lines reorder).

---

## Command Translation Table

| Action | gdb | lldb |
|--------|-----|------|
| Run | `run` / `r` | `run` / `r` |
| Run with args | `run a b` | `run a b` (or `settings set target.run-args a b`) |
| Backtrace | `bt` | `bt` / `thread backtrace` |
| Backtrace all threads | `thread apply all bt` | `bt all` |
| Select frame | `frame 2` / `f 2` | `frame select 2` / `f 2` |
| Up / down frames | `up` / `down` | `up` / `down` |
| Step into | `step` / `s` | `thread step-in` / `s` |
| Step over | `next` / `n` | `thread step-over` / `n` |
| Step out | `finish` | `thread step-out` / `finish` |
| Continue | `continue` / `c` | `continue` / `c` |
| Instruction step | `stepi` / `si` | `thread step-inst` / `si` |
| Breakpoint at function | `break func` / `b func` | `breakpoint set -n func` / `b func` |
| Breakpoint at file:line | `break file.c:42` | `breakpoint set -f file.c -l 42` / `b file.c:42` |
| Conditional breakpoint | `break f if x==0` | `breakpoint set -n f -c 'x==0'` |
| List breakpoints | `info breakpoints` | `breakpoint list` |
| Delete breakpoint | `delete 2` | `breakpoint delete 2` |
| Disable breakpoint | `disable 2` | `breakpoint disable 2` |
| Watchpoint | `watch expr` | `watchpoint set variable expr` |
| Print value | `print x` / `p x` | `p x` / `expression x` |
| Print all locals | `info locals` | `frame variable` |
| Print args | `info args` | `frame variable -a` (or just `frame variable`) |
| Examine memory | `x/16xb ptr` | `memory read -c 16 -f x -s 1 ptr` |
| Registers | `info registers` | `register read` |
| List source | `list` / `l` | `source list` / `l` |
| List threads | `info threads` | `thread list` |
| Switch thread | `thread 3` | `thread select 3` |
| Set variable | `set var x = 5` | `expression x = 5` |
| Call function | `call f(2)` | `expression f(2)` |
| Run a script file | `source cmds.gdb` | `command source cmds.lldb` |
| Reverse continue (rr/native) | `reverse-continue` / `rc` | (use rr under gdb) |

For deeper lldb<->gdb mapping, lldb ships a map at `lldb` -> `help` and the
upstream "GDB to LLDB command map".

---

## Breakpoints and Watchpoints

### Conditional and counted breakpoints

```
# gdb: only stop when the condition holds
break process_node if node->id == 4173
# stop only after the 100th hit
break parse
ignore 1 99

# lldb
breakpoint set -n process_node -c 'node->id == 4173'
breakpoint set -n parse -i 99
```

### Watchpoints — stop when a value changes

Watchpoints are the fastest route to "who is corrupting this variable?".

```
# gdb: hardware watchpoint on a global / in-scope variable
watch g_counter
# break only on writes that make it negative
watch g_counter if g_counter < 0

# lldb
watchpoint set variable g_counter
watchpoint modify -c '(g_counter < 0)' 1
```

Hardware watchpoints are limited in number (typically 4) and scoped to the
variable's lifetime; re-arm after leaving scope.

---

## Inspecting State

```
# gdb
print expr            # evaluate an expression in the current frame
print *ptr            # dereference
print arr@10          # print 10 elements starting at arr
print/x value         # hex
info locals           # all locals in the frame
info args             # function arguments
ptype obj             # the static type / struct layout
x/8xw ptr             # 8 words, hex, from ptr

# lldb
p expr
p *ptr
parray 10 arr         # 10 elements
p/x value
frame variable        # locals + args
frame variable -T obj # with types
memory read -c 8 -f x -s 4 ptr
```

In C++, `p obj` invokes pretty-printers (see below) so containers print as
contents, not raw internals.

---

## TUI Mode

A split source/assembly/registers view inside the terminal — far easier than
blind stepping.

```
# gdb
gdb -tui ./prog          # start in TUI
# or toggle inside a session:
tui enable               # (older: Ctrl-x a)
layout src               # source pane
layout split             # source + assembly
focus cmd                # move keyboard focus to the command line

# lldb
gui                      # lldb's curses UI (b breakpoints, s/n step, etc.)
```

In gdb TUI, `Ctrl-x o` cycles focus between panes; arrow keys scroll the focused
pane. If the display corrupts, `refresh` (gdb) redraws.

---

## Breakpoint Scripting and Automation

Attach commands to a breakpoint so it logs and auto-continues — turning a
debugger into a precise tracer without editing code.

### gdb — `commands`

```
break allocate_buffer
commands
  silent
  printf "alloc size=%d caller=%p\n", size, __builtin_return_address(0)
  continue
end
```

Run a whole session non-interactively:

```bash
gdb -batch -ex 'break main' -ex run -ex 'bt' -ex quit --args ./prog arg
gdb -x cmds.gdb --args ./prog          # cmds.gdb holds the commands above
```

### lldb — breakpoint command add

```
breakpoint set -n allocate_buffer
breakpoint command add
> expression --   (void)printf("alloc size=%d\n", size)
> continue
> DONE
```

Batch:

```bash
lldb -b -o 'breakpoint set -n main' -o run -o bt -o quit -- ./prog arg
lldb -s cmds.lldb -- ./prog
```

Both debuggers also embed Python (`python` in gdb, `script` in lldb) for richer
automation — generate breakpoints from a list, summarize data structures, etc.

---

## Pretty-Printers

Containers print as their contents rather than internal nodes.

- **gdb** ships libstdc++ pretty-printers; on most distros they auto-load. If
  `p myvec` shows raw `_M_impl`, enable them:

  ```
  python
  import sys; sys.path.insert(0, '/usr/share/gcc/python')
  from libstdcxx.v6.printers import register_libstdcxx_printers
  register_libstdcxx_printers(None)
  end
  ```

  Toggle with `set print pretty on`.

- **lldb** has built-in data formatters for `std::` types (libc++). `p myvec`
  and `frame variable myvec` show elements directly. Add your own:

  ```
  type summary add --summary-string "id=${var.id} name=${var.name}" MyStruct
  ```

  gdb equivalent for a custom type is a Python pretty-printer registered against
  the type name.

---

## Core-Dump Workflow

A core dump is a snapshot of the crashed process — debug after the fact, no live
reproduction needed.

### Enable core dumps

```bash
ulimit -c unlimited          # this shell only (put in a wrapper script)
# Linux: where cores go is set by the kernel
cat /proc/sys/kernel/core_pattern
```

On systemd-based Linux, cores are captured by `systemd-coredump`, not dropped in
the working directory.

### Open a core

```bash
# Linux, manual core file
gdb ./prog core
# then: bt, frame N, info locals

# Linux, systemd-coredump
coredumpctl list                 # find the crash
coredumpctl debug                # open newest in gdb
coredumpctl debug <PID|exe>      # a specific one
coredumpctl dump <match> > core  # extract the core file

# macOS (cores under /cores when enabled)
lldb -c /cores/core.<pid> ./prog
# then: bt, frame select N, frame variable
```

Match the *exact* binary (and its debug info / `.debug` files) that produced the
core — a recompiled binary gives wrong line numbers or "no symbols".

---

## Attaching to a Live Process

For hangs, runaway loops, or "it's stuck in production".

```bash
# gdb
gdb -p <pid>            # attach; then bt, thread apply all bt, continue, detach
gdb ./prog <pid>        # attach with symbols from ./prog

# lldb
lldb -p <pid>
# or inside lldb:  process attach --pid <pid>   /   process attach --name prog
```

For a deadlock: attach, `thread apply all bt` (gdb) / `bt all` (lldb), and read
which threads are blocked on which locks. `detach` (gdb) / `detach` (lldb) leaves
the process running.

Linux may restrict attaching (`ptrace_scope`); if attach is denied:

```bash
# allow for this session (needs privilege); or run the debugger as the process owner
sysctl kernel.yama.ptrace_scope     # 0 = unrestricted, 1 = same-process-tree only
```

---

## rr: Record and Replay (Linux)

rr records a run once, then replays it **deterministically** under a
gdb-compatible interface — including reverse execution. It is the answer to flaky,
order-dependent, or rare crashes: capture it once, then debug the recording as
many times as you want. Recording overhead is low (often ~1.2x). **Linux only.**

```bash
rr record ./prog arg1            # record a run (rare crash? loop record until it hits)
rr replay                        # replay the most recent recording under gdb
rr replay -p <pid>               # replay a specific recorded process
rr ps                            # list recorded processes in the latest trace
```

Inside the replay (it is gdb), forward *and* backward commands work:

```
continue                # forward to the crash
reverse-continue        # run backward to the previous breakpoint/watchpoint hit
reverse-next            # step backward over a line
reverse-step            # step backward into
watch -l corrupted_var  # then reverse-continue to find the write that corrupted it
```

The killer move: stop at a use-after-free, set a watchpoint on the freed slot,
`reverse-continue`, and rr stops exactly at the `free`. Determinism means every
replay reproduces the same addresses and scheduling. rr drives multi-process and
multi-threaded workloads, which is why it is used on browsers and emulators.

---

## Debugging Python + Native Together

When a C/C++ extension imported by Python crashes (or hangs), you need both the
native stack and the Python stack.

### Native debugger on the Python process

```bash
# Linux: run python under gdb so the SIGSEGV stops in the C frame
gdb --args python -X faulthandler script.py
# at the crash: bt   -> native (C extension) frames

# macOS
lldb -- python script.py
```

### Get the Python-level stack from inside gdb

CPython ships gdb helpers (`python-gdb.py`, often auto-loaded for a debug build,
or installed as `python3.x-gdb`). Then:

```
# gdb, while stopped in a native frame:
py-bt            # Python-level backtrace interleaved with C frames
py-list          # source around the current Python frame
py-locals        # Python locals in the current frame
py-up / py-down  # move through Python frames
```

If `py-bt` is missing, load the helper explicitly:

```
source /usr/share/gdb/auto-load/.../python3.x-gdb.py
```

### Faster triage without a debugger

- `python -X faulthandler script.py` (or `faulthandler.enable()`) dumps the
  Python traceback on a fatal native signal — often enough to localize the call.
- `py-spy dump --pid <pid>` shows the live Python stack of a hung process, and
  with native support shows C frames too (Linux). See [profiling-tools.md](profiling-tools.md).
- Build the extension with `-g`; without it the native frames are useless.

For *uninitialized*/*overflow*/*UAF* bugs in the extension itself, run it under a
sanitizer first ([sanitizers.md](sanitizers.md) > Python C extensions) — the
debugger then steps you to the exact line the sanitizer named.

---

## Diagnostic Table

| Symptom | Cause | Fix / action | Reference |
|---------|-------|--------------|-----------|
| `No symbol table is loaded` / `??` frames | built without `-g`, or wrong binary | rebuild with `-g`; match the binary to the core | this file > Core-Dump Workflow |
| Variables show `<optimized out>` | optimized build | rebuild target at `-O0`/`-Og` for debugging | this file > Launching |
| `ptrace: Operation not permitted` on attach | `kernel.yama.ptrace_scope` | run as process owner; lower `ptrace_scope` (privileged) | this file > Attaching |
| Core file opens but lines are wrong | binary/core mismatch | open the *exact* built binary + its debug info | this file > Core-Dump Workflow |
| Container prints raw internals | pretty-printers not loaded | enable libstdc++ printers / lldb formatters | this file > Pretty-Printers |
| Watchpoint "cannot set" / silently dropped | out of hardware watch slots or variable out of scope | reduce watchpoints; re-arm in scope | this file > Breakpoints and Watchpoints |
| Crash in C extension, no Python context | native-only stack | `py-bt` / `faulthandler` for the Python frames | this file > Python + Native |
| Race reproduces 1-in-100 runs | scheduling-dependent | record under `rr`, replay + `reverse-continue` | this file > rr |
| gdb on macOS "not in code-signing group" | gdb needs signing on macOS | use lldb instead | this file > Which Debugger |

## Related References

- [sanitizers.md](sanitizers.md) — characterize the bug class before stepping; symbolizer setup
- [profiling-tools.md](profiling-tools.md) — when the program is slow/hung rather than crashing
- [diagnostics SKILL.md](../SKILL.md) — symptom -> tool router and quickstarts
- [c-memory-ownership](../../../c/c-memory-ownership/SKILL.md) — the ownership model behind UAF/leak bugs
