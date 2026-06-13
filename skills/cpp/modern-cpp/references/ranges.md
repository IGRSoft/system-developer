# Ranges: Views, Pipelines, and the Dangling Rules

Use this when:

- You are writing or reviewing C++20/23 ranges pipelines (`views::filter | views::transform | …`).
- A pipeline returns garbage, crashes under ASan, or won't compile with a wall of concept errors.
- You need the C++23 additions: `zip`, `enumerate`, `chunk`, `slide`, `stride`, `cartesian_product`, `fold_left`, `ranges::to`.
- You are on C++17 and need the range-v3 fallback story.

Skip this file if:

- You need other C++23 features (`expected`, `print`, deducing this, `generator` mechanics). Use `cpp23-features.md`.
- You need concepts/`requires` syntax itself rather than range concepts. Use `cpp20-features.md`.
- You are choosing which standard to target. Use the standard-selection table in [../../SKILL.md](../../SKILL.md).

Jump to:

- The Model: Ranges, Views, Algorithms
- Availability and Fallbacks
- Laziness: What Actually Executes, and When
- Dangling and Borrowed Ranges
- Pitfalls That Pass Review and Fail in Production
- Projections
- Splitting Strings
- C++23 View Adaptors
- C++23 Folds: fold_left and Friends
- Materializing: ranges::to
- Writing Range-Friendly APIs
- Worked Example: Loop to Pipeline
- range-v3 Fallback on C++17
- Performance Notes

## The Model: Ranges, Views, Algorithms

**C++20 (`<ranges>`, `<algorithm>`).** Three kinds of things:

- **Range**: anything with `begin()`/`end()` — containers, arrays, views, `std::generator`. Refined by capability: `input_range → forward_range → bidirectional_range → random_access_range → contiguous_range`.
- **View**: a lightweight range — O(1) copy/move/destroy — that describes a computation over another range without performing it. Created by adaptors in `std::views`.
- **Constrained algorithm**: `std::ranges::sort(vec)` instead of `std::sort(vec.begin(), vec.end())` — takes whole ranges, uses concepts for readable-ish errors, supports projections.

```cpp
std::vector<Order> orders = load();

auto totals = orders
    | std::views::filter([](const Order& o) { return o.paid; })
    | std::views::transform(&Order::total);        // member pointer works as callable

double sum = 0;
for (double t : totals) sum += t;                  // work happens HERE, not above
```

The pipeline expression builds a view object; nothing iterates `orders` until the `for` loop. Adaptors compose left to right with `|`, and a partial pipeline (`auto pipeline = views::filter(p) | views::transform(f);`) is itself a reusable object you can apply to multiple ranges.

Core C++20 adaptor vocabulary:

| Adaptor | Produces | Notes |
|---------|----------|-------|
| `views::filter(pred)` | elements passing `pred` | caches `begin()` — see pitfalls |
| `views::transform(f)` | `f(elem)` per element | `f` re-runs on every dereference |
| `views::take(n)` / `drop(n)` | first n / all but first n | |
| `views::take_while(p)` / `drop_while(p)` | prefix rules | `drop_while` caches `begin()` |
| `views::reverse` | reversed | needs `bidirectional_range` |
| `views::keys` / `values` / `elements<N>` | tuple/pair projections | maps, zip results |
| `views::join` | flattens range-of-ranges | |
| `views::split(delim)` / `lazy_split` | subranges between delimiters | `split` (post-P2210) gives contiguous subranges over contiguous input — usable for `string_view{sub.begin(), sub.end()}` |
| `views::common` | view with same iterator/sentinel types | bridge to pre-ranges APIs taking `(first, last)` |
| `views::iota(0)` / `iota(0, n)` | generated integer sequence | infinite without bound — pair with `take` |
| `views::counted(it, n)` | n elements from iterator | |
| `views::all(r)` | the identity view | what `|` applies implicitly to containers |

