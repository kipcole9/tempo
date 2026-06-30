defmodule Tempo.Protocol.InspectIntervalSetTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.IntervalSet

  defp set(sigil), do: sigil |> Tempo.to_interval_set() |> elem(1)

  test "an empty set inspects as an empty list" do
    assert inspect(%IntervalSet{intervals: []}) == "#Tempo.IntervalSet<[]>"
  end

  test "a small set (<= 3 intervals) inspects its members inline" do
    assert inspect(set(~o"{2021,2022,2023}Y")) ==
             ~s|#Tempo.IntervalSet<[~o"2021Y1M/2022Y1M", ~o"2022Y1M/2023Y1M", ~o"2023Y1M/2024Y1M"]>|
  end

  test "a larger set (> 3 intervals) inspects as a count" do
    assert inspect(set(~o"{2021,2022,2023,2024,2025}Y")) == "#Tempo.IntervalSet<5 intervals>"
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
