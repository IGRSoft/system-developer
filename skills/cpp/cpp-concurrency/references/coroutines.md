# C++ Coroutines

Use this when:

- You are using `std::generator` (C++23) or another coroutine type and want the rules.
- You need the `promise_type`/awaiter mental model to read or debug coroutine code.
- You are writing a basic `task<T>` or custom awaiter and need a correct skeleton.
- You are chasing a crash or garbage value inside a coroutine (lifetime/capture bugs).

Skip this file if:

- You just need threads, locks, or atomics. Use [../SKILL.md](../SKILL.md) and [atomics-and-memory-model.md](atomics-and-memory-model.md).
- You want a production async runtime. Pick a maintained coroutine library; this file explains the machinery, it is not a runtime.

Jump to:

- The Mental Model
- Which Level Are You Working At
- std::generator (C++23)
- A C++20 Generator Fallback
- Writing a Basic task<T>
- Custom Awaiters
- Lifetime and Capture Pitfalls
- Exceptions in Coroutines
- Pitfall Quick Reference

## The Mental Model

A coroutine is a function that can suspend itself and be resumed later. Any function whose body contains `co_await`, `co_yield`, or `co_return` is compiled as a coroutine. Three consequences follow:

1. **Locals move off the stack.** Parameters and local variables live in a *coroutine frame*, allocated (usually on the heap) when the coroutine is first called, destroyed when it finishes or when someone calls `handle.destroy()`. The compiler may elide the allocation when it can prove the frame's lifetime is enclosed by the caller's (HALO — heap allocation elision optimization). Treat elision as an optimization, never a guarantee.
2. **Calling a coroutine does not run its body.** The call allocates the frame, constructs the *promise*, obtains the *return object* (your `generator`, `task`, etc.), and then consults `initial_suspend()`. For lazy types (`std::generator`, most `task` designs) the body has not executed a single statement when the call returns.
3. **The return type is in charge.** Everything about a coroutine's behavior — lazy or eager, what `co_yield` means, where exceptions go — is decided by the `promise_type` nested in (or associated with) its return type. The keywords are fixed syntax; the semantics are supplied by library code.

### The promise

The compiler finds `ReturnType::promise_type` (or a `std::coroutine_traits` specialization) and drives the coroutine through it:

| Promise member | Called when | Typical lazy-type choice |
|----------------|-------------|--------------------------|
| `get_return_object()` | at startup, produces what the caller receives | wrap `coroutine_handle::from_promise(*this)` |
| `initial_suspend()` | before the first statement | `suspend_always` (lazy) / `suspend_never` (eager) |
| `yield_value(v)` | at `co_yield v` | stash a pointer to `v`, return `suspend_always` |
| `return_value(v)` / `return_void()` | at `co_return` | store the result |
| `unhandled_exception()` | exception escapes the body | store `std::current_exception()` |
| `final_suspend()` | after the body finishes | `suspend_always`, or symmetric transfer to a continuation — **must be `noexcept`** |

The conceptual rewrite of every coroutine body:

```cpp
// pseudocode of what the compiler generates
{
    promise_type promise(/* maybe from args */);
    auto return_object = promise.get_return_object();   // handed to the caller
    co_await promise.initial_suspend();                 // lazy types stop here
    try {
        /* your body; co_yield v => co_await promise.yield_value(v) */
    } catch (...) {
        promise.unhandled_exception();
    }
    co_await promise.final_suspend();                    // noexcept territory
}
```

### The awaiter

Every `co_await expr` resolves to an *awaiter* — via `promise.await_transform(expr)` if the promise defines it, then `operator co_await` if the type provides one, else `expr` itself. The awaiter answers three questions:

```cpp
struct awaiter {
    bool await_ready();                          // true => skip suspension entirely
    /* void | bool | coroutine_handle<> */
    auto await_suspend(std::coroutine_handle<> h); // we are suspended; decide what runs next
    T await_resume();                            // result of the co_await expression
};
```

`await_suspend` return types:

| Returns | Meaning |
|---------|---------|
| `void` | stay suspended; control returns to resumer |
| `bool` | `false` => resume immediately (race lost: value already available) |
| `coroutine_handle<>` | *symmetric transfer*: resume that handle with no stack growth — return `std::noop_coroutine()` for "nobody" |