## Availability and Fallbacks

Gate on feature-test macros, not compiler versions — C++23 adaptors landed piecemeal across libstdc++/libc++/MSVC; verify against your toolchain.

| Feature | Standard | Feature-test macro | Fallback |
|---------|----------|--------------------|----------|
| Core ranges + C++20 views | C++20 | `__cpp_lib_ranges >= 201911L` | range-v3 on C++17 |
| `views::zip` / `zip_transform` | C++23 | `__cpp_lib_ranges_zip >= 202110L` | range-v3 `views::zip`; index loop |
| `views::enumerate` | C++23 | `__cpp_lib_ranges_enumerate >= 202302L` | `views::zip(views::iota(0uz), r)`; range-v3 |
| `views::chunk` / `chunk_by` | C++23 | `__cpp_lib_ranges_chunk >= 202202L` / `_chunk_by` | range-v3; manual index math |
| `views::slide` | C++23 | `__cpp_lib_ranges_slide >= 202202L` | range-v3 `views::sliding` |
| `views::stride` | C++23 | `__cpp_lib_ranges_stride >= 202207L` | range-v3; index loop with `i += n` |
| `views::cartesian_product` | C++23 | `__cpp_lib_ranges_cartesian_product >= 202207L` | nested loops; range-v3 |
| `views::join_with` | C++23 | `__cpp_lib_ranges_join_with >= 202202L` | range-v3 `views::join(r, delim)` |
| `views::adjacent` / `pairwise` | C++23 | `__cpp_lib_ranges_zip` (same paper family) | `views::slide(2)`; range-v3 |
| `fold_left` family | C++23 | `__cpp_lib_ranges_fold >= 202207L` | `std::accumulate` over `begin/end` |
| `ranges::to` | C++23 | `__cpp_lib_ranges_to_container >= 202202L` | iterator-pair container ctor; range-v3 `ranges::to` |
| `ranges::contains` / `contains_subrange` | C++23 | `__cpp_lib_ranges_contains >= 202207L` | `ranges::find(r, x) != end(r)` |
| `ranges::find_last` | C++23 | `__cpp_lib_ranges_find_last >= 202207L` | `find` over `views::reverse` |

```cpp
#include <version>
#if defined(__cpp_lib_ranges_to_container)
    auto v = r | std::ranges::to<std::vector>();
#else
    auto common = r | std::views::common;
    std::vector<T> v(common.begin(), common.end());
#endif
```

## Laziness: What Actually Executes, and When

Views are *pull-based*: dereferencing an iterator performs the work for that one element, every time.

```cpp
auto expensive = data | std::views::transform(parse_json);   // nothing parsed yet

auto first = *expensive.begin();        // parses element 0
for (auto&& doc : expensive) use(doc);  // parses ALL elements — element 0 AGAIN
```

Consequences:

1. **Transforms re-run on every pass and every dereference.** Iterating a transform view twice doubles the work. If the transform is expensive, materialize once (`ranges::to`, below) and iterate the container.
2. **Side effects in view callables are a design smell.** `filter`/`transform` predicates may be called more times (or fewer, or in different order) than a naive reading suggests — e.g., `filter` invokes its predicate during `begin()` caching, and algorithms may dereference for comparison multiple times. Keep callables pure; do side effects in the terminal `for` loop.
3. **Short-circuiting is free.** `… | views::take(5)` after a filter touches only as many source elements as needed to produce 5 results. This is the headline win over eager STL chains that build whole intermediate vectors.
4. **Infinite ranges are fine until you forget the bound.** `views::iota(0) | views::filter(pred)` loops forever in `begin()` if no element ever satisfies `pred`. Always bound infinite sources before filtering on rare conditions.

### filter caches begin()

`filter_view::begin()` scans for the first match **once** and caches it (to meet the amortized-O(1) `begin()` requirement). Two sharp edges:

