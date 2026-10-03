# Allocators and Arenas

Arena, pool, and stack allocators, alignment, flexible array members, and allocator-aware API design. UB classes and sanitizer reports: `undefined-behavior-catalog.md`; ownership conventions and cleanup ranking: the parent `SKILL.md`.

## Choosing an Allocation Strategy

| Strategy | Free granularity | Best for | Avoid when |
|---|---|---|---|
| `malloc`/`free` per object | Individual | Long-lived objects with independent lifetimes | Thousands of small allocations with one shared lifetime |
| Arena (bump) | Whole arena at once | Parsers, ASTs, per-request/per-frame scratch — many objects, one lifetime | Objects must be freed individually or outlive the scope |
| Growing arena | Whole arena | Same, but total size unknown upfront | Hard real-time bounds on a single allocation call |
| Stack allocator | LIFO, marker-based | Nested scopes: recursive descent, undo points | Frees happen out of order |
| Pool | Individual, O(1) | Many objects of one fixed size churning (nodes, connections) | Mixed sizes (per-size pools or fall back to malloc) |

Decision shortcut: if you can name the single moment when *everything* becomes garbage, use an arena. If objects are uniform and churn, use a pool. Otherwise stay with `malloc` and the ownership conventions from the parent `SKILL.md`.

Beyond speed (a bump allocation is an add and a compare), arenas remove the leak-on-error-path bug class: one `arena_destroy` in the `goto cleanup` block releases everything the scope made.

## Alignment Fundamentals

| Tool | Standard | Notes |
|---|---|---|
| `_Alignof(T)` / `alignof` | C11 (`<stdalign.h>` macro); C23 makes `alignof` a keyword | Query the required alignment of a type |
| `_Alignas(N)` / `alignas` | C11; C23 keyword | Over-align a declaration: `alignas(64) char buf[256];` |
| `max_align_t` | C11, `<stddef.h>` | `malloc` results are aligned for any type with fundamental alignment, i.e., `alignof(max_align_t)` |
| `aligned_alloc(align, size)` | C11; relaxed by DR 460 in C17 | C11 made a `size` that is not a multiple of `align` UB; C17 drops that rule, but older libcs still return NULL, so round `size` up |
| `posix_memalign(&p, align, size)` | POSIX | `align` must be a power-of-two multiple of `sizeof(void *)`; result is `free()`-able |
| `_aligned_malloc` / `_aligned_free` | MSVC (no `aligned_alloc` in UCRT) | Pair with `_aligned_free`, not `free()` |

```c
#include <stdalign.h>     /* pre-C23; harmless under C23 */
#include <stdlib.h>

alignas(64) static unsigned char ring[4096];   /* cache-line aligned static */

void *block = aligned_alloc(64, 4096);         /* size is a multiple of align */
free(block);                                   /* aligned_alloc memory is free()-able */
```

Over-align for SIMD loads, to keep per-thread counters on separate cache lines (`alignas(64)`), or for device/DMA contracts.

- Keep `align` a power of two and round `size` up: `size = (size + align - 1) / align * align;`. Fall back to `posix_memalign` (POSIX) or `_aligned_malloc` (Windows) where `aligned_alloc` is missing.
- A custom allocator must reproduce `malloc`'s alignment guarantee or take an explicit `align` parameter; handing out odd offsets of a `char` buffer is misaligned-access UB on strict targets.

## Arena (Bump) Allocator

Fixed-capacity core — allocation is pointer-bump plus overflow checks:

```c
#include <stdalign.h>
#include <stddef.h>
#include <stdint.h>     /* SIZE_MAX */
#include <stdlib.h>
#include <string.h>

typedef struct {
    unsigned char *base;
    size_t         cap;
    size_t         used;
} arena;

int arena_init(arena *a, size_t cap) {
    a->base = malloc(cap);
    if (!a->base) return -1;
    a->cap  = cap;
    a->used = 0;
    return 0;
}

void arena_destroy(arena *a) {
    if (!a) return;
    free(a->base);
    a->base = NULL;
    a->cap = a->used = 0;
}

static size_t arena_align_up(size_t n, size_t align) {
    return (n + (align - 1)) & ~(align - 1);   /* align: power of two */
}

void *arena_alloc(arena *a, size_t size, size_t align) {
    size_t offset = arena_align_up(a->used, align);
    if (offset < a->used) return NULL;                       /* align_up wrapped */
    if (offset > a->cap || size > a->cap - offset) return NULL;  /* no overflow form */
    void *p = a->base + offset;
    a->used = offset + size;
    return p;
}

void arena_reset(arena *a) { a->used = 0; }    /* everything dies at once */
```

Both checks are load-bearing: `offset < a->used` catches `align_up` wrapping past `SIZE_MAX`, and `size > a->cap - offset` is the overflow-proof form of `offset + size > a->cap`.

