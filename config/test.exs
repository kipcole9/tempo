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
