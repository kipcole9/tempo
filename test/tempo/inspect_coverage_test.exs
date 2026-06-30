defmodule Tempo.InspectCoverageTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  describe "masked years round-trip through inspect" do
    test "decade" do
      assert inspect(~o"201X") == ~s|~o"201XY"|
    end

    test "century" do
      assert inspect(~o"20XX") == ~s|~o"20XXY"|
    end

    test "all 4-digit years" do
      assert inspect(~o"XXXX") == ~s|~o"XXXXY"|
    end
  end

  describe "open-ended intervals" do
    test "open upper bound" do
      assert inspect(~o"2020Y/..") == ~s|~o"2020Y/.."|
    end

    test "open lower bound" do
      assert inspect(~o"../2020Y") == ~s|~o"../2020Y"|
    end
  end

  describe "durations and closed intervals" do
    test "a duration" do
      assert inspect(~o"P1Y2M3D") == ~s|~o"P1Y2M3D"|
    end

    test "a closed interval" do
      assert inspect(~o"2020Y/2021Y") == ~s|~o"2020Y/2021Y"|
    end
  end
end
