defmodule Tempo.ExplainCoverageTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  describe "anchored headlines at each precision" do
    test "year" do
      assert Tempo.explain(~o"2020Y") =~ "The year 2020."
    end

    test "month" do
      assert Tempo.explain(~o"2020Y6M") =~ "June 2020."
    end

    test "day" do
      assert Tempo.explain(~o"2020Y6M15D") =~ "June 15, 2020."
    end
  end

  describe "masked years" do
    test "a decade mask names the decade" do
      assert Tempo.explain(~o"201X") =~ "the 2010s"
    end

    test "a century mask names the century" do
      assert Tempo.explain(~o"20XX") =~ "the 2000s (century)"
    end

    test "an all-digits mask spans every 4-digit year" do
      assert Tempo.explain(~o"XXXX") =~ "all 4-digit years"
    end
  end

  describe "intervals and sets" do
    test "a closed interval is described by its endpoints" do
      prose = Tempo.explain(~o"2020Y/2021Y")
      assert prose =~ "A closed interval."
      assert prose =~ "From: 2020-01-01."
    end

    test "a set reports how many disjoint intervals it materialises to" do
      assert Tempo.explain(~o"{2020,2021,2022,2023}Y") =~ "Materialises to 4 disjoint intervals."
    end
  end
end
