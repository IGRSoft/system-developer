# Atomics and the C++ Memory Model

Use this when:

- You are writing or reviewing code that uses `std::atomic` directly.
- You need to choose (or justify) a `memory_order`.
- You want `atomic::wait`/`notify` or `jthread`/`stop_token` recipes.
- You are evaluating a lock-free design, or fixing false sharing.

Skip this file if:

- A mutex works. It almost always does — start at [../SKILL.md](../SKILL.md) Tool Selection.
- Your problem is coroutines. Use [coroutines.md](coroutines.md).

Jump to:

- Ground Rules
- The Vocabulary: Happens-Before in Five Minutes
- Memory Orders
- The seq_cst Default Policy
- volatile Is Not Atomic
- atomic<T> Mechanics
- Compare-and-Swap Recipes
- atomic wait/notify Recipes (C++20)
- jthread and stop_token Recipes (C++20)
- Lock-Free Caveats
- False Sharing and hardware_destructive_interference_size
- Fences
- Pattern-to-Order Quick Reference

## Ground Rules

1. **A data race is undefined behavior, not a wrong value.** If two threads access the same memory location without synchronization and at least one access writes, the program has no defined meaning — the compiler may assume it cannot happen and optimize accordingly. "It only reads a slightly stale value" is folklore, not the model.
2. **Synchronization is about *happens-before*.** A mutex unlock happens-before the next lock of the same mutex; a release store happens-before an acquire load that reads it. Everything written before the release side is visible after the acquire side. All reasoning about atomics reduces to building these edges.
3. **Atomics are a scalpel; mutexes are the default.** Reach for `std::atomic` when exactly one word of state is shared (flag, counter, pointer to immutable data) or when a profiler shows a specific lock is hot. Multi-field invariants need a mutex — two atomics do not update together.
4. **Verification is TSan**, not inspection. Every claim in code review about ordering should survive `-fsanitize=thread` on the test suite, on both an x86 and an ARM runner if you ship to both — x86's strong hardware ordering hides acquire/release mistakes that ARM exposes.

## The Vocabulary: Happens-Before in Five Minutes

Five terms cover essentially all memory-model reasoning you will do in review:

- **Sequenced-before**: ordinary single-thread program order. Within one thread, `a = 1;` is sequenced before `b = 2;`. The compiler and CPU may still *execute* them in any order — sequencing constrains observable behavior of that thread, not the instruction stream.
- **Synchronizes-with**: the cross-thread edge. A release operation synchronizes-with an acquire operation that reads the value it wrote (same atomic object). Mutex unlock→lock, `thread::join`, `latch::wait` returning, promise/future, and starting a thread all create the same kind of edge.
- **Happens-before**: the transitive closure of sequenced-before and synchronizes-with. If write W happens-before read R, R sees W (or something later in the modification order). If neither access happens-before the other and one is a non-atomic write — that is the data race, and the program's behavior is undefined.
- **Modification order**: every individual atomic object has a single total order of all writes to it, seen consistently by all threads. Even `relaxed` operations respect it — two threads never disagree about the order of writes *to one atomic*. What relaxed forfeits is any relationship to operations on *other* memory.
- **Coherence**: the family of rules saying reads of one atomic don't go backwards in its modification order. This is why a relaxed counter is safe to increment from anywhere: the counts can't be lost, only observed "early" relative to other state.

Worked example — why the publish pattern needs both halves:

```cpp
// thread P                                  // thread C
data = 42;               // (1) non-atomic   if (flag.load(acquire)) {   // (3)
flag.store(true, release); // (2)                use(data);              // (4)
                                             }
```

(1) is sequenced-before (2); (2) synchronizes-with (3) *if* (3) reads `true`; (3) is sequenced-before (4). Transitively (1) happens-before (4): the read of `data` is ordered and sees 42. Downgrade (2) to `relaxed` and the chain snaps at the middle link — now (1) and (4) are unordered, which makes them a data race on `data`, which makes the program undefined. Not "data might be stale": undefined.

The review heuristic that falls out: for every non-atomic object touched by two threads, you must be able to name the happens-before chain. If the answer is a shrug, it's a race regardless of how long it has run in production.

