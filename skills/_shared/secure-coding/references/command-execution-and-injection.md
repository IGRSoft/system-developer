# Command Execution and Injection (C / C++ / Python / Bash)

Use this when:

- You need to run an external program from C, C++, Python, or a shell script.
- You build a command line, set its environment, or wire up its file descriptors.
- You are tempted to interpolate a variable into a shell string, `eval`, or call `system`/`popen`.
- A reviewer flagged a shell-injection or arbitrary-code-execution finding.

Skip this file if:

- You are validating or parsing untrusted input. Use `input-validation-and-parsing.md`.
- You only need the rule summary. Use the parent `SKILL.md`.

Jump to:

- The Core Doctrine
- C — `posix_spawn` / `execvp`
- C++ — Same, Plus `std::system` Is Banned
- Python — `subprocess` Without a Shell
- Bash — Quoting, `--`, and No `eval`
- Environment Scrubbing
- Why Dynamic Code Execution Is Banned
- Execution Checklist

## The Core Doctrine

There are two ways to run a program:

1. **Through a shell** — you hand a single string to `/bin/sh -c`, and the shell parses it: word-splitting, globbing, quotes, `;`, `|`, `$(...)`, `>` redirection. If any part of that string came from untrusted input, the attacker controls the shell. This is **command injection**.
2. **Directly** — you hand the kernel a program path and an explicit argument vector (`argv[]`). No shell, no parsing, no metacharacters. An argument that happens to contain `; rm -rf /` is just a literal string passed to the program.

**Always use direct execution.** The argument vector is the security boundary: each element becomes exactly one `argv` entry, with zero reinterpretation. There is no quoting to get right because there is no shell.

You only need a shell when you genuinely need shell features (pipelines, redirection, globbing). In that case, never put untrusted data in the command string — pass it through the environment or as a positional argument to a fixed script (see Bash, below).

## C — `posix_spawn` / `execvp`

```c
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

// Run: grep -- <pattern> <path>   with NO shell.
int run_grep(const char *pattern, const char *path) {
    char *const argv[] = {
        "grep", "--",          // -- stops option parsing
        (char *)pattern,        // literal; metacharacters are inert
        (char *)path,
        NULL                    // argv MUST be NULL-terminated
    };
    pid_t pid;
    int rc = posix_spawnp(&pid, "grep", NULL, NULL, argv, environ);
    if (rc != 0) return -1;     // posix_spawnp returns errno on failure
    int status;
    if (waitpid(pid, &status, 0) < 0) return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}
```

- `posix_spawn`/`posix_spawnp` is the portable, race-free way to fork+exec; it works on Linux and macOS. The classic `fork()` + `execvp()` is equivalent — just remember that between `fork` and `exec` you may only call async-signal-safe functions.
- Pass `--` as an argv element so a `pattern`/`path` beginning with `-` is not parsed as an option (option injection).
- **Never** `system()` and **never** `popen()` with an interpolated string. `system("grep " + user)` is a shell command line — injection. If you need to read a child's output, set up a pipe with `posix_spawn_file_actions_adddup2` (or pipe+fork+exec), not `popen` on a built string.

## C++ — Same, Plus `std::system` Is Banned

C++ has no safe high-level process API in the standard library, so use the same POSIX primitives. Wrap them in RAII for the `pid`/pipe fds.

```cpp
#include <spawn.h>
#include <sys/wait.h>
#include <vector>
#include <string>
#include <string_view>

extern char **environ;

int run(std::string_view prog, const std::vector<std::string> &args) {
    std::vector<char *> argv;
    argv.reserve(args.size() + 2);
    std::string p{prog};
    argv.push_back(p.data());
    for (auto &a : const_cast<std::vector<std::string> &>(args))
        argv.push_back(a.data());
    argv.push_back(nullptr);

    pid_t pid;
    if (posix_spawnp(&pid, p.c_str(), nullptr, nullptr, argv.data(), environ) != 0)
        return -1;
    int status;
    if (waitpid(pid, &status, 0) < 0) return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}
```

- **`std::system` (and the inherited `system`, `popen`) are banned** — even for "trusted" input. They invoke the shell, the input source drifts over time, and "trusted" is exactly the assumption attackers break. Build an argv vector and `posix_spawn`.
- Keep the `std::string` storage alive for the lifetime of the `argv` pointers (the vector above does this). Do not point `argv` at temporaries.

## Python — `subprocess` Without a Shell

```python
import subprocess

# DO — list args, shell=False (the default). check=True raises on non-zero.
result = subprocess.run(
    ["grep", "--", pattern, path],
    shell=False,
    capture_output=True,
    text=True,
    timeout=30,
    check=True,
)

# DON'T — shell parses the whole string; pattern/path can inject.
subprocess.run(f"grep {pattern} {path}", shell=True)        # injection
subprocess.call("grep " + pattern + " " + path, shell=True) # injection
os.system(f"grep {pattern} {path}")                          # injection
```

