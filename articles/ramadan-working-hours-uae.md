Another recipe from the interval-sets-not-instants files — and this one is the party trick: a set operation **across two calendars**.

### When payroll and the law run on different calendars

UAE labour law ([Article 17 of Federal Decree-Law No. 33 of 2021](https://u.ae/en/information-and-services/jobs/employment-in-the-private-sector/working-hours)) reduces the private-sector workday by two hours — eight becomes six — for every day of Ramadan, for **all** employees regardless of religion, with no pay reduction.

The payroll year is Gregorian. Ramadan is the ninth month of the *Islamic* calendar, and because the Islamic year is ~11 days shorter, Ramadan drifts earlier through the Gregorian year — February one year, January a few years later. So "how many statutory working hours in 2026?" is an intersection between a Gregorian year and an Islamic month. Most date libraries can't even *represent* that question. In Tempo it's the same set algebra as everything else, because a calendar is just the ruler a value is measured with.

### Statutory hours for 2026

```elixir
import Tempo.Sigils

work_year = ~o"2026"
ramadan   = ~o"1447-09[u-ca=islamic-civil]"

standard_hours = 8
ramadan_hours  = 6

{:ok, workdays}         = Tempo.select(work_year, Tempo.workdays(:AE))
{:ok, ramadan_workdays} = Tempo.members_overlapping(workdays, ramadan)
{:ok, normal_workdays}  = Tempo.members_outside(workdays, ramadan)

Tempo.IntervalSet.count(normal_workdays) * standard_hours +
  Tempo.IntervalSet.count(ramadan_workdays) * ramadan_hours
*#=> 2044   (239 normal workdays × 8h + 22 Ramadan workdays × 6h — 44 hours reduced)*
```

### Walkthrough of the recipe

```elixir
# Ramadan is month 9 of the Islamic year — here 1447 AH, written with
# the IXDTF u-ca suffix. The value LIVES in the Islamic calendar; its
# implicit span is the whole month, in its own calendar's terms:
iex> ramadan = ~o"1447-09[u-ca=islamic-civil]"
iex> Tempo.to_interval(ramadan)
{:ok, ~o"1447Y9M1D[u-ca=islamic-civil]/1447Y10M1D[u-ca=islamic-civil]"}

# Where does that land in the Gregorian year? Intersect it with 2026.
# Tempo converts calendars inside the set operation — note the result
# is plain Gregorian, and this is the first recipe that leans on the
# v0.19 fix keeping calendar tags truthful through the conversion:
iex> Tempo.intersection(~o"2026", ramadan)
{:ok, #Tempo.IntervalSet<[~o"2026Y2M18D/2026Y3M20D"]>}

# The UAE's workweek comes from CLDR territory data — and it knows
# the UAE moved its weekend to Saturday–Sunday in 2022, so workdays
# are Monday–Friday. No hand-coded weekday list:
iex> Tempo.workdays(:AE)
~o"{1,2,3,4,5}K"

iex> {:ok, workdays} = Tempo.select(~o"2026", Tempo.workdays(:AE))
iex> Tempo.IntervalSet.count(workdays)
261

# Now partition the year's workdays by Ramadan. `members_overlapping`
# keeps the workdays that fall inside it; `members_outside` keeps the
# rest. Same member-preserving filters as the Business/252 recipe —
# one Gregorian operand, one Islamic:
iex> {:ok, ramadan_workdays} = Tempo.members_overlapping(workdays, ramadan)
iex> ramadan_workdays
#Tempo.IntervalSet<[~o"2026Y2M18D/2026Y2M19D", ~o"2026Y2M19D/2026Y2M20D", ~o"2026Y2M20D/2026Y2M21D", …]>

iex> Tempo.IntervalSet.count(ramadan_workdays)
22

# 22 six-hour days and 239 eight-hour days:
iex> 239 * 8 + 22 * 6
2044
```

And here's the payoff of doing it symbolically: **next year is the same pipeline with two new bindings.** Ramadan 1448 drifts ten days earlier, and nothing else changes:

```elixir
iex> Tempo.intersection(~o"2027", ~o"1448-09[u-ca=islamic-civil]")
{:ok, #Tempo.IntervalSet<[~o"2027Y2M8D/2027Y3M10D"]>}
```

Two production caveats, honestly stated. The tabular `islamic-civil` calendar is a *planning* approximation — the legal month begins with the moon-sighting announcement, so for an actual payroll run pin the announced dates (the same advice as pinning the ANBIMA holiday file in the Business/252 recipe). And Eid al-Fitr, immediately after Ramadan, is a public holiday — subtract it with `Tempo.members_outside/2` exactly as Business/252 subtracts ANBIMA holidays.

### Trying this at home

* The recipe in the cookbook: https://ex-tempo.hexdocs.pm/cookbook.html#ramadan-working-hours-statutory-hours-across-two-calendars
* The supported calendars (Islamic civil/tabular/Umm al-Qura, Hebrew, Coptic, Ethiopic, Persian, …) come from [Calendrical](https://hex.pm/packages/calendrical); the `u-ca` tag vocabulary is CLDR's, via [Localize](https://hex.pm/packages/localize).
* Cross-calendar comparison semantics: https://ex-tempo.hexdocs.pm/cookbook.html#9-cross-calendar-and-cross-timezone
