defmodule Tempo.Tour do
  @moduledoc """
  A guided tour of Tempo's distinctive capabilities, printed to
  the iex console.

  The tour is meant to be read over someone's shoulder in the
  first thirty seconds of using the library — a conference-demo
  sequence that proves the thesis ("time is intervals, not
  instants") through eight small, running examples.

  Invoke from iex:

      iex> Tempo.tour()

  The tour evaluates each example against the current build and
  prints the real result — nothing is mocked.

  """

  import Tempo.Sigil

  @doc """
  Print the guided tour and return `:ok`.

  See the module doc for the intent. The output is stable enough
  to screenshot for conference slides, but each example is live
  Elixir — it runs on every invocation.

  """
  @spec run() :: :ok
  def run do
    Process.put(:tempo_tour_step, 0)
    header()

    step(
      "Time is intervals, not instants",
      "{from, to} = Tempo.Interval.endpoints(Tempo.to_interval!(~o\"2026-06-15\"))",
      fn ->
        {from, to} = Tempo.Interval.endpoints(Tempo.to_interval!(~o"2026-06-15"))
        "{#{inspect(from)}, #{inspect(to)}}"
      end,
      "June 15 IS a span — from midnight to the following midnight, half-open."
    )

    step(
      "Every Tempo value is enumerable at the next-finer unit",
      "Enum.count(~o\"2026-06\")",
      fn -> Enum.count(~o"2026-06") end,
      "A month iterates as 30 days. A year iterates as 12 months."
    )

    step(
      "Archaeological dates — the 1560s as a first-class value",
      "Enum.map(~o\"156X\", &Tempo.year/1)",
      fn -> inspect(Enum.map(~o"156X", &Tempo.year/1)) end,
      "The ISO 8601-2 masked year is a bounded, enumerable span."
    )

    step(
      "Set operations on intervals",
      "{:ok, merged} = Tempo.union(~o\"2022Y\", ~o\"2023Y\"); Tempo.IntervalSet.count(merged)",
      fn ->
        {:ok, merged} = Tempo.union(~o"2022Y", ~o"2023Y")
        Tempo.IntervalSet.count(merged)
      end,
      "Touching years coalesce into one span — [2022-01-01, 2024-01-01)."
    )

    step(
      "Cross-calendar comparison via an IXDTF suffix",
      "{:ok, hebrew} = Tempo.from_iso8601(\"5786-10-30[u-ca=hebrew]\"); Tempo.overlaps?(hebrew, ~o\"2026-06-15\")",
      fn ->
        {:ok, hebrew} = Tempo.from_iso8601("5786-10-30[u-ca=hebrew]")
        Tempo.overlaps?(hebrew, ~o"2026-06-15")
      end,
      "Hebrew ∩ Gregorian — the calendar conversion happens automatically."
    )

    step(
      "Locale-aware selectors — the workdays of June",
      "{:ok, workdays} = Tempo.select(~o\"2026-06\", :workdays); Tempo.IntervalSet.count(workdays)",
      fn ->
        {:ok, workdays} = Tempo.select(~o"2026-06", :workdays)
        Tempo.IntervalSet.count(workdays)
      end,
      "Monday-through-Friday in the default locale (US). Other territories " <>
        "have different weekends — `territory: :SA` picks Friday and Saturday."
    )

    step(
      "Leap seconds as interval metadata",
      "Tempo.Interval.spans_leap_second?(%Tempo.Interval{from: ~o\"2016-12-31T23:00:00Z\", to: ~o\"2017-01-01T01:00:00Z\"})",
      fn ->
        inspect(
          Tempo.Interval.spans_leap_second?(%Tempo.Interval{
            from: ~o"2016-12-31T23:00:00Z",
            to: ~o"2017-01-01T01:00:00Z"
          })
        )
      end,
      "IERS has inserted 27 positive leap seconds since 1972. Tempo exposes " <>
        "them as interval metadata via `spans_leap_second?/1`, `leap_seconds_spanned/1`, " <>
        "and `duration(iv, leap_seconds: true)` — without breaking stdlib interop."
    )

    step(
      "Allen's interval algebra",
      "Tempo.compare(~o\"2022-06\", ~o\"2022-07\")",
      fn -> inspect(Tempo.compare(~o"2022-06", ~o"2022-07")) end,
      "Two intervals relate in one of thirteen named ways. June and July " <>
        "`:meets` — June ends exactly where July begins, no overlap, no gap."
    )

    footer()
    :ok
  end

  ## Private formatting helpers

  defp header do
    IO.puts("")
    IO.puts("  Tempo — a guided tour")
    IO.puts("  #{String.duplicate("─", 60)}")
    IO.puts("")
    IO.puts("  Time is intervals, not instants. Every Tempo value is")
    IO.puts("  a bounded span on the time line. Below, eight examples.")
  end

  defp step(title, code, result_fun, comment) do
    IO.puts("")
    IO.puts("  #{bold()}[#{step_counter()}] #{title}#{reset()}")
    IO.puts("")
    IO.puts("      iex> #{code}")
    IO.puts("      #=> #{result_fun.()}")
    IO.puts("")
    IO.puts("      #{comment}")
  end

  defp footer do
    IO.puts("")
    IO.puts("  #{String.duplicate("─", 60)}")
    IO.puts("  Next steps:")
    IO.puts("    * `Tempo.explain/1`  — describe any value in plain English.")
    IO.puts("    * `guides/cookbook.md`  — recipes for real queries.")
    IO.puts("    * `guides/set-operations.md`  — the full set algebra.")
    IO.puts("")
  end

  # Step counter — the macros would be prettier but a process
  # dictionary counter keeps the tour self-contained and the steps
  # renumber automatically when added or removed.
  defp step_counter do
    current = Process.get(:tempo_tour_step, 0) + 1
    Process.put(:tempo_tour_step, current)
    current
  end

  # ANSI codes — fall back to empty strings when stdout isn't a
  # terminal (e.g. piped to a file or captured in tests).
  defp bold, do: maybe_ansi("\e[1m")
  defp reset, do: maybe_ansi("\e[0m")

  defp maybe_ansi(code) do
    if IO.ANSI.enabled?(), do: code, else: ""
  end
end
