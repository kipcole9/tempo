# Temporal formalisms and where Tempo fits

Tempo is a software library, but it sits on top of forty years of formal
work on how to reason about time. This guide is a short survey of the
main formalisms — Allen's interval algebra, the Vilain–Kautz point
algebra, the Allen–Hayes interval theory, and Grüninger & Li's bounded-
meeting ontology — and an honest account of which choices Tempo inherits,
which it rejects, and the one idea it adds.

If you only remember one thing: **the field splits on a single question —
is a *point* or an *interval* the primitive thing?** Tempo answers
"interval", and everything else follows.

## The four formalisms

### Allen's interval algebra (1983)

James Allen's *Maintaining Knowledge about Temporal Intervals* takes
**intervals as primitive** and defines **thirteen** jointly-exhaustive,
pairwise-disjoint relations between any two of them: `before`/`after`,
`meets`/`met-by`, `overlaps`/`overlapped-by`, `during`/`contains`,
`starts`/`started-by`, `finishes`/`finished-by`, and `equals`. There are
no points in the basic theory — an interval is an indivisible primitive,
and relations are stated directly between intervals.

Allen's algebra is the *lingua franca* of qualitative temporal
reasoning. Its catch is computational: reasoning over the **full** algebra
— networks of *disjunctive* constraints like "*a* is `before` **or**
`after` *b*" — is **NP-complete** in general.

### Vilain–Kautz: the point algebra (1986)

Vilain and Kautz make the opposite ontological choice: **points are
primitive**. Relations between points are just `{<, =, >}`. An interval
becomes an *ordered pair of endpoint points* `(start, end)` with
`start < end`, and any relation between two intervals reduces to a
conjunction of point-relations among the four endpoints.

