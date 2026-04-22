import Config

config :logger,
  level: :info

# Load environment-specific overrides. `dev.exs` and `test.exs`
# install `Tz.TimeZoneDatabase` as the default `Calendar` time-zone
# database — required for iCal 2.0's TZID-parameter parsing and
# handy in iex sessions. Production consumers of `ex_tempo` set
# their own database (see the README).
if File.exists?(Path.join(__DIR__, "#{config_env()}.exs")) do
  import_config "#{config_env()}.exs"
end
