# Launch demo calendars

Two fictional calendars for April 2026, built to exercise Tempo's iCalendar import and set-algebra operations during the launch demo.

## Characters

**Bruce Thompson** — Sydney-based product manager at a growth-stage SaaS company. Weekend rugby with the Randwick Colts, crime-fiction book club, craft beer, fishing with Dad. 82 events once the recurring items expand.

**Shiela Reyes** — Sydney solicitor on the equity-partner track. Hot yoga twice a week, a pottery course, wine-tasting evening class, bushwalking with girlfriends, Women's book club. 67 events once the recurring items expand.

## What they demonstrate

* **Workday overlaps** — Bruce and Shiela both work 9-to-5ish. Some meetings overlap (the demo's intersection query hits ~35), most don't. Realistic for two independent professionals.

* **Shared social events** — four actual joint engagements: Sam's 35th birthday drinks (Fri Apr 3), BBQ at Tom & Claire's (Sat Apr 4), Tom & Claire's wedding (Sat Apr 18), and the ANZAC Day dawn service (Sat Apr 25 — same memorial, not a planned meet-up).

* **Weekend divergence** — Bruce's Saturdays are rugby training/matches and fishing/BBQ; Shiela's are bushwalks, the farmers' market, a yoga retreat, and art galleries. Their interests are plausibly separate.

* **Recurring patterns** — daily standups (Bruce), weekly partners' meetings (Shiela), Mon/Wed/Fri gym, Tue/Thu yoga, weekly pottery classes. Good material for `Tempo.RRule` expansion.

* **Calendar-quarter queries** — both sit entirely inside Q2 2026, so `Tempo.intersection(bruce, ~o"2026Y2Q")` narrows cleanly.

## Format notes

The `ical` 2.0 library that Tempo uses does not currently parse `DTSTART;TZID=...` parameters — the resulting `dtstart` comes through as `nil`. To get the demo working today, these files use naive local times (no TZID, no Z suffix). The `ical` library treats them as UTC on parse, but the narrative "9am standup, 2pm roadmap review" is still correct against Sydney wall clocks. When the upstream parser is fixed we can restore the VTIMEZONE + `TZID=Australia/Sydney` form and the events will re-anchor correctly.

## Quick demo lines

```elixir
{:ok, bruce}  = Tempo.ICal.from_ical(File.read!("demo/calendars/bruce.ics"))
{:ok, shiela} = Tempo.ICal.from_ical(File.read!("demo/calendars/shiela.ics"))

# When are they both busy?
{:ok, clash} = Tempo.intersection(bruce, shiela)

# What workday time do they share? Narrow each to workdays first.
april = ~o"2026Y4M"
{:ok, bruce_weekdays}  = Tempo.select(bruce,  Tempo.workdays(:AU))
{:ok, shiela_weekdays} = Tempo.select(shiela, Tempo.workdays(:AU))

# Find Bruce's free time: his April minus his busy events.
{:ok, bruce_free} = Tempo.difference(april, bruce)

# Mutual free slots for a catch-up coffee.
{:ok, shiela_free} = Tempo.difference(april, shiela)
{:ok, mutual_free} = Tempo.intersection(bruce_free, shiela_free)
```
