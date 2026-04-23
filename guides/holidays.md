# Holidays — Planning with a Real Holiday Calendar

The [workdays-and-weekends guide](./workdays-and-weekends.md) showed how `Tempo.select(interval, Tempo.workdays(:US))` filters out weekends. Holidays are the other half of "when is the office closed?" — they're territory-specific, year-specific, and maintained by people who care about them. Tempo doesn't ship holiday data; instead, it consumes standard iCalendar (`.ics`) feeds through `Tempo.ICal.from_ical/1` and lets set operations do the rest.

This guide walks through fetching a real holiday calendar from [officeholidays.com](https://www.officeholidays.com/subscribe), parsing it into a `%Tempo.IntervalSet{}`, and using it to answer three scheduling questions: "how many working days are actually in Q3?", "which holidays will hit my project?", and "what's five business days from today if we skip holidays?".

## The data source

[officeholidays.com](https://www.officeholidays.com/subscribe) publishes public-holiday calendars for every UN-recognised country and territory, updated weekly, delivered as iCalendar `.ics` feeds. Two URL patterns to know:

* `https://www.officeholidays.com/ics/{country}` — all public holidays (includes state and regional holidays where relevant).

* `https://www.officeholidays.com/ics-fed/{country}` — federal or national-level holidays only.

Country names are lowercase with hyphens: `usa`, `united-kingdom`, `germany`, `japan`, `saudi-arabia`. Subscription URLs are the same as download URLs — a calendar program like iCal or Outlook points at the `webcal://` equivalent; our code fetches the `https://` form as a plain HTTP body.

## Fetching and parsing

The end-to-end fetch-and-parse is three lines:

```elixir
%Req.Response{body: ics} =
  Req.get!("https://www.officeholidays.com/ics-fed/usa")

{:ok, holidays} = Tempo.ICal.from_ical(ics)

Tempo.IntervalSet.count(holidays)
#=> 12    (US federal holidays for 2026)
```

(Any HTTP client works — the examples use [`:req`](https://hex.pm/packages/req); `:httpc` from OTP or another library is equally fine. What Tempo needs is the response body as a string.)

`Tempo.ICal.from_ical/1` returns a `%Tempo.IntervalSet{}` where each member is a `%Tempo.Interval{}` with the iCal event metadata preserved on `:metadata` — `summary`, `description`, `location`, `uid`, custom `X-*` properties. The intervals themselves are half-open `[from, to)` day-spans in Tempo's standard convention.

```elixir
holidays
|> Tempo.IntervalSet.to_list()
|> Enum.take(3)
|> Enum.each(fn iv ->
  IO.puts "#{iv.from.time[:month]}/#{iv.from.time[:day]}: #{iv.metadata.summary}"
end)
#=> 1/1: New Year's Day
#=> 1/19: Martin Luther King Jr. Day
#=> 2/16: President's Day (Regional Holiday)
```

**Caching** — don't fetch on every request. The calendar updates weekly at most; store the parsed `%Tempo.IntervalSet{}` in an Agent, GenServer, `:persistent_term`, or your application's config cache and refresh on a schedule.

## Three planning questions

Assume the calendar has been fetched and parsed into `holidays`.

### 1. How many working days are actually in Q3 2026?

Pure set algebra: workdays minus holidays.

```elixir
q3 = %Tempo.Interval{from: ~o"2026-07-01", to: ~o"2026-10-01"}

{:ok, workdays}     = Tempo.select(q3, Tempo.workdays(:US))
{:ok, net_workdays} = Tempo.difference(workdays, holidays)

Tempo.IntervalSet.count(net_workdays)
#=> 64    (66 workdays − 2 federal holidays in Q3)
```

Read aloud: *"Workdays in Q3 are the Monday-through-Friday days inside July-September. Net working days are those workdays that aren't federal holidays."*

`Tempo.difference/2` is **member-preserving**: each workday that survives the filter is kept as a distinct member, with its own day-level endpoints. This is the natural shape for "count the days" and "list the days" queries — no interval coalescing silently collapses the result into weekly spans.

#### Expressing the Q3 window

The `%Tempo.Interval{from:, to:}` form above is the most explicit. Three more concise alternatives all compose equally well with `Tempo.select/2` and the set operations:

```elixir
# ISO 8601 interval range:
q3 = ~o"2026-07/2026-10"

# ISO 8601-2 quarter designator:
q3 = ~o"2026Y3Q"

# Range-in-slot:
q3 = ~o"2026Y{7..9}M"
```

All four produce the same 66-workday count when passed through `Tempo.select(q3, Tempo.workdays(:US))`. Pick whichever reads most naturally for your domain. The quarter designator is the shortest and most direct for calendar-quarter queries; the range form `~o"2026-07/2026-10"` is the best fit when your window doesn't align to a standard quarter.

The same composition works for **seasons** (ISO 8601-2 codes 25–32, astronomical equinox/solstice bounded — e.g. `~o"2026Y26M"` for Northern summer), **month ranges** (`~o"2026Y{3..6}M"` for H1 minus Q1), and **archaeological masks** (`~o"156X"` for the 1560s). Each of these AST shapes materialises to concrete endpoints and flows cleanly through the workday selector and set operations.

### 2. Which holidays will hit my project?

`Tempo.intersection/2` returns the holiday members that fall inside the query window — with their iCal metadata intact:

```elixir
q3 = ~o"2026-07/2026-10"
{:ok, q3_holidays} = Tempo.intersection(holidays, q3)

q3_holidays
|> Tempo.IntervalSet.to_list()
|> Enum.each(fn iv ->
  IO.puts "#{iv.from.time[:month]}/#{iv.from.time[:day]}: #{iv.metadata.summary}"
end)
#=> 7/3: Independence Day (in lieu)
#=> 7/4: Independence Day
#=> 9/7: Labor Day
```

Read aloud: *"The Q3 holidays are the holiday-set members that overlap the Q3 window. Each one carries its name from the iCal feed."*

Because `Tempo.intersection/2` keeps surviving members whole — with their original metadata — you can compose further: intersect with a team's availability, difference out someone's PTO, union multiple territories' holidays for an international team. The names travel through.

### 3. What's five business days from today, skipping holidays?

Four composed set operations. The whole pipeline is set-algebra; no list-level filtering required.

```elixir
today  = ~o"2026-06-30"
window = %Tempo.Interval{from: today, to: Tempo.shift(today, week: 3)}

{:ok, workdays}  = Tempo.select(window, Tempo.workdays(:US))
{:ok, open_days} = Tempo.difference(workdays, holidays)

target =
  open_days
  |> Tempo.IntervalSet.to_list()
  |> Enum.at(5)
#=> %Tempo.Interval{from: ~o"2026Y7M8D", ...}
```

Read aloud: *"Starting today, build a three-week window. Keep the workdays inside it. Subtract the holidays. The sixth survivor is the answer for 'five business days from today' under the banking convention where today is day zero."*

(`Enum.at(5)` picks the sixth element. If your convention counts today as day one, use `Enum.at(n - 1)`.)

## Territory-aware planning

Change the URL, get a different country's holidays. The same code works for every territory officeholidays.com publishes:

```elixir
defmodule MyApp.HolidayCalendar do
  def fetch(territory) do
    url = "https://www.officeholidays.com/ics/#{territory_slug(territory)}"

    with {:ok, %Req.Response{status: 200, body: ics}} <- Req.get(url),
         {:ok, set} <- Tempo.ICal.from_ical(ics) do
      {:ok, set}
    end
  end

  defp territory_slug(:US), do: "usa"
  defp territory_slug(:GB), do: "united-kingdom"
  defp territory_slug(:DE), do: "germany"
  defp territory_slug(:JP), do: "japan"
  defp territory_slug(:SA), do: "saudi-arabia"
  # extend as needed
end
```

Pair this with `Tempo.select(interval, Tempo.workdays(:SA))` for a fully territory-consistent planning layer: Saudi weekends (Fri/Sat) are excluded by the workday query; Saudi holidays come from the ICS feed; the set operations compose across both.

For teams across multiple territories, **union the holiday sets before differencing** — "office closed" becomes "any member territory's holiday":

```elixir
{:ok, us_holidays} = MyApp.HolidayCalendar.fetch(:US)
{:ok, gb_holidays} = MyApp.HolidayCalendar.fetch(:GB)
{:ok, de_holidays} = MyApp.HolidayCalendar.fetch(:DE)

{:ok, all_closed} = Tempo.union(us_holidays, gb_holidays)
{:ok, all_closed} = Tempo.union(all_closed, de_holidays)
```

Then compute "working days for the global team" as `Tempo.difference(workdays, all_closed)`. Each member interval still carries the territory/name metadata — so the July 3 entry stays labelled as US in the global union, and you can render conflicts with full attribution.

## Scheduling a training week

A concrete example that ties it together: pick the first five-day work week in Q3 2026 with no US federal holidays, suitable for scheduling a training course.

```elixir
q3 = ~o"2026-07/2026-10"

{:ok, workdays}  = Tempo.select(q3, Tempo.workdays(:US))
{:ok, open_days} = Tempo.difference(workdays, holidays)

candidate_weeks =
  open_days
  |> Tempo.IntervalSet.to_list()
  |> Enum.chunk_by(&week_key/1)
  |> Enum.filter(&(length(&1) == 5))

first_available = hd(candidate_weeks)
#=> five-member list starting the Monday of the first clean week
```

Read aloud: *"Take the open workdays of Q3, group them by week, keep only the weeks that still have all five workdays, and pick the first."* `week_key/1` is a helper you'd write — the year-week pair derived from each interval's `from` endpoint. The core logic is four composable set operations on Tempo's primitives.

## Related reading

* [Working with workdays and weekends](./workdays-and-weekends.md) — `Tempo.workdays/1`, `Tempo.weekend/1`, territory-aware weekend conventions, and the primitive patterns this guide builds on.

* [Set operations](./set-operations.md) — union, intersection, difference, the member-preserving semantics, and the instant-level `overlap_trim`/`split_difference` variants.

* [iCalendar integration](./ical-integration.md) — full detail on `Tempo.ICal.from_ical/1`, metadata preservation, and round-tripping `.ics` files.

* [Cookbook](./cookbook.md) — recipe-format examples for scheduling, availability, and related queries.