```cpp
auto evens = nums | std::views::filter(is_even);

auto b1 = evens.begin();      // scan happens, position cached
nums.push_back(2);            // container modified…
auto b2 = evens.begin();      // …but cache NOT refreshed: stale iterator — UB territory
```

- **Don't reuse a filter view across container mutation.** Rebuild the pipeline after modifying the underlying range.
- **Filter (and several other) views are not const-iterable**: `begin()` mutates the cache, so it isn't `const`. A function taking `const auto&` view can't iterate it. **Pass views by value** — they're cheap by definition.

### Mutating through a filter view

```cpp
for (int& x : nums | std::views::filter(is_even)) x += 1;   // BROKEN
```

Writing through the iterator so the element *stops satisfying the predicate* violates the view's preconditions (the cached/assumed positions become lies) — the standard makes this a contract violation. If a mutation can change membership, collect indices/pointers first, or use a plain loop.

## Dangling and Borrowed Ranges

The lifetime rules are where ranges bugs concentrate. Three interlocking mechanisms:

### 1. Views borrow lvalue containers

A view over an lvalue container stores a pointer to it. The container must outlive every use of the view:

```cpp
auto bad() {
    std::vector<int> local = compute();
    return local | std::views::filter(is_even);   // DANGLES: view refers to dead local
}
```

Returning a view is only safe when it owns or outlives its source (see `owning_view` below) or views static/caller-owned data. Default rule: **functions return containers (via `ranges::to`) or take the view as a parameter; they don't return views over locals.** Same discipline as `string_view`/`span` in [../SKILL.md](../SKILL.md).

### 2. Rvalue containers become owning_view

**C++20 (as amended by P2415, applied retroactively by implementations).** Piping a *temporary* container moves it into the view:

```cpp
auto ok = std::vector<int>{1, 2, 3} | std::views::filter(is_even);
// ok holds an owning_view: the vector was MOVED in. Safe to return and reuse.
```

So: rvalue source → safe (owned); lvalue source → borrowed (caller manages lifetime). This asymmetry is deliberate and worth memorizing.

### 3. Algorithms on rvalue ranges return ranges::dangling

Constrained algorithms refuse to hand you an iterator into a temporary that just died:

```cpp
auto it = std::ranges::find(load_vector(), 7);   // load_vector() temporary destroyed
*it;   // COMPILE ERROR: it is std::ranges::dangling, which has no operator*
```

The error appears at *use*, mentioning `ranges::dangling` — that's the signal to bind the range to a variable first:

```cpp
auto vec = load_vector();
auto it = std::ranges::find(vec, 7);             // fine: vec outlives it
```

### Borrowed ranges

A `borrowed_range` is one whose iterators remain valid even after the range object is destroyed — because the range doesn't own the elements. `std::string_view`, `std::span`, `std::ranges::subrange`, and reference-semantics views over them qualify; containers do not. Algorithms return real iterators (not `dangling`) for rvalue borrowed ranges:

```cpp
auto it = std::ranges::find(std::string_view{text}, 'x');   // OK: string_view is borrowed
```

Only opt your own type in (`template<> inline constexpr bool std::ranges::enable_borrowed_range<MyView> = true;`) if it truly owns nothing — lying here converts compile errors back into use-after-free.

## Pitfalls That Pass Review and Fail in Production

| Pitfall | Symptom | Rule |
|---------|---------|------|
| View over local returned from function | ASan use-after-free / garbage | return `ranges::to<std::vector>()` instead |
| Filter view reused after container mutation | skipped/duplicated elements, crashes | rebuild pipeline after mutation |
| Mutation through `filter` changing membership | elements skipped, invariant breakage | plain loop or collect-then-mutate |
| Expensive `transform` iterated twice | 2× CPU, mysterious slowness | materialize once with `ranges::to` |
| `const` view member / `const auto&` view param | "no member named 'begin'" compile error | pass views by value; don't store as `const` members |
| View stored as class member referencing another member | dangles on move/copy of the class | store the container; build views in accessors |
| `views::split` on the fly vs `lazy_split` confusion | subranges lack expected operations | `split` for forward+ ranges (contiguous-friendly); `lazy_split` for input ranges / const iteration |
| Pipeline into old API taking `(first, last)` | iterator/sentinel type mismatch error | append `\| views::common` |
| `iota(0)` filtered on never-true predicate | infinite loop in `begin()` | bound the source: `iota(0, n)` or `take(n)` before filter |

