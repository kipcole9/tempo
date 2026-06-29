defmodule Tempo.Network.RelationTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Network.Relation

  describe "to_atomic/1 — qualitative relations" do
    test "before / after are strict on the integer scale" do
      assert Relation.new(:before, :a, :b) |> Relation.to_atomic() ==
               [{{:end, :a}, {:start, :b}, -1}]

      assert Relation.new(:after, :a, :b) |> Relation.to_atomic() ==
               [{{:end, :b}, {:start, :a}, -1}]
    end

    test "contemporary requires a non-empty overlap" do
      assert Relation.new(:contemporary, :a, :b) |> Relation.to_atomic() ==
               [{{:start, :b}, {:end, :a}, 0}, {{:start, :a}, {:end, :b}, 0}]
    end

    test "includes and included_in are duals" do
      assert Relation.new(:includes, :a, :b) |> Relation.to_atomic() ==
               [{{:start, :a}, {:start, :b}, 0}, {{:end, :b}, {:end, :a}, 0}]

      assert Relation.new(:included_in, :a, :b) |> Relation.to_atomic() ==
               [{{:start, :b}, {:start, :a}, 0}, {{:end, :a}, {:end, :b}, 0}]
    end

    test "equals constrains both boundaries (four edges)" do
      atomics = Relation.new(:equals, :a, :b) |> Relation.to_atomic()

      assert atomics == [
               {{:start, :a}, {:start, :b}, 0},
               {{:start, :b}, {:start, :a}, 0},
               {{:end, :a}, {:end, :b}, 0},
               {{:end, :b}, {:end, :a}, 0}
             ]
    end

    test "synchronous_start / synchronous_end pin one shared boundary" do
      assert Relation.new(:synchronous_start, :a, :b) |> Relation.to_atomic() ==
               [{{:start, :a}, {:start, :b}, 0}, {{:start, :b}, {:start, :a}, 0}]

      assert Relation.new(:synchronous_end, :a, :b) |> Relation.to_atomic() ==
               [{{:end, :a}, {:end, :b}, 0}, {{:end, :b}, {:end, :a}, 0}]
    end

    test "overlaps is non-strict per the paper (start ≤ start ≤ end ≤ end)" do
      assert Relation.new(:overlaps, :a, :b) |> Relation.to_atomic() ==
               [
                 {{:start, :a}, {:start, :b}, 0},
                 {{:start, :b}, {:end, :a}, 0},
                 {{:end, :a}, {:end, :b}, 0}
               ]
    end

    test "starts_during places A's start inside B" do
      # start(B) ≤ start(A) ≤ end(B)
      assert Relation.new(:starts_during, :a, :b) |> Relation.to_atomic() ==
               [{{:start, :b}, {:start, :a}, 0}, {{:start, :a}, {:end, :b}, 0}]
    end

    test "ends_during places A's end inside B" do
      # start(B) ≤ end(A) ≤ end(B)
      assert Relation.new(:ends_during, :a, :b) |> Relation.to_atomic() ==
               [{{:start, :b}, {:end, :a}, 0}, {{:end, :a}, {:end, :b}, 0}]
    end
  end

  describe "to_atomic/1 — metric (delay) relations" do
    test "exactly emits both directions" do
      relation = Relation.new({:delay, :end, :start, :exactly, ~o"P10Y"}, :a, :b)

      assert Relation.to_atomic(relation) == [
               {{:start, :b}, {:end, :a}, {:duration, ~o"P10Y"}},
               {{:end, :a}, {:start, :b}, {:neg_duration, ~o"P10Y"}}
             ]
    end

    test "at_least is a single lower-bound edge" do
      relation = Relation.new({:delay, :start, :start, :at_least, ~o"P20Y"}, :a, :b)

      assert Relation.to_atomic(relation) ==
               [{{:start, :a}, {:start, :b}, {:neg_duration, ~o"P20Y"}}]
    end

    test "at_most is a single upper-bound edge" do
      relation = Relation.new({:delay, :start, :start, :at_most, ~o"P20Y"}, :a, :b)

      assert Relation.to_atomic(relation) ==
               [{{:start, :b}, {:start, :a}, {:duration, ~o"P20Y"}}]
    end
  end

  describe "Allen bridge" do
    test "to_allen / from_allen round-trip the one-to-one relations" do
      for type <- [
            :before,
            :after,
            :immediately_precedes,
            :immediately_follows,
            :overlaps,
            :includes,
            :included_in,
            :equals
          ] do
        assert Relation.from_allen(Relation.to_allen(type)) == type
      end
    end

    test "loose relations map to a disjunction of Allen relations" do
      assert :equals in Relation.to_allen(:synchronous_start)
      assert :starts in Relation.to_allen(:synchronous_start)
      assert Relation.to_allen({:delay, :start, :start, :exactly, ~o"P1Y"}) == nil
    end
  end
end