The reward is **tractability**: reasoning in the point algebra is
polynomial (path-consistency suffices), where the full interval algebra
is not. The price is ontological — you have committed to instants as the
furniture of the world, and intervals are derived. The interval relations
expressible this way are the *pointizable* / *convex* subclass; later work
(Nebel & Bürckert's ORD-Horn class, 1995) mapped the exact tractable
boundary.

### Allen–Hayes: moments and points (1985 / 1989)

Allen and Hayes put the interval ontology on a rigorous first-order
footing. Remarkably, they axiomatise the entire algebra from a **single
primitive relation, `meets`** — all thirteen relations are derived from
it. Points are *not* primitive here either; they are **reconstructed** as
derived entities, in two flavours:

* **Moments** — intervals with no proper subinterval (atomic, but still
  intervals, not points).
* **Meeting-places** — a "point" is the place where one interval meets
  another, a Dedekind-cut-like construction, never a first-class object.

This is the deepest expression of the interval-first stance: even points
are made of intervals.

### Grüninger & Li: the bounded-meeting ontology (TIME 2017)

Grüninger and Li identify the first-order time ontology that is logically
synonymous with Allen's algebra and prove a representation theorem for its
models. Their `T_bounded_meeting` continues the interval-only lineage and
makes the exclusions explicit: **degenerate (zero-length) intervals and
points are not in the domain at all.** This is the ontology Tempo cites
and follows.

## The dividing line, at a glance

| Formalism | Primitive | Status of points | Reasoning cost |
|---|---|---|---|
| Vilain–Kautz (1986) | **points** | the primitives | polynomial |
| Allen (1983) | intervals + 13 relations | absent | full algebra NP-complete |
| Allen–Hayes (1989) | intervals + `meets` | *derived* (moments, meeting-places) | first-order theory |
| Grüninger–Li (2017) | intervals only | *excluded from the domain* | derives Allen's relations |

## Where Tempo fits

Tempo is a deliberate **synthesis across the divide**: an interval
ontology with a point-algebra engine, plus one new idea.

### Ontologically, Tempo is interval-only

There are no instants. Every value — a year, a date, a timestamp — *is*
a bounded interval, and degenerate intervals are excluded, exactly as
`T_bounded_meeting` prescribes. The library rejects empty intervals at
its boundary:

```elixir
# from == to is not a value in the domain
{:error, _} = Tempo.Interval.new(from: ~o"2026-01-01", to: ~o"2026-01-01")
```

The half-open `[from, to)` convention realises Hayes' open-connected
model — adjacent intervals **`meet`** at a shared boundary they don't
both contain, rather than overlapping at a shared point (Allen's original
closed-interval reading):

```elixir
Tempo.relation(~o"2022-W24", ~o"2022-W25")
#=> :meets
```

`Tempo.relation/2` returns Allen's thirteen relations directly; the
named predicates (`within?/2`, `overlaps?/2`, `adjacent?/2`) are just
human-readable unions of them.

### Computationally, Tempo is Vilain–Kautz

Under the hood, comparison projects every endpoint to a real number on a
single UTC frame (`Tempo.Compare.to_utc_seconds/1`) and orders intervals
by those endpoints — *precisely* the point-algebra reduction, used as an
engine beneath the interval ontology. The endpoints are points; the
domain is intervals.

This buys two things:

* **It sidesteps the intractability** that motivated Vilain–Kautz — but
  for a different reason than they did. Tempo's intervals are always
  *fully grounded* (concrete endpoints, never disjunctive "before-or-
  after" constraints), so it never enters the NP-hard qualitative-
  constraint regime. A relation query is a handful of constant-time
  endpoint comparisons, not constraint propagation. Tempo is an *algebra
  over concrete values*, not a constraint solver.

* **Cross-calendar and cross-zone comparison fall out for free**: project
  both operands' endpoints to the shared real-number frame and order
  them, regardless of calendar or zone.

### The new idea: resolution-indexed atomicity

Here is the element with no direct precedent in the formalisms above.
Tempo recovers the "instant" not as a primitive point, but as **the
interval of one unit at the value's *finest declared resolution*** — a
*moment* in Allen and Hayes' sense, but **relativised to representational
precision**:

```elixir
# A second-resolution timestamp is a one-second interval
{:ok, iv} = Tempo.from_elixir(~U[2022-07-04 14:30:45Z]) |> Tempo.to_interval()
Tempo.Interval.duration(iv)
#=> ~o"PT1S"
```

A day value materialises to a one-day interval, a microsecond value to a
one-microsecond interval. The width of the "atom" is determined by ISO
8601 *syntax*, not by an absolute smallest unit. Classical moments are
absolute atoms; Tempo's are resolution-relative. This is what lets the
library treat `2026`, `2026-01`, and `2026-01-15T10:30:45` as
first-class spans of different widths without ever inventing an
"uncertain instant" — the recurring failure mode catalogued in the
[falsehoods guide](falsehoods.md).

See the [interop guide](interop.md) for how this plays out when you
convert Elixir `Date`/`DateTime` values, and the
[enumeration semantics guide](enumeration-semantics.md) for how the
implicit span drives iteration.

## Summary

* Tempo takes the **interval-first** ontology of Allen–Hayes and
  Grüninger–Li (no instants, no degenerate intervals).
* It uses the **point-algebra** reduction of Vilain–Kautz as its
  computational engine (endpoints projected to a real UTC frame).
* Because its values are **fully grounded**, it gets the point algebra's
  tractability without inheriting the interval algebra's NP-hard
  constraint reasoning — it isn't a constraint solver.
* Its one novel move is **resolution-indexed atomicity**: an "instant" is
  the one-unit interval at the finest declared ISO 8601 resolution.

## Further reading

* J. F. Allen. *Maintaining Knowledge about Temporal Intervals.* CACM
  26(11), 1983.
* M. B. Vilain and H. A. Kautz. *Constraint Propagation Algorithms for
  Temporal Reasoning.* AAAI-86, 1986.
* J. F. Allen and P. J. Hayes. *Moments and Points in an Interval-Based
  Temporal Logic.* Computational Intelligence 5(3), 1989.
* B. Nebel and H.-J. Bürckert. *Reasoning about Temporal Relations: A
  Maximal Tractable Subclass of Allen's Interval Algebra.* JACM 42(1),
  1995.
* M. Grüninger and Z. Li. *The Time Ontology of Allen's Interval
  Algebra.* TIME 2017.

The accompanying paper, *Tempo: Intervals as the Primitive Datetime
Type* (`papers/time-2026/`), develops this positioning in full.
