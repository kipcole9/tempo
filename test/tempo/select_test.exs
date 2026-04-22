defmodule Tempo.Select.Test do
  use ExUnit.Case, async: false
  import Tempo.Sigil

  doctest Tempo.Select

  # `Tempo.select/2` narrows a base span by a selector, returning
  # an `{:ok, %Tempo.IntervalSet{}}` tuple. The tests below cover
  # every selector shape, every base shape (Tempo / Interval /
  # IntervalSet), and every rung of the territory-resolution chain
  # inside `Tempo.workdays/1` / `Tempo.weekend/1`.
  #
  # This suite is `async: false` because a couple of tests mutate
  # `Application.put_env(:ex_tempo, :default_territory, _)` to exercise
  # the app-config rung of the territory chain.

  describe "integer-list selector" do
    test "on a month base, indices apply at day resolution" do
      {:ok, set} = Tempo.select(~o"2026-02", [1, 15])
      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      assert days == [1, 15]
    end

    test "on a year base, indices apply at month resolution" do
      {:ok, set} = Tempo.select(~o"2026", [1, 4, 7, 10])
      months = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:month])
      assert months == [1, 4, 7, 10]
    end

    test "on a day base, indices apply at hour resolution" do
      {:ok, set} = Tempo.select(~o"2026-02-15", [9, 12, 17])
      hours = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:hour])
      assert hours == [9, 12, 17]
    end

    test "empty list returns an empty IntervalSet" do
      assert {:ok, %Tempo.IntervalSet{intervals: []}} = Tempo.select(~o"2026-02", [])
    end
  end

  describe "range selector" do
    test "a range expands to an integer list" do
      {:ok, set} = Tempo.select(~o"2026-02", 6..8)
      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      assert days == [6, 7, 8]
    end

    test "a range on a year base selects months" do
      {:ok, set} = Tempo.select(~o"2026", 6..8)
      months = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:month])
      assert months == [6, 7, 8]
    end
  end

  describe "integer selector on an Interval base" do
    # An Interval's from-endpoint has been filled by `to_interval/1`
    # down to day resolution, but the SPAN's declared resolution is
    # the unit at which from and to differ. The selector must use
    # that span resolution — not the endpoint's filled resolution.

    test "derives next-finer unit from the span, not the from-endpoint" do
      {:ok, base} = Tempo.to_interval(~o"2026-02")
      {:ok, set} = Tempo.select(base, [1, 15])

      result =
        set
        |> Tempo.IntervalSet.to_list()
        |> Enum.map(&{&1.from.time[:month], &1.from.time[:day]})

      assert result == [{2, 1}, {2, 15}]
    end

    test "year-resolution Interval projects indices as months" do
      {:ok, base} = Tempo.to_interval(~o"2026")
      {:ok, set} = Tempo.select(base, [3, 6, 9])

      months = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:month])
      assert months == [3, 6, 9]
    end
  end

  describe "Tempo.workdays/1 and Tempo.weekend/1 as selectors" do
    # The default Localize locale is `en` which resolves to `:US`,
    # where weekdays = [1..5] (Mon..Fri) and weekend = [6, 7] (Sat,
    # Sun). The test month (Feb 2026) starts on a Sunday.

    test "Tempo.workdays(:US) on Feb 2026 returns Monday..Friday" do
      {:ok, set} = Tempo.select(~o"2026-02", Tempo.workdays(:US))
      count = set |> Tempo.IntervalSet.to_list() |> length()
      # Feb 2026 has 20 workdays (28 days – 8 weekend days).
      assert count == 20
    end

    test "Tempo.weekend(:US) on Feb 2026 returns Saturday..Sunday" do
      {:ok, set} = Tempo.select(~o"2026-02", Tempo.weekend(:US))
      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      # Sundays: 1, 8, 15, 22. Saturdays: 7, 14, 21, 28.
      assert days == [1, 7, 8, 14, 15, 21, 22, 28]
    end

    test "Tempo.workdays(:US) intervals are half-open day spans" do
      {:ok, set} = Tempo.select(~o"2026-02", Tempo.workdays(:US))
      [first | _] = set |> Tempo.IntervalSet.to_list()

      # Feb 2 is the first Monday of Feb 2026.
      assert first.from.time == [year: 2026, month: 2, day: 2]
      assert first.to.time == [year: 2026, month: 2, day: 3]
    end

    test "workdays and weekend partition the seven days of the week" do
      assert Enum.sort(
               Tempo.workdays(:US).time[:day_of_week] ++
                 Tempo.weekend(:US).time[:day_of_week]
             ) == [1, 2, 3, 4, 5, 6, 7]

      assert Enum.sort(
               Tempo.workdays(:SA).time[:day_of_week] ++
                 Tempo.weekend(:SA).time[:day_of_week]
             ) == [1, 2, 3, 4, 5, 6, 7]
    end
  end

  describe "territory resolution inside Tempo.workdays/1 and Tempo.weekend/1" do
    # Saudi Arabia has weekend = [5, 6] (Fri, Sat) vs US [6, 7]
    # (Sat, Sun). Feb 2026 Friday/Saturday pattern differs from
    # Saturday/Sunday, so a correctly-applied SA override produces
    # days [6, 7, 13, 14, 20, 21, 27, 28].

    @sa_feb_weekend [6, 7, 13, 14, 20, 21, 27, 28]
    @us_feb_weekend [1, 7, 8, 14, 15, 21, 22, 28]

    test "explicit territory argument" do
      {:ok, set} = Tempo.select(~o"2026-02", Tempo.weekend(:SA))
      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      assert days == @sa_feb_weekend
    end

    test "locale string resolves via Localize.Territory" do
      {:ok, set} = Tempo.select(~o"2026-02", Tempo.weekend("ar-SA"))
      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      assert days == @sa_feb_weekend
    end

    test "accepts string, atom, and LanguageTag forms" do
      {:ok, tag} = Localize.validate_locale("ar-SA")

      for value <- ["ar-SA", :"ar-SA", tag] do
        {:ok, set} = Tempo.select(~o"2026-02", Tempo.weekend(value))
        days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
        assert days == @sa_feb_weekend, "value=#{inspect(value)} did not resolve to SA"
      end
    end

    test "territory strings in 'XX', 'xx', 'xx-zzzz' forms all resolve" do
      for territory <- [:SA, "SA", "sa", "sazzzz"] do
        {:ok, set} = Tempo.select(~o"2026-02", Tempo.weekend(territory))
        days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
        assert days == @sa_feb_weekend, "territory=#{inspect(territory)} did not resolve to SA"
      end
    end

    test "app config is used when territory argument is nil" do
      Application.put_env(:ex_tempo, :default_territory, :SA)

      try do
        {:ok, set} = Tempo.select(~o"2026-02", Tempo.weekend())
        days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
        assert days == @sa_feb_weekend
      after
        Application.delete_env(:ex_tempo, :default_territory)
      end
    end

    test "default fallback uses the Localize locale (en → US)" do
      {:ok, set} = Tempo.select(~o"2026-02", Tempo.weekend())
      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      assert days == @us_feb_weekend
    end
  end

  describe "Tempo / Interval projection selector" do
    test "project a single Tempo onto a larger base" do
      {:ok, set} = Tempo.select(~o"2026", ~o"12-25")
      [xmas] = Tempo.IntervalSet.to_list(set)

      assert xmas.from.time[:year] == 2026
      assert xmas.from.time[:month] == 12
      assert xmas.from.time[:day] == 25
    end

    test "project a list of Tempos onto a base" do
      {:ok, set} = Tempo.select(~o"2026", [~o"07-04", ~o"12-25"])

      pairs =
        set
        |> Tempo.IntervalSet.to_list()
        |> Enum.map(&{&1.from.time[:month], &1.from.time[:day]})

      assert pairs == [{7, 4}, {12, 25}]
    end

    test "project an Interval (projects using its from-endpoint)" do
      vacation = %Tempo.Interval{from: ~o"2026-07-10", to: ~o"2026-07-20"}
      {:ok, set} = Tempo.select(~o"2026", vacation)

      [projected] = Tempo.IntervalSet.to_list(set)
      assert projected.from.time[:month] == 7
      assert projected.from.time[:day] == 10
    end

    test "projection of a list of Intervals" do
      vacations = [
        %Tempo.Interval{from: ~o"2026-07-10", to: ~o"2026-07-20"},
        %Tempo.Interval{from: ~o"2026-12-20", to: ~o"2026-12-31"}
      ]

      {:ok, set} = Tempo.select(~o"2026", vacations)

      pairs =
        set
        |> Tempo.IntervalSet.to_list()
        |> Enum.map(&{&1.from.time[:month], &1.from.time[:day]})

      assert pairs == [{7, 10}, {12, 20}]
    end

    test "day-of-week-only projection (`~o\"5K\"`) — every Friday in the base" do
      {:ok, set} = Tempo.select(~o"2026-06", ~o"5K")

      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      assert days == [5, 12, 19, 26]
    end

    test "day-of-week projection in a whole-year base" do
      {:ok, set} = Tempo.select(~o"2026", ~o"5K")
      # 2026 has 52 Fridays.
      assert Tempo.IntervalSet.count(set) == 52
    end

    test "day-of-week projection composes with quarter-shaped base" do
      {:ok, set} = Tempo.select(~o"2026Y3Q", ~o"5K")
      # Q3 2026: 13 Fridays.
      assert Tempo.IntervalSet.count(set) == 13
    end

    test "ordinal-day projection (`~o\"10O\"`) — the 10th day of the year" do
      {:ok, set} = Tempo.select(~o"2026", ~o"10O")

      [iv] = Tempo.IntervalSet.to_list(set)
      assert iv.from.time[:year] == 2026
      assert iv.from.time[:month] == 1
      assert iv.from.time[:day] == 10
    end

    test "ordinal-day projection produces a day-shaped span" do
      # The 10th day of 2026 is Jan 10 — the projection's span is
      # one day, not one hour.
      {:ok, set} = Tempo.select(~o"2026", ~o"10O")

      [iv] = Tempo.IntervalSet.to_list(set)
      assert iv.to.time[:day] == 11
      assert iv.to.time[:month] == 1
    end

    test "month-day projection (`~o\"12-25\"`) produces a day-shaped span" do
      {:ok, set} = Tempo.select(~o"2026", ~o"12-25")

      [iv] = Tempo.IntervalSet.to_list(set)
      assert iv.from.time[:day] == 25
      assert iv.to.time[:day] == 26
    end
  end

  describe "function selector" do
    test "the function receives the base and its result is recursed" do
      fun = fn _base -> [1, 15] end
      {:ok, set} = Tempo.select(~o"2026-02", fun)
      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      assert days == [1, 15]
    end

    test "the function can return a workdays selector" do
      fun = fn _base -> Tempo.workdays(:US) end
      {:ok, set} = Tempo.select(~o"2026-02", fun)
      count = set |> Tempo.IntervalSet.to_list() |> length()
      assert count == 20
    end
  end

  describe "IntervalSet base" do
    test "selector flat-maps across every member interval" do
      {:ok, jan} = Tempo.to_interval(~o"2026Y1M")
      {:ok, mar} = Tempo.to_interval(~o"2026Y3M")
      {:ok, base} = Tempo.IntervalSet.new([jan, mar])

      {:ok, set} = Tempo.select(base, [1, 15])

      triples =
        set
        |> Tempo.IntervalSet.to_list()
        |> Enum.map(&{&1.from.time[:year], &1.from.time[:month], &1.from.time[:day]})

      assert triples == [{2026, 1, 1}, {2026, 1, 15}, {2026, 3, 1}, {2026, 3, 15}]
    end

    test "workdays flat-maps across non-touching months" do
      {:ok, jan} = Tempo.to_interval(~o"2026Y1M")
      {:ok, mar} = Tempo.to_interval(~o"2026Y3M")
      {:ok, base} = Tempo.IntervalSet.new([jan, mar])

      {:ok, set} = Tempo.select(base, Tempo.workdays(:US))
      count = set |> Tempo.IntervalSet.to_list() |> length()

      # Jan 2026: 22 workdays. Mar 2026: 22 workdays. Total 44.
      assert count == 44
    end
  end

  describe "grouped / ISO 8601-2 bases" do
    test "quarter (`3Q`) materialises and filters to quarter workdays" do
      # Q3 2026 — July, August, September. 66 Mon–Fri days in the
      # US territory.
      {:ok, set} = Tempo.select(~o"2026Y3Q", Tempo.workdays(:US))
      assert Tempo.IntervalSet.count(set) == 66
    end

    test "season code 26 (Northern summer) filters to workdays inside it" do
      # Season 26 runs Jun 21 → Sep 23 (solstice-to-equinox). All
      # workdays inside that 94-day window.
      {:ok, set} = Tempo.select(~o"2026Y26M", Tempo.workdays(:US))
      count = Tempo.IntervalSet.count(set)
      # Rough sanity: 94 days × 5/7 ≈ 67. Exact value depends on
      # which days of week the season boundaries land on.
      assert count in 65..70
    end

    test "month-range in a slot (`{6..8}M`) filters each member's workdays" do
      # Jun + Jul + Aug — three-month window of 66 workdays.
      {:ok, set} = Tempo.select(~o"2026Y{6..8}M", Tempo.workdays(:US))
      assert Tempo.IntervalSet.count(set) == 66
    end

    test "masked year (`156X`) flows through — 1560s workdays count" do
      # Ten years × ~261 workdays/year ≈ 2600 workdays (coarse).
      # Historical Gregorian in the 1560s is well-defined.
      {:ok, set} = Tempo.select(~o"156X", Tempo.workdays(:US))
      count = Tempo.IntervalSet.count(set)
      assert count > 2500 and count < 2700
    end

    test "stepped month range (`{1..-1//3}M`) returns workdays in each quarterly month" do
      # Jan, Apr, Jul, Oct — four months worth of workdays.
      {:ok, set} = Tempo.select(~o"2026Y{1..-1//3}M", Tempo.workdays(:US))
      count = Tempo.IntervalSet.count(set)
      # 4 months × ~22 workdays ≈ 88. Exact value depends on which
      # days of week the month edges land on.
      assert count in 80..95
    end
  end

  describe "error cases" do
    test "an unrecognised selector returns an error tuple" do
      assert {:error, message} = Tempo.select(~o"2026-02", :banana)
      assert Exception.message(message) =~ "does not recognise selector :banana"
      assert Exception.message(message) =~ "selector vocabulary"
    end

    test "workdays on an open-ended interval returns an error" do
      {:ok, open} = Tempo.from_iso8601("2026-02/..")

      assert {:error, %Tempo.IntervalEndpointsError{} = e} =
               Tempo.select(open, Tempo.workdays(:US))

      assert Exception.message(e) =~ "open-ended"
    end
  end

  describe "return shape" do
    test "always returns {:ok, %Tempo.IntervalSet{}} on success" do
      assert {:ok, %Tempo.IntervalSet{}} = Tempo.select(~o"2026-02", [1, 15])
      assert {:ok, %Tempo.IntervalSet{}} = Tempo.select(~o"2026-02", Tempo.workdays(:US))
      assert {:ok, %Tempo.IntervalSet{}} = Tempo.select(~o"2026", ~o"12-25")
      assert {:ok, %Tempo.IntervalSet{}} = Tempo.select(~o"2026-02", fn _ -> [1] end)
    end

    test "selected day intervals are half-open single-day spans" do
      {:ok, set} = Tempo.select(~o"2026-02", [15])
      [day] = Tempo.IntervalSet.to_list(set)

      # The span runs from day 15 to day 16 — half-open. `to_interval`
      # may additionally fill the endpoints with `hour: 0` etc., so
      # we compare only the year/month/day components.
      assert {day.from.time[:year], day.from.time[:month], day.from.time[:day]} ==
               {2026, 2, 15}

      assert {day.to.time[:year], day.to.time[:month], day.to.time[:day]} ==
               {2026, 2, 16}
    end
  end
end
