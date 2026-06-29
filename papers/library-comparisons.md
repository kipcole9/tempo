# Tempo vs. other Allen-interval-algebra implementations

A comparison of Tempo with three other implementation lineages: Haskell's `interval-algebra`, Rust's `allen-intervals` (with brief notes on `interavl` and `intervallum`), and Prolog interval-reasoning packages (ETALIS, RTEC). The goal is to identify (a) where Tempo's scope is unusually broad, (b) where the other libraries are deeper than Tempo on specific axes, and (c) what Tempo might learn from them.

## TL;DR

Tempo is the only library in this group that integrates **Allen's algebra + ISO 8601 + IXDTF + multi-calendar arithmetic + time-zone projection + set operations** into a single value type. The other libraries each occupy a much narrower point in the design space:

* The Haskell, Rust, and Prolog libraries are **pure Allen** — abstract intervals over `Ord` point types, no calendar / zone / format support.
* The Rust ecosystem also has interval-tree libraries (`interavl`) and integer set-operation libraries (`intervallum`), but they don't claim Allen-algebra purity.
* The Prolog ecosystem (ETALIS, RTEC) puts Allen relations inside event-calculus / stream-reasoning systems — the interval algebra is one component of a larger reasoning engine.

What Tempo could learn from the others, ordered by ease of adoption:

1. **Axiom property tests.** Haskell's library has explicit property tests verifying compliance with Allen-Hayes (1987). Tempo should add property tests that verify the 13 relations satisfy the bounded-meeting axioms.
2. **Typeclass-style abstraction.** Haskell's `Intervallic` typeclass lets users attach Allen-algebra semantics to their own data structures without forcing them to copy values into a library type. A Tempo `Intervallic` protocol could do the same.
3. **Explicit discrete vs. continuous domain marker.** Rust's `allen-intervals` distinguishes integer (exclusive-end, "meets" at shared endpoint) from floating-point (inclusive-end, "meets" at infinitesimal touch) domains. Tempo is implicitly continuous; making this explicit would head off a reviewer question.
4. **Interval-tree backing store for large sets.** Rust's `interavl` shows that interval trees give millions-to-billions of stabbing queries per second. For large `IntervalSet`s (calendars with thousands of events), Tempo's sort+coalesce could be supplemented by an interval-tree internal representation.

## Library-by-library

### Haskell — `interval-algebra` (Hackage)

The most mature pure-Allen library in the comparison. Maintained, well-documented, with explicit axiom-compliance testing.

* **Data model:** `Interval a` wraps `(a, a)` (pair of points). Empty intervals are *rejected by the type* — "Allen's interval relations cannot be defined for such intervals." Mirrors Tempo's recently-tightened `Interval.new/1` rejection of `from == to`.
* **Typeclasses:** `Iv` (the 13 relations), `PointedIv` (cast to canonical `Interval`), `SizedIv` (construct and manipulate), `Intervallic` (data structures containing intervals).
* **Naming convention:** `starts` / `contains` for generalised relations, `ivStarts` / `ivContains` for class-specific variants. This is a slightly unusual API choice that probably isn't worth copying.
* **Theoretical basis:** explicitly cites Allen 1983 and Allen-Hayes 1987/1989. Includes axiom tests for compliance.
* **What it doesn't have:** no set operations (union, intersection, difference), no time-zone or calendar support, no ISO 8601 — abstract over `Ord` instances.

Source: <https://hackage.haskell.org/package/interval-algebra>

### Rust — `allen-intervals` (crates.io)

A focused Allen-algebra implementation, MPL-2.0 licensed, with first-class handling of the discrete vs. continuous domain distinction.

* **Data model:** Several interval kinds — `Interval`, `IntervalFrom` (`a..`), `IntervalTo` (`..b`), `IntervalFull` (`..`). Discrete domain (integers) uses exclusive end bounds; continuous domain (floats) uses inclusive bounds. Tempo's half-open `[from, to)` matches the discrete-domain convention.
* **Non-emptiness as a type:** `NonEmpty<T>` wrapper required because "Allen's algebra applies exclusively to non-empty intervals." Same conclusion as Haskell and as Tempo's recent change.
* **Relations:** all 13 as separate traits (`Precedes`, `Meets`, `Overlaps`, `Starts`, `Contains`, `Finishes`, `Equals`) each with forward and inverted methods. Inverse is paired with a relation via an `is_inverted` flag on the `Relation` enum.
* **Theoretical basis:** cites Allen 1983.
* **What it doesn't have:** set operations, time-zone or calendar support, ISO 8601 — abstract over standard comparison and bound operations.