## Projections

Every constrained algorithm takes an optional projection — a callable applied to each element *before* the algorithm's comparator/predicate sees it. Kills boilerplate lambdas:

```cpp
struct Person { std::string name; int age; };
std::vector<Person> people = load();

std::ranges::sort(people, {}, &Person::age);             // sort by age ({} = std::less)
auto it  = std::ranges::find(people, "Ada", &Person::name);
auto max = std::ranges::max_element(people, {}, &Person::age);
```

Projections compose with member pointers, member functions, and free functions. Inside *view* pipelines there are no projection parameters — use `views::transform` or pass member pointers directly to adaptors that accept invocables.

```cpp
// Projection + comparator together: descending sort by computed key
std::ranges::sort(files, std::ranges::greater{}, [](const FileInfo& f) { return f.size; });

// unique/equal-style algorithms project before comparing:
auto dupes = std::ranges::adjacent_find(people, {}, &Person::name) != people.end();
```

One restriction worth knowing: projections apply to algorithm *inputs*, not outputs — `ranges::copy` with a projection does not exist (that's `views::transform | ranges::copy`).

## Splitting Strings

**C++20**, with semantics fixed by P2210 (early C++20 implementations shipped the older, less usable `split`; verify against your toolchain if subrange operations misbehave).

Two adaptors:

| Adaptor | Input requirement | Output element | Use when |
|---------|-------------------|----------------|----------|
| `views::split` | `forward_range`+ | `subrange` preserving the source's iterator strength | normal case — strings, vectors |
| `views::lazy_split` | `input_range` (works on single-pass) | an inner *range of ranges* with weaker iterators | streaming input; const-iterating the split view |

Over contiguous input (`std::string`, `string_view`), `split` yields contiguous subranges, which convert cleanly to `string_view` — the foundation of allocation-free tokenizing:

```cpp
std::string_view line = "alpha,beta,,gamma";

auto fields = line
    | std::views::split(',')
    | std::views::transform([](auto sub) { return std::string_view{sub}; })
    | std::ranges::to<std::vector>();        // ["alpha", "beta", "", "gamma"]
```

Notes:

- The delimiter may be a single element (`','`) or a sub-pattern (`std::string_view{"::"}`); the pattern overload requires `forward_range` input.
- Empty fields between adjacent delimiters are produced (see `""` above) — filter them explicitly (`views::filter([](auto f) { return !f.empty(); })`) when the format treats runs of delimiters as one.
- `std::string_view{sub}` construction from a subrange is C++23's iterator-pair `string_view` constructor working with C++20 `split` output on most toolchains; the portable C++20 spelling is `std::string_view{&*sub.begin(), std::ranges::distance(sub)}` (guard the empty case) — or just verify the direct construction compiles on your toolchain.
- For parsing the resulting fields into numbers, `std::from_chars` on each `string_view` keeps the whole pipeline allocation-free.

## C++23 View Adaptors

All entries here are **C++23**; macros and fallbacks in the availability table above.

### zip and zip_transform

Iterate several ranges in lockstep; stops at the shortest. Elements are tuples *of references*, so writing through them works:

```cpp
std::vector<std::string> names{"a", "b", "c"};
std::vector<int>         scores{10, 20, 30};

for (auto [name, score] : std::views::zip(names, scores))
    std::println("{}: {}", name, score);

// Writes go through to the underlying ranges:
for (auto [name, score] : std::views::zip(names, scores))
    if (score > 15) name += "!";

// zip_transform: fuse the combination step
auto sums = std::views::zip_transform(std::plus{}, xs, ys);   // x[i] + y[i]
```

C++23 also fixed `std::tuple`/`std::pair` swap and assignment for reference-tuples, which is what makes `std::ranges::sort(views::zip(keys, values))` — sorting parallel arrays together — actually work. Pre-23 fallback: classic index loop over `std::min(a.size(), b.size())`.

### enumerate

Index + element without manual counters; index type is the range's difference type:

```cpp
for (auto [i, item] : std::views::enumerate(items))
    std::println("{:>3}: {}", i, item);
// Fallback: views::zip(views::iota(0uz), items)
```

### chunk and chunk_by

```cpp
// chunk(n): consecutive groups of n (last group may be short)
for (auto batch : jobs | std::views::chunk(64))
    submit(std::vector(batch.begin(), batch.end()));

// chunk_by(pred): split where pred(prev, curr) is FALSE — group while predicate holds
std::vector<int> v{1, 2, 2, 3, 1, 1};
auto runs = v | std::views::chunk_by(std::ranges::equal_to{});  // [1][2,2][3][1,1]
```

`chunk_by` requires a `forward_range` (it must look at pairs); `chunk` works down to input ranges with weaker chunk types. Typical uses: batching work, grouping pre-sorted data by key (`chunk_by` on key equality replaces a hand-rolled group-by loop).

### slide

Overlapping windows of width n — each window shifted by one:

```cpp
std::vector<double> prices = load();
auto sma3 = prices
    | std::views::slide(3)                                   // [p0,p1,p2], [p1,p2,p3], …
    | std::views::transform([](auto w) {
          return std::ranges::fold_left(w, 0.0, std::plus{}) / 3.0;
      });
```

`slide(2)` is the general "adjacent pairs" tool; `views::adjacent<2>` (a.k.a. `views::pairwise`) is the compile-time-width sibling yielding tuples instead of subranges.

### stride

Every nth element, starting with the first:

```cpp
auto sampled = signal | std::views::stride(10);   // elements 0, 10, 20, …
// Downsampling, taking every k-th row of a flattened matrix, decimating logs.
```

### cartesian_product

All combinations, odometer order (last range varies fastest):

```cpp
for (auto [w, h, fmt] : std::views::cartesian_product(widths, heights, formats))
    run_test_case(w, h, fmt);
```

Replaces triple-nested test loops. Size multiplies fast — combine with `views::take`/sampling for property-style exploration. Fallback: nested `for` loops (which also remain clearer when the body needs `break` across dimensions).

### join_with

Flatten a range of ranges with a delimiter between the inner ranges — the lazy `join(parts, sep)`:

```cpp
std::vector<std::string> parts{"usr", "local", "bin"};
auto path = parts | std::views::join_with('/') | std::ranges::to<std::string>();
// "usr/local/bin"
```

## C++23 Folds: fold_left and Friends

**C++23 (`__cpp_lib_ranges_fold`).** Range-based reduction, replacing `std::accumulate` (which never got a ranges overload and hides an unwanted copy-per-step in pre-20 forms):

```cpp
double total = std::ranges::fold_left(prices, 0.0, std::plus{});

// fold_left_first: no init value — uses the first element; returns optional
std::optional<int> mx = std::ranges::fold_left_first(values, std::ranges::max);
// empty range → nullopt: the empty case is explicit, not a sentinel init guess

// fold_right: right-associative — matters for non-commutative ops
auto folded = std::ranges::fold_right(items, std::string{}, concat);
```

| Function | Init | Returns | Use when |
|----------|------|---------|----------|
| `fold_left(r, init, f)` | explicit | value | normal reduction |
| `fold_left_first(r, f)` | first element | `optional<value>` | min/max-style where init would be wrong for empty input |
| `fold_right(r, init, f)` | explicit | value | right-associative ops |
| `fold_left_with_iter` | explicit | iterator + value | need the end position too (partial folds) |

These are *algorithms* (eager, terminal), not views — they end a pipeline. Pre-23 fallback: `std::accumulate(begin(r), end(r), init, f)` after `views::common` if the range has a sentinel.

## Materializing: ranges::to

**C++23 (`__cpp_lib_ranges_to_container`).** The missing terminal step: collect a view into a container, deducing the element type:

```cpp
auto evens = nums
    | std::views::filter(is_even)
    | std::ranges::to<std::vector>();                 // vector<int> deduced

auto index = pairs | std::ranges::to<std::map>();     // map<K, V> from pair elements
auto s     = chars | std::ranges::to<std::string>();

// Explicit element type when you want a conversion on the way in:
auto sizes = names
    | std::views::transform(&std::string::size)
    | std::ranges::to<std::vector<std::uint32_t>>();  // narrowing made visible

// Nested: range of ranges → vector of vectors
auto grid = rows | std::ranges::to<std::vector<std::vector<int>>>();
```

It reserves capacity when the source size is known (`sized_range`), forwards extra constructor arguments (allocators), and works with any container constructible from a range, iterator pair, or via `push_back`/`insert`.

Use `ranges::to` whenever a pipeline's result is (a) iterated more than once, (b) returned from a function, or (c) stored — the three cases where keeping it lazy is a bug or a perf trap.

Pre-23 fallback:

```cpp
auto common = view | std::views::common;
std::vector<int> v(common.begin(), common.end());     // C++20
// range-v3: view | ranges::to<std::vector<int>>()    // note: type often required
```

## range-v3 Fallback on C++17

The range-v3 library is the proving ground the standard features came from; it runs on C++17 and provides nearly everything above plus more. Migration notes:

- Namespaces: `ranges::views::filter` (or legacy `ranges::view::`) vs `std::views::filter`. An alias header per project (`namespace rv = ranges::views;` ↔ `namespace rv = std::views;`) makes later migration a one-line change.
- `ranges::to<std::vector<int>>()` in range-v3 frequently needs the full type where `std::ranges::to<std::vector>()` deduces.
- Some semantics drifted during standardization (notably `split`, and dangling protection — range-v3 has its own `dangling` story). Don't assume behavior transfers exactly; test pipelines when migrating.
- Mixing range-v3 views with `std::ranges` algorithms in one expression sometimes works and sometimes hits concept mismatches — keep each pipeline within one ecosystem.

When stuck on C++17 with no third-party budget: the STL algorithm + named-lambda style remains perfectly serviceable. Ranges are a readability/composability win, not a capability gate.

## Performance Notes

- **At `-O2`, simple pipelines compile to loop-equivalent code** on current GCC/Clang — iterators inline away. Verify on your hot paths with the profiler rather than assuming either direction; deeply nested pipelines (especially through `join`) can defeat inlining.
- **Order adaptors cheapest-first**: `filter` before `transform` so discarded elements are never transformed; `take` as early as correctness allows.
- **Don't recompute — materialize.** Multi-pass consumers of expensive transforms should pay once via `ranges::to`. Memory for CPU is usually the right trade off the hot path.
- **`random_access`/`sized` properties unlock algorithm fast paths** and `ranges::to` preallocation. `filter` *destroys* sized-ness (size unknowable without scanning); pipelines that only `transform`/`take`/`stride` keep it.
- Debug builds run pipelines dramatically slower than raw loops (no inlining); benchmark optimized builds only. Sanitizer builds: see [diagnostics](../../../tooling/diagnostics/SKILL.md).
- A plain `for` loop is still the right call when the body mutates the source, needs `break`/`continue` across multiple concerns, or when the pipeline would need three `views::common` bridges to fit old APIs. Ranges are a tool, not a purity test.
