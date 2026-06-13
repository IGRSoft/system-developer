---
name: secure-coding
description: Non-negotiable security rules and bug-class defenses for C, C++, Python, and Bash — injection-safe process execution, memory-corruption sanitizer mapping, integer safety, path-traversal/TOCTOU resistance, and secrets hygiene. Use when writing or reviewing systems code that touches untrusted input, spawns processes, parses data, handles paths, or manages credentials.
---

# Secure Coding (C / C++ / Python / Bash)

**Cross-language security rules that gate every diff. Violations are P0 review findings.**

## When to Use

Use this skill when:
- Code accepts untrusted input (CLI args, env, files, network, IPC, API responses).
- Code spawns a subprocess, builds a command line, or constructs SQL/queries.
- Code parses, deserializes, or canonicalizes paths.
- Code allocates, indexes, or does arithmetic that feeds a size or offset.
- Code handles secrets (tokens, keys, passwords).

## Non-Negotiable Rules

These mirror the global security rules and never have exceptions without a documented, reviewed justification:

1. **No raw user input in paths, command lines, or queries** — always sanitize, canonicalize, or pass through structured APIs (argv arrays, parameterized queries, `openat`).
2. **No dynamic code construction or execution** — no `eval`/`exec`, no `system("…" + input)`, no shelling out to an interpreter on attacker data.
3. **Validate all external API responses** — assume every byte from outside the process is hostile; check length, type, range, and encoding before use.
4. **Never disable a security control without documented justification** — sanitizers off, `-Werror` removed, `verify=False`, suppression files: each needs an inline comment with the reason and a tracking reference.

> A change that breaks any of these does not pass DR/SR review. See [workflow-integration](../workflow-integration/SKILL.md) for stage gates.

## Injection-Safe Execution (per language)

Never hand a string to a shell. Pass an argument vector to `exec`-family / structured APIs.

| Language | Banned | Required |
|----------|--------|----------|
| C | `system(cmd)`, `popen(cmd, …)` with interpolated input | `posix_spawn` / `fork` + `execvp(file, argv)` with an explicit `argv[]` array; build args, never a shell string |
| C++ | `std::system(...)`, `system`, `popen` | Same as C — `posix_spawn`/`execvp` with an argv vector; never `std::system` even for "trusted" input |
| Python | `subprocess.run(cmd, shell=True)`, `os.system`, `eval`, `exec`, `pickle.loads`/`yaml.load` on untrusted data | `subprocess.run([prog, arg1, arg2], shell=False)` (the default); `json.loads`, `yaml.safe_load`; never `pickle` on external bytes |
| Bash | `eval "$x"`, unquoted `$var`, command in a variable run bare | Quote **everything** (`"$var"`), use `--` before positional args, run fixed argv; never `eval` |

```python
# DO — argv list, no shell
subprocess.run(["grep", "--", pattern, path], shell=False, check=True)
# DON'T — shell interprets pattern/path
subprocess.run(f"grep {pattern} {path}", shell=True)  # injection
```

```bash
# DO — quoted, with -- guard against leading-dash filenames
rm -- "$file"
# DON'T — word-splitting + glob + option injection
rm $file
```

Full doctrine, `posix_spawn` examples, environment scrubbing, and why dynamic code exec is banned: [references/command-execution-and-injection.md](references/command-execution-and-injection.md).

## Memory-Corruption Bug Classes (C / C++) → which sanitizer catches it

| Bug class | What it is | Caught by | Notes |
|-----------|-----------|-----------|-------|
| Use-after-free (UAF) | Access freed heap | **ASan** | Also dangling-stack with `detect_stack_use_after_return=1` |
| Double-free | `free` same pointer twice | **ASan** | |
| Heap/stack/global OOB read/write | Index past bounds | **ASan** | Stack & global redzones built in |
| Uninitialized read | Use of unset memory | **MSan** (Clang-only; instrument all deps or false positives) | Often impractical; prefer init-on-declare |
| Signed integer overflow / shift / null-deref / misaligned | Undefined behavior | **UBSan** | Combine with ASan |
| Data race | Concurrent unsynchronized access | **TSan** | Exclusive — cannot combine with ASan/MSan |
| Memory leak | Never freed | **LSan** (bundled in ASan on Linux) | RAII / cleanup attribute prevents |

Combination rules: ASan + UBSan compose; TSan and MSan are mutually exclusive with ASan and with each other. Sanitizers find bugs only on paths you execute — pair with fuzzing/tests. Flag sets and dedupe workflow: [diagnostics](../../tooling/diagnostics/SKILL.md).

## Integer Safety

Overflow in size/index/offset arithmetic is the root of most OOB. Use checked arithmetic at every untrusted boundary.

| Language | Mechanism | Marker / fallback |
|----------|-----------|-------------------|
| C | `ckd_add` / `ckd_sub` / `ckd_mul` from `<stdckdint.h>` | **C23**; pre-C23 fallback: `__builtin_*_overflow` (GCC/Clang) or manual pre-checks against `SIZE_MAX` |
| C++ | `std::cmp_less` / `cmp_greater` / `cmp_equal` family + `std::in_range<T>(v)` from `<utility>` | **C++20**; pre-C++20 fallback: cast carefully and compare with explicit bounds, or `__builtin_*_overflow` |
| Python | Ints are arbitrary precision — overflow risk lives at the **C-extension boundary** | Validate before passing to `ctypes`/C API; range-check against the target C type's limits |

