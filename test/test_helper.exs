ExUnit.configure(exclude: [all: true])

# Ensure the CLDR locales used by Tempo.FormatTest are present.
# Localize lazily downloads on miss, but a few formatting tests
# assert specific locale strings ("de", "en-GB"), so pre-fetching
# them here keeps the test suite hermetic and fast.
_ =
  Mix.Task.run("localize.download_locales", ~w(en en-GB de fr he))

ExUnit.start()
