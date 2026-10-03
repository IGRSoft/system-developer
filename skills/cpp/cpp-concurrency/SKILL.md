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

Standard availability: [cpp entry skill](../SKILL.md) standard-selection table. Deep dives: [references/coroutines.md](references/coroutines.md), [references/atomics-and-memory-model.md](references/atomics-and-memory-model.md).

## Tool Selection: Threads and Shared State

| You need | Reach for | Min standard | Fallback |
|----------|-----------|--------------|----------|
| a thread | `std::jthread`, not `std::thread` | C++20 | `std::thread` + RAII join wrapper |
| protect shared data | `std::mutex` + `std::scoped_lock` | C++17 | — |
| read-mostly shared data | `std::shared_mutex` + `shared_lock`/`scoped_lock` | C++17 | — |
| one shared flag/counter/pointer | `std::atomic<T>` (default `seq_cst`) | C++17 | — |
| wait for an arbitrary condition | `condition_variable` + predicate wait | C++17 | — |
| cooperative cancellation | `std::stop_token` / `std::stop_callback` | C++20 | polled `std::atomic<bool>` |

## Tool Selection: Coordination, Async, Parallel

| You need | Reach for | Min standard | Fallback |
|----------|-----------|--------------|----------|
| one-time start gate / countdown | `std::latch` | C++20 | cv + counter |
| repeated phase sync | `std::barrier` | C++20 | cv + generation counter |
| bound concurrent access | `std::counting_semaphore` | C++20 | cv + counter |
| block until a value changes | `atomic<T>::wait` / `notify_*` | C++20 | `condition_variable` |
| lazy sequence, no threads | `std::generator` | C++23 | handwritten iterator, range-v3 |
| data parallelism | parallel algorithms (`std::execution::par`) | C++17 | chunked work across `jthread`s |
| async task graphs | vetted coroutine task library | C++20 | thread pool + futures |

## Threads: jthread

```cpp
std::jthread worker([](std::stop_token st) {
    while (!st.stop_requested()) { process_next(); }
});
// destructor: request_stop() then join(). No terminate, no leak.
```

- A joinable `std::thread` destroyed calls `std::terminate`; `jthread` auto-joins and passes a `stop_token` as the first parameter if the callable accepts one.
- Don't `detach()`: a detached thread touching anything with a lifetime is a use-after-free waiting for load. Use an owned worker with shutdown instead.
- C++17 fallback: an RAII wrapper that joins `std::thread` in its destructor, plus an `std::atomic<bool>` stop flag.

## Cancellation: stop_token and stop_callback

```cpp
std::jthread worker([&](std::stop_token st) {
    std::unique_lock lock{m};                              // m: std::mutex
    cv.wait(lock, st, [&] { return work_available(); });  // cv: condition_variable_any
    if (st.stop_requested()) return;                       // woken by request_stop()
});
```

- Poll `st.stop_requested()` at loop boundaries; pass `st` into `condition_variable_any::wait` (C++20) so blocked waits wake on cancellation.
- For waits the token can't reach (sockets, pipes), register a `std::stop_callback` that unblocks them: `std::stop_callback cb{st, [&] { ::shutdown(fd, SHUT_RDWR); }};`
- Cancellation is cooperative; there is no safe way to kill a thread, so every loop and blocking call must observe the token.

## Locking Rules

```cpp
std::scoped_lock lock{accounts_mtx, audit_mtx};  // multiple mutexes, deadlock-free order
```

- `std::scoped_lock` (C++17) for one mutex or several acquired together with deadlock avoidance; it subsumes `lock_guard`. `unique_lock` only where `condition_variable` requires it.
- Don't lock two mutexes in different orders in different places (ABBA deadlock): fix one global order or acquire both in one `scoped_lock`.
- Don't hold a lock across a callback, virtual call, or `co_await`; you don't control what runs there.
- Call `condition_variable::wait` with a predicate: `cv.wait(lock, [&]{ return ready; });`. Without one, spurious wakeups and notifies that ran before the wait go unhandled.
- Wanting `recursive_mutex` is a design smell: split into a locking public wrapper and an unlocked private implementation.

## Atomics: seq_cst by Default

- All `std::atomic` operations default to `memory_order_seq_cst`. Keep the default: it is correct in every pattern and rarely measurable outside hot lock-free structures.
- Use `acquire`/`release` (or `relaxed` for pure counters) only with a measured reason, documented at the call site:

```cpp
// relaxed: statistics counter, read only after threads join (#1742 perf trace)
hits.fetch_add(1, std::memory_order_relaxed);
```

- `volatile` is not atomic: no protection against data races, tearing, or CPU reordering. A `volatile bool stop_flag` is a bug; use `std::atomic<bool>`.
- An atomic protects exactly one object. If two values must change together, use a mutex.
- Memory model, CAS loops, `atomic_ref`: [references/atomics-and-memory-model.md](references/atomics-and-memory-model.md).

