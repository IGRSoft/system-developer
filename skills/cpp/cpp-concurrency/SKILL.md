---
name: cpp-concurrency
description: >-
  C++ concurrency: jthread and stop_token, mutexes and scoped_lock, atomics
  and memory ordering, latch/barrier/semaphore, atomic wait/notify,
  coroutines and std::generator, parallel algorithms, and TSan-first
  verification. Use when writing or reviewing multithreaded C++ code,
  choosing a synchronization primitive, fixing a data race or deadlock,
  selecting a memory order, cancelling threads cleanly, or deciding how
  to use coroutines.
---

# C++ Concurrency

**jthread, locks, atomics, coroutines — and how to prove them race-free**

## When to Use

- Writing or reviewing any C++ code that spawns threads or shares state
- Choosing the right primitive: lock vs atomic vs latch vs semaphore
- Implementing cooperative cancellation
- Deciding whether (and how) to use coroutines
- Diagnosing data races, deadlocks, or lost wakeups

Standard availability: [cpp entry skill](../SKILL.md) standard-selection table. Deep dives: [references/coroutines.md](references/coroutines.md), [references/atomics-and-memory-model.md](references/atomics-and-memory-model.md).

## Tool Selection (start here)

| You need | Reach for | Min standard | Fallback |
|----------|-----------|--------------|----------|
| a thread | `std::jthread` — **always**, never `std::thread` | C++20 | `std::thread` + RAII join wrapper |
| protect shared data | `std::mutex` + `std::scoped_lock` | C++17 | — (baseline) |
| read-mostly shared data | `std::shared_mutex` + `shared_lock`/`scoped_lock` | C++17 | — (baseline) |
| one shared flag/counter/pointer | `std::atomic<T>` (default `seq_cst`) | C++17 baseline | — |
| one-time start gate / countdown | `std::latch` | C++20 | `condition_variable` + counter |
| repeated phase synchronization | `std::barrier` | C++20 | `condition_variable` + generation counter |
| bound concurrent access to a resource | `std::counting_semaphore` | C++20 | `condition_variable` + counter |
| block until a value changes | `std::atomic<T>::wait` / `notify_one`/`notify_all` | C++20 | `condition_variable` |
| wait for an arbitrary condition | `condition_variable` + predicate wait | baseline | — |
| cooperative cancellation | `std::stop_token` / `std::stop_callback` | C++20 | polled `std::atomic<bool>` |
| lazy sequence, no threads | `std::generator` | C++23 | handwritten iterator, range-v3 |
| data parallelism, no thread management | parallel algorithms (`std::execution::par`) | C++17 | chunked work across `jthread`s |
| async task graphs | vetted coroutine task library | C++20 machinery | thread pool + futures |

## Threads: jthread, Always

```cpp
std::jthread worker([](std::stop_token st) {
    while (!st.stop_requested()) { process_next(); }
});
// destructor: request_stop() then join(). No terminate, no leak.
```

- `std::thread` destroyed while joinable calls `std::terminate` — `jthread` auto-joins.
- `jthread` passes a `stop_token` as the first parameter if the callable accepts one.
- Never `detach()`. A detached thread that touches anything with a lifetime is a use-after-free waiting for load. If you think you need detach, you need an owned worker with shutdown.
- C++17 fallback: wrap `std::thread` in an RAII type that joins in its destructor, plus an `std::atomic<bool>` stop flag.

## Cancellation: stop_token and stop_callback

```cpp
std::jthread worker([](std::stop_token st) {
    std::mutex m;
    std::condition_variable_any cv;
    std::unique_lock lock{m};
    cv.wait(lock, st, [&] { return work_available(); });  // wakes on request_stop()
    if (st.stop_requested()) return;                       // clean exit
});
worker.request_stop();  // or let ~jthread do it
```

- Poll `st.stop_requested()` at loop boundaries; pass `st` into `condition_variable_any::wait` (C++20) so blocked waits wake on cancellation.
- For waits the token cannot reach (sockets, pipes), register a `std::stop_callback` that unblocks them: `std::stop_callback cb{st, [&] { ::shutdown(fd, SHUT_RDWR); }};`
- Cancellation is cooperative — there is no safe way to kill a thread. Design every loop and blocking call to observe the token.

