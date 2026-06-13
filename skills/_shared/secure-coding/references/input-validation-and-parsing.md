# Input Validation and Parsing (C / C++ / Python / Bash)

Use this when:

- You accept bytes from outside the process — CLI args, env vars, files, network, IPC, or an external API response.
- You parse untrusted numbers, lengths, encodings, or structured data.
- You canonicalize a path that contains user-controlled components.
- You deserialize data and need to know which formats are safe.

Skip this file if:

- You are spawning a subprocess or building a command line. Use `command-execution-and-injection.md`.
- You only need the rule summary. Use the parent `SKILL.md`.

Jump to:

- Validation Doctrine
- Length, Encoding, and Range Checks
- Safe Integer Parsing
- Path Canonicalization and Traversal
- TOCTOU-Resistant File Access
- Deserialization Risks
- External API Responses
- Validation Checklist

## Validation Doctrine

Treat the process boundary as a trust boundary. Every value crossing it is hostile until proven otherwise. Three properties must hold before an untrusted value is used:

1. **Bounded** — length and count are within a known maximum (reject, never truncate silently when truncation changes meaning).
2. **Well-formed** — encoding, type, and structure match the expected grammar.
3. **In range** — numeric values fall inside the domain the code actually supports.

Validate **once, at the boundary**, into a typed internal representation; do not re-validate ad hoc deep in the call stack. Prefer allow-lists (enumerate what is permitted) over deny-lists (enumerate what is forbidden) — deny-lists always miss a case.

Fail closed: on any validation failure, reject the whole input and return an error. Never "best-effort fix" attacker data.

## Length, Encoding, and Range Checks

### C — bound everything before you copy

```c
// Reject oversized input up front; never assume NUL termination from the network.
static int parse_name(const char *buf, size_t len, char out[64]) {
    if (len == 0 || len >= sizeof out) return -1;   // bounded
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)buf[i];
        if (c < 0x20 || c == 0x7f) return -1;        // well-formed: printable only
    }
    memcpy(out, buf, len);
    out[len] = '\0';
    return 0;
}
```

- Never use `strcpy`, `strcat`, `sprintf`, `gets`. Use `snprintf` with an explicit size and check the return value; if `snprintf` returns `>= size`, the output was truncated — treat that as an error when truncation matters.
- For network/file reads, carry an explicit length; do not rely on a trailing `\0`.
- `strncpy` does **not** guarantee NUL termination — set `out[n-1] = '\0'` yourself, or prefer `snprintf`.

### C++ — use `std::string_view` / `std::span` with their sizes

```cpp
#include <string_view>
#include <span>

bool valid_token(std::string_view s) {
    if (s.empty() || s.size() > 64) return false;          // bounded
    return std::ranges::all_of(s, [](unsigned char c) {     // well-formed
        return std::isalnum(c) || c == '_' || c == '-';
    });
}
```

- `string_view`/`span` carry their length — never read past `.size()`.
- **Lifetime trap**: a `string_view`/`span` is a non-owning view. Never return one referring to a local, a temporary, or a freed buffer. If the source can outlive the view, copy into a `std::string`/owning container.

### Python — validate before use, normalize encoding explicitly

```python
def parse_name(raw: bytes) -> str:
    if len(raw) > 64:                       # bounded
        raise ValueError("too long")
    try:
        name = raw.decode("utf-8")          # well-formed: strict decode
    except UnicodeDecodeError as exc:
        raise ValueError("invalid encoding") from exc
    if not name.isprintable():
        raise ValueError("non-printable")
    return name
```

- Decode bytes with an explicit codec and let it raise on malformed input — do not pass `errors="ignore"`/`"replace"` on security-relevant data (it silently mutates the input).
- Normalize Unicode (`unicodedata.normalize("NFC", s)`) before comparing user-supplied identifiers to avoid homoglyph/confusable bypasses.

### Bash — reject before you use

```bash
# Validate with a strict pattern; reject anything that does not match.
if [[ ! "$id" =~ ^[A-Za-z0-9_]{1,64}$ ]]; then
    printf 'invalid id\n' >&2
    exit 1
fi
```

- Quote on every expansion (`"$id"`); an empty or whitespace value must not silently word-split into nothing.
- Use `[[ ... =~ ... ]]` (Bash) for anchored regex; for POSIX `sh`, use a `case` glob.

## Safe Integer Parsing

