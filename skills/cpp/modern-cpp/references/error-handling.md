# Error Handling: Exceptions, std::expected, and Error Codes

Use this when:

- You are deciding how a function, module, or whole codebase should report failures.
- You are writing `noexcept` specifications and need the policy, not folklore.
- You need `std::error_code` custom domains, or `expected` chaining with `and_then`/`transform`/`or_else`.
- Errors must cross a boundary: module edges, shared libraries, or `extern "C"` into C callers.

Skip this file if:

- You need `std::expected` construction/observation mechanics and feature-test macros. Use `cpp23-features.md` — this file covers *policy* and *chaining*.
- You are handling errors in C code (errno conventions, goto-cleanup). Use the C skills: [modern-c](../../../c/modern-c/SKILL.md).
- You want crash diagnostics rather than error design. Use [diagnostics](../../../tooling/diagnostics/SKILL.md).

Jump to:

- Decision Framework
- Exceptions Done Right
- The noexcept Policy
- Exception-Safety Guarantees
- std::error_code and Custom Error Domains
- std::expected Chaining in Practice
- Designing Error Types
- Boundary Translation
- The extern "C" Edge
- Worked Example: A Three-Layer Service
- Anti-Patterns That Pass Review
- Availability and Fallbacks

## Decision Framework

There is no single right mechanism; there is a right mechanism *per failure class*. Decide per API, write the decision into the header comment, and be consistent within a layer.

| Failure class | Mechanism | Rationale |
|---------------|-----------|-----------|
| Expected, frequent, caller-must-handle (parse failure, lookup miss, validation) | `std::expected<T, E>` (C++23; `tl::expected` pre-23) | failure is part of the signature; no hidden control flow; fast |
| Absence that needs no explanation ("not found" with one obvious cause) | `std::optional<T>` | lighter than `expected`; don't smuggle error info into `nullopt` |
| Rare, exceptional, cross-cutting (resource exhaustion, broken invariants surfacing far from cause, constructor failure) | exceptions | zero cost on the success path; propagate through layers that can't handle them |
| OS/syscall results, system-level errors | `std::error_code` (alone, or as `E` in `expected<T, std::error_code>`) | preserves the platform error + domain without losing fidelity |
| Crossing `extern "C"`, plugin ABIs, or mixed-toolchain shared libraries | integer codes + out-parameters | the only representation every ABI understands |
| Programming bugs (precondition violations, impossible states) | assertions / `std::terminate` paths — **not** recoverable errors | bugs aren't inputs; don't design recovery for them |
| `-fno-exceptions` targets (some embedded, games, kernels) | `expected` / error codes exclusively | throwing calls `std::abort`; design it out |

Cross-cutting rules:

- **Destructors never report failures.** Log and swallow, or terminate. There is no third option (see noexcept below).
- **Constructors** may throw — that's the one place exceptions are structurally hard to replace. Where exceptions are banned, use a named factory: `static std::expected<Conn, Error> Conn::open(…)` with a private constructor.
- **Don't mix mechanisms within one layer.** A module where some functions throw and siblings return `expected` for the same failure class forces every caller to handle both. Translate at layer boundaries instead (below).
- Exceptions' real cost is not the happy path (table-based unwinding is ~zero there); it's the *throw* path (orders of magnitude slower than a return) and the binary-size/unpredictability budget. That's why high-frequency failures don't belong in exceptions and rare ones do.

## Exceptions Done Right

When exceptions are the chosen mechanism (C++17 baseline — all of this is standard-version-stable):

```cpp
// Throw by value, a type derived from std::exception, with context:
struct ConfigError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

[[noreturn]] void fail_config(std::string_view key) {
    throw ConfigError{std::format("missing required key '{}'", key)};
}

// Catch by const reference; catch only what you can handle:
try {
    auto cfg = load_config(path);
} catch (const ConfigError& e) {
    std::println(stderr, "config: {}", e.what());
    return EXIT_FAILURE;
}                       // anything else propagates — on purpose
```

- **Throw by value, catch by `const&`.** Catching by value slices derived types; throwing pointers creates ownership puzzles.
- Derive from the `std::exception` hierarchy (`runtime_error` for environmental failures, `logic_error` family for contract violations you nevertheless want catchable) so generic boundaries can `catch (const std::exception&)`.
- **Catch-and-rethrow to add context** with `std::throw_with_nested` / `std::rethrow_if_nested` — preserves the original cause as a chain:

```cpp
try { parse(file); }
catch (...) { std::throw_with_nested(ConfigError{std::format("while loading {}", path)}); }
```

