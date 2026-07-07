Sometimes  interesting (at least to me!) use cases surface. Since `Tempo` is a different way of thinking about time, it can take a while for cognition to switch. Therefore I think posting interesting recipes from time-to-time (no pun intended) might be useful.

### Calculating business days in a year

@tubedude is working on a [Financial Calulation](https://hex.pm/packages/finance) library. Turns out that there are [many ways to count days](https://www.investopedia.com/terms/d/daycount.asp#:~:text=actual%2F360%3A%20calculates%20the%20daily,days%20in%20each%20time%20period.) when calculating daily interest. Most of them are straight forward.

However, Brazil has a [particular](https://www.anbima.com.br/feriados/feriados.asp) way of determining the day count: All of the working days of the year, not including the holidays declared by ANBIMA.

### Business/252: Brazil fixed-income instruments

Here's the recipe, following which we'll work through the code step-by-step. 
```elixir
import Tempo.Sigils
{:ok, holidays} = Tempo.ICal.from_ical_file("feriados_anbima.ics")

settlement = ~o"2024-01-01"
maturity   = ~o"2025-01-01"

{:ok, window} = Tempo.Interval.new(from: settlement, to: maturity)
{:ok, workdays} = Tempo.select(window, Tempo.workdays(:BR))
{:ok, business_days} = Tempo.members_outside(workdays, holidays)

Tempo.IntervalSet.count(business_days) / 252
*#=> 1.003968253968254   (253 business days in 2024)*
```
### Walkthrough of the recipe

The recipe leverages the fact that in Tempo, everything is an *interval* (not an *instant*). And therefore, operations on an interval are *set* operations, not scalar.

```elixir
# Import the ~o sigil which compiles an ISO8601 time expression
# into a `Tempo.t` struct at compile time. 
iex> import Tempo.Sigils

# Import an `.ics` (iCalendar) file and interpret each event as a 
# Tempo interval. This uses the fabulous [ical](https://hex.pm/packages/ical) library for parsing
# the calendar file. The data itself comes from [ANBIMA](https://www.anbima.com.br/feriados/feriados.asp) and is converted to an iCal file by [a script](https://github.com/kipcole9/tempo/blob/main/scripts/anbima_xls_to_ics.py).
iex> {:ok, holidays} = Tempo.ICal.from_ical_file("feriados_anbima.ics")
{:ok, #Tempo.IntervalSet<[#Tempo.Interval<~o"2001Y1M1D/2001Y1M2D" · Confraternização Universal>, #Tempo.Interval<~o"2001Y2M26D/2001Y2M27D" · Carnaval>, #Tempo.Interval<~o"2001Y2M27D/2001Y2M28D" · Carnaval>, #Tempo.Interval<~o"2001Y4M13D/2001Y4M14D", ....]>

# Now we describe the settlement and maturity dates. These look
# a lot like a ~D[2024-01-01] date in Elixir. But unlike the native 
# Date type, ~o[2024-01-01] is describing an *implicit* interval of
# one year. We could also have entered it as an *explicit* interval
# as ~o"2024-01-01/2024-01-02". Note that Tempo intervals are
# [half-open](https://en.wikipedia.org/wiki/Interval_(mathematics))
iex> settlement = ~o"2024-01-01"
iex> maturity   = ~o"2025-01-01"

# We are explicitly creating the interval for a loan here, we could 
# also have used a the direct notation ~o"2024-01-01/2024-01-02"
# we described previously.
iex> {:ok, window} = Tempo.Interval.new(from: settlement, to: maturity)

# From all the days in the year, we want to select only
# those days that are working days. Since Tempo leans on 
# [Localize](https://hex.pm/packages/localize), we can derive
# the working days directly for any given [ISO 3166](https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes)
# territory code. Notice that the return value is also a Tempo
# interval. In this case its the interval that selects the days of the
# week 1 through 5 denoting Monday through Friday. Different
# territories define different working weeks (try the example
# with the territory :SA).
iex> brazil_workdays = Tempo.workdays(:BR)
~o"{1,2,3,4,5}K"

# Now we're getting the heart of Tempo's power. Given the
# full year interval we described in `window`, select only the
# working days. This is more formally a *projection*, but `select`
# is a more common idiom so we use that.
# Tempo.select/2` picks the sub-intervals of a span that match a
# selector (workdays, the 15th, every Friday, holidays…) and
# returns them as an `IntervalSet`.
iex> {:ok, workdays} = Tempo.select(window, brazil_workdays)
{:ok,
 #Tempo.IntervalSet<[~o"2024Y1M1D/2024Y1M2D", ~o"2024Y1M2D/2024Y1M3D", ~o"2024Y1M3D/2024Y1M4D", ~o"2024Y1M4D/2024Y1M5D", ~o"2024Y1M5D/2024Y1M6D", ...]>

# Tempo.members_outside is a member-preserving anti-overlap 
# filter — returns the whole members of workdays that do NOT 
# overlap any member of holidays.
iex> {:ok, business_days} = Tempo.members_outside(workdays, holidays)
{:ok,
 #Tempo.IntervalSet<[~o"2024Y1M2D/2024Y1M3D", ~o"2024Y1M3D/2024Y1M4D", ~o"2024Y1M4D/2024Y1M5D", ~o"2024Y1M5D/2024Y1M6D", ~o"2024Y1M8D/2024Y1M9D", ~o"2024Y1M9D/2024Y1M10D", ~o"2024Y1M10D/2024Y1M11D", ~o"2024Y1M11D/2024Y1M12D", ...]>

# And how any days is that? It's the number of spans in the
# IntervalSet, so we can just count them.
iex> Tempo.IntervalSet.count(business_days)
253
```

### Trying this at home
All the pieces are in the documentation and the GitHub repo.

* Script to convert the ANBIMA holiday spreadsheet into an `.ics` file: https://github.com/kipcole9/tempo/blob/main/scripts/anbima_xls_to_ics.py
* Documentation of the recipe in the cookbook: https://ex-tempo.hexdocs.pm/cookbook.html#business-252-brazil-s-business-day-year-fraction