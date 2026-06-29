defmodule Tempo.NetworkTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Network
  alias Tempo.Network.{Relation, TimePeriod}

  doctest Tempo.Network.TimePeriod
  doctest Tempo.Network.Relation
  doctest Tempo.Network

  describe "TimePeriod.new/2 bound specifications" do
    test "an exact start fixes both start bounds" do
      period = TimePeriod.new(:k1, start: 1200)
      assert TimePeriod.year(period.earliest_start) == 1200
      assert TimePeriod.year(period.latest_start) == 1200
    end

    test "a range start sets the lower and upper bounds" do
      period = TimePeriod.new(:k1, start: {1200, 1250})
      assert TimePeriod.year(period.earliest_start) == 1200
      assert TimePeriod.year(period.latest_start) == 1250
    end

    test "not_before / not_after are one-sided" do
      not_before = TimePeriod.new(:k1, start: {:not_before, 1200})
      assert TimePeriod.year(not_before.earliest_start) == 1200
      assert not_before.latest_start == nil

      not_after = TimePeriod.new(:k2, end: {:not_after, 1300})
      assert not_after.earliest_end == nil
      assert TimePeriod.year(not_after.latest_end) == 1300
    end

    test "duration accepts at_least / at_most / exact / range" do
      assert TimePeriod.new(:a, duration: {:at_least, 20}).min_duration == ~o"P20Y"
      assert TimePeriod.new(:b, duration: {:at_most, 50}).max_duration == ~o"P50Y"

      exact = TimePeriod.new(:c, duration: 30)
      assert exact.min_duration == ~o"P30Y" and exact.max_duration == ~o"P30Y"

      ranged = TimePeriod.new(:d, duration: {20, 50})
      assert ranged.min_duration == ~o"P20Y" and ranged.max_duration == ~o"P50Y"
    end

    test "BCE years are accepted as negative integers and Tempo values" do
      period = TimePeriod.new(:dyn26, start: -664, end: ~o"-525Y")
      assert TimePeriod.year(period.earliest_start) == -664
      assert TimePeriod.year(period.earliest_end) == -525
    end

    test "EDTF/ISO 8601 strings are parsed" do
      period = TimePeriod.new(:k1, start: "1200Y")
      assert TimePeriod.year(period.earliest_start) == 1200
    end

    test "metadata rides along untouched" do
      period = TimePeriod.new(:k1, metadata: %{source: "Manetho"})
      assert period.metadata == %{source: "Manetho"}
    end
  end

  describe "Network builder" do
    test "periods, sequences, and relations accumulate" do
      network =
        Network.new()
        |> Network.add_period(:k1, start: {:not_before, 1200})
        |> Network.add_period(:k2, duration: {:at_least, 35})
        |> Network.add_sequence([:k1, :k2])
        |> Network.add_relation(:immediately_precedes, :k1, :k2)

      assert Map.keys(network.periods) |> Enum.sort() == [:k1, :k2]
      assert network.sequences == [[:k1, :k2]]
      assert [%Relation{type: :immediately_precedes, from: :k1, to: :k2}] = network.relations
    end

    test "add_period/2 with a prebuilt struct replaces a same-id period" do
      period = TimePeriod.new(:k1, name: "first")
      replacement = TimePeriod.new(:k1, name: "second")

      network =
        Network.new()
        |> Network.add_period(period)
        |> Network.add_period(replacement)

      assert map_size(network.periods) == 1
      assert network.periods[:k1].name == "second"
    end

    test "period_ids/1 includes ids named only in relations or sequences" do
      network =
        Network.new()
        |> Network.add_period(:k1, [])
        |> Network.add_sequence([:k1, :k2])
        |> Network.add_relation(:before, :k2, :k3)

      assert Enum.sort(Network.period_ids(network)) == [:k1, :k2, :k3]
    end
  end
end