- **Never `catch (...)` and swallow silently** except at the three legitimate sinks: `main`, thread entry points, and `extern "C"` boundaries — and even there, log before converting/terminating.
- RAII is the other half of exceptions: every resource in a destructor-cleaned owner means unwinding can't leak. A codebase with manual cleanup between acquire and release is not exception-safe no matter how careful the catches are. See ownership rules in [../SKILL.md](../SKILL.md).

## The noexcept Policy

`noexcept` is a *promise enforced by terminate*: if an exception tries to escape a `noexcept` function, `std::terminate` runs — no unwinding to a caller's catch. Since C++17 it is also part of the function's type. So treat it as API contract, not optimization sprinkle.

**Mark `noexcept`:**

| What | Why |
|------|-----|
| Move constructors and move assignment | `std::vector` and friends use `std::move_if_noexcept`: a throwing-move type gets **copied** during reallocation — silent, large performance loss. This is the single most consequential `noexcept` site. |
| `swap` | strong-guarantee implementations (copy-and-swap) rely on a nothrow swap |
| Destructors | already implicitly `noexcept`; never write `noexcept(false)` on one — a destructor throwing during unwinding is instant terminate |
| Hash functions, comparators handed to containers | container invariant code assumes it |
| Leaf utilities that genuinely cannot throw | documentation value |

```cpp
class Buffer {
public:
    Buffer(Buffer&& other) noexcept            // mandatory for container friendliness
        : data_{std::exchange(other.data_, nullptr)},
          size_{std::exchange(other.size_, 0)} {}
    Buffer& operator=(Buffer&& other) noexcept { /* … */ }
};
static_assert(std::is_nothrow_move_constructible_v<Buffer>);  // pin it in tests
```

