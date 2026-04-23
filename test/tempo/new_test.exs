defmodule Tempo.NewTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  # `Tempo.new/1` is the developer-facing constructor for
  # `%Tempo{}`. Unlike the `~o` sigil (compile-time literal) and
  # `Tempo.from_iso8601/1` (string parsing), `new/1` accepts
  # structured keyword data at runtime — form inputs, database
  # rows, API payloads, test fixtures — and validates it.

  describe "Tempo.new/1 — basic shapes" do
    test "year-only" do
      {:ok, t} = Tempo.new(year: 2026)
      assert t.time == [year: 2026]
      assert t.calendar == Calendrical.Gregorian
    end

    test "year and month" do
      {:ok, t} = Tempo.new(year: 2026, month: 6)
      assert t.time == [year: 2026, month: 6]
    end

    test "calendar date" do
      {:ok, t} = Tempo.new(year: 2026, month: 6, day: 15)
      assert t.time == [year: 2026, month: 6, day: 15]
    end

    test "datetime" do
      {:ok, t} = Tempo.new(year: 2026, month: 6, day: 15, hour: 14, minute: 30)
      assert t.time == [year: 2026, month: 6, day: 15, hour: 14, minute: 30]
    end

    test "bare time of day" do
      {:ok, t} = Tempo.new(hour: 14, minute: 30)
      assert t.time == [hour: 14, minute: 30]
    end

    test "ISO week date" do
      {:ok, t} = Tempo.new(year: 2026, week: 24, day_of_week: 3)
      assert t.time == [year: 2026, week: 24, day_of_week: 3]
    end

    test "ordinal (day-of-year) date" do
      {:ok, t} = Tempo.new(year: 2026, day_of_year: 166)
      assert t.time == [year: 2026, day_of_year: 166]
    end
  end

  describe "Tempo.new/1 — component reordering" do
    # A user may pass components in whatever order is convenient;
    # the constructor reorders them coarse-to-fine (year → month →
    # day → hour → …) so the resulting struct's `:time` always
    # reads naturally and materialisation doesn't depend on caller
    # ordering.

    test "reverse order produces the same canonical order" do
      {:ok, a} = Tempo.new(day: 15, month: 6, year: 2026)
      {:ok, b} = Tempo.new(year: 2026, month: 6, day: 15)
      assert a.time == b.time
    end

    test "chaotic order" do
      {:ok, t} = Tempo.new(minute: 30, year: 2026, day: 15, hour: 14, month: 6)
      assert t.time == [year: 2026, month: 6, day: 15, hour: 14, minute: 30]
    end

    test "week axis reorders correctly" do
      {:ok, t} = Tempo.new(day_of_week: 3, year: 2026, week: 24)
      assert t.time == [year: 2026, week: 24, day_of_week: 3]
    end
  end

  describe "Tempo.new/1 — options" do
    test "zone is set on :extended.zone_id when a time is present" do
      {:ok, t} = Tempo.new(year: 2026, month: 6, day: 15, hour: 14, zone: "Australia/Sydney")
      assert t.extended.zone_id == "Australia/Sydney"
    end

    test "manual shift offset" do
      {:ok, t} = Tempo.new(year: 2026, hour: 14, shift: [hour: 5, minute: 30])
      assert t.shift == [hour: 5, minute: 30]
    end

    test "non-Gregorian calendar" do
      {:ok, t} = Tempo.new(year: 5786, month: 10, day: 30, calendar: Calendrical.Hebrew)
      assert t.calendar == Calendrical.Hebrew
    end

    test "qualification" do
      {:ok, t} = Tempo.new(year: 2026, qualification: :approximate)
      assert t.qualification == :approximate
    end

    test "metadata attaches to :extended.tags" do
      {:ok, t} = Tempo.new(year: 2026, metadata: %{"source" => "form"})
      assert t.extended.tags == %{"source" => "form"}
    end
  end

  describe "Tempo.new/1 — validation errors" do
    test "empty keyword list is rejected" do
      assert {:error, %ArgumentError{}} = Tempo.new([])
    end

    test "unknown component key is rejected" do
      assert {:error, %ArgumentError{message: msg}} = Tempo.new(year: 2026, gremlin: 3)
      assert msg =~ ":gremlin"
    end

    test "non-integer component value is rejected" do
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.new(year: "2026")
    end

    test "month outside calendar range is rejected" do
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.new(year: 2026, month: 13)
    end

    test "day outside month's range is rejected" do
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.new(year: 2026, month: 2, day: 30)
    end

    test "hour outside 0..23 is rejected" do
      assert {:error, %Tempo.InvalidDateError{}} = Tempo.new(year: 2026, hour: 30)
    end

    test "mixing calendar axes is rejected" do
      assert {:error, %ArgumentError{message: msg}} = Tempo.new(year: 2026, month: 6, week: 24)
      assert msg =~ "cannot mix calendar axes"
    end

    test "mixing month and day_of_year is rejected" do
      assert {:error, %ArgumentError{}} = Tempo.new(year: 2026, month: 6, day_of_year: 166)
    end

    test "zone without a time of day is rejected" do
      assert {:error, %ArgumentError{message: msg}} =
               Tempo.new(year: 2026, month: 6, day: 15, zone: "Europe/Paris")

      assert msg =~ ":zone requires"
    end

    test "unknown qualification value is rejected" do
      assert {:error, %ArgumentError{}} = Tempo.new(year: 2026, qualification: :maybe)
    end

    test "non-keyword input is rejected" do
      assert {:error, %ArgumentError{}} = Tempo.new([1, 2, 3])
    end
  end

  describe "Tempo.new!/1" do
    test "returns the bare struct on success" do
      assert %Tempo{time: [year: 2026, month: 6, day: 15]} =
               Tempo.new!(year: 2026, month: 6, day: 15)
    end

    test "raises on invalid input" do
      assert_raise Tempo.InvalidDateError, fn ->
        Tempo.new!(year: 2026, month: 13)
      end
    end

    test "raises ArgumentError for axis mixing" do
      assert_raise ArgumentError, ~r/cannot mix calendar axes/, fn ->
        Tempo.new!(year: 2026, month: 6, week: 24)
      end
    end
  end

  describe "Tempo.Interval.new/1" do
    setup do
      from = Tempo.new!(year: 2026, month: 6, day: 15, hour: 9)
      to = Tempo.new!(year: 2026, month: 6, day: 15, hour: 17)
      %{from: from, to: to}
    end

    test "builds a closed interval from two Tempos", %{from: from, to: to} do
      {:ok, iv} = Tempo.Interval.new(from: from, to: to)
      assert iv.from == from
      assert iv.to == to
    end

    test "open-ended to", %{from: from} do
      {:ok, iv} = Tempo.Interval.new(from: from, to: :undefined)
      assert iv.to == :undefined
    end

    test "open-ended from", %{to: to} do
      {:ok, iv} = Tempo.Interval.new(from: :undefined, to: to)
      assert iv.from == :undefined
    end

    test "from + duration (to is derived lazily)", %{from: from} do
      {:ok, duration} = Tempo.Duration.new(hour: 8)
      {:ok, iv} = Tempo.Interval.new(from: from, duration: duration)
      assert iv.from == from
      assert iv.duration == duration
    end

    test "recurrence and metadata", %{from: from, to: to} do
      {:ok, iv} = Tempo.Interval.new(from: from, to: to, recurrence: 5, metadata: %{name: "demo"})
      assert iv.recurrence == 5
      assert iv.metadata == %{name: "demo"}
    end

    test "from > to is rejected", %{from: from, to: to} do
      # Swap them so from > to
      assert {:error, %Tempo.IntervalEndpointsError{}} =
               Tempo.Interval.new(from: to, to: from)
    end

    test "requires at least one of :from, :to, :duration" do
      assert {:error, %ArgumentError{}} = Tempo.Interval.new([])
    end

    test "rejects unknown option" do
      assert {:error, %ArgumentError{message: msg}} = Tempo.Interval.new(from: nil, nope: 1)
      assert msg =~ ":nope"
    end

    test "rejects non-Tempo :from" do
      assert {:error, %ArgumentError{}} = Tempo.Interval.new(from: "yesterday")
    end

    test "new!/1 raises on invalid input", %{from: from, to: to} do
      assert_raise Tempo.IntervalEndpointsError, fn ->
        Tempo.Interval.new!(from: to, to: from)
      end
    end

    test "new!/1 returns the bare struct on success", %{from: from, to: to} do
      iv = Tempo.Interval.new!(from: from, to: to)
      assert %Tempo.Interval{} = iv
    end
  end

  describe "Tempo.Duration.new/1" do
    test "basic duration" do
      {:ok, d} = Tempo.Duration.new(year: 1, month: 6)
      assert d.time == [year: 1, month: 6]
    end

    test "components reorder coarse-to-fine" do
      {:ok, d} = Tempo.Duration.new(second: 30, year: 1, hour: 2)
      assert d.time == [year: 1, hour: 2, second: 30]
    end

    test "negative components (reverse-direction duration)" do
      {:ok, d} = Tempo.Duration.new(day: -3)
      assert d.time == [day: -3]
    end

    test "rejects unknown key" do
      assert {:error, %ArgumentError{message: msg}} = Tempo.Duration.new(fortnight: 1)
      assert msg =~ ":fortnight"
    end

    test "rejects non-integer value" do
      assert {:error, %ArgumentError{}} = Tempo.Duration.new(day: "3")
    end

    test "rejects empty keyword list" do
      assert {:error, %ArgumentError{}} = Tempo.Duration.new([])
    end

    test "new!/1 raises on invalid input" do
      assert_raise ArgumentError, fn ->
        Tempo.Duration.new!(fortnight: 1)
      end
    end
  end

  describe "composability with Tempo's existing API" do
    test "constructed Tempo plugs into to_interval/1" do
      tempo = Tempo.new!(year: 2026, month: 6, day: 15)
      {:ok, iv} = Tempo.to_interval(tempo)
      assert %Tempo.Interval{} = iv
    end

    test "constructed Tempo plugs into select/2" do
      base = Tempo.new!(year: 2026)
      {:ok, set} = Tempo.select(base, ~o"12-25")
      [xmas] = Tempo.IntervalSet.to_list(set)
      assert xmas.from.time == [year: 2026, month: 12, day: 25]
    end

    test "constructed Interval plugs into intersection/2" do
      june =
        Tempo.Interval.new!(
          from: Tempo.new!(year: 2026, month: 6, day: 1),
          to: Tempo.new!(year: 2026, month: 7, day: 1)
        )

      {:ok, set} = Tempo.intersection(june, ~o"2026-06-15")
      assert Tempo.IntervalSet.count(set) == 1
    end

    test "constructed Duration plugs into Math.add/2" do
      start = Tempo.new!(year: 2026, month: 6, day: 15)
      {:ok, d} = Tempo.Duration.new(day: 7)
      result = Tempo.Math.add(start, d)
      assert result.time[:day] == 22
    end
  end
end
