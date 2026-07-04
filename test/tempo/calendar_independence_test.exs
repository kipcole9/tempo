defmodule Tempo.CalendarIndependenceTest do
  @moduledoc """
  Operations must be calendar-independent. Comparison and duration route each
  value through its calendar's date→absolute-day conversion, so cross-calendar
  relations, `within?`, and non-Gregorian durations are as accurate as
  single-calendar ones — while the Gregorian fast path is unchanged.
  """
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Compare
  alias Tempo.Interval

  # Build a value in the named calendar via its IXDTF `u-ca` tag.
  defp cal(string, calendar), do: Tempo.from_iso8601!("#{string}[u-ca=#{calendar}]")

  # The real elapsed length of a value's enclosing span, in whole days.
  defp span_days(value) do
    {:ok, interval} = Tempo.to_interval(value)
    seconds = Compare.to_utc_seconds(interval.to) - Compare.to_utc_seconds(interval.from)
    round(seconds / 86_400)
  end

  describe "cross-calendar comparison routes through the shared absolute frame" do
    test "equivalent dates in different calendars compare as :equals" do
      # Tishri 1, 5786 AM = 2025-09-23; Nowruz 1404 = 2025-03-21;
      # Muharram 1, 1447 AH = 2025-06-27.
      assert Tempo.relation(~o"2025-09-23", cal("5786-01-01", "hebrew")) == :equals
      assert Tempo.relation(~o"2025-03-21", cal("1404-01-01", "persian")) == :equals
      assert Tempo.relation(~o"2025-06-27", cal("1447-01-01", "islamic-civil")) == :equals
    end

    test "a Hebrew date falls within its Gregorian year" do
      assert Tempo.within?(cal("5786-01-01", "hebrew"), ~o"2025")
    end

    test "ordering is correct across calendars" do
      assert Tempo.before?(cal("5786-01-01", "hebrew"), ~o"2025-12-31")
      assert Tempo.after?(cal("1447-06-01", "islamic-civil"), ~o"2025-06-27")
    end

    test "the Gregorian fast path is preserved" do
      assert Tempo.relation(~o"2025-01-01", ~o"2025-06-01") == :precedes
      assert Tempo.within?(~o"2025-06-15", ~o"2025")
    end
  end

  describe "durations are calendar-correct" do
    test "a Hebrew common year is 354 days, not a Gregorian 365" do
      assert span_days(cal("5786", "hebrew")) == 354
    end

    test "an Islamic year is 354 or 355 days" do
      assert span_days(cal("1447", "islamic-civil")) in [354, 355]
    end

    test "a Gregorian year is unchanged at 365 days" do
      assert span_days(~o"2021") == 365
      assert Interval.duration(elem(Tempo.to_interval(~o"2021"), 1)) == ~o"PT31536000S"
    end
  end

  describe "u-ca round-trip" do
    test "multi-word calendar identifiers round-trip through to_iso8601" do
      for calendar <- ["islamic-civil", "islamic-umalqura", "hebrew", "persian", "japanese"] do
        value = cal("1447-01-15", calendar)
        serialised = Tempo.to_iso8601(value)
        assert String.contains?(serialised, "[u-ca=#{calendar}]")
        assert {:ok, reparsed} = Tempo.from_iso8601(serialised)
        assert reparsed.calendar == value.calendar
      end
    end
  end

  describe "a month that does not exist in a calendar year" do
    test "Hebrew Adar I in an ordinary year is a clear error, not a crash" do
      # Month 6 (Adar I) exists only in leap years; 2026 AM is ordinary.
      assert {:error, %Tempo.InvalidDateError{reason: reason}} =
               Tempo.from_iso8601("2026-06-15[u-ca=hebrew]")

      assert reason =~ "does not exist"
    end

    test "the corresponding real month still resolves" do
      # In an ordinary year Adar is month 7, not 6.
      assert {:ok, _} = Tempo.from_iso8601("2026-07-15[u-ca=hebrew]")
    end
  end
end
