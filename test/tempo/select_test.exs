defmodule Tempo.Select.Test do
  use ExUnit.Case, async: false
  import Tempo.Sigil

  # `Tempo.select/3` narrows a base span by a selector, returning
  # an `{:ok, %Tempo.IntervalSet{}}` tuple. The tests below cover
  # every selector shape, every base shape (Tempo / Interval /
  # IntervalSet), and every rung of the territory-resolution chain.
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

  describe ":workdays / :weekend with default territory" do
    # The default Localize locale is `en` which resolves to `:US`,
    # where weekdays = [1..5] (Mon..Fri) and weekend = [6, 7] (Sat,
    # Sun). The test month (Feb 2026) starts on a Sunday.

    test ":workdays on Feb 2026 returns Monday..Friday" do
      {:ok, set} = Tempo.select(~o"2026-02", :workdays)
      count = set |> Tempo.IntervalSet.to_list() |> length()
      # Feb 2026 has 20 workdays (28 days – 8 weekend days).
      assert count == 20
    end

    test ":weekend on Feb 2026 returns Saturday..Sunday" do
      {:ok, set} = Tempo.select(~o"2026-02", :weekend)
      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      # Sundays: 1, 8, 15, 22. Saturdays: 7, 14, 21, 28.
      assert days == [1, 7, 8, 14, 15, 21, 22, 28]
    end

    test ":workdays intervals are half-open day spans" do
      {:ok, set} = Tempo.select(~o"2026-02", :workdays)
      [first | _] = set |> Tempo.IntervalSet.to_list()

      # Feb 2 is the first Monday of Feb 2026.
      assert first.from.time == [year: 2026, month: 2, day: 2]
      assert first.to.time == [year: 2026, month: 2, day: 3]
    end
  end

  describe "territory resolution chain" do
    # Saudi Arabia has weekend = [5, 6] (Fri, Sat) vs US [6, 7]
    # (Sat, Sun). Feb 2026 Friday/Saturday pattern differs from
    # Saturday/Sunday, so a correctly-applied SA override produces
    # days [6, 7, 13, 14, 20, 21, 27, 28].

    @sa_feb_weekend [6, 7, 13, 14, 20, 21, 27, 28]
    @us_feb_weekend [1, 7, 8, 14, 15, 21, 22, 28]

    test "explicit territory: option overrides the default locale" do
      {:ok, set} = Tempo.select(~o"2026-02", :weekend, territory: :SA)
      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      assert days == @sa_feb_weekend
    end

    test "explicit locale: option resolves via Localize.Territory" do
      {:ok, set} = Tempo.select(~o"2026-02", :weekend, locale: "ar-SA")
      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      assert days == @sa_feb_weekend
    end

    test "locale: accepts string, atom, and LanguageTag forms" do
      {:ok, tag} = Localize.validate_locale("ar-SA")

      for locale <- ["ar-SA", :"ar-SA", tag] do
        {:ok, set} = Tempo.select(~o"2026-02", :weekend, locale: locale)
        days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
        assert days == @sa_feb_weekend, "locale=#{inspect(locale)} did not resolve to SA"
      end
    end

    test "explicit territory: takes precedence over locale:" do
      {:ok, set} = Tempo.select(~o"2026-02", :weekend, territory: :US, locale: "ar-SA")
      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      assert days == @us_feb_weekend
    end

    test "locale: takes precedence over IXDTF u-rg tag" do
      {:ok, tempo} = Tempo.from_iso8601("2026-02[u-rg=uszzzz]")
      {:ok, set} = Tempo.select(tempo, :weekend, locale: "ar-SA")
      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      assert days == @sa_feb_weekend
    end

    test "invalid locale returns the Localize error" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Tempo.select(~o"2026-02", :weekend, locale: "not-a-real-locale-%%%")
    end

    test "territory: accepts string, atom, and 'rg-zzzz' forms" do
      for territory <- [:SA, "SA", "sa", "sazzzz"] do
        {:ok, set} = Tempo.select(~o"2026-02", :weekend, territory: territory)
        days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
        assert days == @sa_feb_weekend, "territory=#{inspect(territory)} did not resolve to SA"
      end
    end

    test "IXDTF u-rg=XX tag on the base applies when no opt is given" do
      {:ok, tempo} = Tempo.from_iso8601("2026-02[u-rg=sazzzz]")
      {:ok, set} = Tempo.select(tempo, :weekend)
      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      assert days == @sa_feb_weekend
    end

    test "explicit territory: takes precedence over an IXDTF tag" do
      # IXDTF says SA, opt says US — opt wins.
      {:ok, tempo} = Tempo.from_iso8601("2026-02[u-rg=sazzzz]")
      {:ok, set} = Tempo.select(tempo, :weekend, territory: :US)
      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      assert days == @us_feb_weekend
    end

    test "app config is used when neither opt nor IXDTF is present" do
      Application.put_env(:ex_tempo, :default_territory, :SA)

      try do
        {:ok, set} = Tempo.select(~o"2026-02", :weekend)
        days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
        assert days == @sa_feb_weekend
      after
        Application.delete_env(:ex_tempo, :default_territory)
      end
    end

    test "IXDTF takes precedence over app config" do
      Application.put_env(:ex_tempo, :default_territory, :US)

      try do
        {:ok, tempo} = Tempo.from_iso8601("2026-02[u-rg=sazzzz]")
        {:ok, set} = Tempo.select(tempo, :weekend)
        days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
        assert days == @sa_feb_weekend
      after
        Application.delete_env(:ex_tempo, :default_territory)
      end
    end

    test "default fallback uses the Localize locale (en → US)" do
      {:ok, set} = Tempo.select(~o"2026-02", :weekend)
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
  end

  describe "function selector" do
    test "the function receives the base and its result is recursed" do
      fun = fn _base -> [1, 15] end
      {:ok, set} = Tempo.select(~o"2026-02", fun)
      days = set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      assert days == [1, 15]
    end

    test "the function can return an atom selector" do
      fun = fn _base -> :workdays end
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

      {:ok, set} = Tempo.select(base, :workdays)
      count = set |> Tempo.IntervalSet.to_list() |> length()

      # Jan 2026: 22 workdays. Mar 2026: 22 workdays. Total 44.
      assert count == 44
    end
  end

  describe "error cases" do
    test "an unrecognised selector returns an error tuple" do
      assert {:error, message} = Tempo.select(~o"2026-02", :banana)
      assert message =~ "does not recognise selector :banana"
      assert message =~ "selector vocabulary"
    end

    test "workdays on an open-ended interval returns an error" do
      {:ok, open} = Tempo.from_iso8601("2026-02/..")
      assert {:error, message} = Tempo.select(open, :workdays)
      assert message =~ "open-ended"
    end
  end

  describe "return shape" do
    test "always returns {:ok, %Tempo.IntervalSet{}} on success" do
      assert {:ok, %Tempo.IntervalSet{}} = Tempo.select(~o"2026-02", [1, 15])
      assert {:ok, %Tempo.IntervalSet{}} = Tempo.select(~o"2026-02", :workdays)
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
