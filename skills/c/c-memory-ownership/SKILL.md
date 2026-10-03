---
name: c-memory-ownership
description: >-
  C memory ownership conventions, cleanup patterns, allocator selection, and
  sanitizer-first debugging. Use when designing C APIs that allocate memory,
  fixing leaks, double-frees, or use-after-free bugs, choosing between goto
  cleanup and arena allocation, or interpreting AddressSanitizer reports.
---

# C Memory Ownership

Every allocation has exactly one owner at any moment, and the header documents who it is.

## Ownership Conventions

### Document ownership in the header

Label every pointer parameter and return value: caller owns (caller must release), borrowed (valid only for the call or a stated window), or transfers (callee takes ownership). Undocumented ownership is a review finding.

```c
/**
 * Parse src into a newly allocated tree.
 * @param src  Borrowed; must remain valid only for the duration of the call.
 * @return     Tree owned by the caller; release with ast_destroy(). NULL on error.
 */
ast *ast_parse(const char *src);
```

### `_create`/`_destroy` pairing

- Every `foo_create()` ships a matching `foo_destroy()` in the same header; callers never `free()` directly, because the struct may own nested resources and the allocator must match.
- `foo_destroy(NULL)` is a no-op, mirroring `free(NULL)`.
- Destroy releases members in reverse order of acquisition, then the struct itself.

### Opaque handles

Keep the struct definition in the `.c` file; the header sees only a forward declaration. Callers then cannot copy, stack-allocate, or partially free it, and the ABI stays stable.

```c
/* widget.h */
typedef struct widget widget;                /* opaque */
widget *widget_create(const char *name);     /* caller owns; widget_destroy() */
void    widget_destroy(widget *w);           /* NULL-safe */
```

### Out-param vs returned pointer

| API shape | Signature | Use when |
|---|---|---|
| Returned pointer | `widget *widget_create(void);` | One failure mode; `NULL` says enough |
| Out-param + status | `int widget_create(widget **out);` | Caller needs distinct error codes (0 / negative errno-style) |
| Caller-provided storage | `int widget_init(widget *w);` + `widget_fini()` | Caller controls placement: stack, arena, embedded in another struct |
| Two-call sizing | `size_t fmt(char *buf, size_t cap, ...);` | Variable-size results without allocating (`snprintf` pattern) |

On the out-param path, write `*out` only on success and never leave it half-initialized.

## Cleanup Patterns (ranked)

| Rank | Pattern | Portability | Use when |
|---|---|---|---|
| 1 | `goto cleanup` | ISO C, every compiler | Default for any function acquiring 2+ resources |
| 2 | `__attribute__((cleanup(fn)))` | GCC/Clang extension, no MSVC | Fixed-toolchain codebases (systemd-style `_cleanup_` macros) |
| 3 | Arena allocation | ISO C library pattern | Many allocations sharing one lifetime: parsers, request scopes |

### 1. `goto cleanup`

Initialize every resource to its sentinel first, jump to a single exit, release in reverse order:

```c
int process(const char *path) {
    int   rc  = -1;
    FILE *f   = NULL;
    char *buf = NULL;

    f = fopen(path, "r");
    if (!f) goto cleanup;
    buf = malloc(BUF_SIZE);
    if (!buf) goto cleanup;

    /* ... work ... */
    rc = 0;
cleanup:
    free(buf);          /* free(NULL) is a no-op */
    if (f) fclose(f);   /* fclose(NULL) is UB */
    return rc;
}
```

### 2. Scope-bound cleanup (GCC/Clang only)

```c
static void free_p(void *p) { free(*(void **)p); }
#define AUTOFREE __attribute__((cleanup(free_p)))

void demo(void) {
    AUTOFREE char *buf = malloc(256);
    /* freed on every scope exit: return, goto, fallthrough */
}
```

Runs in reverse declaration order; does not run on `exit()` or `longjmp()`.

### 3. Arenas

One `arena_destroy()` replaces hundreds of `free()` calls and makes leaks within the scope structurally impossible. Implementations: [references/allocators-and-arenas.md](references/allocators-and-arenas.md).

## Key Allocation Facts

| Fact | Standard | Consequence |
|---|---|---|
| `free(NULL)` is a no-op | C89+ | Don't write `if (p) free(p);` |
| `realloc` failure keeps the original block valid | C89+ | `p = realloc(p, n)` leaks on failure; use a temp |
| `realloc(p, 0)` | UB in C23; implementation-defined in C17 and earlier | Call `free(p)` explicitly instead |
| Pointer value after `free` is indeterminate | C89+ | Even comparing a freed pointer is UB; NULL it out |
| `calloc(n, size)` returns NULL on `n * size` overflow | Explicit in C23; all major libcs | Prefer it over `malloc(n * size)` for arrays |
| `malloc(n * size)` wraps silently on overflow | — | Use `calloc`, `ckd_mul` (C23), or a `SIZE_MAX` guard |

