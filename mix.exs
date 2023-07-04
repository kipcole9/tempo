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
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:nimble_parsec, "~> 1.0"},
      {:ex_cldr_calendars, "~> 1.22"},
      {:astro, "~> 0.10"},
      {:ex_doc, "~> 0.21", runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "mix", "test", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "mix", "bench"]
  defp elixirc_paths(_), do: ["lib"]
end