Typed helpers keep call sites honest about alignment:

```c
#define ARENA_NEW(a, T)      ((T *)arena_alloc((a), sizeof(T), alignof(T)))
#define ARENA_NEW_N(a, T, n) ((T *)arena_alloc_n((a), sizeof(T), alignof(T), (n)))

void *arena_alloc_n(arena *a, size_t size, size_t align, size_t n) {
    if (size && n > SIZE_MAX / size) return NULL;   /* pre-C23 ckd_mul fallback */
    return arena_alloc(a, size * n, align);
}

char *arena_strdup(arena *a, const char *s) {
    size_t n = strlen(s) + 1;
    char *p = arena_alloc(a, n, 1);
    return p ? memcpy(p, s, n) : NULL;
}
```

Ownership rules an arena imposes (document them in the header):

- Pointers returned by `arena_alloc` are borrowed from the arena: never passed to `free()`, never used after `arena_reset`/`arena_destroy`.
- There is no per-object free. If a caller needs one, the object does not belong in this arena.
- Objects holding non-memory resources (file descriptors, `FILE *`, sockets) may *live* in an arena, but the arena will not close them — pair with `goto cleanup` for handles.

## Growing Arena with Chained Blocks

When total size is unknown, chain fixed blocks; allocation stays O(1) amortized:

```c
typedef struct arena_block arena_block;
struct arena_block {
    arena_block *next;
    size_t       cap;
    size_t       used;
    max_align_t  data[];     /* FAM typed max_align_t: storage aligned for anything */
};

typedef struct {
    arena_block *head;       /* block currently being filled */
    size_t       block_size; /* growth unit, e.g. 64 KiB */
} garena;

static arena_block *block_new(size_t data_cap) {
    size_t bytes;
    if (ckd_add(&bytes, sizeof(arena_block), data_cap)) return NULL;  /* C23 */
    arena_block *b = malloc(bytes);
    if (!b) return NULL;
    b->next = NULL; b->cap = data_cap; b->used = 0;
    return b;
}

void *garena_alloc(garena *g, size_t size, size_t align) {
    arena_block *b = g->head;
    if (b) {
        size_t off = arena_align_up(b->used, align);
        if (off >= b->used && off <= b->cap && size <= b->cap - off) {
            b->used = off + size;
            return (unsigned char *)b->data + off;
        }
    }
    size_t cap = size > g->block_size ? size : g->block_size;  /* oversize: own block */
    arena_block *nb = block_new(cap);
    if (!nb) return NULL;
    nb->next = g->head;
    g->head  = nb;
    nb->used = size;
    return nb->data;
}

void garena_destroy(garena *g) {
    for (arena_block *b = g->head, *next; b; b = next) {
        next = b->next;
        free(b);
    }
    g->head = NULL;
}
```

Pre-C23 fallback for `ckd_add`: `if (data_cap > SIZE_MAX - sizeof(arena_block)) return NULL;`. Typing `data` as `max_align_t[]` aligns offset 0 of every block for any fundamental type; `align_up` handles interior offsets.

## Stack Allocator (LIFO Markers)

A stack allocator is an arena plus the ability to roll back to a saved point. Frees must be strictly LIFO:

```c
typedef size_t arena_marker;

arena_marker arena_mark(const arena *a)            { return a->used; }
void         arena_release(arena *a, arena_marker m) { a->used = m; }

/* Usage: per-iteration scratch inside a long-lived arena */
for (size_t i = 0; i < n_files; i++) {
    arena_marker m = arena_mark(&scratch);
    char *tmp = arena_strdup(&scratch, paths[i]);
    process(tmp);
    arena_release(&scratch, m);       /* iteration's garbage gone, O(1) */
}
```

Everything allocated after the marker dangles once `arena_release` runs: a use-after-free that ASan misses unless you poison (see Testing and Hardening). Keep marker scopes small and lexically obvious.

## Pool Allocator (Fixed-Size Free List)

For high-churn objects of one size, a pool gives O(1) alloc/free with zero fragmentation:

```c
typedef struct pool_node { struct pool_node *next; } pool_node;

typedef struct {
    unsigned char *slab;
    pool_node     *free_list;
    size_t         obj_size;
} pool;

int pool_init(pool *p, size_t obj_size, size_t count) {
    if (obj_size < sizeof(pool_node)) obj_size = sizeof(pool_node);
    obj_size = arena_align_up(obj_size, alignof(max_align_t));
    size_t bytes;
    if (ckd_mul(&bytes, obj_size, count)) return -1;          /* C23 */
    p->slab = malloc(bytes);
    if (!p->slab) return -1;
    p->obj_size  = obj_size;
    p->free_list = NULL;
    for (size_t i = count; i-- > 0; ) {                       /* thread the free list */
        pool_node *n = (pool_node *)(p->slab + i * obj_size);
        n->next = p->free_list;
        p->free_list = n;
    }
    return 0;
}

void *pool_alloc(pool *p) {
    pool_node *n = p->free_list;
    if (!n) return NULL;
    p->free_list = n->next;
    return n;
}

void pool_free(pool *p, void *obj) {
    pool_node *n = obj;          /* intrusive: reuse the object's first bytes */
    n->next = p->free_list;
    p->free_list = n;
}

void pool_destroy(pool *p) { free(p->slab); p->slab = NULL; p->free_list = NULL; }
```

