# gdb / lldb Reference

Interactive debugging commands for C/C++ on Linux (gdb) and macOS (lldb): core dumps, attaching, rr replay, and Python + native extensions. For a memory or race bug you haven't characterized, run a sanitizer first ([sanitizers.md](sanitizers.md)); the debugger is for after you know roughly where.

## Which Debugger

| Platform | Default | Notes |
|----------|---------|-------|
| Linux | gdb | pairs with rr for reverse debugging |
| macOS | lldb | ships with the command-line tools; gdb on macOS needs code signing and is rarely worth it |

## Launching and Basic Loop

```bash
gdb --args ./prog arg1 arg2     # gdb (Linux)
lldb -- ./prog arg1 arg2        # lldb (macOS)
```

Post-crash loop (gdb / lldb):

```
run            / run
bt             / bt
frame 2        / frame select 2
print var      / p var
continue       / continue
quit           / quit
```

Build with `-g`, and `-O0` or `-Og` for faithful stepping; at `-O2` variables get optimized out and lines reorder.

## Command Translation Table

### Execution and breakpoints

| Action | gdb | lldb |
|--------|-----|------|
| Run with args | `run a b` | `run a b` |
| Backtrace / all threads | `bt` / `thread apply all bt` | `bt` / `bt all` |
| Select frame | `frame 2` | `frame select 2` / `f 2` |
| Step into / over / out | `step` / `next` / `finish` | `s` / `n` / `finish` |
| Instruction step | `stepi` | `si` |
| Breakpoint at function | `break func` | `b func` |
| Breakpoint at file:line | `break file.c:42` | `b file.c:42` |
| Conditional breakpoint | `break f if x==0` | `breakpoint set -n f -c 'x==0'` |
| List / delete / disable | `info breakpoints` / `delete 2` / `disable 2` | `breakpoint list` / `breakpoint delete 2` / `breakpoint disable 2` |
| Watchpoint | `watch expr` | `watchpoint set variable expr` |
| Run a script file | `source cmds.gdb` | `command source cmds.lldb` |
| Reverse continue | `reverse-continue` (rr or native record) | — use rr under gdb |

### State

| Action | gdb | lldb |
|--------|-----|------|
| Print value | `print x` | `p x` |
| Locals / args | `info locals` / `info args` | `frame variable` / `frame variable --no-locals` |
| Examine memory | `x/16xb ptr` | `memory read -c 16 -f x -s 1 ptr` |
| Registers | `info registers` | `register read` |
| List source | `list` | `source list` |
| Threads / switch | `info threads` / `thread 3` | `thread list` / `thread select 3` |
| Set variable / call | `set var x = 5` / `call f(2)` | `expression x = 5` / `expression f(2)` |

The full mapping is the upstream "GDB to LLDB command map".

## Breakpoints and Watchpoints

```
# gdb: stop only when the condition holds; or only after the 100th hit
break process_node if node->id == 4173
break parse
ignore 1 99

# lldb
breakpoint set -n process_node -c 'node->id == 4173'
breakpoint set -n parse -i 99
```

Watchpoints are the fastest route to "who is corrupting this variable?":

```
# gdb
watch g_counter
watch g_counter if g_counter < 0

# lldb
watchpoint set variable g_counter
watchpoint modify -c '(g_counter < 0)' 1
```

Hardware watchpoints are few (typically 4) and scoped to the variable's lifetime; re-arm after leaving scope.

## Inspecting State

```
# gdb
print *ptr
print *arr@10         # 10 elements starting at arr[0]
print/x value
ptype obj             # static type / struct layout
x/8xw ptr             # 8 words, hex

# lldb
p *ptr
parray 10 arr
p/x value
frame variable -T obj # with types
memory read -c 8 -f x -s 4 ptr
```

In C++, `p obj` uses pretty-printers, so containers print as contents.

## TUI Mode

```
# gdb
gdb -tui ./prog          # or inside a session: tui enable (Ctrl-x a)
layout src               # source pane; layout split = source + assembly
focus cmd                # keyboard focus to the command line

# lldb
gui                      # curses UI
```

In gdb TUI, `Ctrl-x o` cycles pane focus and `refresh` redraws a corrupted display.

## Breakpoint Scripting and Automation

Attach commands to a breakpoint so it logs and continues — a tracer without editing code.

```
# gdb
break allocate_buffer
commands
  silent
  printf "alloc size=%d\n", size
  continue
end

# lldb
breakpoint set -n allocate_buffer
breakpoint command add
> expression -- (void)printf("alloc size=%d\n", size)
> continue
> DONE
```

Non-interactive runs:

```bash
gdb -batch -ex 'break main' -ex run -ex bt -ex quit --args ./prog arg
gdb -x cmds.gdb --args ./prog
lldb -b -o 'breakpoint set -n main' -o run -o bt -o quit -- ./prog arg
lldb -s cmds.lldb -- ./prog
```

Both embed Python (`python` in gdb, `script` in lldb) for richer automation.