**Do NOT blanket-`noexcept`** everything that "currently doesn't throw": it is a one-way door (removing it breaks callers' types and assumptions), and a future maintainer adding an allocation inside converts an error into process death. When the truth is conditional, say so:

```cpp
template <class T>
void relocate(T& dst, T& src) noexcept(std::is_nothrow_move_constructible_v<T>);
```

Functions reporting via `expected`/error codes should usually be `noexcept` — that's the point of choosing value-based errors — but only after the body truly cannot throw (watch for allocating `std::string` error messages).

## Exception-Safety Guarantees

Every function provides one of these whether you thought about it or not; the review question is *which*:

| Guarantee | Promise | Cost |
|-----------|---------|------|
| **Nothrow** | cannot fail (`noexcept`) | strongest; only for moves, swaps, cleanup |
| **Strong** | on failure, state is unchanged (commit-or-rollback) | may require copies; copy-and-swap idiom |
| **Basic** | on failure, invariants hold, no leaks — but state may have changed | the floor every function must meet; RAII gives it nearly for free |
| **None** | leaks or broken invariants on failure | a bug, not a choice |

```cpp
// Strong guarantee via copy-and-swap: all throwing work before the commit point
Config& Config::operator=(const Config& other) {
    Config tmp{other};        // may throw — *this untouched
    swap(*this, tmp);         // noexcept commit
    return *this;
}
```

Don't pay for strong where basic suffices — strong on a multi-container update means staging every change. Document the guarantee where it's load-bearing; assume basic elsewhere. The same taxonomy applies to `expected`-returning code: "returned an error — what state is the object in?" needs an answer either way.

## std::error_code and Custom Error Domains

**C++11 baseline (`<system_error>`)** — predates `expected` and pairs perfectly with it. An `std::error_code` is `{int value, const std::error_category* domain}`: it preserves the exact platform error without forcing every layer to enumerate every possible cause.

```cpp
// Capturing a syscall failure without losing information:
std::error_code last_os_error() { return {errno, std::generic_category()}; }

std::expected<File, std::error_code> open_file(const char* path) {
    int fd = ::open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return std::unexpected(last_os_error());
    return File{fd};
}

// Callers compare against PORTABLE conditions, not raw numbers:
if (auto f = open_file(p); !f) {
    if (f.error() == std::errc::no_such_file_or_directory) { /* create it */ }
    else log("open failed: {}", f.error().message());
}
```

Key distinction: `error_code` is the *exact* (possibly platform-specific) error; `std::error_condition` (what `std::errc` values are) is the *portable meaning*. `ec == std::errc::…` triggers the category's mapping — that comparison is the portable spelling.

### A custom error domain

Give a subsystem its own enum + category so its errors flow through generic `error_code` plumbing:

```cpp
enum class ParseErrc { ok = 0, unexpected_token = 1, eof = 2, depth_exceeded = 3 };

class ParseCategory final : public std::error_category {
public:
    const char* name() const noexcept override { return "parser"; }
    std::string message(int v) const override {
        switch (static_cast<ParseErrc>(v)) {
            case ParseErrc::unexpected_token: return "unexpected token";
            case ParseErrc::eof:              return "unexpected end of input";
            case ParseErrc::depth_exceeded:   return "nesting depth exceeded";
            default:                          return "ok";
        }
    }
};

const std::error_category& parse_category() {
    static ParseCategory c; return c;            // category identity = address: ONE instance
}
std::error_code make_error_code(ParseErrc e) {
    return {static_cast<int>(e), parse_category()};
}
template <> struct std::is_error_code_enum<ParseErrc> : std::true_type {};

// Now: std::expected<Ast, std::error_code> parse(…);  return std::unexpected(ParseErrc::eof);
```

Rules: value `0` means success by convention; the category must be a singleton (comparison is by address); `message()` may allocate — fine, it runs on error paths only. To bridge into exception land, `throw std::system_error{ec, "context"}` wraps any `error_code`.

When to prefer a plain project enum as `E` instead: when errors never leave your module and you don't need interop with `errno`/OS errors — the category machinery is boilerplate you can skip. `error_code` earns its keep at OS and cross-library boundaries.

## std::expected Chaining in Practice

Mechanics and feature macros live in `cpp23-features.md`; this is the usage doctrine. **C++23** (`__cpp_lib_expected >= 202211L` for the monadic ops); pre-23 fallback `tl::expected` has the same surface.

```cpp
std::expected<Request, std::error_code>  read_request(Socket&);
std::expected<Command, std::error_code>  parse(const Request&);
std::expected<Reply,   std::error_code>  execute(const Command&);

std::expected<Reply, std::error_code> handle(Socket& s) {
    return read_request(s)
        .and_then(parse)        // fallible step: short-circuits on error
        .and_then(execute);     // never runs if parse failed
}
```

| Need | Use | Callable shape |
|------|-----|----------------|
| next fallible step | `and_then(f)` | `T → expected<U, E>` |
| infallible mapping of the value | `transform(f)` | `T → U` |
| recover from / inspect error | `or_else(f)` | `E → expected<T, F>` |
| convert the error type (layer boundary) | `transform_error(f)` | `E → F` |

Doctrine:

- **Chain for linear pipelines; early-return for branching logic.** When step 3 needs values from steps 1 *and* 2, nesting lambdas to keep both in scope is worse than:

```cpp
auto req = read_request(s);
if (!req) return std::unexpected(req.error());
auto cmd = parse(*req);
if (!cmd) return std::unexpected(cmd.error());
return execute_with(*req, *cmd);          // needs both — flat style wins
```

- If the project has a `TRY(expr)`-style propagation macro, use it consistently; don't add a second spelling.
- `transform_error` is the boundary tool: a storage layer returning `std::error_code` becomes a domain layer returning `AppError` in one hop, without touching success paths.
- Logging belongs in `or_else` (which sees the error) — not sprinkled inside every step.

## Designing Error Types

The `E` in `expected<T, E>` is API. Guidelines:

- **Small and cheap**: an enum, or enum + small context struct. `expected` carries `E` in every return; a `std::string` message member makes every failure allocate — acceptable at top layers, wrong in inner loops.
- **Actionable over descriptive**: callers branch on *what to do* (`retry`, `not_found`, `invalid_input`), not on prose. Put prose in `message()`/formatting, not in the discriminant.
- **Context via composition** when needed:

```cpp
struct IoError {
    std::error_code code;                                   // what happened
    std::string     path;                                   // on what
    std::source_location where = std::source_location::current();  // C++20; pre-20: __FILE__/__LINE__ macro pair
};
```

- `std::source_location` default arguments capture the *call site* for free (C++20). For deep post-mortem context, a `std::stacktrace` member captured at construction (C++23, link-flag caveats — see `cpp23-features.md`) — error path only, never on success.
- Avoid `expected<T, std::string>`: stringly-typed errors can't be branched on and lock the message format into the API.

## Boundary Translation

Mechanisms don't survive contact with foreign layers; translate at each boundary, in the direction the boundary demands.

### Exceptions → expected (wrapping a throwing dependency)

```cpp
template <class F>
auto to_expected(F&& f) noexcept
    -> std::expected<std::invoke_result_t<F>, std::error_code> {
    try {
        return std::forward<F>(f)();
    } catch (const std::system_error& e) {
        return std::unexpected(e.code());                       // preserve the domain
    } catch (const std::bad_alloc&) {
        return std::unexpected(make_error_code(std::errc::not_enough_memory));
    } catch (...) {
        return std::unexpected(make_error_code(std::errc::state_not_recoverable));
    }
}
```

### expected → exceptions (wrapping a value-based core for a throwing API)

```cpp
Reply handle_or_throw(Socket& s) {
    auto r = handle(s);
    if (!r) throw std::system_error{r.error(), "handle"};
    return std::move(*r);
}
```

`expected::value()` already throws `bad_expected_access<E>` — fine internally, but `system_error` with a real `error_code` is the better public surface.

### Shared-library boundaries

Throwing across a shared-library boundary is only safe when both sides use the same compiler, standard library, *and* exception ABI — same-toolchain plugins can get away with it; anything user-extensible cannot. For plugin ABIs: C-compatible surface (below), or at minimum document the toolchain contract loudly.

## The extern "C" Edge

**An exception escaping through an `extern "C"` function is undefined behavior** (commonly terminate, sometimes worse — C frames have no unwind tables). Every `extern "C"` entry point that calls C++ must be a firewall:

```cpp
// public_api.h — consumable from C
typedef enum { LIB_OK = 0, LIB_EINVAL = 1, LIB_ENOMEM = 2, LIB_EINTERNAL = 3 } lib_status;
lib_status lib_process(const char* input, char* out, size_t out_len);
const char* lib_last_error_message(void);   // optional rich-text channel

// impl.cpp — the firewall pattern
static thread_local std::string g_last_error;

extern "C" lib_status lib_process(const char* input, char* out, size_t out_len) noexcept {
    try {
        if (!input || !out) return LIB_EINVAL;
        auto result = core::process(input);           // C++ may throw freely inside
        if (!result) { g_last_error = result.error().message(); return LIB_EINVAL; }
        copy_to(out, out_len, *result);
        return LIB_OK;
    } catch (const std::bad_alloc&) {
        return LIB_ENOMEM;
    } catch (const std::exception& e) {
        g_last_error = e.what();  return LIB_EINTERNAL;
    } catch (...) {
        g_last_error = "unknown error";  return LIB_EINTERNAL;
    }
}
extern "C" const char* lib_last_error_message(void) noexcept { return g_last_error.c_str(); }
```

Rules for the C edge:

- **`catch (...)` is mandatory** at every entry point — one missed exception type is UB, not a bug report.
- Mark the definitions `noexcept`: if the firewall itself has a hole, terminate loudly rather than corrupt a C caller.
- Status codes are the return value; results travel via out-parameters. `0` = success, per C convention.
- Rich error text goes through a **thread-local** last-error channel (the `errno`/`GetLastError` pattern) — a global string is a data race.
- **Callbacks handed *to* C libraries** (comparators for `qsort`, pthread start routines, signal-adjacent hooks) are the same edge in reverse: the C++ body must be exception-tight (`noexcept` + internal try/catch). The C library's frames between caller and callback cannot unwind.
- No C++ types in the boundary signatures — not even `std::string&`. Sizes, pointers, integer codes. (Full FFI doctrine, including Python bindings: [ffi-interop](../../../tooling/ffi-interop/SKILL.md).)

## Worked Example: A Three-Layer Service

This ties the framework together: each layer picks the mechanism its callers need, and translates exactly once at the boundary it owns. The progression — OS error → domain error → C ABI — is the most common real-world shape.

```cpp
// ── Layer 1: storage. Talks to the OS, so it speaks std::error_code. ──────────
namespace storage {
std::expected<std::string, std::error_code> read(const std::filesystem::path& p) {
    std::ifstream in{p, std::ios::binary};
    if (!in) return std::unexpected(std::error_code{errno, std::generic_category()});
    std::string data{std::istreambuf_iterator<char>{in}, {}};
    if (in.bad()) return std::unexpected(std::make_error_code(std::errc::io_error));
    return data;                                       // success
}
}  // namespace storage

// ── Layer 2: domain. Has its own actionable error enum; the OS code is an ─────
//    implementation detail callers must not branch on, so it is translated away.
namespace app {
enum class LoadError { not_found, corrupt, io };

std::expected<Document, LoadError> load(std::string_view name) {
    return storage::read(path_for(name))
        .transform_error([](std::error_code ec) {      // boundary: ec → LoadError
            if (ec == std::errc::no_such_file_or_directory) return LoadError::not_found;
            return LoadError::io;
        })
        .and_then([](std::string raw) -> std::expected<Document, LoadError> {
            auto doc = parse_document(raw);             // returns std::optional<Document>
            if (!doc) return std::unexpected(LoadError::corrupt);
            return *std::move(doc);
        });
}
}  // namespace app

// ── Layer 3: C ABI. Exceptions and C++ types cannot cross; collapse to codes. ─
extern "C" int svc_load(const char* name, Document** out) noexcept {
    try {
        auto doc = app::load(name);
        if (!doc) return doc.error() == app::LoadError::not_found ? 2 : 1;
        *out = new Document{std::move(*doc)};
        return 0;
    } catch (...) { return 1; }                         // firewall: nothing escapes
}
```

What each boundary does:

- **Storage → domain**: `transform_error` runs only on the failure path and never touches the success value. The OS error's fidelity is deliberately discarded here because no caller above this layer should branch on `errno`.
- **Within domain**: an `optional`-returning parser is lifted into the `expected` chain by mapping `nullopt` to a domain error in `and_then` — the standard adapter between "absence" and "named failure".
- **Domain → C**: the only place a `try/catch` appears, because it is the only place an exception would be UB. Even though the layers below return values, an allocation (`std::string`, `new Document`) can still throw `bad_alloc`, so the firewall is not optional.

## Anti-Patterns That Pass Review

| Anti-pattern | Why it bites | Do instead |
|--------------|--------------|------------|
| `catch (std::exception e)` (by value) | slices the derived type; loses the real message/type | `catch (const std::exception& e)` |
| `catch (...) {}` (empty) outside the three sinks | swallows bugs; failures vanish silently | handle a specific type, or let it propagate |
| `noexcept` on a function that allocates an error string | one `bad_alloc` → `std::terminate`, no recovery | drop `noexcept`, or pre-size/avoid the allocation |
| Throwing move constructor (no `noexcept`) | `vector` reallocation silently switches to copies | `noexcept` + `static_assert(is_nothrow_move_constructible_v<T>)` |
| `expected<T, std::string>` as a public API | callers can't branch; message format frozen into the ABI | enum / small struct `E`; prose in formatting |
| Reusing one error enum across unrelated modules | every caller handles cases that can't occur; coupling | per-module enum, translate at the boundary |
| Exception thrown across `extern "C"` or into a C callback | undefined behavior (terminate or worse) | `noexcept` firewall with `catch (...)` |
| `error_category` instance per call (not a singleton) | identity compares by address → comparisons silently fail | `static` local; return by reference |
| Mixing throw and `expected` for the *same* failure class in one layer | every caller must handle both paths | one mechanism per layer; translate at edges |
| Destructor that can throw | throwing during unwinding → instant terminate | log-and-swallow; never `noexcept(false)` |
| `if (expected_value.value())` to test success | `value()` *throws* on error — that's not a test | `if (e)` / `if (e.has_value())` |
| Ignoring an `expected`/`error_code` return | `[[nodiscard]]` on the type catches it; without it, errors leak | mark fallible returns `[[nodiscard]]`; check every one |

`std::expected`, `std::optional`, and `std::error_code` are not `[[nodiscard]]` by default in every standard library — mark *your* fallible-returning functions `[[nodiscard]]` so a dropped error is a warning, not a latent bug.

## Availability and Fallbacks

| Facility | Standard | Pre-version fallback |
|----------|----------|----------------------|
| Exceptions, `<system_error>`, `error_code`/`error_category` | C++11 baseline — everywhere | — |
| `noexcept` in the type system | C++17 | behavioral `noexcept` only (C++11) |
| `std::optional` | C++17 | — (baseline for this plugin) |
| `std::source_location` | C++20 (`__cpp_lib_source_location`) | `__FILE__`/`__LINE__` macro pair |
| `std::expected` + monadic ops | C++23 (`__cpp_lib_expected >= 202211L`) | `tl::expected` — API-compatible, works on C++17 |
| `std::stacktrace` in error types | C++23 (`__cpp_lib_stacktrace`) — extra link flags on some toolchains; verify against your toolchain | `boost::stacktrace` |
| `std::print` for error reporting | C++23 (`__cpp_lib_print`) | `fmt::print` / `std::format` + stream |

Standard-selection policy and the full fallback table: [../../SKILL.md](../../SKILL.md). Toolchain minimums: [version-feature-matrix](../../../_shared/version-feature-matrix.md).
