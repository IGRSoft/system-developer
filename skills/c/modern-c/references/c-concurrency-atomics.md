# C Concurrency: <threads.h>, _Atomic, Memory Orders

Use this when:

- You are writing or reviewing multithreaded C using C11/C17 `<threads.h>` or `<stdatomic.h>`.
- You need to choose a memory order, or to justify one in review.
- You are deciding between ISO C threads and pthreads.

Skip this file if:

- You need C23 language features. Use [c23-features.md](c23-features.md).
- You are debugging a specific data race. Run TSan first via `${CLAUDE_SKILL_DIR}/tooling/diagnostics/SKILL.md`, then return here for the fix pattern.

Jump to:

- API Choice: ISO C Threads vs pthreads vs Atomics-Only
- Availability Matrix
- <threads.h> Essentials
- _Atomic Essentials
- Memory Orders
- Canonical Patterns
- Thread-Local Storage
- When pthreads Instead
- Verification with TSan
- Pitfalls

## API Choice: ISO C Threads vs pthreads vs Atomics-Only

| Situation | Use |
|-----------|-----|
| Shared counter, flag, or pointer publish | `_Atomic` only — no thread API dependency at all |
| Portable-in-principle worker threads, simple mutex/condvar | `<threads.h>` (check availability matrix first) |
| Anything on macOS, or needing rwlocks, barriers, attributes, cancellation | pthreads |
| Library code that must build everywhere | pthreads behind a thin internal shim, or C11 atomics + no thread creation |

`<stdatomic.h>` and `<threads.h>` are independent: atomics are far more
portable than the thread API and are the part of C11 concurrency you should
reach for first.

## Availability Matrix

| Platform / toolchain | `<stdatomic.h>` | `<threads.h>` |
|----------------------|-----------------|---------------|
| Linux + glibc | Yes | glibc 2.28+ |
| Linux + musl | Yes | Yes (1.1.5+) |
| FreeBSD / NetBSD | Yes | Yes |
| macOS | Yes | Historically absent from the SDK — verify against your SDK; assume pthreads on Apple platforms |
| MSVC | Partial (`/experimental:c11atomics` history — verify) | VS 2022 17.8+ (verify) |

Feature-test macros (test in this order, at compile time):

```c
#if defined(__STDC_NO_ATOMICS__)
#  error "C11 atomics required"
#endif
#if defined(__STDC_NO_THREADS__) || defined(__APPLE__)
#  include <pthread.h>   /* fallback path */
#else
#  include <threads.h>
#endif
```

## <threads.h> Essentials

### Thread Lifecycle

```c
#include <threads.h>

static int worker(void *arg) {            // note: int return, not void *
    struct job *j = arg;
    process(j);
    return 0;                             // retrieved by thrd_join
}

int run(struct job *j) {
    thrd_t t;
    if (thrd_create(&t, worker, j) != thrd_success) return -1;
    int rc;
    if (thrd_join(t, &rc) != thrd_success) return -1;
    return rc;
}
```

Return codes: `thrd_success`, `thrd_nomem`, `thrd_timedout`, `thrd_busy`,
`thrd_error`. **Check every one** — `thrd_create` fails under resource
pressure exactly when you least expect it.

Other lifecycle calls: `thrd_detach(t)` (then never join), `thrd_current()`,
`thrd_equal(a, b)`, `thrd_yield()`, `thrd_exit(rc)`,
`thrd_sleep(&(struct timespec){.tv_sec = 1}, NULL)`.

### Mutexes

```c
static mtx_t lock;

int init(void) {
    return mtx_init(&lock, mtx_plain) == thrd_success ? 0 : -1;
}

void critical(void) {
    mtx_lock(&lock);
    /* ... */
    mtx_unlock(&lock);
}
```

| Type flag | Meaning |
|-----------|---------|
| `mtx_plain` | Default; relocking from same thread is UB |
| `mtx_recursive` | Same thread may relock; usually a design smell |
| `mtx_timed` | Enables `mtx_timedlock` (combine: `mtx_timed \| mtx_recursive`) |

There is **no static initializer** (no `PTHREAD_MUTEX_INITIALIZER`
equivalent) — call `mtx_init` exactly once, e.g. via `call_once`:

```c
static once_flag once = ONCE_FLAG_INIT;
static void init_lock(void) { mtx_init(&lock, mtx_plain); }
void critical(void) {
    call_once(&once, init_lock);
    mtx_lock(&lock);
    /* ... */
    mtx_unlock(&lock);
}
```

### Condition Variables

Always wait in a predicate loop — spurious wakeups are allowed:

