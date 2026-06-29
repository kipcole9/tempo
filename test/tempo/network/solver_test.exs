defmodule Tempo.Network.SolverTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Network
  alias Tempo.Network.{Solver, TimePeriod}

  doctest Tempo.Network.Solver
  doctest Tempo.Network.Normalize

  # Read the integer year of a tightened bound.
  defp years(period) do
    %{
      start: {TimePeriod.year(period.earliest_start), TimePeriod.year(period.latest_start)},
      end: {TimePeriod.year(period.earliest_end), TimePeriod.year(period.latest_end)},
      duration: {duration_years(period.min_duration), duration_years(period.max_duration)}
    }
  end

  defp duration_years(nil), do: nil
  defp duration_years(%Tempo.Duration{time: time}), do: Keyword.get(time, :year)

  describe "consistency" do
    test "a single well-formed period is consistent" do
      assert Network.new()
             |> Network.add_period(:k, start: 1200, duration: {:at_least, 10})
             |> Solver.consistent?()
    end

    test "an end before a start is inconsistent" do
      refute Network.new()
             |> Network.add_period(:k, start: 1200, end: 1180)
             |> Solver.consistent?()
    end

    test "a sequence whose links cannot be satisfied is inconsistent" do
      # k1 must end by 1210, k2 must start by 1205, but k1 meets k2 and
      # k1 lasts at least 30 years from a start no earlier than 1200.
      refute Network.new()
             |> Network.add_period(:k1,
               start: {:not_before, 1200},
               duration: {:at_least, 30},
               end: {:not_after, 1210}
             )
             |> Network.add_period(:k2, [])
             |> Network.add_sequence([:k1, :k2])
             |> Solver.consistent?()
    end

    test "contradictory relations are inconsistent" do
      # a is both strictly before b and strictly after b.
      refute Network.new()
             |> Network.add_period(:a, [])
             |> Network.add_period(:b, [])
             |> Network.add_relation(:before, :a, :b)
             |> Network.add_relation(:after, :a, :b)
             |> Solver.consistent?()
    end
  end

  describe "tightening — sequence with two-sided bounds" do
    setup do
      {:ok, tightened} =
        Network.new()
        |> Network.add_period(:k1, start: {1200, 1210}, duration: {20, 30})
        |> Network.add_period(:k2, duration: {35, 50})
        |> Network.add_sequence([:k1, :k2])
        |> Solver.tighten()

      %{network: tightened}
    end

    test "k1 propagates start + duration into its end", %{network: network} do
      assert years(network.periods[:k1]) == %{
               start: {1200, 1210},
               # end = start + duration ∈ [1200+20, 1210+30]
               end: {1220, 1240},
               duration: {20, 30}
             }
    end

    test "k2 inherits its start from k1's end and pushes its own end", %{network: network} do
      assert years(network.periods[:k2]) == %{
               # start(k2) = end(k1) ∈ [1220, 1240]
               start: {1220, 1240},
               # end(k2) = start(k2) + duration ∈ [1220+35, 1240+50]
               end: {1255, 1290},
               duration: {35, 50}
             }
    end
  end

  describe "tightening — relations" do
    test "inclusion nests one period inside another" do
      {:ok, network} =
        Network.new()
        |> Network.add_period(:k, start: {1200, 1200}, end: {1260, 1260})
        |> Network.add_period(:s, duration: {:at_least, 10})
        |> Network.add_relation(:included_in, :s, :k)
        |> Solver.tighten()

      # s sits within k = [1200, 1260]: its start ≥ 1200, end ≤ 1260,
      # and (start ≤ end − 10) so start ≤ 1250 and end ≥ 1210.
      assert years(network.periods[:s]) == %{
               start: {1200, 1250},
               end: {1210, 1260},
               duration: {10, 60}
             }
    end

    test "a delay relation enforces a minimum gap" do
      # start(b) is at least 40 years after start(a): a delay where
      # start(a) is at least 40 before start(b).
      {:ok, network} =
        Network.new()
        |> Network.add_period(:a, start: {1000, 1000})
        |> Network.add_period(:b, [])
        |> Network.add_relation({:delay, :start, :start, :at_least, ~o"P40Y"}, :a, :b)
        |> Solver.tighten()

      assert TimePeriod.year(network.periods[:b].earliest_start) == 1040
    end

    test "contemporaneity forces overlapping windows to meet" do
      # a ends by 1100; b is contemporary with a, so b starts by 1100.
      {:ok, network} =
        Network.new()
        |> Network.add_period(:a, end: {:not_after, 1100})
        |> Network.add_period(:b, start: {:not_before, 1050})
        |> Network.add_relation(:contemporary, :a, :b)
        |> Solver.tighten()

      assert TimePeriod.year(network.periods[:b].latest_start) == 1100
    end
  end

  describe "tighten/1 on an inconsistent network" do
    test "returns an error tuple" do
      assert {:error, :inconsistent} =
               Network.new()
               |> Network.add_period(:k, start: 1200, end: 1180)
               |> Solver.tighten()
    end
  end

  describe "trace/3" do
    test "explains an earliest bound as a chain of named constraints" do
      {:ok, trace} =
        Network.new()
        |> Network.add_period(:k1, start: {:not_before, 1200}, duration: {:at_least, 20})
        |> Network.add_period(:k2, duration: {:at_least, 35})
        |> Network.add_sequence([:k1, :k2])
        |> Solver.trace({:end, :k2})

      assert TimePeriod.year(trace.value) == 1255
      assert List.last(trace.steps).boundary == {:end, :k2}
      assert trace.prose =~ "immediately precedes"
    end

    test "an unbounded boundary returns {:error, :unbounded}" do
      assert {:error, :unbounded} =
               Network.new()
               |> Network.add_period(:k, duration: {:at_least, 10})
               |> Solver.trace({:end, :k}, bound: :latest)
    end

    test "an inconsistent network returns {:error, :inconsistent}" do
      assert {:error, :inconsistent} =
               Network.new()
               |> Network.add_period(:k, start: 1200, end: 1180)
               |> Solver.trace({:start, :k})
    end
  end
end
