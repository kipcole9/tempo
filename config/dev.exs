import Config

# `Tz.TimeZoneDatabase` is installed as the process-wide
# `Calendar` time-zone database in dev and test so:
#
#   * iCal 2.0's DTSTART/DTEND parsing resolves TZID parameters
#     (otherwise the event's datetime fields come through as `nil`);
#
#   * `DateTime.shift_zone/2` and friends work against named IANA
#     zones in iex sessions without the caller having to pass a
#     database explicitly.
#
# Production consumers of `ex_tempo` are free to install any
# `Calendar.TimeZoneDatabase` — `Tzdata.TimeZoneDatabase` (which
# ex_tempo already depends on) is a natural choice.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