## Memory Orders

Every atomic operation takes a `std::memory_order`. The default for all operations is `memory_order_seq_cst`.

| Order | Guarantees | Legitimate use |
|-------|-----------|----------------|
| `seq_cst` | acquire+release plus a single global order over *all* seq_cst ops | **default**; required when reasoning spans multiple atomics |
| `acquire` (loads) | reads-from edge: everything before the matching release is visible | consume side of publish pattern |
| `release` (stores) | everything before this store is visible to the acquiring reader | publish side of publish pattern |
| `acq_rel` (RMW) | both, for read-modify-write ops | CAS loops, refcount upgrades that publish |
| `relaxed` | atomicity only — **no ordering at all** | counters read after a join/synchronization point; sequence numbers |
| `consume` | dependency ordering | **do not use** — specified, never usefully implemented; compilers promote it to `acquire` |

### The publish pattern (release/acquire)

The one non-default pattern worth knowing cold:

```cpp
// producer
auto* cfg = new Config{load_config()};       // (A) build the object
config.store(cfg, std::memory_order_release); // (B) publish

// consumer
if (auto* c = config.load(std::memory_order_acquire)) {  // reads (B)
    use(*c);   // guaranteed to see all of (A)
}
```

The acquire load that observes the released value creates the happens-before edge; without it the consumer may see the pointer but stale object contents (on weakly ordered hardware — i.e., your ARM deployment, not your x86 dev box).

### Where acquire/release is NOT enough

If correctness depends on the relative order of operations on **two different atomics**, you need `seq_cst`. Classic store/load (Dekker-style) example:

```cpp
// thread 1                          // thread 2
x.store(1);                          y.store(1);
if (y.load() == 0) enter_critical(); if (x.load() == 0) enter_critical();
```

With `seq_cst` (the defaults), both threads entering is impossible. Rewrite those with release/acquire and *both* threads can read 0 — store-load reordering is exactly what release/acquire does not forbid. This is the standard postmortem behind "we relaxed the orders and it failed only on ARM, weekly."

### Relaxed: atomicity without ordering

```cpp
// hot path: count, don't synchronize
allocs.fetch_add(1, std::memory_order_relaxed);

// report AFTER worker threads have been joined — the join supplies the
// happens-before edge, so relaxed counts are complete and stable here
std::println("allocations: {}", allocs.load(std::memory_order_relaxed));
```

Relaxed is correct only when some *other* mechanism (thread join, mutex, latch arrival) orders the reads against the writes, or when no read depends on cross-thread ordering at all. Relaxed flags that gate access to non-atomic data are bugs, full stop.

## The seq_cst Default Policy

House rule (same as [../SKILL.md](../SKILL.md)): **write atomics with the default order.** Weaken only when all four hold:

1. A profile shows the atomic op itself in a hot path (on the weakly ordered target — seq_cst loads are nearly free on x86; the cost question is ARM).
2. The pattern is one of the cataloged ones above (publish, counter, CAS loop) — not novel ordering reasoning.
3. The order is written explicitly at every site (never rely on someone reading defaults).
4. A comment states the pattern and the evidence:

```cpp
// release/acquire publish pair with `table_` consumers (perf: issue #882,
// 11% of frame time was this seq_cst store on the arm64 build)
head_.store(node, std::memory_order_release);
```

A reviewer who cannot match a weakened order to a cataloged pattern should request seq_cst back. That is not pedantry; it is the cheapest of all available insurance.

## volatile Is Not Atomic

`volatile` tells the compiler each access is observable (it cannot cache or elide it). That is all. It provides:

- **no atomicity** — a `volatile uint64_t` write can tear on 32-bit targets;
- **no ordering** — the CPU reorders volatile accesses against everything else;
- **no visibility guarantee** — no happens-before edge, so a data race on a volatile is still UB.

```cpp
volatile bool stop = false;        // BUG: data race, may never be observed
std::atomic<bool> stop{false};     // correct, and the load is just as cheap
```

