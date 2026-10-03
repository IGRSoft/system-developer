---
name: secure-coding
description: Security rules and bug-class defenses for C, C++, Python, and Bash — injection-safe process execution, sanitizer mapping, integer safety, path-traversal/TOCTOU resistance, secrets hygiene, and dependency supply-chain trust. Use when writing or reviewing systems code that touches untrusted input, spawns processes, parses data, handles paths, manages credentials, or adds a dependency.
---

# Secure Coding (C / C++ / Python / Bash)

Cross-language security rules for every diff. A violation is a P0 review finding.

Applies when code accepts untrusted input (CLI args, env, files, network, IPC, API responses), spawns a subprocess or builds a query, parses or deserializes data, canonicalizes paths, does arithmetic that feeds a size or offset, or handles secrets.

## Core Rules

Exceptions need a documented, reviewed justification.

1. **No raw user input in paths, command lines, or queries** — sanitize, canonicalize, or pass through structured APIs (argv arrays, parameterized queries, `openat`).
2. **No dynamic code construction or execution** — no `eval`/`exec`, no `system("…" + input)`, no shelling out to an interpreter on attacker data.
3. **Validate all external API responses** — every byte from outside the process is hostile; check length, type, range, and encoding before use.
4. **Don't disable a security control without justification** — sanitizers off, `-Werror` removed, `verify=False`, suppression files: each needs an inline comment with the reason and a tracking reference.

## Injection-Safe Execution

Pass an argument vector to `exec`-family or structured APIs; never hand a string to a shell.

| Language | Banned | Required |
|----------|--------|----------|
| C | `system(cmd)`, `popen(cmd, …)` with interpolated input | `posix_spawn` / `fork` + `execvp(file, argv)` with an explicit `argv[]` |
| C++ | `std::system`, `system`, `popen`, even for "trusted" input | Same as C, with an argv vector |
| Python | `subprocess.run(cmd, shell=True)`, `os.system`, `eval`, `exec`, `pickle.loads`/`yaml.load` on untrusted data | `subprocess.run([prog, arg1, arg2])` (`shell=False` is the default); `json.loads`, `yaml.safe_load` |
| Bash | `eval "$x"`, unquoted `$var`, a command stored in a variable and run bare | Quote every expansion (`"$var"`), `--` before positional args, fixed argv or arrays |

```python
subprocess.run(["grep", "--", pattern, path], check=True)   # DO: argv list, no shell
subprocess.run(f"grep {pattern} {path}", shell=True)         # DON'T: injection
```

```bash
rm -- "$file"   # DO: quoted, -- guards leading-dash names
rm $file        # DON'T: word-splitting, glob, option injection
```

`posix_spawn` examples, environment scrubbing, and the full dynamic-code ban: [references/command-execution-and-injection.md](references/command-execution-and-injection.md).

To scan a tree for banned constructs, run `../scripts/injection_audit.sh --lang {c|cpp|python|bash} --path .`. It prints each hit as `path:line` (heuristic, so confirm in context) and exits non-zero on findings, so it works as a review or CI gate.

## Memory-Corruption Bug Classes (C / C++)

| Bug class | Caught by | Notes |
|-----------|-----------|-------|
| Use-after-free | **ASan** | Stack UAF needs `detect_stack_use_after_return=1` |
| Double-free | **ASan** | |
| Heap/stack/global out-of-bounds | **ASan** | |
| Uninitialized read | **MSan** | Clang-only; uninstrumented deps give false positives. Prefer init-on-declare |
| Signed overflow, bad shift, null deref, misalignment | **UBSan** | Combine with ASan |
| Data race | **TSan** | |
| Leak | **LSan** (bundled in ASan on Linux) | |

ASan + UBSan compose; TSan and MSan each run alone. Sanitizers only see executed paths, so pair them with tests or fuzzing. Flag sets and triage: [diagnostics](../../tooling/diagnostics/SKILL.md).

**Release hardening:** `-D_FORTIFY_SOURCE=3` (needs `-O2`), `-fstack-protector-strong`, PIE/RELRO, `-ftrivial-auto-var-init=zero`. GCC 14+ bundles the set as `-fhardened`. C++ adds `-D_GLIBCXX_ASSERTIONS` (libstdc++) or `_LIBCPP_HARDENING_MODE` (libc++) for bounds-checked standard containers.

## Integer Safety

Overflow in size/index/offset arithmetic causes most out-of-bounds bugs. Use checked arithmetic at every untrusted boundary.

