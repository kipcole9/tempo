defmodule Tempo.MixProject do
  use Mix.Project

  @version "0.2.0-dev"

  def project do
    [
      app: :ex_tempo,
      version: @version,
      name: "Tempo",
      source_url: "https://github.com/kipcole9/tempo",
      docs: docs(),
      deps: deps(),
      description: description(),
      package: package(),
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      dialyzer: [
        flags: [
          :error_handling,
          :unknown,
          :underspecs,
          :extra_return,
          :missing_return
        ]
      ]
    ]
  end

  def description do
    "Time as an interval, not an instant — ISO 8601 and IXDTF-compliant " <>
      "date, time, interval, duration, recurrence, and set-algebra library " <>
      "for Elixir. Calendar- and timezone-aware."
  end

  def package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: links(),
      files: [
        "lib",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*",
        "assets/logo.png"
      ]
    ]
  end

  def links do
    %{
      "GitHub" => "https://github.com/kipcole9/tempo",
      "Readme" => "https://github.com/kipcole9/tempo/blob/v#{@version}/README.md",
      "Changelog" => "https://github.com/kipcole9/tempo/blob/v#{@version}/CHANGELOG.md"
    }
  end

  def docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      logo: "assets/logo.png",
      extras:
        [
          "README.md",
          "LICENSE.md",
          "CHANGELOG.md"
        ] ++ Path.wildcard("guides/*.md"),
      formatters: ["html"],
      groups_for_modules: groups_for_modules(),
      groups_for_extras: groups_for_extras(),
      skip_undefined_reference_warnings_on:
        [
          "CHANGELOG.md"
        ] ++ Path.wildcard("guides/*.md")
    ]
  end

  def groups_for_modules do
    [
      Core: ~r/^Tempo(?:\.(Interval|IntervalSet|Duration|Range|Set))?$/,
      "Set algebra and comparison":
        ~r/^Tempo\.(Operations|Compare|Math|Rounding|Split|Select|Mask)$/,
      "Recurrence (RRULE)": ~r/^Tempo\.RRule(\.|$)/,
      "iCalendar integration": ~r/^Tempo\.ICal(\.|$)/,
      "ISO 8601 and IXDTF": ~r/^Tempo\.Iso8601(\.|$)/,
      Enumeration: ~r/^Tempo\.Enumeration$|^Enumerable\.Tempo/,
      "Explanation and inspection": ~r/^Tempo\.(Explain|Explanation|Inspect|Sigil|Validation)$/,
      Visualizer: ~r/^Tempo\.Visualizer(\.|$)/,
      Exceptions: ~r/^Tempo\.\w+Error$/
    ]
  end

  defp groups_for_extras do
    [
      Guides: [
        "guides/cookbook.md",
        "guides/set-operations.md",
        "guides/enumeration-semantics.md",
        "guides/ical-integration.md"
      ],
      Reference: [
        "guides/iso8601-conformance.md",
        "guides/shared-ast-iso8601-and-rrule.md"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :tzdata, :localize]
    ]
  end

  defp deps do
    [
      {:nimble_parsec, "~> 1.0"},
      {:calendrical, "~> 0.3"},
      {:astro, "~> 2.0"},
      {:localize, "~> 0.20"},
      {:tzdata, "~> 1.1"},
      {:ical, github: "expothecary/ical", optional: true},
      {:plug, "~> 1.15", optional: true},
      {:bandit, "~> 1.5", optional: true},
      {:ex_doc, "~> 0.21", runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ] ++ maybe_json_polyfill()
  end

  defp maybe_json_polyfill do
    if Code.ensure_loaded?(:json) do
      []
    else
      [{:json_polyfill, "~> 0.2 or ~> 1.0"}]
    end
  end

  defp elixirc_paths(:test), do: ["lib", "mix", "test", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "mix", "bench"]
  defp elixirc_paths(_), do: ["lib"]
end