Source: <https://docs.rs/allen-intervals>

### Rust — `interavl` (related, but interval-tree-focused)

Worth mentioning because it shows what a *performance-optimised* Allen-relation backend looks like.

* **Data model:** AVL-backed interval tree. Half-open intervals over any ordered key type.
* **Positioning:** Allen's algebra as a *capability* of the tree, not the primary value proposition. The crate is marketed as "an optimised interval tree for efficient interval stabbing."
* **Operations:** overlap detection, interval stabbing, membership lookup, subtree pruning for query optimisation. Millions to billions of keys per second per the documentation.
* **What it doesn't have:** same gaps as `allen-intervals` (no calendar/zone), plus it isn't trying to be Allen-pure — it's a data-structure library that happens to expose Allen relations.

Source: <https://docs.rs/interavl>

### Rust — `intervallum` (related, set-ops-focused)

Worth mentioning because it shows the *other* axis Tempo combines that purely-Allen libraries don't.

* **Data model:** `Interval` (pair of integers) plus `IntervalSet` (vector of intervals). Restricted to integer types.
* **Operations:** union, intersection, and other set operations — the focus of the library.
* **Allen relations:** not the primary surface. The library is a set-operation tool that happens to operate over intervals.
* **What it doesn't have:** floating-point or any non-integer point type, no calendar/zone, no Allen-algebra-as-API.

Source: <https://crates.io/crates/intervallum>

### Prolog — ETALIS

A complex-event-recognition engine with Allen interval algebra as one component. Runs on YAP, SWI, SICStus, XSB, tuProlog and LPA Prolog.

* **Data model:** intervals as Prolog terms — `interval(Start, End)` — typically constrained by CLP(FD) or CHR.
* **Operations:** all 13 Allen operators (`during`, `meets`, `starts`, `finishes`, …) plus event-pattern matching.
* **Positioning:** Allen relations are a substrate for *temporal event recognition* — detecting patterns like "A overlaps B and then C meets A" in event streams. The library is geared toward streaming temporal queries, not toward direct user-level interval comparison.
* **What it doesn't have:** time-zone or calendar support; pure Prolog data model.

Source: <https://github.com/sspider/etalis>

### Prolog — RTEC

Run-Time Event Calculus. Optimised for stream reasoning. Includes an Allen relations module among its utilities.

* **Data model:** event-calculus fluents and events; intervals derive from these.
* **Operations:** Allen relations in support of event-calculus reasoning, not as the primary API.
* **Positioning:** like ETALIS, more an event-recognition framework than an Allen-algebra library proper.

Source: <https://github.com/aartikis/RTEC>

### Other adjacent implementations

A non-exhaustive list of Allen implementations in other languages, for breadth:

* **Java** — `allentemporalrelationships` (jornfranke): the 13 relations plus path-consistency algorithm for temporal constraint propagation.
* **Python** — `pyintervals` (bartonip): Allen relations on Python `datetime`-backed intervals.
* **.NET** — `DotNetRanges` (DanielLoth): Allen-style range operations.
* **Ruby** — `Allens-Interval-Algebra` (AndrewClarke): the essential operators with some combinatorial-operator metaprogramming.

These mostly share the same shape: pair-of-points, abstract over comparable types, no calendar/zone awareness.

## Capability comparison

