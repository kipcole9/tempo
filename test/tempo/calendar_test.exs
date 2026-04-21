defmodule Tempo.CalendarTest do
  use ExUnit.Case, async: true

  # `Tempo.Calendar` resolves BCP 47 / CLDR calendar identifier
  # atoms (as produced by the IXDTF `[u-ca=NAME]` tokenizer path
  # via `Localize.validate_calendar/1`) to `Calendrical.*` calendar
  # modules. The mapping is built at compile time by asking each
  # known calendar module for its `cldr_calendar_type/0`.

  describe "module_from_name/1" do
    test "resolves :gregorian to Calendrical.Gregorian" do
      assert {:ok, Calendrical.Gregorian} = Tempo.Calendar.module_from_name(:gregorian)
    end

    test "resolves :hebrew to Calendrical.Hebrew" do
      assert {:ok, Calendrical.Hebrew} = Tempo.Calendar.module_from_name(:hebrew)
    end

    test "resolves all Islamic variants to their nested modules" do
      assert {:ok, Calendrical.Islamic.Observational} =
               Tempo.Calendar.module_from_name(:islamic)

      assert {:ok, Calendrical.Islamic.UmmAlQura} =
               Tempo.Calendar.module_from_name(:islamic_umalqura)

      assert {:ok, Calendrical.Islamic.Civil} =
               Tempo.Calendar.module_from_name(:islamic_civil)

      assert {:ok, Calendrical.Islamic.Rgsa} =
               Tempo.Calendar.module_from_name(:islamic_rgsa)

      assert {:ok, Calendrical.Islamic.Tbla} =
               Tempo.Calendar.module_from_name(:islamic_tbla)
    end

    test "resolves :ethiopic_amete_alem to the nested module" do
      assert {:ok, Calendrical.Ethiopic.AmeteAlem} =
               Tempo.Calendar.module_from_name(:ethiopic_amete_alem)
    end

    test "resolves :persian, :buddhist, :chinese, :coptic, :indian, :japanese, :roc" do
      assert {:ok, Calendrical.Persian} = Tempo.Calendar.module_from_name(:persian)
      assert {:ok, Calendrical.Buddhist} = Tempo.Calendar.module_from_name(:buddhist)
      assert {:ok, Calendrical.Chinese} = Tempo.Calendar.module_from_name(:chinese)
      assert {:ok, Calendrical.Coptic} = Tempo.Calendar.module_from_name(:coptic)
      assert {:ok, Calendrical.Indian} = Tempo.Calendar.module_from_name(:indian)
      assert {:ok, Calendrical.Japanese} = Tempo.Calendar.module_from_name(:japanese)
      assert {:ok, Calendrical.Roc} = Tempo.Calendar.module_from_name(:roc)
    end

    test "returns an error for unknown identifiers" do
      assert {:error, message} = Tempo.Calendar.module_from_name(:not_a_calendar)
      assert message =~ ":not_a_calendar"
    end
  end

  describe "supported_names/0" do
    test "includes the common calendars" do
      names = Tempo.Calendar.supported_names()
      assert :gregorian in names
      assert :hebrew in names
      assert :islamic_umalqura in names
      assert :persian in names
    end
  end

  describe "Tempo.from_iso8601/1 with [u-ca=NAME] suffix" do
    # The IXDTF suffix, when no explicit calendar argument is
    # given, resolves to a concrete `Calendrical.*` module and
    # the resulting Tempo struct's `:calendar` field is swapped
    # accordingly. Parsing and validation then use that calendar's
    # domain rules.

    test "[u-ca=hebrew] swaps the struct's calendar to Calendrical.Hebrew" do
      {:ok, tempo} = Tempo.from_iso8601("5786-10-30[u-ca=hebrew]")
      assert tempo.calendar == Calendrical.Hebrew
      # The extended metadata still captures the raw tag value.
      assert tempo.extended.calendar == :hebrew
    end

    test "multi-segment identifiers (dash-separated) work" do
      {:ok, tempo} = Tempo.from_iso8601("1447-01-15[u-ca=islamic-umalqura]")
      assert tempo.calendar == Calendrical.Islamic.UmmAlQura
      assert tempo.extended.calendar == :islamic_umalqura
    end

    test "[u-ca=gregory] is accepted as an alias for :gregorian" do
      # BCP 47 uses `gregory` as the identifier; Localize normalises
      # it to `:gregorian`.
      {:ok, tempo} = Tempo.from_iso8601("2026-06-15[u-ca=gregory]")
      assert tempo.calendar == Calendrical.Gregorian
      assert tempo.extended.calendar == :gregorian
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
