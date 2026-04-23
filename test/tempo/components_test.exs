defmodule Tempo.Components.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  # `Tempo.year/1`, `month/1`, `day/1`, `hour/1`, `minute/1`,
  # `second/1` are commodity component accessors — they return the
  # named component as an integer, `nil` when that component isn't
  # specified, and raise on an interval whose span is ambiguous for
  # that component.

  describe "on a Tempo value" do
    test "returns each specified component as an integer" do
      t = ~o"2026-06-15T10:30:45"

      assert Tempo.year(t) == 2026
      assert Tempo.month(t) == 6
      assert Tempo.day(t) == 15
      assert Tempo.hour(t) == 10
      assert Tempo.minute(t) == 30
      assert Tempo.second(t) == 45
    end

    test "returns nil for unspecified components" do
      # A year-only value has no month/day/hour/etc.
      year_only = ~o"2026"
      assert Tempo.year(year_only) == 2026
      assert Tempo.month(year_only) == nil
      assert Tempo.day(year_only) == nil
      assert Tempo.hour(year_only) == nil

      # A day-resolution value has no hour/minute/second.
      day_only = ~o"2026-06-15"
      assert Tempo.day(day_only) == 15
      assert Tempo.hour(day_only) == nil
      assert Tempo.minute(day_only) == nil
    end
  end

  describe "on an unambiguous Interval" do
    test "reads the component from the from-endpoint" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06-15")

      assert Tempo.year(iv) == 2026
      assert Tempo.month(iv) == 6
      assert Tempo.day(iv) == 15
    end

    test "a month-resolution interval has an unambiguous month" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06")

      assert Tempo.year(iv) == 2026
      assert Tempo.month(iv) == 6
    end

    test "a day-resolution interval has an unambiguous hour when within a single day" do
      iv = %Tempo.Interval{from: ~o"2026-06-15T10", to: ~o"2026-06-15T11"}

      assert Tempo.day(iv) == 15
      assert Tempo.hour(iv) == 10
    end
  end

  describe "on an ambiguous Interval" do
    test "day/1 on a month-spanning interval raises" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06")

      assert_raise ArgumentError, ~r/ambiguous/, fn -> Tempo.day(iv) end
    end

    test "month/1 on a year-spanning interval raises" do
      {:ok, iv} = Tempo.to_interval(~o"2026")

      assert_raise ArgumentError, ~r/ambiguous/, fn -> Tempo.month(iv) end
    end

    test "hour/1 on a day-spanning interval raises" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06-15")

      assert_raise ArgumentError, ~r/ambiguous/, fn -> Tempo.hour(iv) end
    end

    test "error message points to endpoints/1 as the escape hatch" do
      {:ok, iv} = Tempo.to_interval(~o"2026")

      assert_raise ArgumentError, ~r/Tempo.Interval.endpoints\/1/, fn ->
        Tempo.day(iv)
      end
    end
  end
end