| Capability | Tempo | Haskell `interval-algebra` | Rust `allen-intervals` | Rust `interavl` | Rust `intervallum` | Prolog ETALIS / RTEC |
| ---------- | ----- | -------------------------- | ----------------------- | --------------- | ------------------ | -------------------- |
| All 13 Allen relations | ✓ | ✓ | ✓ | ✓ (as tree capability) | partial | ✓ |
| Named-predicate vocabulary (`within?`, `overlaps?`, `adjacent?`) | ✓ | partial | partial | — | — | — |
| Empty intervals rejected | ✓ (recently) | ✓ (by type) | ✓ (`NonEmpty<T>`) | n/a (tree) | — | — |
| Half-open `[from, to)` convention | ✓ | implicit | ✓ (discrete) | ✓ | — | varies |
| Set operations on intervals | ✓ (union/intersection/difference/complement/symmetric_diff) | — | — | — | ✓ | partial |
| Set operations on interval *sets* (coalesce, canonical form) | ✓ | — | — | — | ✓ | — |
| ISO 8601 + ISO 8601-2 parsing | ✓ | — | — | — | — | — |
| IXDTF (RFC 9557) support | ✓ | — | — | — | — | — |
| EDTF uncertainty markers | ✓ | — | — | — | — | — |
| Time-zone awareness (named zones via Tzdata) | ✓ | — | — | — | — | — |
| DST gap rejection at parse time | ✓ | n/a | n/a | n/a | n/a | n/a |
| DST fold disambiguation (RFC 9557 §4.5) | ✓ | n/a | n/a | n/a | n/a | n/a |
| Multi-calendar arithmetic (Gregorian, Hebrew, Islamic Civil, …) | ✓ | — | — | — | — | — |
| Recurrence rules (iCalendar RRULE) | ✓ | — | — | — | — | partial (events) |
| Partial-date materialisation (`~o"2026"` → year interval) | ✓ | — | — | — | — | — |
| Calendar-relative duration (`P1M` = one calendar month) | ✓ | — | — | — | — | — |
| Property tests verifying Allen / Allen-Hayes axioms | — | ✓ | partial | — | n/a | — |
| Typeclass / trait for user-defined "intervallic" types | partial | ✓ (`Intervallic`) | ✓ (`IntervalBounds`) | — | — | — |
| Interval-tree backing store for large sets | — | — | — | ✓ | — | — |
| Citation of Grüninger & Li's `T_{bounded_meeting}` ontology | ✓ (TIME 2027 paper) | — | — | — | — | — |

The cells that aren't checked for Tempo are the **interesting** ones — they're what the next four sections of this document discuss.

## What Tempo could learn

These are concrete suggestions, ordered from "trivially adoptable" to "would require design work."

### 1. Property tests for Allen / Allen-Hayes / bounded-meeting axioms

Haskell's `interval-algebra` includes axiom tests that mechanically verify the implementation satisfies Allen-Hayes (1987). For Tempo this is straightforward to add: a property-test module that generates random pairs of intervals and asserts the 13 relations are jointly exhaustive (exactly one holds), pairwise disjoint (no two hold), and that `inverse_relation(relation(a, b)) == relation(b, a)`. Could also verify the Sum Axiom of `T_{bounded_meeting}` (three chain-meeting intervals coalesce).

**Effort:** A few hours; uses StreamData or similar. **Reward:** Discharges one of the concrete weaknesses the convenor reviewer would flag in the TIME 2027 submission — "the realisation claim is asserted, not proven."

### 2. Typeclass / protocol for user-defined "intervallic" types

Haskell's `Intervallic` and Rust's `IntervalBounds` let users attach Allen-algebra semantics to their own data structures without copying values into the library's interval type. In Elixir terms: a `Tempo.Intervallic` protocol that requires `from/1` and `to/1` implementations. Then `Tempo.relation/2`, `Tempo.overlaps?/2`, etc. could accept any value that implements the protocol, not only `Tempo.Interval`. This would let a user with their own struct (e.g., `%Booking{check_in, check_out}`) participate in Tempo's set operations and Allen comparisons.

**Effort:** Modest; protocol definition plus dispatch in `Operations.align/3` and `Interval.relation/2`. **Reward:** Enables third-party data types without copying; reduces friction for adoption.

### 3. Explicit discrete vs. continuous domain marker

Rust's `allen-intervals` distinguishes the two cases by domain type: integers get exclusive ends and "meets at shared endpoint" semantics; floats get inclusive ends and "meets at infinitesimal touch" semantics. Tempo is implicitly continuous (gregorian-second projection is a real number) but treats intervals half-open in the discrete style. The two are consistent at second-resolution and finer, but a TIME reviewer might want this clarified. A documentation paragraph in the `Tempo.Interval` `@moduledoc` would suffice; a type-level marker would be over-engineering.