- `shell=False` is the default and is what you want. When `args` is a list and `shell=False`, special characters cannot be interpreted as shell metacharacters — each list element is one `argv` entry.
- Add `--` (or the program's option terminator) before positional arguments that could start with `-`.
- Use `timeout=` to bound runaway children and `check=True` to surface failures instead of silently continuing.
- **Never** build a command string and pass `shell=True`. If you truly need a pipeline, prefer composing two `subprocess.Popen` objects with `stdout=`/`stdin=`, not a shell string.
- `os.system`, `os.popen`, and `commands.*` (Py2) are all shell-based — do not use them on any data influenced by input.

## Bash — Quoting, `--`, and No `eval`

In shell scripts the shell is unavoidable, so the discipline is: never let untrusted data become shell syntax.

```bash
#!/usr/bin/env bash
set -euo pipefail

file=$1

# DO — quote every expansion; -- guards leading-dash filenames.
rm -- "$file"
grep -- "$pattern" "$file"

# DON'T
rm $file                 # word-splits, globs, option-injects
grep $pattern $file      # same
eval "rm $file"          # eval = arbitrary command execution
cmd="rm $file"; $cmd     # variable run bare = re-parsed as syntax
```

Rules:

- **Quote everything**: `"$var"`, `"${arr[@]}"`, `"$(cmd)"`. Unquoted expansions undergo word-splitting and globbing — the source of SC2086/SC2046 findings.
- **Use `--`** before user-controlled positional arguments so a value like `-rf` or `--output=/etc/passwd` is treated as data, not an option.
- **Never `eval`** on data you do not fully control. `eval` re-parses its argument as shell code — it is the shell equivalent of `exec`. The same applies to running a command stored in a variable bare (`$cmd`); use an array instead: `cmd=(rm -- "$file"); "${cmd[@]}"`.
- Run ShellCheck and treat SC2086 (unquoted), SC2046 (unquoted command substitution), and SC2068 (`$@` unquoted) as errors.
- When you must call a helper, exec it directly (`./helper "$arg"`), not via a constructed `sh -c "$string"`.

## Environment Scrubbing

A child process inherits the parent's environment by default. Untrusted or stale environment variables can change how the child behaves (`PATH`, `IFS`, `LD_PRELOAD`, `LD_LIBRARY_PATH`, `BASH_ENV`, `PYTHONPATH`, locale vars).

- **Set an explicit, minimal environment** for children when running with elevated privilege or on behalf of untrusted callers. In C, pass a curated `envp` to `posix_spawn`/`execve` instead of `environ`. In Python, pass `env={...}` to `subprocess.run` with only the variables the child needs.
- **Pin `PATH`** to a known-safe absolute value (or invoke programs by absolute path) so an attacker-controlled `PATH` cannot substitute a malicious binary. This defeats PATH-hijacking.
- **Drop dangerous variables**: `LD_PRELOAD`, `LD_LIBRARY_PATH`, `DYLD_*` (macOS), `IFS`, `BASH_ENV`/`ENV`. The dynamic loader already ignores most of these for setuid binaries — do not rely on that for your own privilege transitions; scrub explicitly.
- **Secrets in the environment**: a child's environment is visible to that child and (on Linux) via `/proc/PID/environ` to the same user. Prefer passing secrets via a pipe/fd over env, and never via `argv` (world-readable through `ps` and `/proc/PID/cmdline`).

```python
import subprocess

subprocess.run(
    ["/usr/bin/tool", "--", arg],
    shell=False,
    env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"},   # minimal, pinned PATH
    timeout=30, check=True,
)
```

## Why Dynamic Code Execution Is Banned

Constructing code from data and then executing it collapses the data/code boundary — the single most powerful primitive an attacker can reach. It is a non-negotiable rule: **no dynamic code construction or execution at runtime.**

What this bans:

| Language | Banned construct | Why |
|----------|-----------------|-----|
| Python | `eval`, `exec`, `compile`+exec, `pickle.loads`/`marshal.loads` on untrusted data, `__import__` on a computed name | Each runs attacker-controlled Python |
| C / C++ | `system`/`popen`/`std::system` on built strings; `dlopen` on an attacker-chosen path; generating + compiling + loading code at runtime | Runs attacker-controlled commands or native code |
| Bash | `eval`, `source`/`.` on an attacker-controlled file, running a variable as a command | Re-parses data as shell code |
| All | Building SQL/queries by string concatenation | SQL injection — use parameterized queries / prepared statements |

The replacement is always the same shape: **structured APIs over string interpolation.** Argv vectors instead of command strings. Parameterized queries instead of concatenated SQL. Data parsers (`json.loads`, `yaml.safe_load`) instead of `eval`/`pickle`. A dispatch table (`dict` of allowed callables) instead of `eval`-ing a function name.

If you believe you have a legitimate need to disable this rule, that requires a documented, reviewed justification recorded inline at the call site — and it must never accept data that crosses a trust boundary.

## Execution Checklist

- [ ] No `system`/`popen`/`std::system` anywhere — children launched via `posix_spawn`/`execvp` with an explicit argv array.
- [ ] No `subprocess(..., shell=True)`, no `os.system`/`os.popen`; list args + `shell=False` + `timeout` + `check=True`.
- [ ] `--` (option terminator) precedes any user-controlled positional argument.
- [ ] Bash: every expansion quoted; no `eval`; commands stored as arrays, not bare strings; ShellCheck clean (SC2086/SC2046/SC2068).
- [ ] Child environment is minimal with a pinned absolute `PATH`; `LD_PRELOAD`/`LD_LIBRARY_PATH`/`DYLD_*`/`IFS` scrubbed for privileged or untrusted-caller paths.
- [ ] Secrets passed via fd/pipe, not argv; never logged; never under `set -x`.
- [ ] No `eval`/`exec`/`pickle`/`dlopen`-on-data; queries are parameterized, not concatenated.

## Related

- `input-validation-and-parsing.md` — validating the data that flows into arguments and the deserialization-RCE table
- `../SKILL.md` — non-negotiable rules and the per-language injection table
- `../../bash/bash-scripting/SKILL.md` — strict mode, quoting, and defensive shell patterns
