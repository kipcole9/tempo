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
    test "~T[10:30:00] → :minute (second is zero)" do
      assert Tempo.from_elixir(~T[10:30:00]).time == [hour: 10, minute: 30]
    end

    test "~T[10:30:45] → :second (all non-zero to second)" do
      assert Tempo.from_elixir(~T[10:30:45]).time == [hour: 10, minute: 30, second: 45]
    end

    test "~T[10:00:00] → :hour (minute and second both zero)" do
      assert Tempo.from_elixir(~T[10:00:00]).time == [hour: 10]
    end

    test "~T[00:00:00] → :hour fallback (all zero; no coarser unit for a bare Time)" do
      # A bare Time has no date component to widen to, so we stop
      # at `:hour` — the coarsest Time-only unit.
      assert Tempo.from_elixir(~T[00:00:00]).time == [hour: 0]
    end

    test "microsecond is discarded (Tempo has no sub-second unit)" do
      # `~T[10:30:45.123]` has microsecond != 0 but we truncate to
      # second for inference. Existing `from_time/1` already drops
      # microsecond silently.
      assert Tempo.from_elixir(~T[10:30:45.123]).time ==
               [hour: 10, minute: 30, second: 45]
    end
  end

  describe "from_elixir/2 — NaiveDateTime.t (resolution inference)" do
    test "midnight falls back to :day" do
      # `~N[2022-06-15 00:00:00]` — all time components zero. The
      # semantically-correct resolution is day (the value IS a date).
      assert Tempo.from_elixir(~N[2022-06-15 00:00:00]) == ~o"2022Y6M15D"
    end

    test "hour resolution" do
      assert Tempo.from_elixir(~N[2022-06-15 10:00:00]).time ==
               [year: 2022, month: 6, day: 15, hour: 10]
    end

    test "minute resolution" do
      assert Tempo.from_elixir(~N[2022-06-15 10:30:00]).time ==
               [year: 2022, month: 6, day: 15, hour: 10, minute: 30]
    end

    test "second resolution" do
      assert Tempo.from_elixir(~N[2022-06-15 10:30:45]).time ==
               [year: 2022, month: 6, day: 15, hour: 10, minute: 30, second: 45]
    end

    test "microsecond is discarded" do
      assert Tempo.from_elixir(~N[2022-06-15 10:30:45.123]).time ==
               [year: 2022, month: 6, day: 15, hour: 10, minute: 30, second: 45]
    end

    test "explicit :resolution overrides inference" do
      # Source is minute resolution; we ask for day.
      tempo = Tempo.from_elixir(~N[2022-06-15 10:30:00], resolution: :day)
      assert tempo.time == [year: 2022, month: 6, day: 15]
    end
  end

  describe "from_elixir/2 — DateTime.t" do
    test "UTC datetime at minute resolution" do
      tempo = Tempo.from_elixir(~U[2022-06-15 10:30:00Z])
      assert tempo.time == [year: 2022, month: 6, day: 15, hour: 10, minute: 30]
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

    test "midnight UTC falls back to :day" do
      tempo = Tempo.from_elixir(~U[2022-06-15 00:00:00Z])
      assert tempo.time == [year: 2022, month: 6, day: 15]
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

    test "NaiveDateTime round-trip at :second requires explicit resolution" do
      # Source minute-resolution; `to_naive_date_time/1` needs second.
      # NaiveDateTime's microsecond field defaults to `{0, 0}` for
      # sigil literals and to `{0, 6}` for `to_naive_date_time/1`
      # output, so compare component-wise rather than structurally.
      naive = ~N[2022-06-15 10:30:00]
      tempo = Tempo.from_elixir(naive, resolution: :second)
      assert {:ok, round_tripped} = Tempo.to_naive_date_time(tempo)
      assert NaiveDateTime.compare(round_tripped, naive) == :eq
    end
  end
end
