Another recipe from the "time as intervals, not instants" files — this one is small, but it's the one most likely to be silently wrong in production payroll code right now.

### The 25-hour day

Twice a year, wall clocks lie. On the night the US falls back (the first Sunday of November), the hour from 01:00 to 02:00 happens *twice*. On the spring-forward night, 02:00 to 03:00 never happens at all. A night-shift worker clocking 21:00–05:00 works **nine** hours on the first night and **seven** on the second — and US wage law ([FLSA](https://www.dol.gov/agencies/whd/flsa), via the [DOL's own guidance](https://webapps.dol.gov/elaws/whd/flsa/hoursworked/screenEr80.asp)) pays non-exempt workers for hours *actually worked*. Payroll code that computes `end - start` on wall-clock times gets both nights wrong, in opposite directions.

### Counting the hours a worker actually lived

Here's the recipe — three shifts, one of each kind:

```elixir
import Tempo.Sigils

normal     = ~o"2026-10-24T21[America/New_York]/2026-10-25T05[America/New_York]"
fall_back  = ~o"2026-10-31T21[America/New_York]/2026-11-01T05[America/New_York]"
spring_fwd = ~o"2026-03-07T21[America/New_York]/2026-03-08T05[America/New_York]"

Enum.count(normal)
*#=> 8*
Enum.count(fall_back)
*#=> 9   (01:00 EDT and 01:00 EST — both worked, both paid)*
Enum.count(spring_fwd)
*#=> 7   (02:00 never happened)*
```

### Walkthrough of the recipe

The recipe leans on two Tempo ideas: an explicit interval iterates at the resolution of its own boundaries (hour boundaries → hour steps), and enumeration is driven by the timezone database rather than by naive arithmetic.

```elixir
# A shift is an explicit, half-open, hour-resolution interval in the
# worker's own zone — written with the IXDTF [zone] suffix.
iex> fall_back = ~o"2026-10-31T21[America/New_York]/2026-11-01T05[America/New_York]"

# Enumerating it walks the wall clock the worker actually lived
# through. Watch what happens at 01:00:
iex> Enum.to_list(fall_back)
[
  ~o"2026Y10M31DT21H[America/New_York]",
  ~o"2026Y10M31DT22H[America/New_York]",
  ~o"2026Y10M31DT23H[America/New_York]",
  ~o"2026Y11M1DT0H[America/New_York]",
  ~o"2026Y11M1DT1HZ-4H[America/New_York]",
  ~o"2026Y11M1DT1HZ-5H[America/New_York]",
  ~o"2026Y11M1DT2H[America/New_York]",
  ~o"2026Y11M1DT3H[America/New_York]",
  ~o"2026Y11M1DT4H[America/New_York]"
]
```

The 01:00 hour appears **twice** — and the two occurrences are *distinct values*, disambiguated by their UTC offset exactly as [RFC 9557](https://www.rfc-editor.org/rfc/rfc9557) prescribes: `Z-4H` is the EDT hour, `Z-5H` the EST hour. That means a payroll record built from this walk round-trips each hour to the correct UTC instant — the two 01:00s don't collapse into one.

On the spring-forward night the enumeration simply never yields an 02:00 — the timezone database says that hour doesn't exist, so `Enum.count` says 7.

The general point: `Enum.count` here is *not* elapsed time divided by 3600 — it's the number of wall-clock hours the zone actually contained. (When you want elapsed physical time instead, that's `Tempo.duration/1`, which measures on the UTC line — the two questions genuinely have different answers on these two nights, and Tempo makes you pick one on purpose.)

### Trying this at home

* The recipe in the cookbook: https://ex-tempo.hexdocs.pm/cookbook.html#the-25-hour-shift-dst-and-payroll
* How enumeration treats DST gaps and folds: https://ex-tempo.hexdocs.pm/enumeration-semantics.html