## Locking Rules

```cpp
std::scoped_lock lock{accounts_mtx, audit_mtx};  // multiple mutexes, deadlock-free order
```

- `std::scoped_lock` (C++17) for everything: single mutex, or several acquired atomically with deadlock-avoidance. `lock_guard` is fine but `scoped_lock` subsumes it; `unique_lock` only where `condition_variable` requires it.
- Never lock two mutexes in different orders in different places — that is the ABBA deadlock. Either fix one global order or acquire both in one `scoped_lock`.
- Never hold a lock across a callback, virtual call, or `co_await` — you don't control what runs there.
- `condition_variable::wait` **only** with a predicate: `cv.wait(lock, [&]{ return ready; });`. The no-predicate form loses wakeups and wakes spuriously.
- Wanting `recursive_mutex` is a design smell: split the locked function into a locking public wrapper and an unlocked private implementation.

## Atomics: seq_cst by Default

- All `std::atomic` operations default to `memory_order_seq_cst`. **Keep the default.** It is correct in every pattern and rarely measurable as a bottleneck outside hot lock-free structures.
- Use `acquire`/`release` (or `relaxed` for pure counters) only with a measured reason, and document it at the call site:

```cpp
// relaxed: statistics counter, read only after threads join (#1742 perf trace)
hits.fetch_add(1, std::memory_order_relaxed);
```

- **`volatile` is not atomic.** It does not prevent data races, tearing, or reordering by the CPU; it only suppresses compiler caching. Any pre-C++11 `volatile bool stop_flag` is a bug — use `std::atomic<bool>`.
- An atomic protects exactly one object. Two atomics do not make a transaction; if two values must change together, use a mutex.
- Full memory-model treatment, CAS loops, and `atomic_ref`: [references/atomics-and-memory-model.md](references/atomics-and-memory-model.md).

## Coordination: latch, barrier, semaphore, atomic wait

```cpp
std::latch start{1};
std::vector<std::jthread> pool;
for (int i = 0; i < n; ++i)
    pool.emplace_back([&] { start.wait(); run(i); });  // all release together
start.count_down();
```

- `latch` = single-use countdown (start gates, init-complete). `barrier` = reusable phase sync with optional completion step. `counting_semaphore` = bound N concurrent users of a resource.
- `atomic<T>::wait(old)` / `notify_all()` (C++20) is the lightest "block until this value changes" tool — no mutex needed. Recipes in [references/atomics-and-memory-model.md](references/atomics-and-memory-model.md).
- All four are C++20. C++17 fallback for each is a `condition_variable` + counter under a mutex.

## Coroutines: Consume, Don't Build

- The C++20 coroutine machinery (`promise_type`, awaiters, `coroutine_handle`) is **library-author level**. Application code should consume coroutine types, not define them.
- `std::generator<T>` (C++23, `<generator>`, gate on `__cpp_lib_generator`) is the first standard coroutine type you should actually use — lazy sequences that plug into ranges:

```cpp
std::generator<int> primes_below(int n);
for (int p : primes_below(1000) | std::views::take(10)) use(p);
```

- For async tasks, use a maintained coroutine library or your framework's task type rather than hand-rolling one. Writing a minimal `task<T>` to *understand* the machinery: [references/coroutines.md](references/coroutines.md).
- **Never capture into a coroutine lambda** — by reference *or* by value. Captures live in the closure object, not the coroutine frame; once the closure dies, every capture dangles at the first suspension:

```cpp
auto bad  = [&data]() -> std::generator<int> { co_yield data.front(); };  // dangles
auto good = [](const Data& d) -> std::generator<int> { co_yield d.front(); };
// parameters are copied/bound into the frame; captures are not
```

## No Threads at All: Parallel Algorithms

```cpp
std::sort(std::execution::par_unseq, v.begin(), v.end());      // C++17
std::transform(std::execution::par, in.begin(), in.end(), out.begin(), f);
```

