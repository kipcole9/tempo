defmodule Tempo.FromElixir.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  # `Tempo.from_elixir/2` unifies Date, Time, NaiveDateTime, and
  # DateTime into `%Tempo{}`. The intended resolution is inferred
  # from the input (or overridden by `:resolution`), then applied
  # via `at_resolution/2`.
  #
  # These tests also cover the two primitives `from_elixir` builds
  # on: `extend_resolution/2` (pad with minimums) and
  # `at_resolution/2` (dispatcher between trunc and extend).

  setup_all do
    # DateTime construction with IANA zones needs a time zone DB.
    Calendar.put_time_zone_database(Tzdata.TimeZoneDatabase)
    :ok
  end

  describe "from_elixir/2 — Date.t" do
    test "default resolution is :day" do
      assert Tempo.from_elixir(~D[2022-06-15]) == ~o"2022Y6M15D"
    end

    test "explicit :resolution :hour pads with hour: 0" do
      tempo = Tempo.from_elixir(~D[2022-06-15], resolution: :hour)
      assert tempo.time == [year: 2022, month: 6, day: 15, hour: 0]
    end

    test "explicit :resolution :second pads all the way" do
      tempo = Tempo.from_elixir(~D[2022-06-15], resolution: :second)

      assert tempo.time == [
               year: 2022,
               month: 6,
               day: 15,
               hour: 0,
               minute: 0,
               second: 0
             ]
    end

    test "explicit :resolution :year truncates to year" do
      tempo = Tempo.from_elixir(~D[2022-06-15], resolution: :year)
      assert tempo.time == [year: 2022]
    end
  end

  describe "from_elixir/2 — Time.t (resolution inference)" do
    # A `Time` is second-granular by type; resolution follows the
    # declared precision, not the magnitude of the components. A zero
    # second/minute is a fully specified zero, not an absent unit.
    test "~T[10:30:00] → :second (zero second is still specified)" do
      assert Tempo.from_elixir(~T[10:30:00]).time == [hour: 10, minute: 30, second: 0]
    end

    test "~T[10:30:45] → :second (all non-zero to second)" do
      assert Tempo.from_elixir(~T[10:30:45]).time == [hour: 10, minute: 30, second: 45]
    end

    test "~T[10:00:00] → :second (zero minute and second still specified)" do
      assert Tempo.from_elixir(~T[10:00:00]).time == [hour: 10, minute: 0, second: 0]
    end

    test "~T[00:00:00] → :second (midnight is a fully specified second)" do
      assert Tempo.from_elixir(~T[00:00:00]).time == [hour: 0, minute: 0, second: 0]
    end

    test "microsecond is preserved as a :microsecond component" do
      # `~T[10:30:45.123]` carries microsecond precision 3; it is
      # threaded into a `:microsecond {value, precision}` component.
      assert Tempo.from_elixir(~T[10:30:45.123]).time ==
               [hour: 10, minute: 30, second: 45, microsecond: {123_000, 3}]
    end
  end

  describe "from_elixir/2 — NaiveDateTime.t (resolution inference)" do
    # A `NaiveDateTime` is second-granular by type, so even an all-zero
    # time is second resolution — not coarsened to day/hour/minute by
    # the magnitude of its components. Pass `:resolution` to widen.
    test "midnight is second resolution (not coarsened to :day)" do
      assert Tempo.from_elixir(~N[2022-06-15 00:00:00]).time ==
               [year: 2022, month: 6, day: 15, hour: 0, minute: 0, second: 0]
    end

    test "zero minute and second stay specified" do
      assert Tempo.from_elixir(~N[2022-06-15 10:00:00]).time ==
               [year: 2022, month: 6, day: 15, hour: 10, minute: 0, second: 0]
    end

    test "zero second stays specified" do
      assert Tempo.from_elixir(~N[2022-06-15 10:30:00]).time ==
               [year: 2022, month: 6, day: 15, hour: 10, minute: 30, second: 0]
    end

    test "second resolution" do
      assert Tempo.from_elixir(~N[2022-06-15 10:30:45]).time ==
               [year: 2022, month: 6, day: 15, hour: 10, minute: 30, second: 45]
    end

    test "microsecond is preserved as a :microsecond component" do
      assert Tempo.from_elixir(~N[2022-06-15 10:30:45.123]).time ==
               [
                 year: 2022,
                 month: 6,
                 day: 15,
                 hour: 10,
                 minute: 30,
                 second: 45,
                 microsecond: {123_000, 3}
               ]
    end

    test "explicit :resolution overrides inference" do
      # Source is minute resolution; we ask for day.
      tempo = Tempo.from_elixir(~N[2022-06-15 10:30:00], resolution: :day)
      assert tempo.time == [year: 2022, month: 6, day: 15]
    end
  end

  describe "from_elixir/2 — DateTime.t" do
    test "UTC datetime is second resolution" do
      tempo = Tempo.from_elixir(~U[2022-06-15 10:30:00Z])
      assert tempo.time == [year: 2022, month: 6, day: 15, hour: 10, minute: 30, second: 0]
      assert tempo.shift == [hour: 0]
      assert tempo.extended.zone_id == "Etc/UTC"
    end

    test "zoned datetime carries zone_id and offset" do
      dt = DateTime.new!(~D[2022-06-15], ~T[10:30:00], "Europe/Paris")
      tempo = Tempo.from_elixir(dt)
      assert tempo.extended.zone_id == "Europe/Paris"
      # June is summer time (CEST = UTC+2).
      assert tempo.shift == [hour: 2]
      assert tempo.extended.zone_offset == 120
    end

    test "negative offset (America/New_York winter)" do
      dt = DateTime.new!(~D[2022-12-25], ~T[14:00:00], "America/New_York")
      tempo = Tempo.from_elixir(dt)
      # EST = UTC-5.
      assert tempo.shift == [hour: -5]
      assert tempo.extended.zone_offset == -300
    end

    test "midnight UTC is second resolution (not coarsened to :day)" do
      tempo = Tempo.from_elixir(~U[2022-06-15 00:00:00Z])
      assert tempo.time == [year: 2022, month: 6, day: 15, hour: 0, minute: 0, second: 0]
    end
  end

  describe "extend_resolution/2" do
    test "year → day" do
      assert Tempo.extend_resolution(~o"2020Y", :day) == ~o"2020Y1M1D"
    end

    test "year-month → hour" do
      assert Tempo.extend_resolution(~o"2020Y6M", :hour) == ~o"2020Y6M1DT0H"
    end

    test "year-month-day → second" do
      tempo = Tempo.extend_resolution(~o"2020Y6M15D", :second)
      assert tempo.time == [year: 2020, month: 6, day: 15, hour: 0, minute: 0, second: 0]
    end

    test "idempotent at the current resolution" do
      source = ~o"2020Y6M15D"
      assert Tempo.extend_resolution(source, :day) == source
    end

    test "coarser target returns an error" do
      assert {:error, message} = Tempo.extend_resolution(~o"2020Y6M15D", :year)
      assert Exception.message(message) =~ ":year is coarser"
      assert Exception.message(message) =~ "Tempo.trunc/2"
    end
  end

  describe "at_resolution/2" do
    test "finer target calls extend_resolution" do
      assert Tempo.at_resolution(~o"2020Y", :day) == ~o"2020Y1M1D"
    end

    test "coarser target calls trunc" do
      assert Tempo.at_resolution(~o"2020Y6M15DT10H", :day) == ~o"2020Y6M15D"
    end

    test "equal target is idempotent" do
      source = ~o"2020Y6M15D"
      assert Tempo.at_resolution(source, :day) == source
    end

    test "invalid unit atom returns error" do
      assert {:error, _} = Tempo.at_resolution(~o"2020Y", :nonsense)
    end
  end

  describe "round-trip via from_elixir/2 and to_*/1" do
    test "Date round-trip at :day" do
      date = ~D[2022-06-15]
      tempo = Tempo.from_elixir(date)
      assert {:ok, ^date} = Tempo.to_date(tempo)
    end

    test "NaiveDateTime round-trips at the default (second) resolution" do
      # Previously this required an explicit `resolution: :second`
      # because `from_elixir/1` coarsened `10:30:00` to minute
      # resolution and `to_naive_date_time/1` then failed. The default
      # is now second resolution, so the round-trip succeeds with no
      # override. NaiveDateTime's microsecond field defaults to
      # `{0, 0}` for sigil literals and to `{0, 6}` for
      # `to_naive_date_time/1` output, so compare component-wise
      # rather than structurally.
      naive = ~N[2022-06-15 10:30:00]
      tempo = Tempo.from_elixir(naive)
      assert {:ok, round_tripped} = Tempo.to_naive_date_time(tempo)
      assert NaiveDateTime.compare(round_tripped, naive) == :eq
    end

    test "zoned DateTime → to_naive_date_time keeps wall-clock, drops zone" do
      # Paris is UTC+2 in June; the wall reading is 10:30, not 08:30.
      paris = DateTime.new!(~D[2022-06-15], ~T[10:30:00], "Europe/Paris")
      tempo = Tempo.from_elixir(paris)
      assert {:ok, ~N[2022-06-15 10:30:00.000000]} = Tempo.to_naive_date_time(tempo)
    end

    test "zoned DateTime → to_date_time preserves the zone and instant" do
      paris = DateTime.new!(~D[2022-06-15], ~T[10:30:00], "Europe/Paris")
      tempo = Tempo.from_elixir(paris)
      assert {:ok, round_tripped} = Tempo.to_date_time(tempo)
      assert round_tripped.time_zone == "Europe/Paris"
      assert DateTime.compare(round_tripped, paris) == :eq
    end
  end
end
