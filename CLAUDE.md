# Tempo — Project Guidance

## Project objective

Tempo treats **date and time as intervals, not as instants**. Every value represents a bounded span on the time line, which means:

* We can **reduce and map** across intervals as first-class structures.

* We can **compare** intervals using [Allen's Interval Algebra](https://ics.uci.edu/~alspaugh/cls/shr/allen.html).

* We **never run the risk of invalid dates** because every value is a bounded interval — partial specifications like `2022Y` or `2022Y-11M` are intervals spanning the whole year or month, not uncertain instants.

### Next major milestone

Define **set operations on intervals**:

1. `union/2` and `intersection/2` on a pair of intervals (first).

2. Extend those operations to **lists of intervals**, including coalescing overlapping intervals into a canonical, non-overlapping form.

All subsequent work (difference, symmetric difference, containment queries, etc.) builds on these primitives.

## Architecture — implicit vs explicit spans

Every Tempo value is a span on the time line. Spans come in two forms and the distinction matters for iteration, comparison, and set operations.

### Implicit span

A single ISO 8601 datetime **is** an interval. Its span runs from the stated datetime to the same datetime incremented by one unit **at the next-higher-precision-that-is-not-defined**. For example:

* `2026` → `2026-01-01 .. 2027-01-01` (year precision, span of one year)

* `2026-01` → `2026-01-01 .. 2026-02-01` (month precision, span of one month)

* `2026-01-15` → `2026-01-15 .. 2026-01-16` (day precision, span of one day)

* `2026-01-15T10` → `2026-01-15T10:00 .. 2026-01-15T11:00` (hour precision, span of one hour)

Map and reduce on implicit spans is already implemented. The iteration unit is the **next-higher-precision below what is stated** — e.g., iterating over `2026-01` yields days, iterating over `2026` yields months (or weeks, depending on calendar).

### Explicit span

An explicit span is a pair of datetimes written with a range operator, such as `2026-01-01..2026-02-01`. It is always iterated at **its own highest precision** — the precision of the boundaries. Iterating `2026-01-01..2026-02-01` yields days, not months.

### Half-open convention

**Every span is inclusive of the first boundary and exclusive of the last boundary** — `[first, last)`. This is deliberate, not incidental. It:

* Makes map/reduce work uniformly regardless of the iteration precision.

* Makes adjacent spans concatenate cleanly: `[a, b)` followed by `[b, c)` is exactly `[a, c)` with no overlap or gap.

* Matches the implicit-span semantics above (`2026-01` ends just before `2026-02-01`, not on it).

Any new span, interval, comparison, or set-operation code **must honour this convention**. Code that treats the upper bound as inclusive is a bug.

### Planned: explicit-span conversion

A near-term todo is to materialise an implicit span into its explicit form — i.e., convert `2026-01` into `2026-01-01..2026-02-01`. This normalisation is the bridge that will let set operations (union/intersection, coalescing) work uniformly whether the caller supplied implicit or explicit spans.

## Reference documents

The following documents are **critical** when working on this project. Consult them whenever behaviour, syntax, or semantics need to be verified — do not guess.

* **ISO 8601 standards** — the canonical PDFs live in `~/Documents/Development/iso_standards/`. These are the source of truth for ISO 8601 Part 1 (date/time representations) and Part 2 (extensions), which Tempo implements.

* **IETF draft-ietf-sedate-datetime-extended-09 (IXDTF)** — <https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html#name-format-of-extended-informat>. Defines the extended information suffix syntax (`[zone]`, `[u-ca=calendar]`, `[key=value]`, critical `!` flag) parsed by `Tempo.Iso8601.Tokenizer.Extended`.

* **Allen's Interval Algebra** — <https://ics.uci.edu/~alspaugh/cls/shr/allen.html>. The 13 base relations (`precedes`, `meets`, `overlaps`, `finished_by`, `contains`, `starts`, `equals`, and their inverses, plus `preceded_by`) used by `Tempo.Comparison` when comparing intervals.