**Effort:** Documentation only. **Reward:** Pre-empts a reviewer question.

### 4. Interval-tree backing store for very large IntervalSets

Rust's `interavl` and similar tree-based libraries show that millions of stabbing queries per second are achievable. Tempo's current `IntervalSet` is a sorted, coalesced list — O(n log n) construction, O(log n) lookup via binary search for some operations, but O(n) for others. A user with a multi-year iCalendar feed (tens of thousands of events) would benefit from an interval-tree internal representation. This is purely an internal-representation change: the API stays identical.

**Effort:** Significant; would require an interval-tree implementation (or a dependency) and careful benchmarking. **Reward:** Concrete performance win for large set operations. Worth doing only if a real user reports the need.

### 5. Type-level pairing of relations with their inverses

Rust's `Relation` enum carries an `is_inverted: bool` so each relation and its inverse are the same value with a flag. Tempo currently uses 13 distinct atoms (`:precedes`, `:preceded_by`, …) and `inverse_relation/1` as a function. The atom-level form is more idiomatic for Elixir and easier to pattern-match on, so this is *not* worth adopting — but it's worth noting that the design space includes both.

**Effort:** Would be a breaking change. **Reward:** Marginal. **Recommendation:** Skip.

## What's unique to Tempo (and worth keeping)

The capabilities that distinguish Tempo from every other library in the comparison:

1. **Implicit-span semantics for ISO 8601 partial dates.** `~o"2026"` *is* the interval `[2026-01-01, 2027-01-01)` — not a "year value" that someone has to materialise via a helper. No other library treats partial ISO 8601 datetimes as first-class intervals.
2. **Multi-calendar arithmetic.** Hebrew, Islamic Civil, Persian, Coptic, etc., via Calendrical. All Allen relations and set operations work across calendars by projecting to the same UTC reference frame.
3. **DST handling via IXDTF offset.** DST gaps rejected at parse time, DST folds disambiguated by RFC 9557 §4.5 (offset is part of the string and round-trips). No other library in the comparison handles DST at all.
4. **Calendar-relative durations.** `P1M` is one calendar month (variable in days). `at_least?/2`, `shorter_than?/2` predicate vocabulary.
5. **Recurrence rules.** iCalendar RRULE expansion and back-projection.
6. **EDTF uncertainty.** `~o"2022~"` (approximately 2022), `~o"2022?"` (uncertain), `~o"156X"` (the 1560s).
7. **Predicate vocabulary as a design discipline.** Named predicates (`within?`, `adjacent?`, `contains?`) defined as specific subsets of Allen relations, so application code never falls back to relation-list pattern matching.
8. **Grüninger & Li ontological alignment.** The TIME 2027 paper positions Tempo as a software realisation of `T_{bounded_meeting}`. No other library in this comparison engages with the ontology literature at this depth.

None of the pure-Allen libraries can be a drop-in replacement for Tempo without re-implementing 80% of what Tempo does. Conversely, Tempo doesn't compete with the pure-Allen libraries on minimalism, type-safety in pure-functional settings, or raw query throughput.

## Summary

If a user asks "should I use Tempo or one of these libraries?":

* **Use Haskell `interval-algebra`** if you want a pure, axiom-tested Allen algebra over abstract `Ord` points in Haskell. Not relevant to Elixir users.
* **Use Rust `allen-intervals`** if you want a focused, no-dependency Allen-relation library for embedded or systems work where intervals are over integers or floats and no calendar/zone semantics are needed.
* **Use Rust `interavl`** if you have a large interval-set workload (overlap queries, stabbing) and need maximum throughput.
* **Use Rust `intervallum`** if you want integer-interval set operations (union/intersection) and don't need Allen relations.
* **Use ETALIS or RTEC** if you're doing complex-event recognition in Prolog and need Allen relations as part of a larger reasoning system.
* **Use Tempo** if you have date/time values in any of the senses humans actually use — partial dates, calendars, time zones, recurrences, durations, free-busy schedules, archaeological periods — and want set-theoretic operations on them with Allen-algebra semantics.

The libraries don't really compete; they cover different scopes. The principled adoption suggestions from the four-item list above (axiom property tests, intervallic protocol, discrete/continuous documentation, interval-tree backend) would each strengthen Tempo without changing its public surface.
