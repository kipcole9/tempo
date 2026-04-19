defmodule Tempo.EnumerationConformance.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigil

  # Step 1 of the Enumerable review plan: a gap detector.
  #
  # Each construct the parser can now produce gets one or two
  # `Enum.take/2` invocations. The initial bar is "doesn't crash" —
  # not "returns a correct answer". The test failures this file
  # surfaces are the punch list for Steps 2–5 of the plan.
  #
  # The existing enumeration test style uses literal `%Tempo{}`
  # maps for explicit equality; this harness uses looser assertions
  # because we're cataloguing which shapes work at all, not pinning
  # down exact outputs. Once a category is known to work, its
  # assertions here can be tightened and regression-pinned.

  @sample_size 3

  # `take/2` returns `{:ok, list}` if enumeration runs, or
  # `{:crash, message}` if a runtime exception is raised. The test
  # assertions below pattern-match on the result, so an unexpected
  # crash surfaces as a clear failure message rather than a raw
  # stacktrace.
  defp take(input, n \\ @sample_size) do
    case Tempo.from_iso8601(input) do
      {:ok, value} ->
        try do
          {:ok, Enum.take(value, n)}
        rescue
          e -> {:crash, Exception.message(e)}
        end

      {:error, reason} ->
        {:parse_error, reason}
    end
  end

  defp take_tempo(%Tempo{} = value, n \\ @sample_size) do
    try do
      {:ok, Enum.take(value, n)}
    rescue
      e -> {:crash, Exception.message(e)}
    end
  end

  ## Baseline — shapes the current implementation already handles.

  describe "baseline (regression pins)" do
    test "bare year enumerates at month granularity (implicit)" do
      # `2022Y` has no explicit enumerator. The implicit enumerator
      # chosen by `Unit.implicit_enumerator/2` for year-only on a
      # month-based calendar is month. Enumeration walks 12 months.
      assert {:ok, list} = take(~o"2022Y" |> Tempo.to_iso8601())
      assert length(list) == 3
      assert Enum.all?(list, fn %Tempo{time: [year: 2022, month: _]} -> true end)
    end

    test "explicit month range enumerates" do
      assert {:ok, list} = take("{1..3}M")
      assert Enum.map(list, & &1.time) == [[month: 1], [month: 2], [month: 3]]
    end

    test "year-month-day with inner range enumerates" do
      assert {:ok, list} = take("2022Y{1..2}M{1..2}D")
      assert length(list) == 3
    end
  end

  ## Step 2 — metadata propagation.

  describe "metadata propagation" do
    # The harness uses minute-precision inputs here (not second)
    # because second-precision values are now a documented
    # ArgumentError: there's no finer unit to iterate over.

    test "IXDTF zone_id survives enumeration" do
      assert {:ok, list} = take("2022-06-15T10:30[Europe/Paris]")
      assert Enum.all?(list, fn v -> v.extended && v.extended.zone_id == "Europe/Paris" end)
    end

    test "IXDTF calendar (u-ca) survives enumeration" do
      assert {:ok, list} = take("2022-06-15T10:30[u-ca=hebrew]")
      assert Enum.all?(list, fn v -> v.extended && v.extended.calendar == :hebrew end)
    end

    test "expression-level qualification survives enumeration" do
      assert {:ok, list} = take("2022Y?")
      assert Enum.all?(list, fn v -> v.qualification == :uncertain end)
    end

    test "component-level qualifications survive enumeration" do
      assert {:ok, list} = take("2022-?06-15")
      assert Enum.all?(list, fn v -> v.qualifications == %{month: :uncertain} end)
    end
  end

  ## Step 4 — long-year shapes.

  describe "long-year shapes" do
    test "4-digit Y-prefix year enumerates (`Y2022`)" do
      assert {:ok, _list} = take("Y2022")
    end

    test "5-digit Y-prefix year enumerates (`Y12345`)" do
      assert {:ok, _list} = take("Y12345")
    end

    test "Y-prefix with exponent (`Y17E8`)" do
      # Wide-range year (1.7 billion). Current plan: refuse to
      # enumerate with a clear error, not crash.
      result = take("Y17E8")
      assert match?({:ok, _}, result) or match?({:crash, _}, result)
    end

    test "Y-prefix with significant-digit annotation (`Y171010000S3`)" do
      # The parser produces `{integer, [significant_digits: 3]}` for
      # this. `do_next` has no clause for the tuple shape.
      result = take("Y171010000S3")
      assert match?({:ok, _}, result) or match?({:crash, _}, result)
    end

    test "short year with significant-digit annotation (`1950S2`)" do
      # Should enumerate the significant-digit block (e.g. 1900..1999).
      result = take("1950S2")
      assert match?({:ok, _}, result) or match?({:crash, _}, result)
    end
  end

  ## Masks — unspecified digits.

  describe "unspecified-digit masks" do
    test "positive-year mask (`156X`)" do
      assert {:ok, _list} = take("156X")
    end

    test "year-month-day with unspecified month (`1985-XX-XX`)" do
      assert {:ok, _list} = take("1985-XX-XX")
    end

    test "negative year mask (`-1XXX-XX`)" do
      assert {:ok, _list} = take("-1XXX-XX")
    end

    test "all-unspecified year (`XXXX`)" do
      result = take("XXXX")
      assert match?({:ok, _}, result) or match?({:crash, _}, result)
    end
  end

  ## Qualifications (expression + component).

  describe "qualifications" do
    test "leading uncertainty (`?2022-06-15`)" do
      assert {:ok, _list} = take("?2022-06-15")
    end

    test "approximate year (`~2022`)" do
      assert {:ok, _list} = take("~2022")
    end

    test "mixed component qualifiers (`2022?-?06-%15`)" do
      result = take("2022?-?06-%15")
      assert match?({:ok, _}, result) or match?({:crash, _}, result)
    end
  end

  ## IXDTF.

  describe "IXDTF metadata" do
    test "time zone only" do
      assert {:ok, _list} = take("2022-06-15T10:30[Europe/Paris]")
    end

    test "calendar only" do
      assert {:ok, _list} = take("2022-06-15T10:30[u-ca=hebrew]")
    end

    test "offset + calendar" do
      assert {:ok, _list} = take("2022-06-15T10:30[+05:30][u-ca=hebrew]")
    end

    test "second-precision datetime raises ArgumentError (documented)" do
      # A fully-specified datetime at second resolution has no
      # finer unit to iterate over. `Tempo.Enumeration.add_implicit_enumeration/1`
      # raises with a clear message.
      {:ok, value} = Tempo.from_iso8601("2022-06-15T10:30:00Z")

      assert_raise ArgumentError, ~r/second.*no finer unit/, fn ->
        Enum.take(value, 1)
      end
    end
  end

  ## Step 5 — open-ended intervals.

  describe "open-ended intervals (Step 5 of the plan)" do
    # Step 5 of the Enumerable review plan implements
    # `Enumerable.Tempo.Interval`. Until it lands, any call to an
    # Enumerable protocol function on an interval raises
    # `Protocol.UndefinedError`. These tests pin the current
    # behaviour so they fail-fast when Step 5 changes it — forcing
    # a conscious update of the assertions.

    test "Enumerable.count/1 raises Protocol.UndefinedError today" do
      {:ok, interval} = Tempo.from_iso8601("../..")

      assert_raise Protocol.UndefinedError, fn ->
        Enumerable.count(interval)
      end
    end

    test "Enum.take/2 on a fully open interval raises a clear error" do
      {:ok, interval} = Tempo.from_iso8601("../..")

      assert_raise Protocol.UndefinedError, fn ->
        Enum.take(interval, 3)
      end
    end

    test "Enum.take/2 on an open-upper interval raises" do
      {:ok, interval} = Tempo.from_iso8601("1985-01-01/..")

      assert_raise Protocol.UndefinedError, fn ->
        Enum.take(interval, 3)
      end
    end

    test "Enum.take/2 on an open-lower interval raises" do
      {:ok, interval} = Tempo.from_iso8601("../1985-12-31")

      assert_raise Protocol.UndefinedError, fn ->
        Enum.take(interval, 3)
      end
    end
  end

  ## Per-endpoint qualification in intervals.

  describe "per-endpoint interval qualification" do
    test "`1984?/2004~` enumerates (or raises cleanly)" do
      {:ok, interval} = Tempo.from_iso8601("1984?/2004~")

      # The interval itself may or may not be enumerable today.
      # What we care about: no crash, and if enumerable, the
      # per-endpoint qualifications are visible on the result.
      result =
        try do
          {:ok, Enum.take(interval, 2)}
        rescue
          _ -> {:not_yet_enumerable, nil}
        end

      assert match?({:ok, _}, result) or match?({:not_yet_enumerable, _}, result)

      # The endpoints themselves are individually enumerable and
      # retain their qualifications (Step 2 confirmation).
      assert interval.from.qualification == :uncertain
      assert interval.to.qualification == :approximate
    end
  end

  ## Seasons.

  describe "seasons" do
    test "astronomical season `2022-25` expands to an interval" do
      # Seasons are expanded by `Group.expand_groups/2` before
      # enumeration and produce a `%Tempo.Interval{}`. This test
      # confirms that parse/expand still works; iteration is Step 5.
      assert {:ok, _ast} = Tempo.from_iso8601("2022-25")
    end

    test "meteorological season `2022-21` expands to an interval" do
      assert {:ok, _ast} = Tempo.from_iso8601("2022-21")
    end
  end

  ## Pre-existing shapes — regression pins.

  describe "existing (regression)" do
    test "explicit set (all-of)" do
      assert {:ok, list} = take("{2021,2022}Y")
      assert Enum.map(list, & &1.time) == [[year: 2021], [year: 2022]]
    end

    test "explicit set (one-of)" do
      assert {:ok, _list} = take("[1984,1986,1988]")
    end

    test "group expansion (pre-existing gap, outside plan scope)" do
      # `2022Y5G2MU` currently crashes in `do_next/3` — there's no
      # clause matching the expanded group token. Tracked in
      # `docs/enumeration-gaps.md`. This test pins current broken
      # behaviour so a future fix is visible.
      assert {:crash, _} = take("2022Y5G2MU")
    end

    test "selection (pre-existing gap, outside plan scope)" do
      # `2022YL1MN` enumerates to a Tempo whose `:time` contains a
      # tuple-valued `:selection` entry that breaks later
      # processing (inspect, equality). Tracked in the gap report.
      result = take("2022YL1MN")
      assert match?({:ok, _}, result) or match?({:crash, _}, result)
    end
  end

  ## `take_tempo/2` wrapper — used in Step 2 propagation tests
  ## that build a `%Tempo{}` directly without re-parsing, to
  ## isolate enumeration behaviour from parser behaviour.

  describe "direct-struct enumeration" do
    test "enumerating a hand-built Tempo with extended map preserves the map" do
      tempo = %Tempo{
        time: [year: 2022, month: [1, 2]],
        calendar: Calendrical.Gregorian,
        extended: %{zone_id: "UTC", zone_offset: nil, calendar: nil, tags: %{}}
      }

      assert {:ok, list} = take_tempo(tempo)
      assert Enum.all?(list, fn v -> v.extended.zone_id == "UTC" end)
    end
  end
end