## Coordination: latch, barrier, semaphore, atomic wait

```cpp
std::latch start{1};
std::vector<std::jthread> pool;
for (int i = 0; i < n; ++i)
    pool.emplace_back([&start, i] { start.wait(); run(i); });  // all release together
start.count_down();
```

- `latch` = single-use countdown (start gates, init-complete). `barrier` = reusable phase sync with optional completion step. `counting_semaphore` = bound N concurrent users.
- `atomic<T>::wait(old)` / `notify_all()` is the lightest "block until this value changes" tool, no mutex needed. Recipes in [references/atomics-and-memory-model.md](references/atomics-and-memory-model.md).
- All four are C++20; the C++17 fallback for each is a `condition_variable` + counter under a mutex.

## Coroutines: Consume, Don't Build

- The C++20 machinery (`promise_type`, awaiters, `coroutine_handle`) is library-author level. Application code consumes coroutine types.
- `std::generator<T>` (C++23, gate on `__cpp_lib_generator`) is the standard coroutine type to use: lazy sequences that plug into ranges.

```cpp
for (int p : primes_below(1000) | std::views::take(10)) use(p);  // std::generator<int>
```

- For async tasks, use a maintained coroutine library or your framework's task type. Machinery and a teaching `task<T>`: [references/coroutines.md](references/coroutines.md).
- Coroutine lambdas capture nothing, by reference or by value. Captures live in the closure, not the frame, so they dangle once the closure dies:

```cpp
auto bad  = [&data]() -> std::generator<int> { co_yield data.front(); };  // dangles
auto good = [](const Data& d) -> std::generator<int> { co_yield d.front(); };
```

## No Threads at All: Parallel Algorithms

```cpp
std::sort(std::execution::par_unseq, v.begin(), v.end());      // C++17
std::transform(std::execution::par, in.begin(), in.end(), out.begin(), f);
```

- Often the right answer to "make this loop faster": no thread lifecycle, no locks of your own.
- `f` must not touch shared mutable state (still a data race), and an exception escaping it calls `std::terminate`.
- libstdc++ needs TBB linked to actually parallelize; libc++ support is newer. Confirm the policy parallelizes on your toolchain before claiming a win.

## Verification: TSan First

- ThreadSanitizer is the gate: run the full test suite under `-fsanitize=thread -O1 -g` before concurrent code merges. With all code (dependencies included) instrumented, it has essentially no false positives.
- TSan and ASan can't share a binary. Keep `build-tsan/` and `build-asan/` and run two CI jobs: TSan, and ASan+UBSan (those two combine).
- TSan only sees races on paths that execute: run racy suites repeatedly (`--gtest_repeat=`), oversubscribe threads.
- TSan reports lock-order inversions even when the run doesn't hang. Treat `lock-order-inversion` as a P1 bug.

Flag sets, suppressions, slowdown figures: [diagnostics](../../tooling/diagnostics/SKILL.md).

## Diagnostics: Threads and Locks

| Error/symptom | Cause | Fix |
|---------------|-------|-----|
| TSan `data race` with two stacks | unsynchronized shared access | one mutex, or make the object `std::atomic` |
| TSan `lock-order-inversion`, or hang with all threads in `lock()` | ABBA order, or self-lock on a non-recursive mutex | one `scoped_lock{a, b}`; split locking wrapper from unlocked impl |
| `terminate called without an active exception` at thread destruction | joinable `std::thread` destroyed | `std::jthread` |
| `condition_variable` wait never returns | lost wakeup, or state changed outside the mutex | predicate-form `wait`; change state under the same mutex |
| ASan `heap-use-after-free` from a worker | detached thread or reference outliving owner | `jthread` owned by the data's owner |

## Diagnostics: Atomics, Coroutines, Algorithms

| Error/symptom | Cause | Fix |
|---------------|-------|-----|
| `atomic::wait` never wakes | value never changed, or `notify` on another object | store the new value, then notify the same atomic |
| works on x86, crashes on ARM | weakened atomics hidden by x86's strong ordering | restore `seq_cst` or fix acquire/release pairing; re-run TSan on ARM |
| garbage or crash inside a coroutine after caller returned | lambda captures or reference parameters outlived | by-value parameters; no captures ([coroutines](references/coroutines.md)) |
| `std::terminate` from a parallel algorithm | exception escaped the element callable | catch inside; report failures via results |

## Related Skills

- [modern-cpp](../modern-cpp/SKILL.md) — RAII and ownership rules the locking patterns build on
- [modern-c](../../c/modern-c/SKILL.md) — C11 `<stdatomic.h>` and pthreads at `extern "C"` boundaries
- [python-concurrency](../../python/python-concurrency/SKILL.md) — the Python-side decision table
- [secure-coding](../../_shared/secure-coding/SKILL.md) — TOCTOU and shared-state validation pitfalls