## Pretty-Printers

gdb ships libstdc++ pretty-printers and most distros auto-load them. If `p myvec` shows raw `_M_impl`, load them (path varies by distro):

```
python
import sys; sys.path.insert(0, '/usr/share/gcc/python')
from libstdcxx.v6.printers import register_libstdcxx_printers
register_libstdcxx_printers(None)
end
```

`set print pretty on` formats structs across lines. lldb has built-in formatters for libc++ `std::` types; add your own with `type summary add --summary-string "id=${var.id} name=${var.name}" MyStruct`. The gdb equivalent is a Python pretty-printer registered against the type name.

## Core-Dump Workflow

A core dump lets you debug a crash after the fact.

```bash
ulimit -c unlimited                  # this shell only
cat /proc/sys/kernel/core_pattern    # Linux: where cores go

gdb ./prog core                      # Linux, core file
coredumpctl list                     # Linux, systemd-coredump captures cores
coredumpctl debug [PID|exe]          # newest (or a specific) crash in gdb
coredumpctl dump <match> > core      # extract the core file

lldb -c /cores/core.<pid> ./prog     # macOS (cores under /cores when enabled)
```

Open it with the exact binary and debug info that produced it; a rebuilt binary gives wrong lines or no symbols.

## Attaching to a Live Process

For hangs, runaway loops, or a stuck production process.

```bash
gdb -p <pid>            # or: gdb ./prog <pid> for symbols from ./prog
lldb -p <pid>           # or inside lldb: process attach --name prog
```

For a deadlock, attach and run `thread apply all bt` (gdb) / `bt all` (lldb) to see which threads wait on which locks; `detach` leaves the process running.

If Linux denies the attach, check `sysctl kernel.yama.ptrace_scope` (1 = descendants only); run the debugger as the process owner or lower it with privilege.

## rr: Record and Replay (Linux)

rr records a run once, then replays it deterministically under gdb, including reverse execution — the answer to flaky, order-dependent, or rare crashes. Recording overhead is often ~1.2x. Linux only.

```bash
rr record ./prog arg1     # loop this until a rare crash hits
rr replay                 # replay the latest recording under gdb
rr ps                     # recorded processes in the latest trace
rr replay -p <pid>        # replay a specific one
```

### Reverse execution

```
continue                # forward to the crash
reverse-continue        # back to the previous breakpoint/watchpoint hit
reverse-next            # step back over a line
reverse-step            # step back into
watch -l corrupted_var  # then reverse-continue to the write that corrupted it
```

At a use-after-free, watch the freed slot and `reverse-continue`: rr stops at the `free`. Every replay reproduces the same addresses and scheduling, across threads and processes.

## Debugging Python + Native Together

When a C/C++ extension crashes or hangs, you need both stacks.

```bash
gdb --args python -X faulthandler script.py   # Linux; bt at the crash shows C frames
lldb -- python script.py                      # macOS
```

CPython's gdb helpers (`python-gdb.py`, auto-loaded for debug builds or shipped as `python3.x-gdb`) add Python-level commands; if missing, `source` the helper explicitly:

```
py-bt            # Python backtrace interleaved with C frames
py-list          # source around the current Python frame
py-locals        # Python locals
py-up / py-down  # move through Python frames
```

### Without a debugger

- `python -X faulthandler` (or `faulthandler.enable()`) dumps the Python traceback on a fatal signal.
- `py-spy dump --pid <pid>` shows the live stack of a hung process, with C frames on Linux ([profiling-tools.md](profiling-tools.md)).
- Build the extension with `-g`, or native frames are useless.

For UAF, overflow, or uninitialized bugs in the extension, run it under a sanitizer first ([sanitizers.md](sanitizers.md) > Python C extensions).

## Diagnostic Table

| Symptom | Cause | Fix |
|---------|-------|-----|
| `No symbol table is loaded` / `??` frames | no `-g`, or wrong binary | rebuild with `-g`; match binary to core |
| `<optimized out>` | optimized build | rebuild at `-O0`/`-Og` |
| `ptrace: Operation not permitted` | `ptrace_scope` | run as owner; lower it (privileged) |
| core opens, lines wrong | binary/core mismatch | the exact binary + debug info |
| container prints raw internals | pretty-printers not loaded | see Pretty-Printers |
| watchpoint can't be set or vanishes | out of hardware slots / out of scope | fewer watchpoints; re-arm in scope |
| C-extension crash, no Python context | native-only stack | `py-bt` / `faulthandler` |
| race reproduces 1 in 100 runs | scheduling-dependent | `rr record`, replay, `reverse-continue` |
| gdb on macOS: code-signing error | gdb needs signing | use lldb |

## Related References

- [sanitizers.md](sanitizers.md) — characterize the bug class before stepping
- [profiling-tools.md](profiling-tools.md) — slow or hung rather than crashing
- [c-memory-ownership](../../../c/c-memory-ownership/SKILL.md) — the ownership model behind UAF and leak bugs
