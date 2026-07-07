Another recipe from the interval-sets files — this one pairs Tempo with its sibling library [Astro](https://hex.pm/packages/astro), because some scheduling constraints aren't set by law or by calendars. They're set by the sun.

### When the constraint is the sun

Outdoor crews — surveyors, riggers, solar installers, film units — can only use site hours that are also daylight. In Lisbon in December that's a non-issue. In Helsinki it very much is one: on the December solstice the sun rises at 09:23 and sets at 15:12. If your site day is 08:00–16:00, how much *workable* time does a Helsinki crew actually have in December 2026 — and what's the gap against the same crew in Lisbon?

Sunrise and sunset come from Astro's ephemeris. The rest is set algebra: **workable time = site hours ∩ daylight**, summed over the working month.

### Site hours ∩ daylight, city by city

```elixir
import Tempo.Sigils

workable_daylight = fn december, territory, location, zone ->
  {:ok, workdays} = Tempo.select(december, Tempo.workdays(territory))

  for day <- workdays do
    {:ok, date}    = Tempo.to_date(day)
    {:ok, sunrise} = Astro.sunrise(location, date, time_zone: zone)
    {:ok, sunset}  = Astro.sunset(location, date, time_zone: zone)

    {:ok, daylight} =
      Tempo.Interval.new(
        from: Tempo.from_elixir(DateTime.truncate(sunrise, :second)),
        to: Tempo.from_elixir(DateTime.truncate(sunset, :second))
      )

    {:ok, site_hours} = Tempo.select(day, 8..15)
    {:ok, workable}   = Tempo.intersection(site_hours, daylight)
    Tempo.duration(workable)
  end
end

{:ok, helsinki_december} = Tempo.from_iso8601("2026-12[Europe/Helsinki]")
{:ok, lisbon_december}   = Tempo.from_iso8601("2026-12[Europe/Lisbon]")

workable_daylight.(helsinki_december, :FI, {24.9384, 60.1699}, "Europe/Helsinki")
*#=> 137.8 hours across 23 workdays*

workable_daylight.(lisbon_december, :PT, {-9.1393, 38.7223}, "Europe/Lisbon")
*#=> 184.0 hours — every site hour is daylit*
```

Lisbon crews get their full 184 site-hours. Helsinki crews get 137.8 — a **34% December capacity gap** from geography alone, before weather says a word.

### Walkthrough of the recipe

```elixir
# December carries its zone on the value itself (IXDTF suffix), and
# every operation downstream inherits it. This matters — see below.
iex> {:ok, december} = Tempo.from_iso8601("2026-12[Europe/Helsinki]")

# Finland's Monday–Friday, from CLDR territory data.
iex> {:ok, workdays} = Tempo.select(december, Tempo.workdays(:FI))
iex> Tempo.IntervalSet.count(workdays)
23

# Enumerating an IntervalSet yields its member days as values, and a
# day-resolution Tempo converts cleanly to an Elixir Date for Astro.
iex> [day | _] = Enum.take(workdays, 1)
iex> Tempo.to_date(day)
{:ok, ~D[2026-12-01]}

# Astro gives zone-aware sunrise/sunset DateTimes; `from_elixir`
# bridges them into Tempo, and the pair becomes the day's daylight
# interval:
iex> daylight
~o"2026Y12M1DT8H56M20SZ+2H[Europe/Helsinki]/2026Y12M1DT15H21M42SZ+2H[Europe/Helsinki]"

# Site hours are the day selected down to hours 8–15 (08:00–16:00,
# half-open). Because the day inherited Helsinki's zone, so do these:
iex> {:ok, site_hours} = Tempo.select(day, 8..15)

# The intersection trims each site hour to its daylit portion — the
# 8 o'clock hour survives only from sunrise at 08:56:
iex> {:ok, workable} = Tempo.intersection(site_hours, daylight)
iex> workable
#Tempo.IntervalSet<[~o"2026Y12M1DT8H56M20SZ+2H[Europe/Helsinki]/2026Y12M1DT9H0M0S[Europe/Helsinki]", ~o"2026Y12M1DT9H0M0S[Europe/Helsinki]/2026Y12M1DT10H0M0S[Europe/Helsinki]", …]>

# And the day's workable time is the set's total duration:
iex> Tempo.duration(workable)
~o"PT23122S"   # 6.4 hours on December 1st — and shrinking daily toward the solstice
```

Two details are load-bearing. First, the **zone on the month value**: site hours built from a zone-less December would compare as UTC and silently shift the Helsinki overlap by two hours — the answer would be plausible and wrong. Second, `Astro.sunrise/3` takes `time_zone:` explicitly (or resolves it from coordinates if you add [tz_world](https://hex.pm/packages/tz_world) as a dependency).

And a nod to high latitudes: above the Arctic Circle Astro returns `{:error, :no_time}` in midwinter — there is no sunrise to intersect with. Tromsø's December workable hours compute to exactly what the crews there already know they are.

### Trying this at home

* The recipe in the cookbook: https://ex-tempo.hexdocs.pm/cookbook.html#daylight-limited-work-tempo-astro
* Astro — sunrise, sunset, twilight, lunar phases: https://hexdocs.pm/astro
