defmodule Tempo.MixProject do
  use Mix.Project

  @version "0.2.0-dev"

  def project do
    [
      app: :tempo,
      version: @version,
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs()
    ]
  end

  defp docs do
    [
      main: "Tempo",
      logo: "assets/logo.png",
      extras: [
        "README.md",
        "CHANGELOG.md",
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
      {:calendrical, "~> 0.2"},
      {:astro, "~> 2.0"},
      {:localize, path: "../localize/localize", override: true},
      {:tzdata, "~> 1.1"},
      {:plug, "~> 1.15", optional: true},
      {:bandit, "~> 1.5", optional: true},
      {:ex_doc, "~> 0.21", runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "mix", "test", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "mix", "bench"]
  defp elixirc_paths(_), do: ["lib"]
end
