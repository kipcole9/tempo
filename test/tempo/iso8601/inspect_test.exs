defmodule Tempo.Iso8601.InspectTest do
  use ExUnit.Case, async: true
  import Tempo.Sigil

  test "Inspect" do
    assert inspect(Tempo.from_iso8601!("2022Y12M31D")) == "~o\"2022Y12M31D\""
    assert inspect(Tempo.from_iso8601!("2022Y12M31D1H10M59S")) == "~o\"2022Y12M31DT1H10M59S\""
  end

  test "Inspect with groups" do
    assert inspect(Tempo.from_iso8601!("2022Y3G4DU")) == "~o\"2022Y3G4DU\""
  end

  test "Inspect with other calendars" do
    assert inspect(Tempo.from_iso8601!("2022Y3G4DU", Cldr.Calendar.ISOWeek)) == "~o\"2022Y3G4DU\"W"
  end

  test "Inspect interval" do
    assert inspect(Tempo.from_iso8601!("2022Y2M/4M")) == "~o\"2022Y2M/4M\""
  end

  test "Inspect duration" do
    assert inspect(Tempo.from_iso8601!("P2022Y2M1Y")) == "~o\"P2022Y2M1Y\""
    assert inspect(Tempo.from_iso8601!("P2022Y")) == "~o\"P2022Y\""
  end

  test "Inspect set" do
    assert inspect(Tempo.from_iso8601!("{2022Y,2021Y,2021Y12M}")) == "~o\"{2022Y,2021Y,2021Y12M}\""
  end

  test "Groups with sets" do
    assert inspect(~o"{1,4,7..9}G1YU") == "~o\"{1,4,7..9}G1YU\""
    assert inspect(~o"{1,4,7..9}G2YU3M1D") == "~o\"{1,4,7..9}G2YU3M1D\""
  end
end
