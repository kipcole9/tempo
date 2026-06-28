import Config

# See `config/dev.exs` for rationale. Keeping dev and test in sync
# so examples that work in iex also pass the doctest suite.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# Pin the test-suite default locale to English so formatting and
# territory-resolution tests are deterministic regardless of the
# developer's shell environment. Without this, `Localize.default_locale/0`
# walks its resolution chain — `LOCALIZE_DEFAULT_LOCALE` env,
# `:localize / :default_locale` app config, `LANG` env, fallback `:en`.
# A developer with `LANG=es_ES.UTF8` in their shell would otherwise
# see Spanish-formatted output slip into assertions that expect
# English strings. The app config clause sits above `LANG` in that
# chain, so pinning it here wins without our having to scrub the
# shell env at test startup.
config :localize, :default_locale, :en

# Tests use `Tz.TimeZoneDatabase` (above), so tzdata's TZ data is
# never consulted — but tzdata still starts as an application and its
# auto-update GenServer phones home for a newer release. That is
# non-deterministic in CI and, on OTP 29, crashes outright: tzdata
# 1.1.3 builds periods with a `{24, 0, 0}` end-of-day time that
# OTP 29's stricter `:calendar.time_to_seconds/1` rejects. Disable
# the updater for the test suite.
config :tzdata, :autoupdate, :disabled