- Writing `pool_node` into raw `malloc` memory is aliasing-clean: allocated storage has no declared type, so each store sets the effective type.
- The intrusive free list reuses freed objects' bytes, so a use-after-free through a stale pool pointer corrupts the list. Debug builds should fill freed slots with `0xDD` and validate `next` on alloc.
- `pool_free` does not check that `obj` came from this pool; add a range check against `slab` in debug builds if callers can get it wrong.

## Flexible Array Members

A flexible array member (C99) puts a variable-length tail inside one allocation: one `malloc`, one `free`:

```c
typedef struct {
    size_t len;
    char   data[];               /* FAM: must be the last member */
} strbuf;

strbuf *strbuf_create(size_t len) {
    size_t bytes;
    if (ckd_add(&bytes, sizeof(strbuf), len)) return NULL;   /* C23; see fallback below */
    strbuf *s = malloc(bytes);
    if (!s) return NULL;
    s->len = len;
    return s;
}
```

Pre-C23 fallback: `if (len > SIZE_MAX - sizeof(strbuf)) return NULL;`.

Rules (C17 6.7.2.1):

| Rule | Consequence |
|---|---|
| FAM must be the last member of a struct with at least one other named member | `struct { char data[]; }` alone is invalid |
| `sizeof(struct)` excludes the FAM but includes padding before it | `sizeof(strbuf) + len` may slightly over-allocate; that is fine |
| A struct with a FAM cannot be an array element or a member of another struct | Compose by pointer instead |
| Assigning such structs copies everything *except* the FAM | Treat them as non-copyable; allocate + `memcpy` the full byte size |

Replace the pre-C99 `char data[1];` hack with `[]` and drop its `- 1` size adjustments: indexing past element 0 is out-of-bounds UB that `-fsanitize=bounds` reports.

In an arena, `arena_alloc(a, sizeof(strbuf) + len, alignof(strbuf))` carves variable-size records with no per-record overhead.

## Ownership API Design

The caller-facing shapes from the parent `SKILL.md`, by allocator coupling:

| Shape | Who allocates | Who frees | Allocator coupling |
|---|---|---|---|
| `T *t_create(...)` | Library | Caller via `t_destroy` | Hidden — library picks; `t_destroy` must match |
| `int t_create(T **out, ...)` | Library | Caller via `t_destroy` | Same, plus room for error codes |
| `int t_init(T *t, ...)` / `t_fini` | Caller | Caller | None — caller may use stack, arena, pool |
| `size_t t_serialize(char *buf, size_t cap)` | Caller | Caller | None — two-call sizing |

Design rules:

- Export `t_destroy`, not `free()`, even when `t_create` is a single `malloc`: it keeps room for nested allocations or a different allocator without breaking callers.
- Offer `_init`/`_fini` alongside `_create`/`_destroy` when the struct can be public, so callers can embed it in their structs, arrays, arenas, and stacks.
- For two-call sizing, return the required size when the buffer is too small (the `snprintf` contract) and document whether the buffer is truncated or untouched on that path.

## Allocator Injection

Libraries that allocate should let embedders supply the allocator (arena, pool, instrumented wrapper, failing allocator in tests):

```c
typedef struct {
    void *(*alloc)(void *ctx, size_t size, size_t align);
    void  (*release)(void *ctx, void *ptr);     /* may be a no-op (arena) */
    void  *ctx;
} allocator;

/* Default: thread through to malloc/free */
static void *sys_alloc(void *ctx, size_t size, size_t align) {
    (void)ctx; (void)align;                     /* malloc is max_align_t-aligned */
    return malloc(size);
}
static void sys_release(void *ctx, void *p) { (void)ctx; free(p); }

static const allocator sys_allocator = { sys_alloc, sys_release, NULL };
```

The object stores the allocator it was created with, so `_destroy` cannot mismatch:

