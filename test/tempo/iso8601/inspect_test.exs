defmodule Tempo.Iso8601.InspectTest do
  use ExUnit.Case, async: true
  import Tempo.Sigil

  test "Inspect" do
    assert Tempo.from_iso8601!("2022Y12M31D") ==
      ~o"2022Y12M31D"
    assert Tempo.from_iso8601!("2022Y12M31D1H10M59S") ==
      ~o"2022Y12M31DT1H10M59S"
  end

  test "Inspect with groups" do
    assert Tempo.from_iso8601!("2022Y3G4DU") ==
      ~o"2022Y3G4DU"
  end

  test "Inspect with other calendars" do
    assert Tempo.from_iso8601!("2022T3G4DU", Cldr.Calendar.ISOWeek) ==
     Tempo.from_iso8601!("2022Y3G4DU", Cldr.Calendar.ISOWeek)
   end
 end