`volatile` remains correct for memory-mapped I/O registers and `sig_atomic_t` signal flags — hardware and signal contexts, not inter-thread communication. Any `volatile` used for threading predates C++11 or misremembers Java; replace it with `std::atomic`.

## atomic<T> Mechanics

- `T` must be trivially copyable (plus copy/move-constructibility requirements). `std::atomic<std::string>` does not compile; `std::atomic<MySmallPod>` does, but may be implemented with a hidden lock.
- **Check lock-freedom when it matters**: `std::atomic<T>::is_always_lock_free` (compile-time, C++17). A non-lock-free atomic is correct but is a mutex in a trench coat — unsuitable for signal handlers and for the "lock-free" box on your design doc.

```cpp
static_assert(std::atomic<Header>::is_always_lock_free,
              "Header grew past the lock-free width for this target");
```

- `std::atomic<double>` supports `fetch_add`/`fetch_sub` since C++20 (before that: CAS loop).
- `std::atomic<std::shared_ptr<T>>` (C++20) replaces the deprecated free-function `atomic_load(&sp)` API; it is typically **not** lock-free — fine for low-frequency config swaps, wrong for hot paths.
- `std::atomic_ref<T>` (C++20) applies atomic operations to a normal object — useful for parallel loops over arrays you cannot redeclare as atomic. The object must be sufficiently aligned (`std::atomic_ref<T>::required_alignment`), and **all** concurrent accesses during the contended window must go through `atomic_ref` — one plain access reintroduces the race.
- Struct padding historically caused spurious CAS failures (padding bits compare unequal). C++20 (P0528) fixed `compare_exchange` to ignore padding; on mixed/older toolchains, prefer atomics over padding-free types — verify against your toolchain.

### atomic_flag

`std::atomic_flag` is the only type guaranteed lock-free on every implementation. C++20 made it usable: `test()` (read without modifying — missing before C++20), plus `wait`/`notify_one`/`notify_all`.

```cpp
class SpinLock {                          // for ~10-instruction critical sections ONLY
    std::atomic_flag locked_ = ATOMIC_FLAG_INIT;
public:
    void lock() {
        while (locked_.test_and_set(std::memory_order_acquire))
            locked_.wait(true, std::memory_order_relaxed);   // C++20: sleep, don't burn
    }
    void unlock() {
        locked_.clear(std::memory_order_release);
        locked_.notify_one();
    }
};
```

The acquire/release pair here *is* one of the cataloged patterns (a lock is the publish pattern wearing a hat). That said: a userspace spinlock loses to `std::mutex` the moment a holder is preempted, and mainstream `std::mutex` implementations already spin briefly before sleeping. Treat hand-rolled spinlocks as a benchmark-justified exception, not a default — and the C++20 `wait` in the loop above is what keeps the failure mode bounded.

## Compare-and-Swap Recipes

The canonical read-modify-write loop:

```cpp
// atomically: maximum = max(maximum, sample)
uint64_t cur = maximum.load(std::memory_order_relaxed);
while (sample > cur &&
       !maximum.compare_exchange_weak(cur, sample))
    ;   // on failure, `cur` was reloaded with the current value
```

- **`compare_exchange_weak` inside loops, `_strong` for single attempts.** Weak may fail spuriously (no ABA, value actually equal) but maps to cheaper instructions on LL/SC architectures (ARM); since a CAS loop retries anyway, weak costs nothing there.
- The failure path *updates the expected value in place* — that is why `cur` needs no reload in the loop. Forgetting this and re-loading manually is harmless; re-using a stale `expected` without reload livelocks.
- Both success and failure orders can be specified; the two-order form matters only after you've justified leaving seq_cst (see policy above).

### Recipe: one-time lazy publication

Initialize-once-and-publish without a lock, tolerating the duplicate-work race:

```cpp
std::atomic<const Table*> table{nullptr};

const Table& get_table() {
    if (const Table* t = table.load(std::memory_order_acquire)) return *t;
    auto* fresh = new Table{build_table()};          // possibly built by several threads
    const Table* expected = nullptr;
    if (!table.compare_exchange_strong(expected, fresh,
                                       std::memory_order_release,
                                       std::memory_order_acquire)) {
        delete fresh;                                // lost the race; use the winner's
        return *expected;
    }
    return *fresh;
}
```