### The realloc temp pattern

```c
void *tmp = realloc(p, new_size);
if (!tmp) {
    /* p is still valid and still owned — handle or free deliberately */
    return -1;
}
p = tmp;   /* old pointer value is now indeterminate; never touch it */
```

### Overflow-checked sizing

```c
#include <stdckdint.h>                     /* C23: GCC 14+/Clang 18+ */
size_t bytes;
if (ckd_mul(&bytes, n, sizeof *arr)) return NULL;
arr = malloc(bytes);
```

Pre-C23 fallback: `if (sizeof *arr && n > SIZE_MAX / sizeof *arr) return NULL;` or `__builtin_mul_overflow` (GCC/Clang).

### NULL-after-free

`free(p); p = NULL;` turns a later double-free into a no-op and a use-after-free into a clean NULL-deref crash. It protects only that one alias; the real fix is single ownership.

## Sanitizer-First Debugging Workflow

Debug memory bugs with instrumentation before reaching for a debugger:

1. Rebuild with `-fsanitize=address,undefined -fno-omit-frame-pointer -g -O1 -fno-sanitize-recover=all` so the first report halts.
2. Read the first report only; later ones are usually corruption fallout.
3. Read all three ASan stacks (bad access, free, allocation): together they name the two parties that both believed they owned the block.
4. Fix the ownership bug, not the crash site; patching the access hides the dangling alias.
5. Re-run the full suite under ASan+UBSan and check leaks. LeakSanitizer is on with ASan on Linux; Apple clang lacks it, so on macOS use `leaks` or upstream LLVM clang.
6. Use Valgrind memcheck when you cannot rebuild (third-party `.so`), at ~10-50x slowdown.

TSan can't combine with ASan; use a separate build directory per sanitizer.

## ASan Report Diagnostic Table

### Heap and Allocator Reports

| Report header | Cause | Fix |
|---|---|---|
| `heap-use-after-free` | Access through a dangling alias after the owner freed | Single owner; NULL-after-free; fix lifetime |
| `heap-buffer-overflow` | Wrong size math, off-by-one, unterminated string | `calloc`/`ckd_mul`; recheck bounds; FAM sizing |
| `double-free` | Two owners both freed | One `_destroy` path; NULL-after-free |
| `alloc-dealloc-mismatch` | `malloc`/`delete` or cross-allocator free | Pair allocator and deallocator via `_create`/`_destroy` |
| `attempting free on address which was not malloc()-ed` | Freeing a stack, global, interior, or arena pointer | Free only the exact pointer `malloc` returned |

### Stack, Leak, and NULL Reports

| Report header | Cause | Fix |
|---|---|---|
| `stack-buffer-overflow` | Local array overrun | Fix bounds; `sizeof buf` not `sizeof ptr` |
| `stack-use-after-return` | Pointer to a local escaped | Heap or caller buffer; needs `detect_stack_use_after_return=1` (default in Clang 15+ on Linux) |
| `LeakSanitizer: detected memory leaks` | A path skips `free`, often an early error return | Audit `goto cleanup`, or arena the scope |
| `SEGV on unknown address 0x000000000000` | NULL dereference | Check returns; `-fsanitize=null` for the exact site |
| `dynamic-stack-buffer-overflow` | VLA or `alloca` overrun | Bound the size first; prefer a fixed cap |

## Deep-Dive References

- [references/undefined-behavior-catalog.md](references/undefined-behavior-catalog.md): UB classes, the sanitizer flag that detects each, and the correct rewrite
- [references/allocators-and-arenas.md](references/allocators-and-arenas.md): arena/pool/stack allocators, flexible array members, alignment, allocator injection

## Related Skills

- [modern-c](../modern-c/SKILL.md): C23 features (`nullptr`, `<stdckdint.h>`, `constexpr`) and C11 atomics/threads
- [diagnostics](../../tooling/diagnostics/SKILL.md): sanitizer combination rules, gdb/lldb, Valgrind, profiling
- [secure-coding](../../_shared/secure-coding/SKILL.md): input validation and injection-safe command execution
- [modern-cpp](../../cpp/modern-cpp/SKILL.md): RAII and smart pointers when C++ is available at the boundary
