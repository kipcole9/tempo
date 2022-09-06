defmodule Tempo.GroupResolution.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigil

  test "Group resolution days to hours" do
    assert ~o"2022Y1M1G3DUT26H" == ~o"2022Y1M2DT2H"
    assert ~o"2022Y1M1G3DUT24H" == ~o"2022Y1M2DT0H"

    assert ~o"2022Y1M2G1DUT23H" == ~o"2022Y1M2DT23H"
    assert ~o"2022Y1M1G2DUT24H" == ~o"2022Y1M2DT0H"
    assert ~o"2022Y1M2G2DUT24H" == ~o"2022Y1M4DT0H"
  end

  test "Group resolution hours to minutes" do
    assert ~o"T1G1HU1M" == ~o"0H1M"
    assert ~o"T1G4HU1M" == ~o"0H1M"
    assert ~o"T2G1HU1M" == ~o"1H1M"
    assert ~o"T2G4HU1M" == ~o"4H1M"

    assert ~o"T1G4HU239M" == ~o"3H59M"

    assert Tempo.from_iso8601("T1G4HU240M") == {:error, "240 is not valid. The valid values are 0..239"}
  end

  test "Group resolution minutes to seconds" do
    assert ~o"T1G1MU1S" ==~o"0M1S"
    assert ~o"T1G4MU1S" == ~o"0M1S"
    assert ~o"T2G1MU1S" == ~o"1M1S"
    assert ~o"T2G4MU1S" == ~o"4M1S"

    assert Tempo.from_iso8601("T2G4MU240S") == {:error, "480 is not valid. The valid values are 240..479"}
  end

  test "Seasons expanded to groups" do
    assert ~o"2022Y25M" == ~o"2022Y3M/2022Y5M"
    assert ~o"2022Y26M" == ~o"2022Y6M/2022Y8M"
    assert ~o"2022Y27M" == ~o"2022Y9M/2022Y11M"
    assert ~o"2022Y28M" == ~o"2021Y12M/2022Y2M"
  end

end