```c
static cnd_t cond;     // cnd_init(&cond)
static mtx_t lock;
static bool ready;

void waiter(void) {
    mtx_lock(&lock);
    while (!ready)                      // loop, never `if`
        cnd_wait(&cond, &lock);         // unlocks while waiting, relocks after
    consume();
    mtx_unlock(&lock);
}

void producer(void) {
    mtx_lock(&lock);
    ready = true;
    mtx_unlock(&lock);
    cnd_signal(&cond);                  // cnd_broadcast for multiple waiters
}
```

`cnd_timedwait` takes an **absolute** `TIME_UTC` timespec
(`timespec_get(&ts, TIME_UTC)` then add the timeout). There is no monotonic
clock option — a system clock jump skews your timeout. If that matters, use
pthreads with `pthread_condattr_setclock(CLOCK_MONOTONIC)`.

```c
// Helper: absolute deadline N milliseconds from now (TIME_UTC)
static struct timespec deadline_ms(long ms) {
    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    ts.tv_sec  += ms / 1000;
    ts.tv_nsec += (ms % 1000) * 1000000L;
    if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
    return ts;
}

// In the wait loop: check the return code, keep checking the predicate
struct timespec dl = deadline_ms(250);
while (!ready) {
    if (cnd_timedwait(&cond, &lock, &dl) == thrd_timedout)
        break;                          // predicate may STILL be false here
}
```

## _Atomic Essentials

```c
#include <stdatomic.h>

_Atomic int counter = 0;            // direct init (ATOMIC_VAR_INIT is gone in C23)
atomic_size_t bytes;                // convenience typedefs exist for all std types

void on_event(void) {
    atomic_fetch_add_explicit(&counter, 1, memory_order_relaxed);
}

int read_counter(void) {
    return atomic_load_explicit(&counter, memory_order_relaxed);
}
```

Rules of engagement:

- Plain reads/writes of an `_Atomic` object (`counter++`, `x = counter`) are
  atomic with `memory_order_seq_cst` — correct, but hides the ordering
  decision. Prefer `_explicit` calls in reviewed code so the order is visible.
- `_Atomic` is part of the type. Mixing atomic and non-atomic access to the
  same object is UB. There is no blessed "atomic view" of a plain variable.
- `volatile` is **not** atomic and provides **no** ordering. It is for MMIO,
  not threads.
- Whole-struct `_Atomic` works (`_Atomic struct pair p;`) but compiles to a
  lock if not lock-free — check `atomic_is_lock_free(&p)`; prefer packing
  into a `uint64_t` instead.

`atomic_flag` is the only type guaranteed lock-free on all implementations:

```c
static atomic_flag spin = ATOMIC_FLAG_INIT;

void lock(void)   { while (atomic_flag_test_and_set_explicit(&spin, memory_order_acquire)) thrd_yield(); }
void unlock(void) { atomic_flag_clear_explicit(&spin, memory_order_release); }
```

(Spinlocks are almost always worse than a mutex outside very short, very hot
critical sections — measure before keeping one.)

For everything else, query: `atomic_is_lock_free(&obj)` at runtime or the
`ATOMIC_INT_LOCK_FREE` / `ATOMIC_LONG_LOCK_FREE` / `ATOMIC_POINTER_LOCK_FREE`
macros (2 = always lock-free).

## Memory Orders

| Order | Guarantees | Use for |
|-------|------------|---------|
| `memory_order_relaxed` | Atomicity only; no ordering | Counters, stats, stop-flags where no other data is published |
| `memory_order_acquire` | Loads after this load stay after | The read side of publish/consume |
| `memory_order_release` | Stores before this store stay before | The write side of publish/consume |
| `memory_order_acq_rel` | Both, for read-modify-write ops | CAS/fetch ops that both consume and publish |
| `memory_order_seq_cst` | Acq-rel + single global order of all seq_cst ops | Default; anything involving 2+ atomic variables whose relative order matters |
| `memory_order_consume` | In practice promoted to acquire by all compilers | Do not use; write `acquire` |

**Policy**: default to `seq_cst` (omit `_explicit` or spell it out). Downgrade
to acquire/release or relaxed only with a comment justifying it and a TSan-clean
run. The cost difference is zero on x86 for acquire/release vs plain loads and
small everywhere; the debugging cost of a wrong relaxed is enormous.

Fences exist (`atomic_thread_fence(memory_order_release)`) but ordering
attached to the atomic operations themselves is easier to review — prefer it.
`atomic_signal_fence` orders only against a signal handler on the same thread.

## Canonical Patterns

### Publish/Consume (the pattern behind almost everything)