```c
size_t total;
if (ckd_mul(&total, count, elem_size)) return ERR_OVERFLOW;  // C23
void *buf = malloc(total);
```

Never mix signed/unsigned in a comparison that gates a buffer access. Parsing untrusted numbers safely (`strtol`+errno, `from_chars`, Python `int()`): [references/input-validation-and-parsing.md](references/input-validation-and-parsing.md).

## Path Traversal & TOCTOU

| Risk | Defense |
|------|---------|
| `../` escaping a base directory | C/C++: `openat(dirfd, rel, O_NOFOLLOW)` + verify with `realpath`; Python: `base.resolve()` then `path.resolve().is_relative_to(base)` |
| Symlink redirection | `O_NOFOLLOW`, `lstat`, never follow attacker-controlled symlinks |
| Time-of-check/time-of-use | Operate on a file descriptor, not a re-resolved path; use `openat`/`fstat` on the same `fd`, never `access()` then `open()` |
| Predictable temp files | `mkstemp` / Python `tempfile.mkstemp` / `NamedTemporaryFile` — **never** `mktemp`, `tmpnam`, or hand-rolled `/tmp/$$` |

```python
target = (base / user_name).resolve()
if not target.is_relative_to(base.resolve()):
    raise ValueError("path escapes base directory")
```

## Secrets Hygiene

| Rule | C | C++ | Python | Bash |
|------|---|-----|--------|------|
| Scrub after use | `memset_explicit` (**C23**); fallback `explicit_bzero` (BSD/glibc) or `SecureZeroMemory` | same as C on the buffer | overwrite is unreliable (immutable `str`/`bytes`); minimize lifetime, prefer `bytearray` + del | `unset VAR` |
| Never log secrets | redact before any `printf`/log | same | filter logging formatters | never `set -x` around secret lines |
| Pass via env, not argv | argv is world-readable via `/proc/PID/cmdline` and `ps` | same | same | export to env or read from fd/file, never `--password=$PW` on the command line |

A plain `memset` to zero a secret may be optimized away by the compiler ("dead store"); `memset_explicit`/`explicit_bzero` are guaranteed not to be elided.

## Diagnostic Table

| Symptom / finding | Likely cause | Fix | Reference |
|-------------------|-------------|-----|-----------|
| `system()`/`popen` with interpolated input | shell injection | argv array via `execvp`/`posix_spawn` | [command-execution](references/command-execution-and-injection.md) |
| `shell=True` in `subprocess` | shell injection | `shell=False` + list args | [command-execution](references/command-execution-and-injection.md) |
| `eval`/`exec`/`pickle.loads` on external data | arbitrary code execution | structured parser (`json`, `yaml.safe_load`) | [command-execution](references/command-execution-and-injection.md) |
| Unquoted `$var` flagged SC2086 | word-splitting / glob injection | `"$var"`, add `--` | [command-execution](references/command-execution-and-injection.md) |
| ASan: heap-use-after-free | UAF | fix lifetime, RAII/ownership | [diagnostics](../../tooling/diagnostics/SKILL.md) |
| ASan: heap-buffer-overflow | OOB + likely integer overflow | bounds + checked arithmetic (`ckd_*`/`in_range`) | [input-validation](references/input-validation-and-parsing.md) |
| UBSan: signed-integer-overflow | unchecked arithmetic | `ckd_*` (C23) / `__builtin_*_overflow` | [input-validation](references/input-validation-and-parsing.md) |
| Path accepts `../` and escapes base | traversal | `resolve()`+`is_relative_to` / `openat`+`O_NOFOLLOW` | [input-validation](references/input-validation-and-parsing.md) |
| `mktemp`/`tmpnam` usage | predictable temp / race | `mkstemp` | [input-validation](references/input-validation-and-parsing.md) |
| `access()` then `open()` | TOCTOU | operate on the `fd` | [input-validation](references/input-validation-and-parsing.md) |
| Secret in argv / log / `set -x` | credential disclosure | env/fd + redact + `memset_explicit` | this file, Secrets Hygiene |

## Related Skills

- [input-validation-and-parsing.md](references/input-validation-and-parsing.md) — untrusted-input validation, safe integer parsing, canonicalization, deserialization
- [command-execution-and-injection.md](references/command-execution-and-injection.md) — safe process execution, environment scrubbing, dynamic-code ban
- [diagnostics/SKILL.md](../../tooling/diagnostics/SKILL.md) — sanitizer flag sets, combination rules, triage
- [c-memory-ownership/SKILL.md](../../c/c-memory-ownership/SKILL.md) — ownership conventions and UB catalog (C)
- [workflow-integration/SKILL.md](../workflow-integration/SKILL.md) — SR/DR security gates and handoff contract