`_strong` because this is a single attempt, not a loop; the failure order is `acquire` because the loser must see the winner's fully built table. For function-local singletons, prefer the zero-code option: C++ guarantees thread-safe initialization of `static` locals (`static const Table t = build_table();`) — use the CAS form only for non-static lifetimes or when build-twice is acceptable and lock-free init is genuinely required.

### Recipe: atomic bitmask updates

```cpp
std::atomic<uint32_t> flags{0};
flags.fetch_or(kDirty);                  // set a bit — RMW, no CAS loop needed
flags.fetch_and(~kDirty);                // clear a bit
bool was_set = flags.fetch_or(kClosing) & kClosing;   // set-and-test in one op
```

`fetch_or`/`fetch_and`/`fetch_xor` cover most flag work without a CAS loop. A CAS loop is needed only when the new value is a non-monotonic function of the old (e.g., "set bit A only if bit B is clear").

### ABA

CAS compares *values*, not histories. Pointer-based structures can see A→B→A: the CAS succeeds although the node was freed and reallocated in between — a use-after-free with a green checkmark. Mitigations: tagged pointers (pointer + generation counter widened into one CAS-able value), or deferred reclamation (below):

```cpp
struct alignas(16) Head { Node* node; uint64_t version; };   // bump version on every pop
std::atomic<Head> head;   // 16-byte CAS: lock-free on x86_64 with cmpxchg16b and on
                          // arm64 — but check is_always_lock_free; some targets fall
                          // back to a lock, and some compilers require an -mcx16 flag.
                          // Verify against your toolchain.
```

If this subsection is news, the honest mitigation is a mutex.

## atomic wait/notify Recipes (C++20)

`std::atomic<T>::wait(old)` blocks while the value equals `old`; `notify_one`/`notify_all` wake waiters. It is futex-shaped: cheaper than a `condition_variable` (no mutex, no lost-wakeup protocol) whenever the condition is "this one value changed".

### Gate (one-shot event)

```cpp
std::atomic<bool> ready{false};

// waiters
ready.wait(false);            // returns once value != false

// publisher
ready.store(true);            // change value FIRST
ready.notify_all();           // THEN notify
```

Store-then-notify order is the whole protocol: a notify with an unchanged value wakes nobody durably (waiters recheck and sleep again), and a changed value without notify leaves sleepers sleeping until a spurious wake. Both halves, always, in that order.

### Bounded wait loop with a predicate beyond inequality

`wait` only watches *this value vs old*. For a richer predicate, loop:

```cpp
std::atomic<int> state{0};
int s = state.load();
while (!is_acceptable(s)) {
    state.wait(s);            // sleep while state == s
    s = state.load();         // re-evaluate on every change
}
```

### Turnstile: waking a generation of waiters

A reusable "everyone past this point waits for the next tick" — useful for frame loops and batch pipelines:

```cpp
std::atomic<uint64_t> epoch{0};

// waiters: sleep until the epoch advances past what they last saw
void wait_next_tick(uint64_t& seen) {
    epoch.wait(seen);                 // sleeps while epoch == seen
    seen = epoch.load();
}

// ticker
void tick() {
    epoch.fetch_add(1);
    epoch.notify_all();
}
```

A monotonic counter dodges the gate-reset race that a reusable `bool` gate has (a waiter arriving between `store(false)` and the next `store(true)` can miss a whole cycle). For N-party rendezvous with a completion step, `std::barrier` already is this pattern — prefer it; the atomic version earns its keep when waiters come and go dynamically.

### Hybrid spin-then-wait

For sub-microsecond producer latencies, a bounded spin before sleeping cuts wake latency without burning a core forever:

```cpp
int spins = 0;
int s = state.load(std::memory_order_relaxed);
while (!is_acceptable(s)) {
    if (++spins < 64) {                       // bound chosen by measurement, not vibes
        std::this_thread::yield();
    } else {
        state.wait(s);                        // park in the kernel
        spins = 0;
    }
    s = state.load(std::memory_order_relaxed);
}
```

