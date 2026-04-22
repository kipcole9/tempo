# Working with Workdays and Weekends

Business-day queries are the most common reason developers reach for a date library beyond the standard library. "How many working days until the deadline?" "What's five business days from today?" "When does this invoice age out?" Tempo answers these with three primitives and a handful of `Enum` calls — no special business-day module required.

This guide works up from the primitives to the idiomatic compositions, then shows how to wrap them into a reusable helper if you find yourself writing the same shape repeatedly.

## The three primitives

All business-day queries in Tempo reduce to three capabilities the library already provides:

* **Build a window.** `Tempo.shift/2` (keyword-list duration arithmetic) and `%Tempo.Interval{from:, to:}` construct a bounded span to search over.

* **Narrow to workdays.** `Tempo.workdays/1` returns a territory-aware day-of-week selector — `Tempo.workdays(:US)` is Mon-Fri, `Tempo.workdays(:SA)` is Sun-Thu. `Tempo.select(interval, Tempo.workdays(:US))` returns a `%Tempo.IntervalSet{}` of just the workdays inside the window. The companion `Tempo.weekend/1` is the complement — together they partition the seven days of the week.

* **Pick an element.** `Tempo.IntervalSet.to_list/1` produces a plain list of `%Tempo.Interval{}` values that `Enum.at/2`, `Enum.count/1`, `List.last/1`, `hd/1`, and friends operate on directly.

Every workday query below is a one-liner composition of these three.

## Core example — N business days from today

"Five business days from today" is the most-asked version of this question. Here it is end-to-end:

```elixir
today = ~o"2026-06-15"  # a Monday

window_end = Tempo.shift(today, week: 6)                  # generous window
window     = %Tempo.Interval{from: today, to: window_end}

{:ok, workdays} = Tempo.select(window, Tempo.workdays(:US))

target =
  workdays
  |> Tempo.IntervalSet.to_list()
  |> Enum.at(5)
#=> %Tempo.Interval{from: ~o"2026Y6M22D", ...}
```

Read aloud: *"Build a window from today that's long enough to contain five workdays. Narrow it to just the US workdays. Take the fifth one."* The convention here matches banking and SLA usage — today is day zero, so `Enum.at(5)` is "the fifth business day after today". If you want to count today as day one, use `Enum.at(n - 1)`.

The window needs to be generous enough to contain `n` workdays. Six weeks holds 30 workdays in any territory, and `Tempo.select/2` is fast enough that the oversize doesn't matter. The idiomatic way to size it is `Tempo.shift(today, week: n + 1)` — a week per five workdays plus one for good measure.

### Why the window matters

You may wonder why we can't just "walk forward from today until we've counted five workdays". The answer is Tempo's thesis: iteration is bounded by design. Every enumeration is over a finite span — there's no infinite stream of days to filter. The window makes the computation finite and the laziness unnecessary; `Tempo.select/2` returns the complete result, and `Enum.at/2` does the index lookup.

## Related queries

Every scheduling question you'd ask about business days is a small variation on the core pattern.

### Is today a business day?

```elixir
tempo
|> Tempo.day_of_week()
|> Kernel.in(1..5)     # 1 = Mon, 7 = Sun; M-F for the US
#=> true or false
```

This is the fast path — no interval needed. For territory-aware weekend detection, use the selector:

```elixir
{:ok, set} = Tempo.select(tempo, Tempo.workdays(:SA))
Tempo.IntervalSet.count(set) > 0
#=> true if `tempo` is a workday under Saudi Arabia's Fri/Sat weekend
```

### Next business day

```elixir
tomorrow  = Tempo.shift(today, day: 1)
window    = %Tempo.Interval{from: tomorrow, to: Tempo.shift(today, week: 2)}

{:ok, workdays} = Tempo.select(window, Tempo.workdays(:US))

next_wd =
  workdays
  |> Tempo.IntervalSet.to_list()
  |> hd()
#=> Friday's next_wd is the following Monday.
```

Read aloud: *"Starting tomorrow, find the US workdays in the next two weeks and take the first."* A two-week window is generous — the longest weekend in any territory is three days, so the first workday is always within a week.

### Business days between two dates

```elixir
window = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-29"}

{:ok, workdays} = Tempo.select(window, Tempo.workdays(:US))
Tempo.IntervalSet.count(workdays)
#=> 10   (two full work weeks)
```

This is a direct `Enum.count/1` on the members. For inclusive/exclusive day-counting semantics, adjust the `from` and `to` endpoints — Tempo uses half-open `[from, to)` consistently, so a 14-day span (`2026-06-15` through `2026-06-28` inclusive) is `from: 15, to: 29`.

### Nth business day of month

```elixir
{:ok, workdays} = Tempo.select(~o"2026-06", Tempo.workdays(:US))
members         = Tempo.IntervalSet.to_list(workdays)

first = hd(members).from                       #=> ~o"2026Y6M1D"
last  = List.last(members).from                #=> ~o"2026Y6M30D"
third = Enum.at(members, 2).from               #=> ~o"2026Y6M3D"
```