| Language | Mechanism | Fallback |
|----------|-----------|----------|
| C | `ckd_add` / `ckd_sub` / `ckd_mul` from `<stdckdint.h>` (**C23**) | `__builtin_*_overflow` (GCC/Clang) or manual checks against `SIZE_MAX` |
| C++ | `std::cmp_less` etc. and `std::in_range<T>(v)` from `<utility>` (**C++20**) | Explicit casts and bounds, or `__builtin_*_overflow` |
| Python | Ints don't overflow; the risk is at the C-extension/`ctypes` boundary | Range-check against the target C type before crossing |

```c
size_t total;
if (ckd_mul(&total, count, elem_size)) return ERR_OVERFLOW;  // C23
void *buf = malloc(total);
```

Don't mix signed and unsigned in a comparison that gates a buffer access. Safe number parsing (`strtol`+errno, `from_chars`, `int()`): [references/input-validation-and-parsing.md](references/input-validation-and-parsing.md).

## Path Traversal & TOCTOU

| Risk | Defense |
|------|---------|
| `../` escaping a base directory | C/C++: `openat(dirfd, rel, O_NOFOLLOW)` or `realpath` + prefix check; Python: `path.resolve().is_relative_to(base.resolve())` |
| Symlink redirection | `O_NOFOLLOW`, `lstat`; don't follow attacker-controlled symlinks |
| Time-of-check/time-of-use | Open once and act on the fd (`fstat`), not `access()` then `open()` |
| Predictable temp files | `mkstemp` / Python `tempfile.mkstemp` or `NamedTemporaryFile`, not `mktemp`, `tmpnam`, or `/tmp/$$` |

```python
target = (base / user_name).resolve()
if not target.is_relative_to(base.resolve()):
    raise ValueError("path escapes base directory")
```

## Secrets Hygiene

| Rule | C / C++ | Python | Bash |
|------|---------|--------|------|
| Scrub after use | `memset_explicit` (**C23**); fallback `explicit_bzero` or `SecureZeroMemory`. Plain `memset` can be optimized away | `str`/`bytes` can't be overwritten; keep lifetime short, prefer `bytearray` then `del` | `unset VAR` |
| Don't log secrets | Redact before any print/log | Filter in logging formatters | No `set -x` around secret lines |
| Pass via env or fd, not argv | argv is visible to other users via `ps` and `/proc/PID/cmdline` | same | Export or read from fd/file, never `--password=$PW` |

## Supply Chain

A new dependency runs with your process's privileges, so treat adding one like accepting untrusted code.

| Rule | How |
|------|-----|
| Pin exactly and commit the lock | `uv.lock`, vcpkg `builtin-baseline` + `overrides`, `conan.lock`; FetchContent by commit SHA, not a branch or tag |
| Verify what you fetch | `--require-hashes` for pip requirements; `URL_HASH SHA256=` for FetchContent/ExternalProject downloads |
| Vet before adding | Maintained, from the expected publisher (watch for typosquats), license fits, no open critical CVEs (`osv-scanner`, `pip-audit`) |
| Use trusted sources only | No `curl ... \| sh` installers in builds; no extra package indexes that can shadow internal names (dependency confusion) |
| Keep CI least-privilege | Pin third-party CI actions by SHA; no secrets in jobs that build untrusted pull requests |

## Diagnostic Table

| Finding | Cause | Fix | Reference |
|---------|-------|-----|-----------|
| `system`/`popen`/`shell=True` with interpolated input | Shell injection | argv array (`execvp`/`posix_spawn`, list args) | [command-execution](references/command-execution-and-injection.md) |
| `eval`/`exec`/`pickle.loads` on external data | Code execution | Structured parser (`json`, `yaml.safe_load`) | [command-execution](references/command-execution-and-injection.md) |
| Unquoted `$var` (SC2086) | Word-splitting / glob injection | `"$var"`, add `--` | [command-execution](references/command-execution-and-injection.md) |
| ASan heap-use-after-free | Lifetime bug | Fix ownership; RAII | [c-memory-ownership](../../c/c-memory-ownership/SKILL.md) |
| ASan heap-buffer-overflow | OOB, often from integer overflow | Bounds check + `ckd_*`/`in_range` | [input-validation](references/input-validation-and-parsing.md) |
| UBSan signed-integer-overflow | Unchecked arithmetic | `ckd_*` / `__builtin_*_overflow` | [input-validation](references/input-validation-and-parsing.md) |
| Path accepts `../` | Traversal | `resolve`+`is_relative_to` / `openat`+`O_NOFOLLOW` | [input-validation](references/input-validation-and-parsing.md) |
| `mktemp`/`tmpnam`, `access()` then `open()` | Race | `mkstemp`; operate on the fd | [input-validation](references/input-validation-and-parsing.md) |
| Secret in argv, log, or `set -x` | Credential disclosure | env/fd, redact, `memset_explicit` | Secrets Hygiene above |