Measure before adopting: on contended systems the spin phase is pure waste, and quality `atomic::wait` implementations already spin briefly before parking — a second spin layer on top can be strictly worse. Verify the behavior of your standard library against your toolchain.

### When to still use condition_variable

| Situation | Use |
|-----------|-----|
| condition is one atomic value changing | `atomic::wait`/`notify` |
| condition spans several variables / a queue's contents | `condition_variable` + mutex + predicate |
| need timed waits | `condition_variable::wait_for` (atomic `wait` has no timeout until C++26-era additions — verify against your toolchain) |
| need cancellation interop | `condition_variable_any` + `stop_token` (below) |

C++17 fallback for all of the above: `condition_variable` + mutex; or spin-then-yield for very short waits (measure before believing in spinning).

## jthread and stop_token Recipes (C++20)

### Baseline worker

```cpp
std::jthread worker([](std::stop_token st) {
    while (!st.stop_requested()) {
        if (auto item = queue.pop_with_timeout(100ms)) handle(*item);
    }
});
// ~jthread => request_stop() + join(): shutdown is the default, not an afterthought
```

### Interruptible blocking wait

`condition_variable_any` (not plain `condition_variable`) gained stop_token-aware overloads:

```cpp
std::mutex m;
std::condition_variable_any cv;
std::deque<Job> jobs;

std::jthread consumer([&](std::stop_token st) {
    std::unique_lock lock{m};
    while (cv.wait(lock, st, [&] { return !jobs.empty(); })) {
        auto job = std::move(jobs.front());
        jobs.pop_front();
        lock.unlock(); run(job); lock.lock();
    }
    // wait returned false => stop requested while predicate false: clean exit
});
```

`request_stop()` wakes the wait — no sentinel jobs, no `notify_all` shutdown choreography.

### Unblocking what stop_token can't reach

Blocking syscalls don't observe tokens. Register a `stop_callback` that forcibly unblocks them; the callback runs on the `request_stop()` caller's thread (or immediately, if stop was already requested — write it to be safe in both cases):

```cpp
std::jthread reader([fd](std::stop_token st) {
    std::stop_callback unblock{st, [fd] { ::shutdown(fd, SHUT_RDWR); }};
    char buf[4096];
    while (!st.stop_requested()) {
        ssize_t n = ::recv(fd, buf, sizeof buf, 0);
        if (n <= 0) break;            // shutdown() forces recv to return
        consume(buf, n);
    }
});
```

### Periodic worker with prompt shutdown

The naive periodic loop (`sleep_for(30s)` then work) takes up to a full period to notice shutdown. The stop-token-aware timed wait fixes that:

```cpp
std::jthread heartbeat([&](std::stop_token st) {
    std::mutex m;
    std::condition_variable_any cv;
    std::unique_lock lock{m};
    while (!st.stop_requested()) {
        send_heartbeat();
        // sleeps 30s OR wakes immediately on request_stop()
        cv.wait_for(lock, st, 30s, [] { return false; });
    }
});
```

The always-false predicate makes `wait_for` a pure interruptible sleep. This shape — work, interruptible sleep, check token — is the canonical periodic task; destruction of the `jthread` ends it within milliseconds, not within one period.

### Sharing one stop signal

`std::stop_source` fans out one cancellation to many components:

```cpp
std::stop_source shutdown;
spawn_pipeline(shutdown.get_token());     // every stage gets the same token
spawn_metrics(shutdown.get_token());
shutdown.request_stop();                  // one call stops everything
```

Pass `stop_token` by value (it is a cheap shared handle). A `jthread`'s own token is reachable via `get_stop_token()`; you can also hand the thread an external token explicitly and ignore the built-in one — pick one scheme per subsystem, not both.

## Lock-Free Caveats

Before building lock-free structures, internalize what the label buys:

