# Prior Art for Tempo's Interval Architecture

A survey of existing systems, libraries, and literature that treat date/time as bounded intervals and that define set operations over those intervals. The goal is to identify directly applicable designs, informative ideas to borrow, and dead ends to avoid before implementing Tempo's union/intersection/coalescing milestone.

## 1. Prior art for "time as intervals, not instants"

### 1.1 Snodgrass — *Developing Time-Oriented Database Applications in SQL* (1999)

The canonical practitioner reference for treating time as periods in SQL. Explicitly separates *instants*, *intervals* (durations), and *periods* (an anchored span between two instants), and builds the predicate and constructor vocabulary that later became SQL:2011 PERIODs. Covers valid time, transaction time, bitemporal state tables, and how to implement all of them in off-the-shelf SQL with FROM/TO date columns. The book's vocabulary ("period", "sequenced", "non-sequenced") is still the lingua franca of the temporal-DB world.

**Relevance:** Informative. Tempo is not a database, but the period/instant distinction Snodgrass drew is exactly the distinction Tempo is building on — and it's worth using his terminology ("period" for a bounded span, "instant" for a point) consistently, because it is already well-understood.

**URL:** [publications list](http://www2.cs.arizona.edu/~rts/publications.html), [book](https://shop.elsevier.com/books/developing-time-oriented-database-applications-in-sql/snodgrass/978-0-08-050422-3).

### 1.2 TSQL2 and SQL:2011 PERIOD / FOR SYSTEM_TIME / FOR BUSINESS_TIME

TSQL2 (1993–94, committee of Snodgrass, Jensen, Dyreson, Tansel et al.) was the research prototype that tried to add temporal semantics to SQL-92. It never made the standard, but most of its ideas landed in SQL:2011 as PERIOD columns plus the `FOR SYSTEM_TIME` and `FOR BUSINESS_TIME` clauses. A PERIOD is two columns treated as a single closed-open interval. SQL:2011 defines the temporal predicates `EQUALS`, `OVERLAPS`, `CONTAINS`, `PRECEDES`, `SUCCEEDS`, `IMMEDIATELY PRECEDES`, `IMMEDIATELY SUCCEEDS` — a relabelled subset of Allen's 13 relations. PostgreSQL, DB2, Oracle, SQL Server, and Teradata implement varying subsets.

**Relevance:** Informative. SQL:2011's predicate set is a smaller, application-focused subset of Allen's 13 — Tempo should implement all 13 natively (it already does) but expose the SQL:2011 names as aliases where they read more naturally. The standard does **not** define union/intersection/difference as first-class operators; those are left to range-type implementations (see §2).

**URLs:** [SQL:2011 on Wikipedia](https://en.wikipedia.org/wiki/SQL:2011), [PostgreSQL SQL2011Temporal wiki](https://wiki.postgresql.org/wiki/SQL2011Temporal).

### 1.3 Jensen, Dyreson, Tansel — the temporal-DB research canon

Christian S. Jensen and Curtis E. Dyreson edited the 1998 *Consensus Glossary of Temporal Database Concepts* — the authoritative terminology reference. Abdullah Tansel co-edited *Temporal Databases: Theory, Design, and Implementation* (1993). Together these define the precise meanings of "valid time", "transaction time", "bitemporal", "chronon" (an indivisible time unit — directly analogous to Tempo's "precision"), and "now-relative".

**Relevance:** Informative. The concept of a *chronon* is the closest academic match to Tempo's notion that every value has a precision and that precision determines the implicit span. Worth reading if only to borrow vocabulary.

**URL:** [Snodgrass publications](http://www2.cs.arizona.edu/~rts/publications.html) (consensus glossary linked there).

### 1.4 Johnston & Weis — *Managing Time in Relational Databases* (2010) / Asserted Versioning

A practitioner book and product built around *effective time* and *asserted time* (a clearer renaming of valid/transaction time). Every row gets two temporal intervals, and the framework automatically maintains bitemporal history on update/delete.

**Relevance:** Not directly relevant. This is a database persistence pattern — it assumes a storage engine and transaction semantics Tempo doesn't have. The conceptual takeaway (every fact is anchored to a bounded interval, never a point) is already Tempo's premise.

**URL:** [Understanding Bitemporal Data (Johnston, 2011)](http://www.assertedversioning.com/Documents/EDW-2011-Johnston.pdf).

### 1.5 Systems that model year/month/day as a span, not a Date

Very few libraries actually do this:

- **Joda-Time `Partial`** (Java, deprecated in favour of `YearMonth`, `Year` in `java.time`) — a partial date represents "just the year" or "just year-month" but is treated as an incomplete instant to be combined with defaults, not as an interval.
- **`java.time.Year`, `YearMonth`** — represent the concept but don't expose start/end as an interval; `Year.atDay(1)` and manual arithmetic are required.
- **PostgreSQL date/timestamp** — always an instant; ranges are a separate type.
- **Clojure `tick`** has `t/year`, `t/year-month` but treats them as identifiers, not spans.

The idea that `2026-01` **is** the interval `2026-01-01..2026-02-01` appears to be genuinely novel as a primary API convention. The closest precedent is Snodgrass's period literals in TSQL2/SQL:2011, but even there the granularity of the endpoints is explicit (two dates), not implied by the precision of a single literal.

**Relevance:** Tempo's implicit-span-from-precision is the distinctive contribution of the library. There is no prior art to clone here — only vocabulary (chronon, period) to borrow.

## 2. Prior art for set operations on datetime intervals

### 2.1 PostgreSQL range types (`tsrange`, `tstzrange`, `daterange`)

The most thoroughly designed set-op vocabulary on date/time intervals in mainstream production use. All ranges are half-open by default (`[,)`), matching Tempo exactly.

Operators on single ranges:

* `+` union (fails if the result would be disjoint)
* `*` intersection
* `-` difference (fails if the second range splits the first)
* `@>` contains (range or element)
* `<@` contained by
* `&&` overlaps
* `<<` strictly left of, `>>` strictly right of
* `&<`, `&>` not extending beyond
* `-|-` adjacent

Functions: `lower/1`, `upper/1`, `isempty/1`, `lower_inc/1`, `upper_inc/1`, `lower_inf/1`, `upper_inf/1`, `range_merge/2` (smallest range containing both).

**Relevance:** Directly applicable. This operator set is the de-facto reference vocabulary for interval set ops and Tempo should implement functional equivalents of every one. The half-open convention is the same as ours. The "fail on disjoint union" rule is a design choice Tempo needs to decide on — see multiranges below for the alternative.

**URL:** [PostgreSQL Range/Multirange Functions and Operators](https://www.postgresql.org/docs/current/functions-range.html), [Range Types](https://www.postgresql.org/docs/current/rangetypes.html).

### 2.2 PostgreSQL multirange types (PG 14+, 2021)

This is the most directly relevant prior art for Tempo's coalescing milestone. A multirange is an **ordered list of non-contiguous, non-empty, non-null ranges** — exactly the canonical non-overlapping form Tempo wants to produce. Multirange construction automatically coalesces: input `{[1,3), [2,5), [10,12)}` normalises to `{[1,5), [10,12)}`.

Multirange operators mirror the range operators but **never fail** on disjoint results:

* `+` union — result can be disjoint, multiple ranges returned
* `*` intersection
* `-` difference — the common case Tempo needs: `{[5,20)} - {[10,15)}` returns `{[5,10), [15,20)}`
* `&&`, `@>`, `<@`, `<<`, `>>`, `-|-` as with ranges, plus mixed range/multirange variants

Functions: `range_merge(multirange)` (smallest single range spanning everything), `multirange(range)` (wrap), `unnest(multirange)` (expand to rows), and the aggregate `range_agg(range)` (fold a column of ranges into a multirange — this is the canonical "coalesce a list" operation).

**Relevance:** Directly applicable. This is the model Tempo should mimic. "A sorted list of non-overlapping half-open intervals" is the canonical form; all list-level set ops produce or consume that form. The range-vs-multirange split (range ops fail on disjoint; multirange ops don't) is a useful design: offer both, let the caller decide whether disjoint results are an error or data.

**URLs:** [CYBERTEC: Multiranges in PostgreSQL 14](https://www.cybertec-postgresql.com/en/multiranges-in-postgresql-14/), [Crunchy Data: Better Range Types in Postgres 14](https://www.crunchydata.com/blog/better-range-types-in-postgres-14-turning-100-lines-of-sql-into-3), [Postgres OnLine: Multirange types in PostgreSQL 14](https://www.postgresonline.com/article_pfriendly/401.html).

I didn't dig into the PostgreSQL source for the exact coalescing algorithm, but the documented semantics and the classic sweep-line description (§5) match — sort by lower bound, scan once, merge where `prev.upper >= next.lower` (or `>` for adjacency, depending on whether the caller wants adjacency-merged).

### 2.3 Allen's interval algebra — beyond comparison

The 13 base relations are a **comparison** vocabulary, not directly a set-op vocabulary. But set operations fall out naturally:

* `intersection(a, b)` is non-empty iff the Allen relation between `a` and `b` is one of `{overlaps, overlaps⁻¹, during, during⁻¹, starts, starts⁻¹, finishes, finishes⁻¹, equals}`. The other relations (`before`, `after`, `meets`, `met-by`) imply empty intersection.
* `union(a, b)` is a single contiguous interval iff the Allen relation is in `{meets, met-by, overlaps, overlaps⁻¹, during, during⁻¹, starts, starts⁻¹, finishes, finishes⁻¹, equals}` (anything except `before` / `after`). Otherwise it's two disjoint intervals.
* `a − b` is one of: empty, one interval, or two intervals, depending on the Allen relation.

So Allen's algebra is the *classification* layer; the set ops are the *construction* layer built on top. Tempo already has the classification (`Tempo.Comparison`) — the implementation of set ops can use it as a dispatch table rather than re-deriving the cases.

**URLs:** [Wikipedia: Allen's interval algebra](https://en.wikipedia.org/wiki/Allen's_interval_algebra), [Allen's original page (Alspaugh)](https://ics.uci.edu/~alspaugh/cls/shr/allen.html).

## 3. Library implementations worth reviewing

### 3.1 Elixir ecosystem

**`interval` (hex)** — v2.0.3, actively maintained (last release Oct 2025). Explicitly inspired by PostgreSQL range types. Provides `Interval.DateTimeInterval`, `Interval.DateInterval`, etc. Supports `intersection/2`, `union/2`, `difference/2`, `contains?/2`, `overlaps?/2`, with half-open `[)` as the default and explicit `{:inclusive, _}` / `{:exclusive, _}` bound markers. Ships Ecto types that map to Postgres `tstzrange`, `daterange`, etc.

**Crucially, `interval` operates on pairs of intervals, not lists.** There is no multirange/interval-set construct and no coalescing-of-a-list function documented. This is the gap Tempo would fill.

**Relevance:** Directly applicable as an API reference for the pair-level ops. Study its module layout and naming. Consider whether Tempo should depend on it for the primitive bounds handling or reimplement (I lean reimplement — Tempo's implicit-span-from-precision semantics don't match `interval`'s "construct with explicit bounds" model cleanly, and pulling in a dep for three small operations is not worth the coupling).

**URLs:** [GitHub: tudborg/elixir_interval](https://github.com/tudborg/elixir_interval), [hex: interval](https://hex.pm/packages/interval).

**`Timex` / `timex_interval`** — `Timex.Interval` exists but is primarily a thin iteration helper (enumerate days/weeks between two dates). No union/intersection/difference operators. `timex_interval` is a small wrapper. Neither is a serious set-ops library.

**`Date.Range` (stdlib)** — iteration only, no set ops.

**I did not find a serious Elixir multirange/interval-set library.** This is a genuine gap in the ecosystem.

### 3.2 Python — `portion`

The cleanest interval-set library I found in any language. Treats an `Interval` as "a disjunction of atomic intervals" — i.e., every `Interval` is already a multirange. Union (`|`), intersection (`&`), difference (`-`), complement (`~`) all work; adjacent/overlapping atomics are auto-merged on construction via an internal `_mergeable` check. Supports all four bound configurations (`[]`, `[)`, `(]`, `()`) and infinities. Iterating an `Interval` yields its atomic intervals in order.

**Relevance:** Directly applicable as a design model for **how an Elixir API can feel**. `portion`'s "every interval is implicitly a multirange and coalesces on construction" is a strong design choice worth copying for Tempo's list-level operations. Pros: one type, uniform ops. Cons: you lose the range-vs-multirange distinction PostgreSQL offers.

**URL:** [GitHub: AlexandreDecan/portion](https://github.com/AlexandreDecan/portion).

**Pendulum, Arrow, dateutil** — none do interval arithmetic. Their "interval" concepts are durations, not spans.

### 3.3 JavaScript — Luxon `Interval`

`Interval.fromDateTimes(start, end)` — half-open by documented convention. Supports `overlaps`, `contains`, `intersection` (returns `null` if empty), `difference` (returns array of remaining intervals), `engulfs`, `equals`, `abutsStart`/`abutsEnd`, `splitAt`, `splitBy`. Pair-level only; no multirange / list-coalesce.

**ECMAScript Temporal proposal** — no interval type. Only `PlainDate`, `ZonedDateTime`, `Duration`. Interval semantics are left to userland.

**date-fns** — has `Interval` as a plain `{start, end}` object and utility functions `areIntervalsOverlapping`, `getOverlappingDaysInIntervals`, `isWithinInterval`, but no union/intersection returning intervals. Just predicates.

**Relevance:** Luxon is directly applicable as a concise reference for a well-named pair-level API. Its use of `null` for empty intersection is a choice to weigh against `{:ok, _} | :none` tagged tuples.

**URLs:** [Luxon Interval docs](https://moment.github.io/luxon/api-docs/index.html), [TC39 Temporal](https://tc39.es/proposal-temporal/).

### 3.4 Rust

**`chrono`** — no interval set ops in core. Date/time arithmetic only.

**`chrono-intervals`** — generates intervals (per-day, per-week bucketing); not a set-ops library.

**`std::ops::Range`** is half-open `[)` but has no union/intersection methods either. The Rust ecosystem appears to lack a canonical interval-set crate on the date/time side; `intervallum` and `iset` exist for integer intervals.

**Relevance:** Not directly useful. Confirms that the half-open convention is the dominant one in modern systems.

### 3.5 Haskell — `data-interval` / `Data.IntervalSet`

`data-interval` provides `Interval` with all four bound forms and `Data.IntervalSet` as a canonical-form data structure of non-overlapping intervals with insert/delete/union/intersection/difference. `interval-algebra` (Hackage) is a separate package implementing Allen's 13 relations plus utilities to combine interval sets.

**Relevance:** Directly applicable as a reference for *correctly structured* interval-set operations. The Haskell separation — `Interval` (one) and `IntervalSet` (many, canonical) — maps cleanly to PostgreSQL's range/multirange split and is probably the right model for Tempo.

**URLs:** [data-interval on Hackage](https://hackage.haskell.org/package/data-interval), [Data.IntervalSet](https://hackage.haskell.org/package/data-interval/docs/Data-IntervalSet.html), [interval-algebra](https://hackage.haskell.org/package/interval-algebra).

### 3.6 Java — Joda-Time / threeten-extra

**Joda `Interval`** — half-open, inclusive start / exclusive end. Methods: `abuts(other)`, `overlaps(other)`, `overlap(other)` (returns intersection or null), `gap(other)` (returns the gap interval or null), `contains(other)`, `isBefore`, `isAfter`. Notably, Joda has no union or difference method, and no list-level coalesce. Three-state comparison (abut / gap / overlap) is a useful classification.

**`java.time` (JSR-310)** — no `Interval` class at all. `Period` and `Duration` are durations, not spans.

**`threeten-extra`** has a proposal for an `Interval` class mirroring Joda but it was not merged.

**Relevance:** Informative. Joda's `gap` method is an interesting primitive Tempo could borrow — the symmetric counterpart to intersection when intervals don't overlap.

**URL:** [Joda Interval API](https://www.joda.org/joda-time/apidocs/org/joda/time/Interval.html).

### 3.7 Clojure — `tick`

`tick.alpha.interval` implements Allen's algebra and provides `intersection`, `difference`, `union` (on collections, returns a collection). The namespace is marked alpha and not actively maintained. It *does* operate on collections of intervals and returns canonical non-overlapping results, making it one of the few libraries outside PostgreSQL / `portion` / Haskell to do so.

**Relevance:** Informative. Confirms the collection-level API shape is workable and the canonical-form output is expected.

**URLs:** [tick GitHub](https://github.com/juxt/tick), [tick docs](https://juxt.github.io/tick/).

## 4. Half-open convention survey

Systems using half-open `[start, end)`:

* PostgreSQL ranges (default `[)` canonical form for discrete types)
* Python `range`, slice semantics, `portion` (optional but idiomatic), pandas `IntervalIndex` (configurable)
* Rust `std::ops::Range`
* Joda-Time `Interval`
* Luxon `Interval`
* ICU / CLDR date ranges
* SQL:2011 PERIODs (by convention, not mandated)
* Tempo

Systems using closed `[start, end]`:

* Older mathematical texts and many academic papers on Allen's algebra (but Allen himself was agnostic on closure)
* Some date-range library APIs aimed at end users ("from Jan 1 to Jan 31 inclusive") — often a presentation choice over a storage choice

The half-open convention dominates modern software for exactly the reason stated in Tempo's CLAUDE.md: adjacent intervals concatenate without overlap or gap, and `length = end - start` works without a `+1` correction. No credible modern system would choose closed upper bounds as the default today.

## 5. Coalescing — canonical algorithm

The standard sweep-line merge (works for any total order on the lower bound):

```
def coalesce(intervals):
    if empty: return []
    sort intervals by lower bound (tie-break by upper bound)
    result = [first]
    for each next interval:
        prev = result[-1]
        if next.lower <= prev.upper:          # overlap or adjacency
            prev.upper = max(prev.upper, next.upper)
        else:
            result.append(next)
    return result
```

Complexity: O(n log n) sort + O(n) scan. This is the algorithm used by LeetCode "Merge Intervals" (#56), PostgreSQL multirange construction (documented behaviour matches), `portion`'s internal `_mergeable` pass, Haskell `Data.IntervalSet`, and basically every interval-set library. There is no more efficient general algorithm without additional structure (e.g., a persistent interval tree for incremental insert).

For half-open intervals specifically, the overlap test is `next.lower < prev.upper` (strict) if you want to keep truly-disjoint intervals separate, or `next.lower <= prev.upper` if you want to merge adjacent (meeting) intervals too. Tempo needs to decide which: PostgreSQL multiranges **do not** merge adjacent ranges by default (you can have `{[1,5), [5,10)}` as two ranges in a multirange); `portion` **does** merge adjacent closed intervals. Given Tempo's half-open convention and the "adjacent intervals concatenate cleanly" principle from CLAUDE.md, adjacency-merging is the more natural default — but both behaviours are useful and both should be available.

**URLs:** [Sweep Line for Intervals (USACO Guide)](https://usaco.guide/plat/sweep-line), [LeetCode 56 solution](https://neetcode.io/solutions/merge-intervals).

## 6. Recommendations

1. **Mimic PostgreSQL multirange as the conceptual model.** Introduce a `Tempo.IntervalSet` (or `Tempo.Multirange`, or similar) type that stores a sorted list of non-overlapping half-open intervals, auto-coalescing on construction. Pair-level ops return a single `Tempo.Interval` or error; list-level ops return an `IntervalSet`. Offer `union/2`, `intersection/2`, `difference/2`, `complement/1`, `contains?/2`, `overlaps?/2`, `adjacent?/2`, `merge/2` (range_merge — smallest span containing both), and a coalesce/normalise entry point that accepts an arbitrary list. This is the minimum viable surface.

2. **Do not depend on `interval` (the hex package).** It's a good reference but its "explicit bounds per interval" model conflicts with Tempo's "precision determines the span" model, and it doesn't have the multirange concept Tempo needs. Reimplement and credit it in docs. Do study its module structure and naming.

3. **Use the sweep-line coalesce as the canonical algorithm** (sort by lower bound, single pass, O(n log n)). Ship **two coalescing behaviours** via an option: `merge_adjacent: true` (default — `[a,b)` and `[b,c)` collapse to `[a,c)`, consistent with Tempo's half-open / concatenate-cleanly design) and `merge_adjacent: false` (overlap-only, matching PostgreSQL multirange).

4. **Use Allen's 13 relations (already in `Tempo.Comparison`) as the dispatch table for pair-level set ops**, rather than re-deriving case analysis in each function. Intersection, union-possible-as-single-interval, and difference each partition the 13 relations cleanly. This keeps the set-op code short and the correctness argument easy.

5. **Before writing code, materialise the implicit-to-explicit span conversion that CLAUDE.md flags as a near-term todo.** Every set-op function should call that normaliser on entry, so `union(~d"2026-01", ~d"2026-02-01..2026-03-01")` works without duplicating the precision-aware logic in each op. This is the "bridge" the CLAUDE.md describes, and it's the single most valuable piece of plumbing to land before union/intersection.

## Gaps and uncertainties in this research

* I did not read the PostgreSQL source for the exact multirange coalescing implementation. The documented semantics match the sweep-line description, but the precise handling of adjacency-merge, empty ranges, and bound-inclusivity edge cases should be verified against the C source (`src/backend/utils/adt/multirangetypes.c`) before Tempo makes final decisions.
* I did not verify whether `tick.alpha.interval` actually returns canonical-form collections or just does pairwise ops over a sequence. The "alpha, unmaintained" status means it's probably not worth deeper study.
* I could not confirm whether any major system uses Tempo's specific convention of *implying* the span from the precision of a single literal (e.g., `2026-01` = `2026-01-01..2026-02-01`). I believe this is genuinely novel as a primary API, but a longer lit review of calendar systems (ICU, CLDR, SAS, R's `lubridate`) could turn up precedent.
* I did not check Oracle / DB2 / SQL Server temporal implementations in detail beyond noting they implement SQL:2011 PERIODs. If cross-vendor SQL compatibility ever matters, those need a separate pass.