Parsing user-supplied numbers is where overflow and silent truncation enter. Never use `atoi`/`atol` (no error reporting) or unbounded `int(...)` on adversarial input that feeds a size.

### C — `strtol` family with `errno`

```c
#include <errno.h>
#include <limits.h>
#include <stdlib.h>

int parse_index(const char *s, long *out) {
    errno = 0;
    char *end = NULL;
    long v = strtol(s, &end, 10);
    if (end == s || *end != '\0') return -1;        // no digits / trailing junk
    if (errno == ERANGE) return -1;                  // out of long range
    if (v < 0 || v > INT_MAX) return -1;             // domain check
    *out = v;
    return 0;
}
```

- Always set `errno = 0` before, check `ERANGE` after, and verify `end` consumed the whole string.
- Then apply the **domain** range check for your actual type (`INT_MAX`, array bound, etc.).
- Feeding a parsed length into allocation? Use checked arithmetic — `ckd_mul(&total, n, size)` (**C23**, `<stdckdint.h>`; fallback `__builtin_mul_overflow` on GCC/Clang). Verify against your toolchain for exact minimum versions.

### C++ — `std::from_chars`

```cpp
#include <charconv>
#include <string_view>
#include <optional>

std::optional<int> parse_index(std::string_view s) {
    int v{};
    auto [ptr, ec] = std::from_chars(s.data(), s.data() + s.size(), v);
    if (ec != std::errc{} || ptr != s.data() + s.size()) return std::nullopt;  // C++17
    return v;
}
```

- `std::from_chars` (**C++17**) does not allocate, has no locale surprises, reports errors via `std::errc`, and never throws. Prefer it over `std::stoi` (throws, locale-sensitive) and over `atoi` (no error path).
- Guard mixed signed/unsigned comparisons with `std::cmp_less`/`std::in_range<T>(v)` (**C++20**, `<utility>`); pre-C++20 fallback: compare with explicit casts and bounds.

### Python — `int()` with bounds, never `eval`

```python
def parse_index(s: str, *, lo: int = 0, hi: int = 1_000_000) -> int:
    try:
        v = int(s)            # base-10; raises ValueError on junk
    except ValueError as exc:
        raise ValueError("not an integer") from exc
    if not lo <= v <= hi:     # domain check (Python ints don't overflow)
        raise ValueError("out of range")
    return v
```

- `int(s)` is safe and total — it raises on malformed input. **Never** `eval(s)` to "parse" a number; that is arbitrary code execution.
- Python integers are arbitrary precision, so the overflow risk is not in Python arithmetic — it is at the **C-extension / `ctypes` boundary**, where a huge Python int silently wraps or is rejected when narrowed to a C type. Range-check against the target C type before crossing.

## Path Canonicalization and Traversal

The attack: a user-controlled path component containing `..`, an absolute path, or a symlink escapes the directory you intended to confine it to.

### Python — `resolve()` + `is_relative_to`

```python
from pathlib import Path

def safe_join(base: Path, user_part: str) -> Path:
    base = base.resolve()
    target = (base / user_part).resolve()      # collapses .. and follows symlinks
    if not target.is_relative_to(base):        # 3.9+
        raise ValueError("path escapes base directory")
    return target
```

- `resolve()` canonicalizes and resolves symlinks; `is_relative_to` (Python 3.9+) confirms containment. Do this **before** any open/read/write.
- Do not validate the raw string with substring checks for `".."` — encodings and symlinks defeat that. Canonicalize, then compare.

### C / C++ — `openat` + `O_NOFOLLOW`, or `realpath` + prefix check

```c
// Confine within a directory fd; refuse symlinks at the final component.
int fd = openat(dirfd, rel_path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
if (fd < 0) return -1;   // ELOOP if rel_path was a symlink
```

```c
// Or canonicalize and verify the prefix.
char resolved[PATH_MAX];
if (!realpath(user_path, resolved)) return -1;
if (strncmp(resolved, base_dir, base_len) != 0 || resolved[base_len] != '/')
    return -1;  // escaped base
```

- Prefer `openat` against a directory `fd` over re-resolving full path strings — it composes with TOCTOU-safe access below.
- `O_NOFOLLOW` rejects a symlink at the **final** path component; for full-path symlink safety walk component-by-component with `openat` or rely on `realpath` + prefix check.

## TOCTOU-Resistant File Access

