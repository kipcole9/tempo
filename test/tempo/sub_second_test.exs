defmodule Tempo.SubSecondTest do
  @moduledoc """
  Sub-second (fractional-second) resolution: parsing, representation,
  and round-trip. The fractional second is stored as a `:microsecond`
  `{value, precision}` component (Elixir-aligned), with the digit count
  preserved so that `.120` and `.12` remain distinct resolutions.
  """

  use ExUnit.Case, async: true

  import Tempo.Sigils

  defp time(iso) do
    {:ok, tempo} = Tempo.from_iso8601(iso)
    tempo.time
  end

  describe "parsing fractional seconds into a :microsecond component" do
    test "millisecond precision" do
      assert time("2026-06-15T10:30:45.123")[:second] == 45
      assert time("2026-06-15T10:30:45.123")[:microsecond] == {123_000, 3}
    end

    test "trailing zeros are significant (precision differs)" do
      # .120 is millisecond resolution, .12 is centisecond resolution:
      # same microsecond value, different precision.
      assert time("2026-06-15T10:30:45.120")[:microsecond] == {120_000, 3}
      assert time("2026-06-15T10:30:45.12")[:microsecond] == {120_000, 2}
    end

    test "leading zeros are significant" do
      assert time("2026-06-15T10:30:45.000123")[:microsecond] == {123, 6}
    end

    test "microsecond (6-digit) precision" do
      assert time("2026-06-15T10:30:45.123456")[:microsecond] == {123_456, 6}
    end

    test "more than six digits truncate to microsecond resolution" do
      assert time("2026-06-15T10:30:45.1234567")[:microsecond] == {123_456, 6}
      assert time("2026-06-15T10:30:45.123456999")[:microsecond] == {123_456, 6}
    end

    test "comma is accepted as the decimal separator" do
      assert time("2026-06-15T10:30:45,123")[:microsecond] == {123_000, 3}
    end

    test "explicit (designator) form" do
      assert time("2018Y8M8DT10H30M15,3S")[:microsecond] == {300_000, 1}
      assert time("2018Y8M8DT10H30M15.3S")[:microsecond] == {300_000, 1}
    end

    test "a plain second carries no microsecond component" do
      refute Keyword.has_key?(time("2026-06-15T10:30:45"), :microsecond)
      refute Keyword.has_key?(time("2026-06-15T10:30:45Z"), :microsecond)
    end

    test "sub-second coexists with a time zone" do
      t = time("2026-06-15T10:30:45.5+10:00")
      assert t[:second] == 45
      assert t[:microsecond] == {500_000, 1}
    end
  end

  describe "resolution" do
    test "resolution/1 reports the microsecond precision" do
      assert Tempo.resolution(~o"2026Y6M15DT10H30M45.123S") == {:microsecond, 3}
      assert Tempo.resolution(~o"2026Y6M15DT10H30M45.12S") == {:microsecond, 2}
      assert Tempo.resolution(~o"2026Y6M15DT10H30M45.000123S") == {:microsecond, 6}
    end
  end

  describe "materialisation to an interval" do
    defp endpoints(iso) do
      {:ok, iv} = Tempo.to_interval(Tempo.from_iso8601!(iso))
      {Tempo.to_iso8601(iv.from), Tempo.to_iso8601(iv.to)}
    end

    test "the span is [value, value + one ulp) at the value's precision" do
      # millisecond precision: +1 ms
      assert endpoints("2026-06-15T10:30:45.123") ==
               {"2026Y6M15DT10H30M45.123S", "2026Y6M15DT10H30M45.124S"}

      # centisecond precision: +10 ms
      assert endpoints("2026-06-15T10:30:45.12") ==
               {"2026Y6M15DT10H30M45.12S", "2026Y6M15DT10H30M45.13S"}

      # microsecond precision: +1 µs
      assert endpoints("2026-06-15T10:30:45.123456") ==
               {"2026Y6M15DT10H30M45.123456S", "2026Y6M15DT10H30M45.123457S"}
    end

    test "an overflowing ulp carries into the second (precision preserved)" do
      assert endpoints("2026-06-15T10:30:45.999") ==
               {"2026Y6M15DT10H30M45.999S", "2026Y6M15DT10H30M46.000S"}
    end

    test "carry propagates through second and minute" do
      assert endpoints("2026-06-15T10:30:59.999999") ==
               {"2026Y6M15DT10H30M59.999999S", "2026Y6M15DT10H31M0.000000S"}
    end
  end

  describe "comparison and Allen relations" do
    test "sub-second values order by microsecond value" do
      assert Tempo.Compare.compare_endpoints(
               ~o"2026Y6M15DT10H30M45.123S",
               ~o"2026Y6M15DT10H30M45.124S"
             ) == :earlier
    end

    test "precision does not affect instant ordering (.12 == .120)" do
      # Same start moment, different interval width — equal as instants.
      assert Tempo.Compare.compare_endpoints(
               ~o"2026Y6M15DT10H30M45.12S",
               ~o"2026Y6M15DT10H30M45.120S"
             ) == :same
    end

    test "adjacent sub-second intervals meet" do
      {:ok, a} = Tempo.to_interval(~o"2026Y6M15DT10H30M45.123S")
      {:ok, b} = Tempo.to_interval(~o"2026Y6M15DT10H30M45.124S")
      assert Tempo.Interval.relation(a, b) == :meets
    end

    test "cross-zone comparison breaks ties on the sub-second value" do
      # Same UTC second (10:30:45 UTC), microseconds 100000 vs 200000.
      utc = Tempo.from_iso8601!("2026-06-15T10:30:45.100+00:00")
      syd = Tempo.from_iso8601!("2026-06-15T20:30:45.200+10:00")
      assert Tempo.Compare.compare_endpoints(utc, syd) == :earlier
    end
  end

  describe "durations" do
    test "a fractional-second duration preserves its precision on round-trip" do
      assert inspect(Tempo.from_iso8601!("PT1.250S")) == ~s(~o"PT1.250S")
      assert inspect(Tempo.from_iso8601!("PT0.5S")) == ~s(~o"PT0.5S")
    end

    test "adding a sub-second duration carries into the second" do
      result =
        Tempo.Math.add(
          Tempo.from_iso8601!("2026-06-15T10:30:45.900"),
          Tempo.from_iso8601!("PT0.2S")
        )

      assert Tempo.to_iso8601(result) == "2026Y6M15DT10H30M46.100S"
    end

    test "subtracting a sub-second duration borrows from the second" do
      result =
        Tempo.Math.subtract(
          Tempo.from_iso8601!("2026-06-15T10:30:46.100"),
          Tempo.from_iso8601!("PT0.2S")
        )

      assert Tempo.to_iso8601(result) == "2026Y6M15DT10H30M45.900S"
    end

    test "adding a sub-second duration to a second-resolution value introduces sub-second" do
      result =
        Tempo.Math.add(
          Tempo.from_iso8601!("2026-06-15T10:30:45"),
          Tempo.from_iso8601!("PT0.5S")
        )

      assert Tempo.to_iso8601(result) == "2026Y6M15DT10H30M45.500000S"
    end
  end

  describe "Elixir interop" do
    test "from_elixir preserves microsecond precision verbatim" do
      assert Tempo.from_elixir(~U[2026-06-15 10:30:45.123456Z]).time[:microsecond] ==
               {123_456, 6}

      assert Tempo.from_elixir(~N[2026-06-15 10:30:45.250]).time[:microsecond] == {250_000, 3}
      assert Tempo.from_elixir(~T[10:30:45.5]).time[:microsecond] == {500_000, 1}
    end

    test "a value with no sub-second gains no microsecond component" do
      refute Keyword.has_key?(Tempo.from_elixir(~N[2026-06-15 10:30:45]).time, :microsecond)
    end

    test "to_naive_date_time round-trips microseconds (trailing zeros preserved)" do
      assert Tempo.to_naive_date_time(Tempo.from_elixir(~N[2026-06-15 10:30:45.123456])) ==
               {:ok, ~N[2026-06-15 10:30:45.123456]}

      assert Tempo.to_naive_date_time(Tempo.from_elixir(~N[2026-06-15 10:30:45.250])) ==
               {:ok, ~N[2026-06-15 10:30:45.250]}
    end

    test "utc_now stays at second resolution (its documented contract)" do
      assert Tempo.resolution(Tempo.utc_now()) == {:second, 1}
    end
  end

  describe "enumeration" do
    test "an explicit sub-second interval steps by one ulp at its resolution" do
      iv = Tempo.from_iso8601!("2026-06-15T10:30:45.000/2026-06-15T10:30:45.003")

      assert Enum.map(iv, &Tempo.to_iso8601/1) == [
               "2026Y6M15DT10H30M45.000S",
               "2026Y6M15DT10H30M45.001S",
               "2026Y6M15DT10H30M45.002S"
             ]
    end

    test "a sub-second point value cannot be enumerated (finest resolution)" do
      # Consistent with second resolution before sub-second existed:
      # the finest unit has no finer sub-unit to iterate into.
      assert_raise ArgumentError, fn ->
        Enum.take(~o"2026Y6M15DT10H30M45.123S", 1)
      end
    end
  end

  describe "round-trip through inspect / sigil" do
    test "inspect renders the fraction before the S designator" do
      {:ok, t} = Tempo.from_iso8601("2026-06-15T10:30:45.123")
      assert inspect(t) == ~s(~o"2026Y6M15DT10H30M45.123S")
    end

    test "trailing zeros survive a round-trip" do
      {:ok, t} = Tempo.from_iso8601("2026-06-15T10:30:45.120")
      assert inspect(t) == ~s(~o"2026Y6M15DT10H30M45.120S")
    end

    test "the sigil parses the same fractional value" do
      assert ~o"2026Y6M15DT10H30M45.123S".time[:microsecond] == {123_000, 3}
    end
  end
end