```c
static _Atomic(struct config *) g_cfg = nullptr;   // C17: = NULL

void publish(struct config *fresh) {               // writer
    /* fully initialize *fresh BEFORE the store */
    atomic_store_explicit(&g_cfg, fresh, memory_order_release);
}

const struct config *snapshot(void) {              // readers
    return atomic_load_explicit(&g_cfg, memory_order_acquire);
}
```

Release store + acquire load = everything written before `publish` is
visible to a reader that sees the new pointer. With `relaxed` on either side
this is a real-world torn-config bug, not a theoretical one.

### CAS Loop

```c
bool try_reserve(_Atomic int *slots) {
    int cur = atomic_load_explicit(slots, memory_order_relaxed);
    do {
        if (cur == 0) return false;                 // none left
    } while (!atomic_compare_exchange_weak_explicit(
                 slots, &cur, cur - 1,
                 memory_order_acq_rel,              // success order
                 memory_order_relaxed));            // failure order (load only)
    return true;
}
```

- `weak` may fail spuriously — fine inside a loop, and faster on ARM.
- `strong` for single-shot attempts outside loops.
- On failure, `cur` is updated to the current value automatically — do not
  reload by hand.

### Reference Counting

```c
void retain(struct obj *o) {
    atomic_fetch_add_explicit(&o->refs, 1, memory_order_relaxed);  // relaxed OK:
}                                                                   // holder already owns a ref

void release(struct obj *o) {
    if (atomic_fetch_sub_explicit(&o->refs, 1, memory_order_release) == 1) {
        atomic_thread_fence(memory_order_acquire);   // pair with all prior releases
        obj_destroy(o);                              // safe: all writes visible
    }
}
```

This is the one textbook-legitimate fence use; `acq_rel` on the `fetch_sub`
is the simpler, slightly stronger alternative.

### Stop Flag

```c
static atomic_bool stop;

int worker(void *arg) {
    while (!atomic_load_explicit(&stop, memory_order_relaxed))
        do_chunk(arg);             // relaxed OK: no data published via the flag
    return 0;
}
void shutdown(void) { atomic_store_explicit(&stop, true, memory_order_relaxed); }
```

If the worker must also observe data written before the stop request, that is
publish/consume — upgrade to release/acquire.

### Bounded Queue / Worker Pool Skeleton

The mutex + two condvars shape that most C thread pools reduce to:

```c
struct queue {
    mtx_t lock; cnd_t not_empty; cnd_t not_full;
    struct job *items[QCAP];
    size_t head, tail, count;
    bool closed;
};

bool queue_push(struct queue *q, struct job *j) {
    mtx_lock(&q->lock);
    while (q->count == QCAP && !q->closed) cnd_wait(&q->not_full, &q->lock);
    if (q->closed) { mtx_unlock(&q->lock); return false; }
    q->items[q->tail] = j; q->tail = (q->tail + 1) % QCAP; q->count++;
    mtx_unlock(&q->lock);
    cnd_signal(&q->not_empty);
    return true;
}

struct job *queue_pop(struct queue *q) {        // NULL = closed and drained
    mtx_lock(&q->lock);
    while (q->count == 0 && !q->closed) cnd_wait(&q->not_empty, &q->lock);
    struct job *j = NULL;
    if (q->count > 0) {
        j = q->items[q->head]; q->head = (q->head + 1) % QCAP; q->count--;
    }
    mtx_unlock(&q->lock);
    cnd_signal(&q->not_full);
    return j;
}

void queue_close(struct queue *q) {             // wake everyone for shutdown
    mtx_lock(&q->lock);
    q->closed = true;
    mtx_unlock(&q->lock);
    cnd_broadcast(&q->not_empty);
    cnd_broadcast(&q->not_full);
}
```

Ownership rule: a job pointer belongs to exactly one side at a time — the
producer until `queue_push` returns true, the consumer after `queue_pop`
returns it. See [../../c-memory-ownership/SKILL.md](../../c-memory-ownership/SKILL.md).

### Avoiding False Sharing

Two atomics on the same cache line serialize unrelated threads. Pad hot
per-thread counters to a cache line:

```c
struct stats_slot {
    alignas(64) _Atomic uint64_t events;   // one 64-byte line per slot
};
static struct stats_slot per_thread[MAX_THREADS];
```

C17 has `alignas` via `<stdalign.h>`; C23 makes it a keyword. Symptom of
false sharing: throughput *drops* as threads are added while a profiler shows
time in "atomic" instructions — confirm with `perf c2c` on Linux.

## Thread-Local Storage

```c
thread_local int t_depth;                  // C23 keyword
// C11/C17: _Thread_local, or the thread_local macro from <threads.h>
```