Time-of-check/time-of-use: you check a property of a path, then act on the path; an attacker swaps the file in between.

```c
// DON'T — the path is re-resolved twice; the file can change between calls.
if (access(path, W_OK) == 0) {     // check
    int fd = open(path, O_WRONLY); // use — different inode now possible
}

// DO — open once, then interrogate and act on the same fd.
int fd = open(path, O_WRONLY | O_NOFOLLOW | O_CLOEXEC);
if (fd < 0) return -1;
struct stat st;
if (fstat(fd, &st) != 0) { close(fd); return -1; }   // check the fd, not the path
if (!S_ISREG(st.st_mode)) { close(fd); return -1; }
// write to fd
```

- The rule: **resolve once, operate on the descriptor.** Never `access()`-then-`open()`, never `stat()`-then-`open()` by path.
- Temp files: use `mkstemp` (C/C++) / `tempfile.mkstemp` / `tempfile.NamedTemporaryFile` (Python) — they create+open atomically with `O_EXCL`. **Never** `mktemp`, `tmpnam`, `tempnam`, or a hand-built `/tmp/$$` name — those are predictable and racy.

```python
import tempfile, os
fd, path = tempfile.mkstemp(dir=base)   # atomic, 0600, O_EXCL
try:
    with os.fdopen(fd, "w") as f:
        f.write(data)
finally:
    pass  # remove when done
```

## Deserialization Risks

Deserialization that can instantiate arbitrary types or run code is remote code execution.

| Format / API | Safe? | Use instead |
|--------------|-------|-------------|
| Python `pickle` / `marshal` / `shelve` on untrusted bytes | **No — RCE** | `json` for data; a schema-validated format for structure |
| `yaml.load(...)` (full loader) | **No — can construct objects** | `yaml.safe_load(...)` |
| `json.loads` | Yes (data only; still validate the shape) | — |
| `xml.etree` / `xml.dom` on untrusted XML | Risky — entity expansion / XXE | `defusedxml`, disable external entities |
| C/C++ hand-rolled binary parsers | Risky — bounds errors | length-prefixed, bounds-checked reads; fuzz with ASan/UBSan |

- After `json.loads`/`safe_load`, the data is still untrusted — validate the schema (types, required keys, ranges) before use. Parsing is not validation.
- For C/C++ binary parsing, read length-prefixed fields, bound every read against the remaining buffer, and run the parser under ASan+UBSan in CI (it is a prime fuzz target).

## External API Responses

A response from a remote service is untrusted input even when the service is "ours":

- Check the status code and content type before parsing; do not assume `200` or JSON.
- Bound the response size (`max` read length) — a hostile or buggy server can stream forever.
- Validate the parsed structure (schema) before use; never trust a field to be present, in range, or non-malicious.
- Keep TLS verification on. Do not set `verify=False` (Python `requests`/`httpx`), `CURLOPT_SSL_VERIFYPEER=0`, or equivalent — that enables MITM. For a self-signed dev cert, add the CA to the trust store; if you must disable verification, it requires a documented, reviewed justification and must never reach production.

## Validation Checklist

- [ ] Every external value is length-bounded before copy/parse.
- [ ] Encoding is decoded strictly (no `ignore`/`replace` on security data); Unicode normalized before comparison.
- [ ] Numbers parsed with `strtol`+errno / `from_chars` / `int()` — never `atoi`/`eval`; domain range checked after.
- [ ] Size/index arithmetic uses checked ops (`ckd_*` C23 / `in_range` C++20 / boundary check in Python).
- [ ] Paths canonicalized and confined (`resolve`+`is_relative_to` / `openat`+`O_NOFOLLOW` / `realpath`+prefix) before open.
- [ ] File access is TOCTOU-safe — operate on a descriptor, not a re-resolved path.
- [ ] Temp files via `mkstemp`, never `mktemp`/`tmpnam`.
- [ ] No `pickle`/full-`yaml.load` on untrusted data; parsed structures schema-validated.
- [ ] External API responses size-bounded, status/type-checked, schema-validated; TLS verification on.

## Related

- `command-execution-and-injection.md` — safe process execution and the dynamic-code-execution ban
- `../SKILL.md` — non-negotiable rules, bug-class and integer-safety tables, diagnostic table
- `../../tooling/diagnostics/SKILL.md` — sanitizer flag sets for fuzzing parsers
