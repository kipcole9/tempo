## Notes

* When parsing clock time, ommitted higher order is set to zero. This does not apply to dates. Update: nope, they should also be unknown.

* Groups need to be resolved to either an implicit interval (ie like a month, week or day - even quarter and season) or to an explicit interval

* Unspecified components need to be resolved to .... ? update: probably `nil`

* When parsing an interval some heuristic is required to resolve some forms like:
  * 2020-01-01/02 would parse the "02" as a month when it needs to be interpreted as a day. This may be the other exception? - update: probably should always be the largest time unit if its ambiguous

* Support of fractional components in duration? (section 11.4 in Part 2) - update: yes, but resolved at the next lower time unit

* Add significant digits / error / approximation

* Parse season names as well as the fake months

* Parse Q1 for quarters, not just fake months

* Negative time units are fine, they accumulate from the smallest time unit to the largest

* 

------

## Definitions

* A time is `anchored` if it can be placed on the timeline or `floating` if not
  * To be anchored either the year or century must be defined. Note that gaps are not permitted in the time units except at the beginning and the end
* A time unit is either known or unknown. Unknown is represented by `nil`
* For now, no gaps in time units except at the beginning and the end. Ie `Tempo{month: 9, day: 1}` is fine, `%Tempo{year: 2020, day: 1}` is not. Note `%Tempo{year: 2020, day_of_year: 1}` is fine.
* `□` is the symbol for `unknown` time units when inspecting
* `anchor`ing is the function to place a time on the timeline by filling in the higher order time units.
* The `resolution` of a Tempo.t is the smallest known time unit
* `to_date`, `to_time`, to_date_time`_ work as expected, `to_calendar` makes the best decision it can about whether to format a date, a time or a datetime
* We can `trunc` and `round` which reduces resolution. The opposite would be `expand`? `extend`?

## On accuracy, precision and resolution

* https://control.com/technical-articles/what-is-the-difference-between-accuracy-precision-and-resolution/