| Mechanism | Destructor on thread exit | Dynamic key | Notes |
|-----------|---------------------------|-------------|-------|
| `_Thread_local` / `thread_local` | No | No | Zero-cost access; must be static storage duration; cannot be combined with dynamic lifetime |
| `tss_create` / `tss_set` / `tss_get` | Yes (`TSS_DTOR_ITERATIONS` passes) | Yes | `<threads.h>` only; for per-thread heap objects needing cleanup |
| `pthread_key_create` | Yes | Yes | pthreads equivalent, everywhere pthreads is |

Use `thread_local` for plain per-thread scalars/buffers; use tss/pthread keys
only when a destructor must run (e.g., per-thread caches that own memory).

## When pthreads Instead

| Need | ISO C threads | pthreads |
|------|---------------|----------|
| Runs on macOS without a shim | No (`<threads.h>` absent — verify SDK) | Yes |
| Read-write locks | None | `pthread_rwlock_t` |
| Barriers | None | `pthread_barrier_t` |
| Stack size / scheduling attributes | None | `pthread_attr_*` |
| Monotonic-clock timed condvar waits | No (`TIME_UTC` only) | `pthread_condattr_setclock(CLOCK_MONOTONIC)` |
| Static mutex initializer | No (`call_once` dance) | `PTHREAD_MUTEX_INITIALIZER` |
| Cancellation, `pthread_atfork`, process-shared objects | None | Yes |
| Thread names for debuggers | None | `pthread_setname_np` (nonportable suffix; both glibc and BSD variants exist) |
| Semantics | Thin subset, same model | Superset; C11 threads are specified to be implementable on pthreads |

Practical rule: applications targeting Linux-only may enjoy `<threads.h>`;
portable libraries and anything touching macOS use pthreads directly. The
atomics story is unaffected either way — `<stdatomic.h>` works with pthreads.

Mixing is legal (C11 threads are pthreads underneath on every Unix
implementation) but pick one API per module for join/detach sanity.

## Verification with TSan

```sh
# Dedicated build dir - TSan must not be combined with ASan
cc -std=c17 -g -O1 -fsanitize=thread -fno-omit-frame-pointer \
   -o app_tsan app.c -lpthread
TSAN_OPTIONS="halt_on_error=1 second_deadlock_stack=1" ./app_tsan
```

- TSan catches the race your code *exercised*, not all races: drive it with
  stress tests and repeat runs.
- Expect roughly 5-15x slowdown and 5-10x memory — CI job, not default build.
- TSan understands `<stdatomic.h>` and pthreads natively; a TSan report on an
  `_Atomic` access usually means a *paired* non-atomic access elsewhere.
- valgrind `--tool=helgrind` / `--tool=drd` are the no-rebuild fallback; far
  slower, more false positives around atomics.

Full sanitizer workflow: `${CLAUDE_SKILL_DIR}/tooling/diagnostics/SKILL.md`.

## Pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| Works on x86, crashes on ARM | Relaxed (or plain non-atomic) where release/acquire needed; x86's strong hardware ordering hid it | Publish/consume pattern; TSan on any platform finds it |
| `error: address argument to atomic operation must be a pointer to _Atomic type` | Atomic API called on plain object | Declare the object `_Atomic`; never cast around it |
| Deadlock in `cnd_wait` | Predicate checked with `if`, or signal sent before waiter locked | `while` loop + signal while/after holding the mutex |
| `mtx_init` UB / lock corrupt | Relying on zero-init or copying a `mtx_t` | `mtx_init` once via `call_once`; never memcpy mutexes |
| Counter updates lost | `x++` on plain shared int ("it's just an increment") | `_Atomic` fetch_add; plain `++` is load+add+store |
| Timed wait fires early/late after clock change | `cnd_timedwait` uses `TIME_UTC` realtime | pthreads + `CLOCK_MONOTONIC` condattr |
| `'threads.h' file not found` on macOS | Apple SDK does not ship it | pthreads (see matrix above) |
| TSan reports race on `_Atomic` variable | Mixed atomic and non-atomic access to same object | All accesses through atomic ops, including init-after-share |
| Struct atomic is mysteriously slow | Not lock-free; libatomic lock taken per op | `atomic_is_lock_free` check; pack into `uint64_t` or use a mutex honestly |
| `undefined reference to __atomic_*` at link | Target needs libatomic for that width | Link `-latomic` (common on RISC-V/older ARM) |

Cross-references: C23 keyword spellings and `ATOMIC_VAR_INIT` removal in
[c23-features.md](c23-features.md); ownership rules for data handed between
threads in [../../c-memory-ownership/SKILL.md](../../c-memory-ownership/SKILL.md);
TSan/helgrind workflow in `${CLAUDE_SKILL_DIR}/tooling/diagnostics/SKILL.md`.
