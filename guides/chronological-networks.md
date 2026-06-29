# Chronological networks

*For historians and archaeologists — no programming background assumed.*

A chronology is rarely a list of fixed dates. It is a **web of relationships**: a king reigns before another, a stratum is built during a reign, a pottery style overlaps the next, an inscription gives a "no earlier than". Tempo lets you write that web down as a **chronological network**, check it for contradictions, and compute the tightest dates each entity can possibly take.

This implements the ChronoLog scheme of Levy, Geeraerts, Pluquet, Piasetzky and Fantalkin, *"Chronological networks in archaeology: A formalised scheme"* (*Journal of Archaeological Science*, 2020), as a Tempo library layer (`Tempo.Network`).

## 1. Your chronology is a network

Three kinds of thing make up a network:

* **Periods** — the things with a beginning and an end: a reign, an era, the life of a stratum or a pottery style.

* **Sequences** — periods that follow one another with no gap: each one ends exactly where the next begins.

* **Relations** — everything you know that ties two periods together: "is contemporary with", "is included in", "starts during", "ends at least 20 years before", and so on.

You state what you know. Tempo works out what that *implies*.

## 2. Stating what you know

Dates and durations are ordinary Tempo values, written with the `~o` sigil: a year is `~o"1200Y"` (`~o"-664Y"` for BCE), a precise day `~o"1200-06-15"`, a duration `~o"P20Y"`. A period's start, end, and duration are each stated independently, and each can be exact, one-sided, a range, or simply unknown:

```elixir
import Tempo.Sigils
alias Tempo.Network

network =
  Network.new()
  # "King K1's reign began no earlier than 1200 and lasted at most 10 years."
  |> Network.add_period(:k1, name: "King K1", start: {:not_before, ~o"1200Y"}, duration: {:at_most, ~o"P10Y"})
  # "King K2's reign ended by 1300 and lasted at least 35 years."
  |> Network.add_period(:k2, name: "King K2", end: {:not_after, ~o"1300Y"}, duration: {:at_least, ~o"P35Y"})
```

The vocabulary mirrors how an archaeologist actually speaks:

| You want to say | You write |
|---|---|
| "exactly 664 BCE" | `start: ~o"-664Y"` |
| "no earlier than 1200" | `start: {:not_before, ~o"1200Y"}` |
| "no later than 1300" | `end: {:not_after, ~o"1300Y"}` |
| "between 1200 and 1250" | `start: {~o"1200Y", ~o"1250Y"}` |
| "lasted at least 20 years" | `duration: {:at_least, ~o"P20Y"}` |
| "lasted 20 to 100 years" | `duration: {~o"P20Y", ~o"P100Y"}` |
| "circa 720 (`~720`)" | `start: ~o"~720Y"` *(the `~` is kept as a note; it does not move the date)* |

A bare integer year (`1200`, `-664`) and an ISO 8601 string are also accepted as shorthands for year-grained work, but the `~o` form is the idiom — and it is what every bound is stored and returned as.

> *"K1 began no earlier than 1200 and reigned at most 10 years; K2 ended by 1300 and reigned at least 35."*

## 3. Building ChronoLand

The paper's worked example. In the Kingdom of ChronoLand, kings **K1** then **K2** reigned in succession, both between 1200 and 1300 CE; K1 reigned at most 10 years and K2 at least 35. Two strata follow one another: **S1** (built by K1, who founded the city) and **S2** (destroyed by fire under K2). Each stratum lasted 20 to 100 years.

```elixir
import Tempo.Sigils
alias Tempo.Network

chronoland =
  Network.new()
  |> Network.add_period(:k1, name: "King K1", start: {:not_before, ~o"1200Y"}, duration: {:at_most, ~o"P10Y"})
  |> Network.add_period(:k2, name: "King K2", end: {:not_after, ~o"1300Y"}, duration: {:at_least, ~o"P35Y"})
  |> Network.add_period(:s1, name: "Stratum S1", duration: {~o"P20Y", ~o"P100Y"})
  |> Network.add_period(:s2, name: "Stratum S2", duration: {~o"P20Y", ~o"P100Y"})
  |> Network.add_sequence([:k1, :k2])
  |> Network.add_sequence([:s1, :s2])
  |> Network.add_relation(:starts_during, :s1, :k1)
  |> Network.add_relation(:ends_during, :s2, :k2)
```

> *"The kings reign in succession, and so do the strata. Stratum S1 starts during King K1's reign; Stratum S2 is destroyed — ends — during King K2's."*

First, is it even possible? **Consistency** asks whether any assignment of dates satisfies everything at once:

```elixir
Tempo.Network.Solver.consistent?(chronoland)
#=> true
```

## 4. Reading the answer

**Tightening** computes, for every period, the narrowest start, end, and duration the network allows. Anything outside those bounds would break a constraint; anything inside is still possible.

```elixir
{:ok, solved} = Tempo.Network.Solver.tighten(chronoland)

solved.periods[:k2].earliest_end
#=> ~o"1240Y"
```

Every bound comes back as a Tempo value. The strata, which had *no dates at all* as input, now have them — derived purely from the relations:

| Period | Start | End | Duration |
|---|---|---|---|
| King K1 | 1200 – 1260 | 1200 – 1265 | ≤ 10 |
| King K2 | 1200 – 1265 | 1240 – 1300 | 35 – 100 |
| Stratum S1 | 1200 – 1260 | 1220 – 1280 | 20 – 80 |
| Stratum S2 | 1220 – 1280 | 1240 – 1300 | 20 – 80 |

The bounds you typed in are **input**; the ones Tempo worked out are **computed**. For example, the duration of each stratum tightened from "20–100" to "20–80", because the whole dynasty is too short to hold a longer one.

### The trace — *why* a bound holds

Every computed bound can be explained. A **trace** is the chain of constraints that forces it — the same reasoning an archaeologist would write out by hand:

```elixir
{:ok, trace} = Tempo.Network.Solver.trace(chronoland, {:end, :k2}, bound: :earliest)
trace.prose
```

> King K1 starts no earlier than 1200 ⇒ the start of King K1 ≥ 1200; Stratum S1 starts during King K1 ⇒ the start of Stratum S1 ≥ 1200; Stratum S1 lasts at least 20 years ⇒ the end of Stratum S1 ≥ 1220; Stratum S1 immediately precedes Stratum S2 ⇒ the start of Stratum S2 ≥ 1220; Stratum S2 lasts at least 20 years ⇒ the end of Stratum S2 ≥ 1240; Stratum S2 ends during King K2 ⇒ the end of King K2 ≥ 1240.

No hidden assumptions, no "rule of thumb" — every step names the input it rests on. If a colleague disputes the conclusion, they can point at exactly which input they reject.

## 5. Testing a hypothesis

Because consistency is a one-line question, you can *test ideas*. Could King K1 have also built Stratum S2? Add the claim and ask:

```elixir
hypothesis = Tempo.Network.add_relation(chronoland, :starts_during, :s2, :k1)
Tempo.Network.Solver.consistent?(hypothesis)
#=> false
```

The network says **no**: if S2 had begun during K1's reign, that reign would have had to contain the whole of S1 *and* the start of S2 — at least 20 years — which exceeds K1's 10-year maximum. A conclusion that was far from obvious by eye.

## 6. When you don't need a network

A network earns its keep when something is *uncertain* or the structure is *not a simple line*. When neither is true — one anchor, exact durations, plain succession — you don't need it at all. You can just chain intervals.

The Egyptian 26th dynasty (after Kitchen 2000) is six reigns in succession with known lengths, anchored at Psammetichus I's accession in 664 BCE. Each reign runs from its accession to its accession plus its length, and the next begins where the last ended:

```elixir
import Tempo.Sigils

reigns = [
  {"Psammetichus I", ~o"P54Y"},
  {"Necho II", ~o"P15Y"},
  {"Psammetichus II", ~o"P6Y"},
  {"Apries", ~o"P19Y"},
  {"Amasis II", ~o"P44Y"},
  {"Psammetichus III", ~o"P1Y"}
]

{reign_spans, _dynasty_end} =
  Enum.map_reduce(reigns, ~o"-664Y", fn {_name, length}, accession ->
    abdication = Tempo.Math.add(accession, length)
    {Tempo.Interval.new!(from: accession, to: abdication), abdication}
  end)
```

`reign_spans` is now the six reigns as intervals (Psammetichus I is `~o"-664Y/-610Y"`, and so on). Because Tempo's intervals are half-open, the consecutive reigns abut exactly, so collapsing them yields the dynasty as one span:

```elixir
reign_spans |> Tempo.IntervalSet.new!() |> Tempo.IntervalSet.coalesce()
#=> #Tempo.IntervalSet<[~o"-664Y/-525Y"]>
```

> *"Six reigns, each starting where the last ended, collapse to a single 139-year dynasty from 664 to 525 BCE."* No network, no solver — just addition and the half-open convention.

A network would give the identical answer, but it adds nothing here. Reach for `Tempo.Network` the moment a length becomes a *range*, a relation is anything other than succession, or you need to propagate from an anchor that isn't first — exactly the ChronoLand case in §3–5.

## 7. Uncertainty, honestly

* **Qualifiers vs bounds.** An EDTF qualifier such as `~720` ("circa") is carried as a *note* on the period; it does not silently widen a date. If you mean "720 give or take a decade", say so with a range (`{710, 730}`). Keeping the two separate stops a vague "circa" from quietly doing arithmetic.

* **Absolute vs floating.** A period with no tie to a calendar date is *floating*: its duration and its order relative to its neighbours are known, but not its position in absolute time. Tempo handles both in one network — a floating sub-sequence inherits absolute dates the moment any one of its members is anchored.

* **Regional sequences.** Where two regions' phases overlap rather than line up (as in Coldstream's Greek Geometric pottery), model each region as its own sequence and join them with `:overlaps` or `:contemporary` relations, rather than forcing one master sequence.

## 8. Sharing

Every period boundary is an ordinary Tempo value, so it round-trips through ISO 8601 / EDTF for exchange with other tools:

```elixir
Tempo.to_iso8601(solved.periods[:psammetichus_i].earliest_start)
#=> "-664Y"
```

## Reference

Levy, E., Geeraerts, G., Pluquet, F., Piasetzky, E., & Fantalkin, A. (2020). Chronological networks in archaeology: A formalised scheme. *Journal of Archaeological Science*, 105225. <https://doi.org/10.1016/j.jas.2020.105225>. The ChronoLog software is at <http://chrono.ulb.be>.