- **"Lock-free" is a progress guarantee, not a speed guarantee.** It promises some thread completes in bounded steps (no deadlock/priority-inversion via a preempted lock holder). Under typical contention, a well-fitted `std::mutex` (which spins briefly before sleeping in mainstream implementations) frequently *outperforms* a CAS-retry storm — every failed CAS is wasted work plus a cache-line ping.
- **The hard problem is memory reclamation, not the fast path.** Popping a node another thread may still be dereferencing means you cannot `delete` it yet. Through C++23 the standard offers no reclamation primitive; the C++26 cycle standardized hazard pointers and RCU — verify availability against your toolchain before depending on them. Until then: a vetted library (e.g., a maintained concurrent-queue implementation), epoch schemes you did not write yourself, or the design that sidesteps reclamation entirely (fixed slots, indices instead of pointers).
- **Decision ladder**: mutex → sharded mutexes / `shared_mutex` → a proven concurrent library type → bespoke lock-free (with a TSan+stress+ARM test budget to match). Each step needs profiler evidence that the previous one is the bottleneck.
- If you do go bespoke: every weakened order documented per the policy above; stress tests that oversubscribe cores; runs on a weakly ordered target. An x86-only-tested lock-free structure is untested.

## False Sharing and hardware_destructive_interference_size

Two threads writing *different* variables that share a cache line serialize on the coherence protocol — no data race, no TSan report, just a profiler showing cores stalled on memory. Classic shape: an array of per-thread counters.

```cpp
// BAD: 8 counters share one or two 64-byte lines; scaling collapses
std::atomic<uint64_t> counters[8];

// GOOD: one line per counter
struct alignas(std::hardware_destructive_interference_size) PaddedCounter {
    std::atomic<uint64_t> value{0};
};
PaddedCounter counters[8];
```

`std::hardware_destructive_interference_size` (`<new>`, C++17) is the portable spelling of "cache line size for avoiding false sharing"; its sibling `hardware_constructive_interference_size` is the keep-together hint. Practical notes:

- Mainstream values: 64 on common x86_64, 128 on several ARM designs (including Apple silicon's performance cores) — verify against your toolchain and target rather than hardcoding folklore.
- Library support lagged the paper standard; GCC's libstdc++ ships it (GCC 12-era) and warns (`-Winterference-size`) when it is used in ways that leak into ABI, because the value can change with `-mtune`. Heed the warning: keep the constant out of public headers and serialized layouts; a project-local `constexpr std::size_t kCacheLine = 64;` (or 128) is the right call for ABI-stable interfaces.
- Diagnose before padding: `perf c2c` on Linux attributes cache-line contention to source lines; padding speculatively bloats memory for no measured gain. See [profiling-tools](../../../tooling/diagnostics/references/profiling-tools.md).
- Independent per-thread state is better restructured (thread-local accumulation, merged after join) than padded — the fastest shared cache line is the one that doesn't exist.

## Fences

`std::atomic_thread_fence(order)` imposes ordering without an atomic operation at the fence itself. Two facts suffice for almost everyone:

1. You can pair a relaxed store + release fence (and acquire fence + relaxed load) to batch ordering over several relaxed ops — an optimization for ordering-heavy hot loops.
2. Fences are strictly harder to review than per-operation orders, and TSan historically models them less precisely than operation orders — verify against your toolchain. Prefer per-operation `release`/`acquire`; reach for fences only with a profile that indicts the per-op version.

`std::atomic_signal_fence` orders compiler reordering only (same thread vs its signal handler) — unrelated to threads.

## Pattern-to-Order Quick Reference

| Pattern | Recipe |
|---------|--------|
| stop flag | `std::atomic<bool>`, defaults — or better, `stop_token` |
| statistics counter | `fetch_add(1, relaxed)`; read after join/latch |
| publish object via pointer | `store(p, release)` / `load(acquire)`; null-check the load |
| one-shot event, waiters | `atomic<bool>` + `wait/notify_all` (C++20); `latch` for N-party |
| max/min accumulation | `compare_exchange_weak` loop, defaults first |
| refcount | `fetch_add(relaxed)` on copy; `fetch_sub(acq_rel)` + delete on zero |
| flags spanning two atomics | stay `seq_cst` — this is the Dekker trap |
| anything with multi-field invariants | `std::mutex` — atomics are the wrong tool |

When in doubt: defaults (`seq_cst`), a mutex, and a TSan run beat a clever ordering argument every time. The memory model rewards the boring choice.