Symmetric transfer matters: a loop of "task A resumes task B resumes task A…" implemented by calling `handle.resume()` inside `await_suspend` grows the stack and eventually overflows. Returning the handle instead makes the transfer a tail-call.

### The handle

`std::coroutine_handle<promise_type>` is a non-owning pointer to the frame: `resume()`, `done()`, `destroy()`, `promise()`. It has pointer semantics — copying it does not copy the coroutine, and nothing stops you from calling `resume()` on a destroyed frame (UB). Exactly one owner (your return object) should call `destroy()`, in its destructor, exactly once.

## Which Level Are You Working At

| You are... | You need | From this file |
|------------|----------|----------------|
| iterating a `std::generator`, awaiting a library `task` | usage rules and lifetime pitfalls | std::generator + Pitfalls sections |
| reading a framework's coroutine internals | the mental model above | Mental Model section |
| writing a generator on a C++20-only toolchain | the fallback skeleton | C++20 Generator Fallback |
| building a task type to learn the machinery | the `task<T>` walkthrough | Writing a Basic task<T> |
| building a production async runtime | a maintained library, not this file | — |

Application code should *consume* coroutine types. Hand-rolled task types in application repositories are a recurring source of subtle UB (missed `noexcept` on `final_suspend`, double-destroy, lost exceptions). For production async work, adopt a maintained coroutine library (or your framework's task type) after checking its maintenance status — verify against your toolchain and dependency policy.

## std::generator (C++23)

`std::generator<T>` (`<generator>`, feature-test macro `__cpp_lib_generator`) is the first standard coroutine type intended for direct application use: a lazy, synchronous sequence that models `input_range`.

```cpp
#include <generator>

std::generator<int> fibs() {
    for (std::int64_t a = 0, b = 1;; std::swap(a, b))
        co_yield (b += a, a);
}

for (int f : fibs() | std::views::take(10))
    std::println("{}", f);
```

Rules of use:

- **Lazy.** Calling `fibs()` runs nothing; each `++it` (or loop iteration) resumes the body to the next `co_yield`.
- **Single-pass and move-only.** It models `input_range`: one consumer, one traversal. Calling `begin()` twice is precondition-violating; restart by calling the coroutine function again.
- **Yields by reference.** The element you see refers to state inside the frame; copy it if you keep it past the next increment.
- **Not thread-safe.** One generator, one thread (or external synchronization). For cross-thread streaming use a queue, not a generator.
- **Infinite is fine** — laziness plus `views::take` is the idiomatic pairing.

### Yielding nested sequences: std::ranges::elements_of

Recursive or delegating generators should yield a whole inner range with `elements_of`, not loop manually:

```cpp
std::generator<const Node&> walk(const Node& n) {
    co_yield n;
    for (const Node* child : n.children)
        co_yield std::ranges::elements_of(walk(*child));
}
```

`elements_of` makes the nested generator resume directly from the outermost consumer — O(1) per element regardless of nesting depth. A hand-written `for (auto&& e : walk(*child)) co_yield e;` re-suspends through every level: O(depth) per element, and quadratic for deep trees.

### Value vs reference parameters of std::generator

`std::generator<T>` chooses sensible reference/value types from `T`:

| Declaration | Element seen by consumer | Use for |
|-------------|--------------------------|---------|
| `std::generator<int>` | `int&&` (move-ref to frame slot) | cheap value sequences |
| `std::generator<const std::string&>` | `const std::string&` | yielding existing objects without copies |
| `std::generator<std::string>` | `std::string&&` | handing ownership outward |

When yielding `const T&`, the referent must stay alive until the generator is resumed again — yielding a reference to a loop-local that you then mutate is fine (the consumer reads before resuming), yielding a reference to a destroyed temporary is not.

Toolchain note: `std::generator` shipped in GCC 14-era libstdc++; libc++ and MSVC arrived on their own schedules — gate on `__cpp_lib_generator` and verify against your toolchain. Fallbacks: range-v3 generators, or the skeleton below.

## A C++20 Generator Fallback

On C++20-only toolchains, a minimal generator is the one promise type worth writing yourself. Skeleton (error handling and iterator boilerplate compressed):

```cpp
template <typename T>
class [[nodiscard]] generator {
public:
    struct promise_type {
        const T* current = nullptr;
        std::exception_ptr error;

        generator get_return_object() {
            return generator{handle_t::from_promise(*this)};
        }
        std::suspend_always initial_suspend() noexcept { return {}; }   // lazy
        std::suspend_always final_suspend() noexcept { return {}; }     // MUST be noexcept
        std::suspend_always yield_value(const T& v) noexcept {
            current = std::addressof(v);
            return {};
        }
        void return_void() noexcept {}
        void unhandled_exception() { error = std::current_exception(); }
    };
    using handle_t = std::coroutine_handle<promise_type>;

    explicit generator(handle_t h) : h_{h} {}
    generator(generator&& o) noexcept : h_{std::exchange(o.h_, {})} {}
    generator& operator=(generator&&) = delete;
    ~generator() { if (h_) h_.destroy(); }                              // sole owner

    struct iterator {
        handle_t h;
        iterator& operator++() {
            h.resume();
            if (h.done() && h.promise().error)
                std::rethrow_exception(h.promise().error);
            return *this;
        }
        const T& operator*() const { return *h.promise().current; }
        bool operator==(std::default_sentinel_t) const { return h.done(); }
    };
    iterator begin() { h_.resume(); /* same rethrow check */ return {h_}; }
    std::default_sentinel_t end() { return {}; }

private:
    handle_t h_;
};
```

The load-bearing details, in order of how often they are botched:

1. `final_suspend` is `noexcept` and returns `suspend_always` — the frame must stay alive after completion so the owner can `destroy()` it; if it didn't suspend, the frame would self-destroy and the destructor's `destroy()` would be a double-free.
2. The destructor calls `h_.destroy()`; move construction nulls the source. One owner, one destroy.
3. `yield_value` stores a *pointer* to the caller-side value — valid because the coroutine is suspended (its full-expression is paused) while the consumer reads. Do not copy into the promise unless you need to outlive the suspension.
4. Exceptions are captured in the promise and rethrown at `begin()`/`operator++` — the consumer's resume point. See Exceptions in Coroutines.

## Writing a Basic task<T>

A lazy `task<T>` is the canonical exercise for understanding awaiters and symmetric transfer. This is a teaching skeleton — single-threaded resume semantics, no scheduler:

```cpp
template <typename T>
class [[nodiscard]] task {
public:
    struct promise_type {
        std::variant<std::monostate, T, std::exception_ptr> result;
        std::coroutine_handle<> continuation;        // whoever co_awaits us

        task get_return_object() {
            return task{handle_t::from_promise(*this)};
        }
        std::suspend_always initial_suspend() noexcept { return {}; }   // lazy

        struct final_awaiter {
            bool await_ready() noexcept { return false; }
            std::coroutine_handle<>
            await_suspend(std::coroutine_handle<promise_type> h) noexcept {
                // Symmetric transfer: resume the awaiter of this task, if any.
                if (auto c = h.promise().continuation) return c;
                return std::noop_coroutine();
            }
            void await_resume() noexcept {}
        };
        final_awaiter final_suspend() noexcept { return {}; }

        void return_value(T v) { result.template emplace<1>(std::move(v)); }
        void unhandled_exception() {
            result.template emplace<2>(std::current_exception());
        }
    };
    using handle_t = std::coroutine_handle<promise_type>;

    // --- awaitable interface: `co_await someTask` ---
    bool await_ready() const noexcept { return false; }
    std::coroutine_handle<>
    await_suspend(std::coroutine_handle<> awaiting) noexcept {
        h_.promise().continuation = awaiting;
        return h_;                       // start the lazy task now (symmetric transfer)
    }
    T await_resume() {
        auto& r = h_.promise().result;
        if (r.index() == 2) std::rethrow_exception(std::get<2>(r));
        return std::move(std::get<1>(r));
    }

    explicit task(handle_t h) : h_{h} {}
    task(task&& o) noexcept : h_{std::exchange(o.h_, {})} {}
    task& operator=(task&&) = delete;
    ~task() { if (h_) h_.destroy(); }

private:
    handle_t h_;
};
```

How a chain executes:

```cpp
task<int> leaf()   { co_return 42; }
task<int> middle() { co_return co_await leaf() + 1; }
// caller co_awaits middle():
//   middle suspends at initial_suspend (lazy) until awaited
//   awaiting middle: await_suspend stores continuation, returns middle's handle
//   middle runs, hits `co_await leaf()`: stores middle as leaf's continuation,
//     transfers to leaf; leaf co_returns, final_awaiter transfers back to middle
//   middle co_returns; its final_awaiter transfers back to the original awaiter
```

What this skeleton deliberately lacks — and why you use a library in production:

- **No `sync_wait`.** Something at the top of the chain must resume the first task from non-coroutine code and block for the result (typically `atomic<bool>` + `wait`). Easy to get subtly wrong.
- **No scheduler/executor.** Everything resumes inline on the current thread. Real runtimes decide *where* `await_suspend` resumes things.
- **No cancellation**, no `when_all`, no timeouts, no thread-safe completion race (a task completed on thread B while thread A is mid-`await_suspend` requires an atomic state machine).

## Custom Awaiters

You rarely need one; the legitimate cases are bridging a callback API or hopping execution contexts.

```cpp
// Bridge a callback API: co_await read_some(socket)
struct read_awaiter {
    Socket& s;
    std::size_t n = 0;
    std::error_code ec;

    bool await_ready() const noexcept { return false; }
    void await_suspend(std::coroutine_handle<> h) {
        s.async_read([this, h](std::size_t bytes, std::error_code e) mutable {
            n = bytes; ec = e;
            h.resume();                    // resumes ON THE CALLBACK'S THREAD
        });
    }
    std::size_t await_resume() {
        if (ec) throw std::system_error(ec);
        return n;
    }
};
```

Rules:

- Document **which thread `await_resume` continues on**. After the awaiter above, the coroutine is running on the I/O callback thread — every local it touches migrated threads with it. `co_await` is a potential thread switch; code after it must not assume the thread before it.
- If the operation can complete *before* `await_suspend` finishes registering, return `bool` from `await_suspend` (`false` = "already done, resume now") or use an atomic state to avoid the lost-wakeup race.
- `promise.await_transform(x)` lets a promise intercept every `co_await x` in its coroutines — how libraries implement `co_await get_stop_token()` style introspection, and how they *ban* awaiting foreign types (declare a deleted `await_transform` catch-all).

## Lifetime and Capture Pitfalls

Coroutine lifetime bugs dominate real-world coroutine defects. The frame routinely outlives the call expression, so every reference that flows in must be audited.

### Pitfall 1: lambda captures (the big one)

Captures live in the **closure object**. The coroutine frame copies the lambda's *parameters*, not its captures — the frame holds only a reference to the closure. When the closure dies, every capture dangles, **including by-value captures**:

```cpp
auto make = [](std::vector<int> data) {
    // BAD: `data` is captured (even by value) — it lives in the closure,
    // and the closure is a temporary destroyed at the end of this statement.
    return [data]() -> std::generator<int> {
        for (int x : data) co_yield x;        // UB after first resume
    }();
};

// GOOD: parameters are moved into the coroutine frame.
auto good = [](std::vector<int> data) -> std::generator<int> {
    for (int x : data) co_yield x;            // frame owns `data`
};
auto gen = good(load());
```

Rule: a coroutine lambda captures **nothing**. Pass everything as parameters. If a framework forces captures (callback adapters), the closure object must provably outlive the last resumption — which usually means heap-allocating it alongside the work.

### Pitfall 2: reference parameters

Parameters are copied into the frame — but a reference parameter copies *the reference*. With lazy coroutines the temporary bound to it is gone before the body ever runs:

```cpp
std::generator<char> chars(const std::string& s) {   // reference into frame
    for (char c : s) co_yield c;
}

auto g = chars(name + ".txt");   // temporary dies at end of this statement
for (char c : g) use(c);         // UB: body runs now, `s` dangles

for (char c : chars(name + ".txt")) use(c);   // OK: temporary lives for the
                                              // whole range-for full-expression
```

Rule for coroutine signatures: **take parameters by value** unless the coroutine is awaited/consumed within the same full-expression and you can prove it stays that way. By-value `std::string`/`std::vector` parameters are cheap insurance; `std::string_view`/`std::span` parameters inherit the same dangling risk as references.

### Pitfall 3: implicit `this`

A member-function coroutine stores `this` in its frame. The object must outlive every resumption:

```cpp
task<void> Session::run() {                 // frame holds Session*
    co_await socket_.connect();             // Session destroyed meanwhile? UB.
    backoff_ = 0;
}
```

Mitigations, in preference order: have the owner of the `Session` own (and `co_await`/destroy) the task so lifetimes nest; or make `run` a static/free coroutine taking `std::shared_ptr<Session>` **by value**; or keep `shared_from_this()` in a local at the top of the body. "The object usually outlives it" is not a mitigation.

### Pitfall 4: fire-and-forget detachment

A detached coroutine (eager, nobody owns the handle) is the coroutine equivalent of a detached thread: nothing bounds its lifetime against the data it references. If you must have one, it may reference **only** what it owns by value — and you still need a shutdown story (counters/latches) so the process doesn't exit under it.

### Pitfall 5: assuming HALO

Whether the frame allocation is elided depends on inlining, on the coroutine type's design, and on optimization level. Never design APIs that are only correct (or only fast enough) when HALO fires; verify allocation behavior against your toolchain with a profiler if it matters.

## Exceptions in Coroutines

Three distinct phases, three different behaviors:

1. **Before the first suspension point is reached** — i.e., thrown during frame allocation, promise construction, or (for eager types) the early body: the exception propagates out of the *call expression* like any normal function call.
2. **From the body after suspension**: the compiler-generated `try/catch` routes it to `promise.unhandled_exception()`. The standard pattern stores `std::current_exception()` and rethrows it at the consumer's resume point — `await_resume` for tasks, `begin()`/`operator++` for `std::generator`. The consumer therefore sees the exception where they *consume*, not where they created the coroutine:

```cpp
std::generator<int> parse(std::istream& in);   // body may throw

auto g = parse(file);          // never throws from here (lazy)
try {
    for (int v : g) use(v);    // parse errors surface in the loop
} catch (const parse_error& e) { report(e); }
```

3. **From `final_suspend` or `unhandled_exception` themselves**: `final_suspend` must be `noexcept` (the program is ill-formed otherwise); if `unhandled_exception` throws or rethrows immediately, the exception escapes into the coroutine teardown path and the practical result is `std::terminate`. Promises that rethrow inside `unhandled_exception()` are valid only for designs where the resumer is prepared for `resume()` to throw — don't combine that with `noexcept` resumption loops.

Guidelines:

- Tasks: store `exception_ptr`, rethrow in `await_resume` (as the `task<T>` skeleton does). This keeps `co_await` transparent: exceptions flow as if the awaited body were a called function.
- Generators: expect throws from iteration, not construction; wrap the *loop*, not the call.
- A coroutine that must not throw should `catch` internally and report through its result type (`std::expected<T, E>` works inside coroutines like anywhere else — see [error-handling](../../modern-cpp/references/error-handling.md)).
- After `unhandled_exception()` runs, the coroutine still proceeds to `final_suspend`; the frame still needs its normal `destroy()`. Exception paths do not change ownership rules.

## Pitfall Quick Reference

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| garbage/ASan UAF on first iteration of a generator | dangling reference parameter or lambda capture | by-value parameters; no captures |
| crash on second `begin()` of a generator | single-pass range iterated twice | call the coroutine function again |
| stack overflow in deeply chained tasks | `resume()` inside `await_suspend` instead of symmetric transfer | return the handle from `await_suspend` |
| O(n²) traversal of recursive generator | manual re-yield loop | `std::ranges::elements_of` |
| double-free in coroutine type destructor | `final_suspend` returned `suspend_never` while destructor calls `destroy()` | `suspend_always` + owner destroys |
| exception appears at the loop, not the call | normal lazy-coroutine semantics | wrap consumption, not construction |
| coroutine resumes on unexpected thread | awaiter resumed from a callback thread | document/await a re-scheduling awaiter; never assume thread affinity across `co_await` |
| `no member named 'generator' in namespace 'std'` | pre-C++23 stdlib or missing `-std=c++23` | gate on `__cpp_lib_generator`; use the C++20 fallback skeleton |

Sanitizer note: ASan and UBSan understand coroutine frames well; run them on all coroutine code (lifetime bugs above are exactly what they catch). TSan support for coroutines that migrate threads has historically had gaps — verify against your toolchain and treat clean TSan runs on thread-hopping coroutine code with mild suspicion.
