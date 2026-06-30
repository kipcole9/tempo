defmodule Tempo.CoreCoverageTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.InvalidDateError

  describe "duration predicates (delegated to Tempo.Interval)" do
    @one_day ~o"2020Y1M1D/2020Y1M2D"

    test "at_most? / exactly?" do
      assert Tempo.at_most?(@one_day, ~o"P1D")
      assert Tempo.exactly?(@one_day, ~o"P1D")
    end

    test "longer_than? / shorter_than?" do
      assert Tempo.longer_than?(@one_day, ~o"PT1H")
      assert Tempo.shorter_than?(@one_day, ~o"P2D")
    end
  end

  describe "Allen relation predicates (delegated to Tempo.Interval)" do
    test "before? / after? hold across a gap" do
      assert Tempo.before?(~o"2020Y", ~o"2022Y")
      assert Tempo.after?(~o"2022Y", ~o"2020Y")
    end

    test "meets? holds for adjacent spans" do
      assert Tempo.meets?(~o"2020Y/2021Y", ~o"2021Y/2022Y")
    end

    test "during? holds for a contained span" do
      assert Tempo.during?(~o"2020Y6M", ~o"2020Y")
    end
  end

  describe "working-day helpers in their default-territory form" do
    test "workdays/0 returns Monday–Friday" do
      assert inspect(Tempo.workdays()) == ~s|~o"{1,2,3,4,5}K"|
    end

    test "weekend? / workday?" do
      assert Tempo.weekend?(~o"2026-06-13")
      assert Tempo.workday?(~o"2026-06-15")
    end

    test "arithmetic skips the weekend" do
      assert Tempo.add_working_days(~o"2026-06-12", 1) == ~o"2026-06-15"
      assert Tempo.next_working_day(~o"2026-06-12") == ~o"2026-06-15"
      assert Tempo.previous_working_day(~o"2026-06-15") == ~o"2026-06-12"
    end

    test "working_days_in counts business days in an interval" do
      assert Tempo.working_days_in(~o"2026-06-15/2026-06-20") == 5
    end
  end

  describe "bang functions raise on invalid input" do
    test "new!/1 raises on an out-of-range component" do
      assert_raise InvalidDateError, fn -> Tempo.new!(year: 2020, month: 13) end
    end

    test "parse!/2 raises on an unparseable string" do
      assert_raise Calendrical.ParseError, fn -> Tempo.parse!("@@@") end
    end
  end
end
