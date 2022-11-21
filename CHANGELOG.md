# Changelog 

## Tempo v0.1.0

This is the changelog for Tempo v0.1.0 released on _____ 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-cldr/cldr/tags)

### Enhancements

* Add `Tempo.to_date/1`, `Tempo.to_time/1` and `Tempo.to_naive_date_time/1`

* Add `Tempo.to_calendar/1` that will convert a `Tempo.t` struct to the most appropriate native Elixir date, time or naive date time struct.

### Bug Fixes

* Fix implicit enumeration of standalone months like `~o"3M"`. The requires an updated `ex_cldr_calendars` library that supports returning the number of days in the month without a year (returning an error if the result is ambiguous without a year).

* Many miscellaneous bug fixes.