- Often the right answer to "make this loop faster" — no thread lifecycle, no locks of your own.
- `f` must not touch shared mutable state (that's still a data race), and an exception escaping it calls `std::terminate`.
- libstdc++ historically requires linking TBB for real parallelism; libc++ support arrived later — verify against your toolchain that the policy actually parallelizes before claiming a win.

## Verification: TSan First

1. **ThreadSanitizer is the gate.** Run the full test suite under `-fsanitize=thread -O1 -g` before any concurrent code merges. TSan finds real races with essentially no false positives when all code (including dependencies) is instrumented.
2. **TSan and ASan cannot be combined** in one binary. Keep separate build directories (`build-tsan/`, `build-asan/`) and run two CI jobs: TSan, and ASan+UBSan (those two do combine).
3. TSan only reports races on code paths that *execute* — stress the schedule: run tests repeatedly, oversubscribe threads, add `--gtest_repeat=`/loops for racy suites.
4. Deadlocks: TSan reports lock-order inversions even when the run doesn't hang. Treat `lock-order-inversion` warnings as P1 bugs, not noise.

Flag sets, suppressions, and slowdown figures: [diagnostics](../../tooling/diagnostics/SKILL.md).

## Diagnostics

| Error/symptom | Cause | Fix | Reference |
|---------------|-------|-----|-----------|
| TSan `data race` with two stacks | unsynchronized access to shared data | protect with one mutex, or make the object `std::atomic` | [atomics-and-memory-model](references/atomics-and-memory-model.md) |
| TSan `lock-order-inversion (potential deadlock)` | mutexes acquired in different orders (ABBA) | one `scoped_lock{a, b}`, or enforce a global lock order | Locking Rules above |
| `terminate called without an active exception` at thread destruction | joinable `std::thread` destroyed | use `std::jthread` | Threads above |
| program hangs, all threads blocked in `lock()` | deadlock: ABBA, or self-lock on non-recursive mutex | `scoped_lock` both; split locking wrapper from unlocked impl | Locking Rules above |
| `condition_variable` wait never returns | notify ran before wait (lost wakeup), or predicate never re-checked | always use predicate-form `wait`; change state under the same mutex | Locking Rules above |
| `atomic::wait` never wakes | value never changed, or `notify` on a different object | store the new value *then* notify the same atomic | [atomics-and-memory-model](references/atomics-and-memory-model.md) |
| works on x86, crashes on ARM | relaxed/unfenced atomics hiding behind x86's strong ordering | restore `seq_cst` or correct acquire/release pairing; re-run TSan on ARM | [atomics-and-memory-model](references/atomics-and-memory-model.md) |
| ASan `heap-use-after-free` from a worker thread | detached thread or stored reference outliving owner | `jthread` owned by the data's owner; no `detach()` | Threads above |
| garbage values / crash inside a coroutine after caller returned | lambda captures or reference parameters outlived by the coroutine | pass by value as parameters; no captures in coroutine lambdas | [coroutines](references/coroutines.md) |
| `std::terminate` from a parallel algorithm | exception escaped the element callable | catch inside the callable; report failures via results, not exceptions | Parallel Algorithms above |
| TSan + ASan build fails or silently misbehaves | the two sanitizers are mutually exclusive | separate `build-tsan/` and `build-asan/` directories and CI jobs | Verification above |

## Related Skills

- [modern-cpp](../modern-cpp/SKILL.md) — RAII and ownership rules that the locking patterns above build on
- [modern-c](../../c/modern-c/SKILL.md) — C11 `<stdatomic.h>` and pthreads at `extern "C"` boundaries
- [python-concurrency](../../python/python-concurrency/SKILL.md) — the parallel decision table on the Python side (asyncio vs threads vs subinterpreters)
- [diagnostics](../../tooling/diagnostics/SKILL.md) — TSan/ASan flag sets, per-sanitizer build dirs, report triage
- [secure-coding](../../_shared/secure-coding/SKILL.md) — TOCTOU and shared-state validation pitfalls
