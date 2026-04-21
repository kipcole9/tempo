defmodule Tempo.CalendarTest do
  use ExUnit.Case, async: true

  # The IXDTF `[u-ca=NAME]` suffix, when no explicit calendar
  # argument is given to `Tempo.from_iso8601/1`, resolves to a
  # concrete `Calendrical.*` module via
  # `Calendrical.calendar_from_cldr_calendar_type/1` and the
  # resulting Tempo struct's `:calendar` field is swapped
  # accordingly. Parsing and validation then use that calendar's
  # domain rules.

  describe "Tempo.from_iso8601/1 with [u-ca=NAME] suffix" do
    test "[u-ca=hebrew] swaps the struct's calendar to Calendrical.Hebrew" do
      {:ok, tempo} = Tempo.from_iso8601("5786-10-30[u-ca=hebrew]")
      assert tempo.calendar == Calendrical.Hebrew
      # The extended metadata still captures the raw tag value.
      assert tempo.extended.calendar == :hebrew
    end

    test "Islamic variants resolve to their nested Calendrical modules" do
      {:ok, observational} = Tempo.from_iso8601("1447-01-15[u-ca=islamic]")
      assert observational.calendar == Calendrical.Islamic.Observational

      {:ok, umalqura} = Tempo.from_iso8601("1447-01-15[u-ca=islamic-umalqura]")
      assert umalqura.calendar == Calendrical.Islamic.UmmAlQura

      {:ok, civil} = Tempo.from_iso8601("1447-01-15[u-ca=islamic-civil]")
      assert civil.calendar == Calendrical.Islamic.Civil
    end

    test "ethiopic-amete-alem resolves to Calendrical.Ethiopic.AmeteAlem" do
      {:ok, tempo} = Tempo.from_iso8601("2019-05-10[u-ca=ethiopic-amete-alem]")
      assert tempo.calendar == Calendrical.Ethiopic.AmeteAlem
    end

    test "the ethioaa BCP 47 alias works" do
      {:ok, tempo} = Tempo.from_iso8601("2019-05-10[u-ca=ethioaa]")
      assert tempo.calendar == Calendrical.Ethiopic.AmeteAlem
    end

    test "[u-ca=gregory] is accepted as an alias for :gregorian" do
      {:ok, tempo} = Tempo.from_iso8601("2026-06-15[u-ca=gregory]")
      assert tempo.calendar == Calendrical.Gregorian
      assert tempo.extended.calendar == :gregorian
    end

    test "Persian, Buddhist, and other simple calendars resolve directly" do
      {:ok, persian} = Tempo.from_iso8601("1403-10-20[u-ca=persian]")
      assert persian.calendar == Calendrical.Persian

      {:ok, buddhist} = Tempo.from_iso8601("2569-06-15[u-ca=buddhist]")
      assert buddhist.calendar == Calendrical.Buddhist
    end

    test "without a u-ca tag the default calendar is Gregorian" do
      {:ok, tempo} = Tempo.from_iso8601("2026-06-15")
      assert tempo.calendar == Calendrical.Gregorian
    end

    test "critical [!u-ca=fake] fails with a clear error" do
      assert {:error, message} =
               Tempo.from_iso8601("2022-06-15[!u-ca=fakecalendar]")

      assert message =~ "Unknown calendar identifier"
      assert message =~ "fakecalendar"
    end

    test "non-critical [u-ca=fake] is silently ignored" do
      # Per RFC: non-critical unrecognised tags must not fail parse.
      assert {:ok, tempo} =
               Tempo.from_iso8601("2026-06-15[u-ca=fakecalendar]")

      assert tempo.calendar == Calendrical.Gregorian
    end
  end

  describe "Tempo.from_iso8601/2 precedence: explicit calendar wins over IXDTF" do
    test "explicit Gregorian overrides [u-ca=hebrew]" do
      {:ok, tempo} = Tempo.from_iso8601("2022-06-15[u-ca=hebrew]", Calendrical.Gregorian)
      assert tempo.calendar == Calendrical.Gregorian
      # The hint is still recorded on extended for inspection.
      assert tempo.extended.calendar == :hebrew
    end

    test "explicit Hebrew stays Hebrew without any IXDTF suffix" do
      {:ok, tempo} = Tempo.from_iso8601("5786-10-30", Calendrical.Hebrew)
      assert tempo.calendar == Calendrical.Hebrew
    end
  end

  describe "cross-calendar comparisons via IXDTF" do
    test "overlaps?/2 works between an IXDTF-Hebrew date and a Gregorian one" do
      {:ok, hebrew_date} = Tempo.from_iso8601("5786-10-30[u-ca=hebrew]")
      {:ok, gregorian_date} = Tempo.from_iso8601("2026-06-15")

      # Whether they overlap depends on the calendar conversion;
      # the point is that the call succeeds and produces a boolean
      # (not an error from calendar-mismatch handling).
      assert is_boolean(Tempo.overlaps?(hebrew_date, gregorian_date))
    end
  end
end
