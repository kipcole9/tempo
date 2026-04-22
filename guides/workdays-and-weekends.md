# Working with Workdays and Weekends

Business-day queries are the most common reason developers reach for a date library beyond the standard library. "How many working days until the deadline?" "What's five business days from today?" "When does this invoice age out?" Tempo answers these with three primitives and a handful of `Enum` calls — no special business-day module required.

This guide works up from the primitives to the idiomatic compositions, then shows how to wrap them into a reusable helper if you find yourself writing the same shape repeatedly.

## The three primitives

All business-day queries in Tempo reduce to three capabilities the library already provides:

* **Build a window.** `Tempo.shift/2` (keyword-list duration arithmetic) and `%Tempo.Interval{from:, to:}` construct a bounded span to search over.

* **Narrow to workdays.** `Tempo.select(interval, :workdays)` returns a `%Tempo.IntervalSet{}` containing only the workdays inside the window — respecting the territory's weekend convention (Mon-Fri in most places, Fri-Sat in Saudi Arabia, Thu-Fri in some others).

* **Pick an element.** `Tempo.IntervalSet.to_list/1` produces a plain list of `%Tempo.Interval{}` values that `Enum.at/2`, `Enum.count/1`, `List.last/1`, `hd/1`, and friends operate on directly.

Every workday query below is a one-liner composition of these three.

## Core example — N business days from today

"Five business days from today" is the most-asked version of this question. Here it is end-to-end:

```elixir
today = ~o"2026-06-15"  # a Monday

window_end = Tempo.shift(today, week: 6)                  # generous window
window     = %Tempo.Interval{from: today, to: window_end}

{:ok, workdays} = Tempo.select(window, :workdays)

target =
  workdays
  |> Tempo.IntervalSet.to_list()
  |> Enum.at(5)
#=> %Tempo.Interval{from: ~o"2026Y6M22D", ...}
```

Read aloud: *"Build a window from today that's long enough to contain five workdays. Narrow it to just the workdays. Take the fifth one."* The convention here matches banking and SLA usage — today is day zero, so `Enum.at(5)` is "the fifth business day after today". If you want to count today as day one, use `Enum.at(n - 1)`.

The window needs to be generous enough to contain `n` workdays. Six weeks holds 30 workdays in any territory, and `Tempo.select/2` is fast enough that the oversize doesn't matter. The idiomatic way to size it is `Tempo.shift(today, week: n + 1)` — a week per five workdays plus one for good measure.

### Why the window matters

You may wonder why we can't just "walk forward from today until we've counted five workdays". The answer is Tempo's thesis: iteration is bounded by design. Every enumeration is over a finite span — there's no infinite stream of days to filter. The window makes the computation finite and the laziness unnecessary; `Tempo.select/2` returns the complete result, and `Enum.at/2` does the index lookup.

## Related queries

Every scheduling question you'd ask about business days is a small variation on the core pattern.

### Is today a business day?

```elixir
tempo
|> Tempo.day_of_week()
|> Kernel.in(1..5)     # 1 = Mon, 7 = Sun; M-F for en-US
#=> true or false
```

This is the fast path — no interval needed. For territory-aware weekend detection, use the selector:

```elixir
{:ok, set} = Tempo.select(tempo, :workdays, territory: :SA)
Tempo.IntervalSet.count(set) > 0
#=> true if `tempo` is a workday under Saudi Arabia's Fri/Sat weekend
```

### Next business day

```elixir
tomorrow  = Tempo.shift(today, day: 1)
window    = %Tempo.Interval{from: tomorrow, to: Tempo.shift(today, week: 2)}

{:ok, workdays} = Tempo.select(window, :workdays)

next_wd =
  workdays
  |> Tempo.IntervalSet.to_list()
  |> hd()
#=> Friday's next_wd is the following Monday.
```

Read aloud: *"Starting tomorrow, find the workdays in the next two weeks and take the first."* A two-week window is generous — the longest weekend in any territory is three days, so the first workday is always within a week.

### Business days between two dates

```elixir
window = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-29"}

{:ok, workdays} = Tempo.select(window, :workdays)
Tempo.IntervalSet.count(workdays)
#=> 10   (two full work weeks)
```

This is a direct `Enum.count/1` on the members. For inclusive/exclusive day-counting semantics, adjust the `from` and `to` endpoints — Tempo uses half-open `[from, to)` consistently, so a 14-day span (`2026-06-15` through `2026-06-28` inclusive) is `from: 15, to: 29`.

### Nth business day of month

```elixir
{:ok, workdays} = Tempo.select(~o"2026-06", :workdays)
members         = Tempo.IntervalSet.to_list(workdays)

first = hd(members).from                       #=> ~o"2026Y6M1D"
last  = List.last(members).from                #=> ~o"2026Y6M30D"
third = Enum.at(members, 2).from               #=> ~o"2026Y6M3D"
```

Passing a month-resolution Tempo value to `Tempo.select/2` is the cleanest form — the selector treats the implicit month-span as the search window. Read aloud: *"The workdays of June 2026 are these; take the first / last / third."*

## Territory-aware weekends

