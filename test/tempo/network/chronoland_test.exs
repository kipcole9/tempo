defmodule Tempo.Network.ChronoLandTest do
  use ExUnit.Case, async: true

  # The "ChronoLand" worked example from Levy, Geeraerts, Pluquet,
  # Piasetzky & Fantalkin, "Chronological networks in archaeology: A
  # formalised scheme", Journal of Archaeological Science (2020),
  # https://doi.org/10.1016/j.jas.2020.105225 — Fig. 6 (consistent) and
  # Fig. 7 (inconsistent variant). The tightened bounds asserted here
  # are the paper's published values (Fig. 6b).
  #
  # Kingdom of ChronoLand: kings K1 then K2 reign in succession, both
  # between 1200 and 1300 CE; K1's reign is at most 10 years and K2's at
  # least 35. Two strata S1 (built under K1, who founded ChronoCity) and
  # S2 (destroyed by fire under K2) follow one another, each lasting
  # 20–100 years.

  alias Tempo.Network
  alias Tempo.Network.{Solver, TimePeriod}

  defp chronoland do
    Network.new()
    |> Network.add_period(:k1, start: {:not_before, 1200}, duration: {:at_most, 10})
    |> Network.add_period(:k2, end: {:not_after, 1300}, duration: {:at_least, 35})
    |> Network.add_period(:s1, duration: {20, 100})
    |> Network.add_period(:s2, duration: {20, 100})
    |> Network.add_sequence([:k1, :k2])
    |> Network.add_sequence([:s1, :s2])
    |> Network.add_relation(:starts_during, :s1, :k1)
    |> Network.add_relation(:ends_during, :s2, :k2)
  end

  defp bounds(period) do
    %{
      start: {TimePeriod.year(period.earliest_start), TimePeriod.year(period.latest_start)},
      end: {TimePeriod.year(period.earliest_end), TimePeriod.year(period.latest_end)},
      duration: {duration_years(period.min_duration), duration_years(period.max_duration)}
    }
  end

  defp duration_years(nil), do: nil
  defp duration_years(%Tempo.Duration{time: time}), do: Keyword.get(time, :year)

  test "the network is consistent" do
    assert Solver.consistent?(chronoland())
  end

  describe "tightening reproduces the paper's Fig. 6b bounds" do
    setup do
      {:ok, tightened} = Solver.tighten(chronoland())
      %{network: tightened}
    end

    test "K1 — start [1200,1260], end [1200,1265], duration ≤ 10", %{network: network} do
      assert bounds(network.periods[:k1]) == %{
               start: {1200, 1260},
               end: {1200, 1265},
               duration: {nil, 10}
             }
    end

    test "K2 — start [1200,1265], end [1240,1300], duration [35,100]", %{network: network} do
      assert bounds(network.periods[:k2]) == %{
               start: {1200, 1265},
               end: {1240, 1300},
               duration: {35, 100}
             }
    end

    test "S1 — start [1200,1260], end [1220,1280], duration [20,80]", %{network: network} do
      assert bounds(network.periods[:s1]) == %{
               start: {1200, 1260},
               end: {1220, 1280},
               duration: {20, 80}
             }
    end

    test "S2 — start [1220,1280], end [1240,1300], duration [20,80]", %{network: network} do
      assert bounds(network.periods[:s2]) == %{
               start: {1220, 1280},
               end: {1240, 1300},
               duration: {20, 80}
             }
    end
  end

  test "the trace for the earliest end of K2 follows the paper's Fig. 6c" do
    {:ok, trace} = Solver.trace(chronoland(), {:end, :k2}, bound: :earliest)

    assert TimePeriod.year(trace.value) == 1240

    # The six-step propagation: K1 ≥ 1200 → S1 starts during K1 → S1 ≥ 20y
    # → S1 meets S2 → S2 ≥ 20y → S2 ends during K2.
    derived =
      Enum.map(trace.steps, fn step -> {step.boundary, TimePeriod.year(step.value)} end)

    assert derived == [
             {{:start, :k1}, 1200},
             {{:start, :s1}, 1200},
             {{:end, :s1}, 1220},
             {{:start, :s2}, 1220},
             {{:end, :s2}, 1240},
             {{:end, :k2}, 1240}
           ]

    assert trace.prose =~ "lasts at least 20 years"
    assert trace.prose =~ "ends during"
  end

  test "the Fig. 7 variant (K2 at most 25 years) is inconsistent" do
    # The two strata together last at least 40 years, but capping K2 at
    # 25 makes the whole dynasty at most 35 (10 + 25) — too short to
    # contain them.
    network =
      Network.new()
      |> Network.add_period(:k1, start: {:not_before, 1200}, duration: {:at_most, 10})
      |> Network.add_period(:k2, end: {:not_after, 1300}, duration: {:at_most, 25})
      |> Network.add_period(:s1, duration: {20, 100})
      |> Network.add_period(:s2, duration: {20, 100})
      |> Network.add_sequence([:k1, :k2])
      |> Network.add_sequence([:s1, :s2])
      |> Network.add_relation(:starts_during, :s1, :k1)
      |> Network.add_relation(:ends_during, :s2, :k2)

    refute Solver.consistent?(network)
    assert {:error, :inconsistent} = Solver.tighten(network)
  end
end
