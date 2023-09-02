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
    assert inspect(Tempo.from_iso8601!("2022Y3G4DU", Cldr.Calendar.ISOWeek)) ==
             "~o\"2022Y3G4DU\"W"
  end

  test "Inspect interval" do
    assert inspect(Tempo.from_iso8601!("2022Y2M/4M")) == "~o\"2022Y2M/4M\""
  end

  test "Inspect duration" do
    assert inspect(Tempo.from_iso8601!("P2022Y2M1Y")) == "~o\"P2022Y2M1Y\""
    assert inspect(Tempo.from_iso8601!("P2022Y")) == "~o\"P2022Y\""
  end

  test "Inspect set" do
    assert inspect(Tempo.from_iso8601!("{2022Y,2021Y,2021Y12M}")) ==
             "~o\"{2022Y,2021Y,2021Y12M}\""
  end

  test "Groups with sets" do
    assert inspect(~o"{1,4,7..9}G1YU") == "~o\"{1,4,7..9}G1YU\""
    assert inspect(~o"{1,4,7..9}G2YU3M1D") == "~o\"{1,4,7..9}G2YU3M1D\""
  end

  test "Repeat rule" do
    assert inspect(~o"R12/2015Y9M29DT14H0M0S/PT1H30M0S/F2W") ==
             "~o\"R12/2015Y9M29DT14H0M0S/PT1H30M0S/F2W\""

    assert inspect(~o"R/2018-08-08/P1D/F1YL{3,8}M8DN") ==
             "~o\"R/2018Y8M8D/P1D/F1YL{3,8}M8DN\""

    assert inspect(~o"R/2018-09-05/P1D/F1YL9M3K1IN") ==
             "~o\"R/2018Y9M5D/P1D/F1YL9M3K1IN\""

    assert inspect(~o"R/2018Y1M/P1M/F3M") ==
             "~o\"R/2018Y1M/P1M/F3M\""

    assert inspect(~o"R/2018Y1M1D/P1D/F3M") ==
             "~o\"R/2018Y1M1D/P1D/F3M\""

    assert inspect(~o"R/2018Y1M1DT0M/PT10M/F1M") ==
             "~o\"R/2018Y1M1DT0H0M/PT10M/F1M\""

    assert inspect(~o"R/2018-08-01T01:02:03/PT5M/F1D") ==
             "~o\"R/2018Y8M1DT1H2M3S/PT5M/F1D\""

    assert inspect(~o"R/2018Y8M1DT1H/P1D/F2ML{1,3}DN") ==
             "~o\"R/2018Y8M1DT1H/P1D/F2ML{1,3}DN\""
  end

  test "Repeat rule with time after selector" do
    assert inspect(~o"R/2018-08-01T10:20:00/PT10M/F1ML{1,10}DT10H20M0SN") ==
             "~o\"R/2018Y8M1DT10H20M0S/PT10M/F1ML{1,10}DT10H20M0SN\""

    assert inspect(~o"R/20150104T083000/PT15M00S/F2YL1M1KT{8,9}H30MN") ==
             "~o\"R/2015Y1M4DT8H30M0S/PT15M0S/F2YL1M1KT{8..9}H30MN\""
  end

  test "Dates with masks" do
    assert inspect(~o"2023-WX{2,4,6,8,0}") == "~o\"2023YX{0,2,4,6,8}W\""
    assert inspect(~o"2023YX{2,4,6,8,0}W") == "~o\"2023YX{0,2,4,6,8}W\""
  end

  test "Dates with stepped ranges" do
    assert inspect(~o"2023Y{1..-1//2}W") ==
             "~o\"2023Y{1..53//2}W\""

    assert inspect(~o"R/2018-08-01T10:20:00/PT10M/F1ML{1..10//2}DT10H20M0SN") ==
             "~o\"R/2018Y8M1DT10H20M0S/PT10M/F1ML{1..10//2}DT10H20M0SN\""
  end

  test "Unspecified digits" do
    assert inspect(~o"2052Y1MXD") ==
             "~o\"2052Y1MXD\""

    assert inspect(~o"195XY") ==
             "~o\"195XY\""

    assert inspect(~o"1390YXXM") ==
             "~o\"1390YXXM\""

    assert inspect(~o"2052Y1MX*D") ==
             "~o\"2052Y1MX*D\""

    assert inspect(~o"XXXYX*MXD") ==
             "~o\"XXXYX*MXD\""

    assert inspect(~o"X*Y12M28D") ==
             "~o\"X*Y12M28D\""
  end
end