```c
struct widget {
    allocator al;       /* by value: widget owns its way home */
    char     *name;
};

widget *widget_create(const allocator *al, const char *name) {
    if (!al) al = &sys_allocator;
    widget *w = al->alloc(al->ctx, sizeof *w, alignof(widget));
    if (!w) return NULL;
    w->al = *al;
    size_t n = strlen(name) + 1;
    w->name = al->alloc(al->ctx, n, 1);
    if (!w->name) {                          /* unwind with the SAME allocator */
        al->release(al->ctx, w);
        return NULL;
    }
    memcpy(w->name, name, n);
    return w;
}

void widget_destroy(widget *w) {
    if (!w) return;
    allocator al = w->al;                /* copy out before freeing the holder */
    al.release(al.ctx, w->name);
    al.release(al.ctx, w);
}
```

The `allocator al = w->al;` copy matters: reading `w->al` after releasing `w` is use-after-free. With an arena allocator `release` is a no-op, but `_destroy` is still required by contract for non-memory resources; say so in the header.

## Growth Patterns with realloc

Dynamic arrays grow geometrically, with every step overflow-checked and the realloc temp pattern from the parent `SKILL.md`:

```c
typedef struct { int *data; size_t len, cap; } vec;

int vec_reserve(vec *v, size_t need) {
    if (need <= v->cap) return 0;
    size_t cap = v->cap ? v->cap : 8;
    while (cap < need)
        if (ckd_add(&cap, cap, cap / 2)) return -1;   /* 1.5x growth, C23 checked */
    size_t bytes;
    if (ckd_mul(&bytes, cap, sizeof *v->data)) return -1;
    void *tmp = realloc(v->data, bytes);
    if (!tmp) return -1;                               /* v->data still valid */
    v->data = tmp;
    v->cap  = cap;
    return 0;
}
```

- 1.5x or 2x growth are both fine; growing by `+1` is quadratic copying.
- After a successful `realloc`, every pointer into the old block dangles; keep indexes, not element pointers, across `vec_reserve` calls.
- In an arena only the most recent allocation can grow in place; otherwise allocate new and copy, accepting the dead space.

## Testing and Hardening Custom Allocators

ASan only redzones the outer `malloc` blocks, so interior arena overruns land in your own valid memory. Poison manually:

```c
#if defined(__SANITIZE_ADDRESS__)            /* GCC */
#  define HAVE_ASAN 1
#elif defined(__has_feature)
#  if __has_feature(address_sanitizer)       /* Clang */
#    define HAVE_ASAN 1
#  endif
#endif

#ifdef HAVE_ASAN
#  include <sanitizer/asan_interface.h>
#  define POISON(p, n)   ASAN_POISON_MEMORY_REGION((p), (n))
#  define UNPOISON(p, n) ASAN_UNPOISON_MEMORY_REGION((p), (n))
#else
#  define POISON(p, n)   ((void)0)
#  define UNPOISON(p, n) ((void)0)
#endif
```

Wire the hooks at the three lifecycle points:

- `arena_init`: `POISON(base, cap)`.
- `arena_alloc`: `UNPOISON(p, size)`, only the granted bytes; alignment gaps stay poisoned.
- `arena_reset` / `arena_release`: re-`POISON` the reclaimed region, so marker-rollback use-after-free becomes an ASan report.

Further hardening:

| Technique | Cost | Catches |
|---|---|---|
| Debug pattern fill (`0xAA` on alloc, `0xDD` on free/reset) | Debug-only memset | Uninitialized reads, stale-pointer reads become obvious in a debugger |
| Per-allocation canaries before/after user bytes, verified on reset | A few bytes + check loop | Interior overruns without ASan |
| Failure injection (`fail after N allocations` switch in the allocator vtable) | Test-only | Untested error paths — the place leaks live |
| High-water-mark counter | One max() per alloc | Sizing arenas honestly instead of guessing |
| Valgrind client requests (`VALGRIND_MAKE_MEM_NOACCESS` et al.) | Macro calls | The same poisoning for Valgrind runs |

## Diagnostic Pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| ASan stays green but arena data corrupts | Interior overrun inside one big block — no redzones | Manual poisoning hooks (above); per-allocation canaries |
| `attempting free on address which was not malloc()-ed` | Caller `free()`d an arena/pool pointer | Header docs: arena pointers are borrowed; only `arena_destroy` frees |
| `SIGBUS`/`alignment` UBSan report on arena object | `arena_alloc` called with `align = 1` for a typed object | `ARENA_NEW` macros so `alignof(T)` is automatic |
| `aligned_alloc` returns NULL for a "valid" call | `size` not a multiple of `align` on a strict implementation | Round size up; or `posix_memalign`/`_aligned_malloc` per platform |
| Pool hands out a pointer that crashes on use | Stale pointer wrote through `pool_free`d object, corrupting the free list | Debug pattern fill + validate `next` range on alloc |
| Leak report on every arena allocation site | `arena_destroy` missing on one exit path | Arena teardown belongs in the `goto cleanup` block — one line, all paths |