Passing a month-resolution Tempo value to `Tempo.select/2` is the cleanest form — the selector treats the implicit month-span as the search window. Read aloud: *"The US workdays of June 2026 are these; take the first / last / third."*

## Territory-aware weekends

Weekend conventions vary by territory. `Tempo.workdays/1` and `Tempo.weekend/1` honour CLDR data:

```elixir
# United States: Mon–Fri workdays, Sat–Sun weekend.
Tempo.select(~o"2026-06", Tempo.workdays(:US))

# Saudi Arabia: Sun–Thu workdays, Fri–Sat weekend.
Tempo.select(~o"2026-06", Tempo.workdays(:SA))

# Iran: Sat–Wed workdays, Thu–Fri weekend.
Tempo.select(~o"2026-06", Tempo.workdays(:IR))
```

`Tempo.workdays/1` and `Tempo.weekend/1` accept a territory atom (`:US`), a territory string (`"US"`, `"sa"`, `"sazzzz"`), a locale string (`"en-GB"`, `"ar-SA"`), or a `%Localize.LanguageTag{}`. Passing `nil` (or calling with no arguments) walks the resolution chain: `Application.get_env(:ex_tempo, :default_territory)`, then the ambient `Localize.get_locale()`. See `Tempo.Territory.resolve/1` for the full normalisation rules.

## `Tempo.select/2` is pure

`Tempo.select/2` has no ambient reads. Every input that can affect the result is a value on the selector. `Tempo.workdays(:US)` is the value that carries the US workday definition — it's constructed once and composed in:

```elixir
# These produce the same IntervalSet:
Tempo.select(window, Tempo.workdays(:US))
Tempo.select(window, Tempo.workdays("en-US"))

# Hand-rolled day-of-week selector (works but bakes :US-specific knowledge):
Tempo.select(window, %Tempo{time: [day_of_week: [1, 2, 3, 4, 5]]})
```

The benefit of naming a selector `Tempo.workdays(:US)` is that **the territory indirection lives in the constructor**. A hardcoded `[1..5]` would be wrong in Saudi Arabia. `Tempo.workdays(territory)` delegates that decision to CLDR, and because the constructor returns a plain `%Tempo{}` value, it's safe to capture anywhere — including a module attribute, since the territory is explicit and the result isn't locale-sensitive at capture time:

```elixir
@us_workdays Tempo.workdays(:US)  # safe — :US is explicit

def workdays_in(window), do: Tempo.select(window, @us_workdays)
```

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

  Territory defaults to :US; callers pass a different territory
  for locale-specific behaviour.
  """

  @doc """
  Add `n` business days to `from`.

  Today is day zero; `add(today, 1)` is tomorrow-if-workday else
  the next workday.
  """
  @spec add(Tempo.t(), pos_integer(), Tempo.Territory.input()) ::
          {:ok, Tempo.t()} | {:error, term()}
  def add(from, n, territory \\ :US) when n > 0 do
    window_end = Tempo.shift(from, week: n + 1)
    window = %Tempo.Interval{from: from, to: window_end}

    with {:ok, workdays} <- Tempo.select(window, Tempo.workdays(territory)) do
      case workdays |> Tempo.IntervalSet.to_list() |> Enum.at(n) do
        nil -> {:error, :not_enough_workdays_in_window}
        interval -> {:ok, interval.from}
      end
    end
  end

  @doc "Is `tempo` a business day in the given territory?"
  @spec business_day?(Tempo.t(), Tempo.Territory.input()) :: boolean()
  def business_day?(tempo, territory \\ :US) do
    case Tempo.select(tempo, Tempo.workdays(territory)) do
      {:ok, set} -> Tempo.IntervalSet.count(set) > 0
      _ -> false
    end
  end

  @doc "Count business days in `[from, to)`."
  @spec count_between(Tempo.t(), Tempo.t(), Tempo.Territory.input()) :: non_neg_integer()
  def count_between(from, to, territory \\ :US) do
    window = %Tempo.Interval{from: from, to: to}
    {:ok, workdays} = Tempo.select(window, Tempo.workdays(territory))
    Tempo.IntervalSet.count(workdays)
  end
end
```

A hundred lines of helpers for the three or four queries your app actually makes is usually the right shape — these are domain concerns and belong in your app, not in the library. Tempo intentionally stops at the primitives so you aren't constrained by Tempo's opinions on "what counts as a business day" (includes holidays? specific territories? calendar-fiscal-year quarter-end adjustments?). You make those choices; Tempo provides the set algebra.

## Related reading

* [Holidays — planning with a real holiday calendar](./holidays.md) — fetch an ICS holiday feed, compose it with `Tempo.workdays/1` for territory-aware scheduling.
* [Cookbook](./cookbook.md) — recipe-format examples for more scheduling patterns.
* [Set operations](./set-operations.md) — union, intersection, difference.
* [Scheduling](./scheduling.md) — bounded enumeration, wall-clock-vs-UTC, floating vs zoned.
* [Enumeration semantics](./enumeration-semantics.md) — how iteration works on Tempo values and IntervalSets.
