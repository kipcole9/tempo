# Findings — "Models and Algorithms for Chronology" (Geeraerts, Levy & Pluquet, TIME 2017)

**Paper:** Gilles Geeraerts, Eythan Levy, Frédéric Pluquet, *Models and Algorithms for Chronology*, 24th International Symposium on Temporal Representation and Reasoning (TIME 2017), LIPIcs vol. 90, article 13. Open access, DOI [10.4230/LIPIcs.TIME.2017.13](https://doi.org/10.4230/LIPIcs.TIME.2017.13).

**Why it matters for Tempo:** this is, formally, the model and algorithms behind `Tempo.Network` and its STP solver — arrived at independently, peer-reviewed, and proven to run in polynomial time. Reading it tells us (a) Tempo's constraint-network layer sits on solid, published foundations, (b) exactly which problems are cheap and which are impossible in this class, and (c) a hand-verified worked example we can use as a regression fixture (see "Validation" below — done).

This is the earlier, coarser companion to the paper already in `papers/` — Levy, Geeraerts, Pluquet, Piasetzky & Fantalkin, *Chronological networks in archaeology: A formalised scheme*, JAS (2020) — which the same authors extended into the `ChronoLog` tool. The two share the "ChronoLand" running example with slightly different numbers (see the two fixtures in `test/tempo/network/chronoland_test.exs`).

## 1. The model

Fix a finite set of **periods** `P` (eras, strata, reigns, ceramic phases…). The variables are the period endpoints plus a zero:

```
V(P) = { z₀ } ∪ { beg(p), end(p) : p ∈ P }        z₀ ≡ 0   (origin of time)
```

A **chronology** `C` assigns each period an integer interval `[aₚ, bₚ]` — its start and end dates. Dates are integers (years by default, any granularity in principle).

A **constraint** is a finite **conjunction of atomic difference constraints** `x − y ~ c`, with `x, y ∈ V(P)`, `c ∈ ℤ ∪ {+∞}`, `~ ∈ {≤, ≥, =}`. **No disjunction, no negation.** The semantics `⟦φ⟧` is the set of chronologies satisfying every conjunct.

This is exactly the **Simple Temporal Problem (STP)**. The paper says so directly: the class was studied by Shostak, it is "a special case of *zones*" from timed-automata theory, and its normal form (every pair reduced to a single `x − y ≤ c`, `(2n+1)²` constraints) "corresponds to the **Difference Bound Matrix**." Tempo's network representation is a DBM.

## 2. Constraint vocabulary → difference-constraint encoding

Every archaeological relation the paper supports reduces to a handful of difference-constraint pairs. This is the checklist to audit Tempo's relation encodings against:

| Relation | Meaning | Encoding |
|---|---|---|
| Terminus post quem | lower bound `B` on a start/end | `beg(p) ≥ B` / `end(p) ≥ B` |
| Terminus ante quem | upper bound `B` | `beg(p) ≤ B` / `end(p) ≤ B` |
| Date range | TPQ ∧ TAQ | `B₁ ≤ beg(p) ≤ B₂` |
| Duration `[d, D]` | period length bounds | `d ≤ end(p) − beg(p) ≤ D` |
| **Sequence** (p abuts q) | p ends exactly where q starts | `end(p) − beg(q) = 0` |
| **Contemporaneity** | non-empty overlap | `end(p) ≥ beg(q) ∧ end(q) ≥ beg(p)` |
| **Starts during** | `beg(p) ∈ [beg(q), end(q)]` | `beg(p) ≥ beg(q) ∧ beg(p) ≤ end(q)` |
| **Ends during** | `end(p) ∈ [beg(q), end(q)]` | `end(p) ≥ beg(q) ∧ end(p) ≤ end(q)` |
| **Inclusion** (p within q) | | `beg(p) − beg(q) ≥ 0 ∧ end(p) − end(q) ≤ 0` |
| well-formedness | every period starts before it ends | `beg(p) ≤ end(p)` for all p |

**The boundary of the class — worth stating in Tempo's docs.** The one relation they *cannot* express is **non-contemporaneity** ("p is before q **or** q is before p"), because it needs disjunction. Adding disjunctions turns STP into the Disjunctive Temporal Problem, which is NP-hard. Any Tempo `Network` API that lets you assert a hard "these are disjoint / p strictly before q" constraint is stepping outside the polynomial STP class — either it forces one branch (still STP) or it is a genuinely harder problem. Tempo's crisp interval-set algebra handles disjointness fine at the *value* level; the caveat is specifically about the *constraint-network* level.

## 3. The four problems and their algorithms

Build a directed weighted graph `G_φ`: one vertex per variable, an edge `x → y` of weight `c` for each atomic `x − y ≤ c`. Then every question reduces to shortest paths.

| Problem | Result | Tempo op |
|---|---|---|
| **Satisfiability** — is `⟦φ⟧ ≠ ∅`? | **Thm 3:** satisfiable **iff `G_φ` has no negative cycle** | `Solver.consistent?/1` |
| **Tightening** — the tightest equivalent constraint | **Thm 4:** `φ′ = ⋀ₓ,ᵧ  x − y ≤ sp_G(x, y)` — the **all-pairs shortest paths** | `Solver.tighten/1` |
| **Sure-contemporaneity** — do `p₁, p₂` *certainly* overlap (∀ valid dates)? | **Prop 7** (on a *tightened* net): iff `sp(beg p₁, end p₂) ≤ 0` **and** `sp(beg p₂, end p₁) ≤ 0` — **constant time** | a "certainly overlaps" predicate |
| **Possible-contemporaneity** — *can* they overlap (∃ valid dates)? | **Prop 10** (on a tightened net): iff `sp(end p₂, beg p₁) ≥ 0` **and** `sp(end p₁, beg p₂) ≥ 0` — **constant time** | a "possibly overlaps" predicate |

**Complexity.** All four are polynomial in the number of periods. Tightening is Johnson's APSP, `O(|V|² log|V| + |V|·|E|)`, which also detects the negative cycle for free (so satisfiability is a by-product). After one tightening pass, each contemporaneity query is `O(1)`.

The takeaway pattern: **tighten once to the minimal network, then answer contemporaneity/ordering queries in constant time by reading shortest-path weights.** If Tempo recomputes anything per-query, Props 7 and 10 are the exact formulas to reduce to.

## 4. Mapping onto Tempo

| Paper construct | Tempo |
|---|---|
| Period (its `beg`/`end` variables) | `Network.add_period(id, opts)` |
| `end(p) − beg(q) = 0` (sequence) | `Network.add_sequence([p, q])` |
| starts-during / ends-during / inclusion / contemporaneity | `Network.add_relation(type, from, to)` |
| bounds (TPQ / TAQ / duration) | `add_period` `start:` / `end:` / `duration:` options |
| Difference-Bound-Matrix normal form | the network's internal STP representation |
| satisfiable ⇔ no negative cycle | `Solver.consistent?/1` |
| tightest constraint = APSP | `Solver.tighten/1` (returns per-period `earliest/latest_start/end`, `min/max_duration`) |
| sure-contemporaneity (Prop 7) | `Solver.certainly_contemporary?/3` |
| possible-contemporaneity (Prop 10) | `Solver.possibly_contemporary?/3` |
| three-valued contemporaneity | `Solver.contemporaneity/3` → `:certain` / `:possible` / `:impossible` |

## 5. Validation — Tempo reproduces their worked example

Their running example, **ChronoLand** (§1.2, Fig. 1–2): kings `K₁` then `K₂` reign in succession, both within 1200–1300 CE; `K₁`'s reign is at most 15 years, `K₂`'s is 30–100 years. Strata `S₁` (built under `K₁`) then `S₂` (destroyed under `K₂`) follow one another, each lasting 20–100 years; `S₁` starts during `K₁` and `S₂` ends during `K₂`.

Encoded in `Tempo.Network` and tightened, Tempo returns **exactly** the paper's Fig. 2 optimal bounds:

| Period | start | end | duration |
|---|---|---|---|
| K₁ | [1200, 1260] | [1200, 1270] | ≤ 15 |
| K₂ | [1200, 1270] | [1240, 1300] | [30, 100] |
| S₁ | [1200, 1260] | [1220, 1280] | [20, 80] |
| S₂ | [1220, 1280] | [1240, 1300] | [20, 80] |

Note the "retroaction" the paper highlights as the hard part of doing this by hand: `K₁`'s start and `K₂`'s end get refined by 10 years from the strata synchronisms, even though the strata had no absolute dates of their own. Tempo's shortest-path tightening captures this automatically. This is now a regression test in `test/tempo/network/chronoland_test.exs` (the "TIME 2017" fixture, alongside the JAS 2020 variant).

Their motivating query — **"did `K₁` build `S₂`?"** — is answered by the contemporaneity tools: there is **no** sure-contemporaneity between `K₁` and `S₂`, and in fact no possible-contemporaneity, so `K₁` cannot have built `S₂` (his ≤15-year reign can't span the ≥20 years separating the two strata's starts). This is the archaeological pay-off of Props 7/10 and a good target for Tempo's graded relations at the network level.

## 6. Positioning against Holst (the paper originally asked about)

This paper cites Holst (*Complicated relations and blind dating*, in Buck & Millard eds., *Tools for Constructing Chronologies*, Springer LNS 177, 2004) and places itself relative to it. Holst — like Sharon's generalised Harris-matrix schemes — targets a **feasible relative *sorting*** of archaeological features. That ordering problem is **NP-complete**, so those methods rely on heuristics, and they do not estimate an absolute time-frame. Geeraerts–Levy–Pluquet (and Tempo) instead compute **absolute *and* relative metric bounds** in **polynomial time**, because restricting to conjunctions of difference constraints stays inside STP.

So Holst belongs to the seriation/ordering tradition; Tempo sits with this paper in the metric-STP tradition. For Tempo's design purposes, this paper supersedes most of what one would want from Holst, and adds the algorithmic guarantees.

## 7. Actionable takeaways

1. **Tempo's `Network` + STP solver is on published, polynomial foundations** — this is the citation for it.
2. **Sure/possible contemporaneity are implemented** — `Solver.contemporaneity/3` (plus `certainly_contemporary?/3` and `possibly_contemporary?/3`) reads Props 7 & 10 directly as sign checks on the minimal network's shortest-path weights, on the closed-interval semantics matching `add_relation(:contemporary, …)`. The paper's "has K1 built S2?" is now a regression test returning `:impossible`.
3. **Document the STP boundary** — non-contemporaneity / hard "strictly before" as a network constraint needs disjunction and leaves the polynomial class.
4. **Fixtures** — the ChronoLand TIME 2017 bounds are now a regression test; the JAS 2020 variant and the ChronoLog case studies are already tested. Together they pin Tempo's solver to two independent published sources.
5. **Prior art to cite** — Geeraerts–Levy–Pluquet (TIME 2017), the JAS 2020 formalised scheme, and the `ChronoLog` tool. Tempo's differentiator is unifying this STP core with Allen's algebra, set operations, recurrence, and multi-calendar arithmetic in one library.
