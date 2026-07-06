defmodule Tempo.Protocol.InspectIntervalSetTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalSet

  defp set(sigil), do: sigil |> Tempo.to_interval_set() |> elem(1)

  test "an empty set inspects as an empty list" do
    assert inspect(%IntervalSet{intervals: []}) == "#Tempo.IntervalSet<[]>"
  end

  test "a small set inspects its members inline" do
    assert inspect(set(~o"{2021,2022,2023}Y")) ==
             ~s|#Tempo.IntervalSet<[~o"2021Y1M/2022Y1M", ~o"2022Y1M/2023Y1M", ~o"2023Y1M/2024Y1M"]>|
  end

  test "a set within the inspect limit shows every member inline" do
    assert inspect(set(~o"{2021,2022,2023,2024,2025}Y")) ==
             ~s|#Tempo.IntervalSet<[~o"2021Y1M/2022Y1M", ~o"2022Y1M/2023Y1M", ~o"2023Y1M/2024Y1M", ~o"2024Y1M/2025Y1M", ~o"2025Y1M/2026Y1M"]>|
  end

  test "a set larger than :limit shows that many members then the locale ellipsis" do
    assert inspect(set(~o"{2021,2022,2023,2024,2025}Y"), limit: 2) ==
             ~s|#Tempo.IntervalSet<[~o"2021Y1M/2022Y1M", ~o"2022Y1M/2023Y1M", …]>|
  end

  test "the inspect limit is honoured as :infinity" do
    assert inspect(set(~o"{2021,2022,2023,2024,2025}Y"), limit: :infinity) ==
             ~s|#Tempo.IntervalSet<[~o"2021Y1M/2022Y1M", ~o"2022Y1M/2023Y1M", ~o"2023Y1M/2024Y1M", ~o"2024Y1M/2025Y1M", ~o"2025Y1M/2026Y1M"]>|
  end

  test "a calendar name in metadata is shown in the tag" do
    set = %IntervalSet{intervals: [], metadata: %{name: "Holidays"}}
    assert inspect(set) == "#Tempo.IntervalSet<[] · Holidays>"
  end

  test "a prodid in metadata is shown in the tag" do
    set = %IntervalSet{intervals: [], metadata: %{prodid: "-//Acme//EN"}}
    assert inspect(set) == "#Tempo.IntervalSet<[] · -//Acme//EN>"
  end

  test "other metadata falls back to a key count" do
    set = %IntervalSet{intervals: [], metadata: %{source: :ical, imported_at: :now}}
    assert inspect(set) == "#Tempo.IntervalSet<[] · 2 metadata key(s)>"
  end
end