Weekend conventions vary by territory, and `:workdays` honours CLDR data:

```elixir
# en-US default: Mon–Fri workdays, Sat–Sun weekend.
Tempo.select(~o"2026-06", :workdays)

# Saudi Arabia: Sun–Thu workdays, Fri–Sat weekend.
Tempo.select(~o"2026-06", :workdays, territory: :SA)

# Iran: Sat–Wed workdays, Thu–Fri weekend.
Tempo.select(~o"2026-06", :workdays, territory: :IR)
```

The territory resolution chain (explicit option → IXDTF `[u-rg=XX]` suffix → locale's default) is identical to the one used elsewhere in Tempo — see the [set operations guide](./set-operations.md) for the full description.

## The `:workdays` selector is set-algebraic

`Tempo.select(window, :workdays)` is a specific case of a general pattern: narrow a span by predicate, get back a set you can operate on. Under the hood, `:workdays` is the complement of the `:weekend` selector within the window, and both are equivalent to explicit day-of-week filters:

```elixir
# These three produce the same IntervalSet for a given window:
Tempo.select(window, :workdays)
Tempo.select(window, [1, 2, 3, 4, 5], unit: :day_of_week)   # Mon..Fri by number
Tempo.select(window, [:monday, :tuesday, :wednesday, :thursday, :friday])
```

The benefit of naming a selector `:workdays` is that **the territory indirection lives in the name**. A hardcoded `[1..5]` would be wrong in Saudi Arabia. Using `:workdays` with `territory:` delegates that decision to CLDR.

Because the result is an `IntervalSet`, set operations compose naturally and preserve member identity. Three common patterns:

```elixir
# Workdays minus holidays — survivors keep their original member
# identity, each day distinct:
{:ok, net_workdays} = Tempo.difference(workdays, holidays)

# Workdays that overlap a specific window (filter, not trim):
{:ok, q2_workdays} = Tempo.intersection(workdays, ~o"2026-Q2")

# All workdays across territories — union preserves both sides'
# members so per-territory metadata survives:
{:ok, global}   = Tempo.union(us_workdays, de_workdays)
```

See the [set operations guide](./set-operations.md) for the distinction between **member-preserving** operations (`intersection`, `difference`, `union`) and their **instant-level** counterparts (`overlap_trim`, `split_difference`) — the former is what you want for event-list questions; the latter for covered-instant questions.

## Writing your own helper

If you find yourself writing the four-line `add_business_days` pattern repeatedly, wrap it once in a domain module:

```elixir
defmodule MyApp.BusinessDays do
  @moduledoc """
  Business-day arithmetic for MyApp's booking logic.

  Territory defaults to the app's CLDR locale; callers can
  override via the `territory:` option.
  """

  @doc """
  Add `n` business days to `from`.

  Today is day zero; `add(today, 1)` is tomorrow-if-workday else
  the next workday.
  """
  @spec add(Tempo.t(), pos_integer(), keyword()) ::
          {:ok, Tempo.t()} | {:error, term()}
  def add(from, n, opts \\ []) when n > 0 do
    window_end = Tempo.shift(from, week: n + 1)
    window = %Tempo.Interval{from: from, to: window_end}

    with {:ok, workdays} <- Tempo.select(window, :workdays, opts) do
      case workdays |> Tempo.IntervalSet.to_list() |> Enum.at(n) do
        nil -> {:error, :not_enough_workdays_in_window}
        interval -> {:ok, interval.from}
      end
    end
  end

  @doc "Is `tempo` a business day in the given territory?"
  @spec business_day?(Tempo.t(), keyword()) :: boolean()
  def business_day?(tempo, opts \\ []) do
    case Tempo.select(tempo, :workdays, opts) do
      {:ok, set} -> Tempo.IntervalSet.count(set) > 0
      _ -> false
    end
  end

  @doc "Count business days in `[from, to)`."
  @spec count_between(Tempo.t(), Tempo.t(), keyword()) :: non_neg_integer()
  def count_between(from, to, opts \\ []) do
    window = %Tempo.Interval{from: from, to: to}
    {:ok, workdays} = Tempo.select(window, :workdays, opts)
    Tempo.IntervalSet.count(workdays)
  end
end
```

A hundred lines of helpers for the three or four queries your app actually makes is usually the right shape — these are domain concerns and belong in your app, not in the library. Tempo intentionally stops at the primitives so you aren't constrained by Tempo's opinions on "what counts as a business day" (includes holidays? specific territories? calendar-fiscal-year quarter-end adjustments?). You make those choices; Tempo provides the set algebra.

## Related reading

* [Holidays — planning with a real holiday calendar](./holidays.md) — fetch an ICS holiday feed, compose it with the `:workdays` selector for territory-aware scheduling.
* [Cookbook](./cookbook.md) — recipe-format examples for more scheduling patterns.
* [Set operations](./set-operations.md) — union, intersection, difference, and the territory resolution chain.
* [Scheduling](./scheduling.md) — bounded enumeration, wall-clock-vs-UTC, floating vs zoned.
* [Enumeration semantics](./enumeration-semantics.md) — how iteration works on Tempo values and IntervalSets.
