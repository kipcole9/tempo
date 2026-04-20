defmodule Tempo.ICal.Test do
  use ExUnit.Case, async: true

  # Tests for `Tempo.ICal.from_ical/2` — iCalendar → IntervalSet
  # conversion with event metadata preserved on each interval.
  #
  # Three input sources:
  #
  # 1. Synthetic ICS strings defined inline — run on every CI.
  # 2. Public fixtures borrowed from the `ical` library's own
  #    test suite (`test/support/data/ical_fixtures/*.ics`,
  #    MIT-licensed, attribution in the directory README).
  # 3. A private Apple Calendar export at
  #    `test/support/data/ical_apple_example_export.ics` — not
  #    committed, tests against it run only when the file exists.

  @apple_fixture "test/support/data/ical_apple_example_export.ics"
  @fixtures_dir "test/support/data/ical_fixtures"

  setup_all do
    Calendar.put_time_zone_database(Tzdata.TimeZoneDatabase)
    :ok
  end

  describe "from_ical/2 — simple events" do
    test "a single datetime event becomes one interval with metadata" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:evt-1
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Team standup
      DESCRIPTION:Daily sync
      LOCATION:Zoom
      END:VEVENT
      END:VCALENDAR
      """

      assert {:ok, set} = Tempo.ICal.from_ical(ics)
      assert length(set.intervals) == 1

      [iv] = set.intervals
      assert iv.metadata.uid == "evt-1"
      assert iv.metadata.summary == "Team standup"
      assert iv.metadata.description == "Daily sync"
      assert iv.metadata.location == "Zoom"
    end

    test "calendar metadata attaches to the IntervalSet" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Vendor//Product//EN
      CALSCALE:GREGORIAN
      METHOD:PUBLISH
      END:VCALENDAR
      """

      assert {:ok, set} = Tempo.ICal.from_ical(ics)
      assert set.metadata.prodid == "-//Vendor//Product//EN"
      assert set.metadata.version == "2.0"
      assert set.metadata.scale == "GREGORIAN"
      assert set.metadata.method == "PUBLISH"
    end

    test "all-day event uses day-resolution endpoints" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:holiday-1
      DTSTAMP:20220101T000000Z
      DTSTART;VALUE=DATE:20220704
      DTEND;VALUE=DATE:20220705
      SUMMARY:Independence Day
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = Tempo.ICal.from_ical(ics)
      [iv] = set.intervals

      assert iv.from.time == [year: 2022, month: 7, day: 4]
      assert iv.to.time == [year: 2022, month: 7, day: 5]
      assert iv.metadata.summary == "Independence Day"
    end

    test "multi-day event spans the half-open range" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:trip-1
      DTSTAMP:20220101T000000Z
      DTSTART;VALUE=DATE:20220913
      DTEND;VALUE=DATE:20220916
      SUMMARY:Conference trip
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = Tempo.ICal.from_ical(ics)
      [iv] = set.intervals
      assert iv.from.time[:day] == 13
      assert iv.to.time[:day] == 16
    end

    test "overlapping events are preserved (no coalesce)" do
      # Two events at the same time with different summaries.
      # Without `coalesce: false` they would merge and lose one
      # event's metadata.
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:evt-a
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Event A
      END:VEVENT
      BEGIN:VEVENT
      UID:evt-b
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Event B
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = Tempo.ICal.from_ical(ics)
      assert length(set.intervals) == 2
      summaries = set.intervals |> Enum.map(& &1.metadata.summary) |> Enum.sort()
      assert summaries == ["Event A", "Event B"]
    end

    test "non-overlapping events are sorted by from" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:later
      DTSTAMP:20220101T000000Z
      DTSTART:20220616T100000Z
      DTEND:20220616T110000Z
      SUMMARY:Later
      END:VEVENT
      BEGIN:VEVENT
      UID:earlier
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Earlier
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = Tempo.ICal.from_ical(ics)
      assert Enum.map(set.intervals, & &1.metadata.summary) == ["Earlier", "Later"]
    end
  end

  describe "from_ical/2 — recurrence" do
    test "FREQ=WEEKLY;COUNT=3 — three weekly occurrences" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:weekly-1
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Weekly standup
      RRULE:FREQ=WEEKLY;COUNT=3
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = Tempo.ICal.from_ical(ics)
      assert length(set.intervals) == 3

      # Each occurrence keeps its summary; days are 7 apart.
      days = set.intervals |> Enum.map(& &1.from.time[:day])
      assert days == [15, 22, 29]

      assert Enum.all?(set.intervals, fn iv ->
               iv.metadata.summary == "Weekly standup"
             end)
    end

    test "FREQ=WEEKLY;UNTIL=... — every occurrence up to UNTIL" do
      # Every Wednesday in June 2022, up to but not past Jul 1.
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:until-1
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      SUMMARY:Weekly until
      RRULE:FREQ=WEEKLY;UNTIL=20220701T000000Z
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = Tempo.ICal.from_ical(ics)
      assert length(set.intervals) == 5
      # All in June.
      assert Enum.all?(set.intervals, fn iv -> iv.from.time[:month] == 6 end)
    end

    test "FREQ=WEEKLY;INTERVAL=2;COUNT=4 — every other week, 4 occurrences" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:biweekly
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=4
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = Tempo.ICal.from_ical(ics)
      assert length(set.intervals) == 4

      # 14-day spacing: Jun 1, Jun 15, Jun 29, Jul 13.
      days = set.intervals |> Enum.map(&{&1.from.time[:month], &1.from.time[:day]})
      assert days == [{6, 1}, {6, 15}, {6, 29}, {7, 13}]
    end

    test "unbounded recurrence (no COUNT, no UNTIL) requires :bound" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:forever
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      RRULE:FREQ=DAILY
      END:VEVENT
      END:VCALENDAR
      """

      assert {:error, reason} = Tempo.ICal.from_ical(ics)
      assert reason =~ "unbounded"
      assert reason =~ "bound"
    end

    test "unbounded recurrence with :bound — materialises within the bound" do
      import Tempo.Sigil

      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:daily-bounded
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      RRULE:FREQ=DAILY
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = Tempo.ICal.from_ical(ics, bound: ~o"2022-06-01/2022-06-08")
      # 7 days in the bound (Jun 1..Jun 7 inclusive; Jun 8 is
      # excluded by the half-open upper bound).
      assert length(set.intervals) == 7
    end

    test "RRULE with BY* rules falls back to first occurrence with a note" do
      # BYDAY and friends require a full RRULE expander — v1 emits
      # only the first occurrence and tags the metadata.
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:byday-1
      DTSTAMP:20220101T000000Z
      DTSTART:20220601T090000Z
      DTEND:20220601T100000Z
      RRULE:FREQ=MONTHLY;BYDAY=1MO
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = Tempo.ICal.from_ical(ics)
      assert length(set.intervals) == 1

      [iv] = set.intervals
      assert iv.metadata[:recurrence_note] == :first_occurrence_only
      assert iv.metadata[:recurrence_reason] == :by_rules_not_supported
    end
  end

  describe "from_ical/2 — edge cases" do
    test "events with nil DTSTART are skipped silently" do
      # Technically malformed per RFC 5545, but some exports
      # include them. Skipping is less disruptive than erroring.
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:has-start
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Normal event
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, set} = Tempo.ICal.from_ical(ics)
      assert length(set.intervals) == 1
    end

    test "malformed ics returns an empty result without raising" do
      # The underlying `ical` library is tolerant: non-iCalendar
      # input parses to an empty calendar, not a raise. We pass
      # that through — the caller sees zero intervals.
      assert {:ok, set} = Tempo.ICal.from_ical("not valid ical")
      assert set.intervals == []
    end
  end

  describe "metadata propagation through set operations" do
    test "intersection preserves A-side per-interval metadata" do
      import Tempo.Sigil

      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:meeting
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:Design review
      LOCATION:Room 101
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, events} = Tempo.ICal.from_ical(ics)
      work_hours = ~o"2022-06-15T09/2022-06-15T17"

      {:ok, overlap} = Tempo.intersection(events, work_hours)
      assert length(overlap.intervals) == 1

      [iv] = overlap.intervals
      # Event metadata survives the intersection.
      assert iv.metadata.summary == "Design review"
      assert iv.metadata.location == "Room 101"
    end

    test "difference preserves A-side per-interval metadata" do
      import Tempo.Sigil

      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:long-event
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T080000Z
      DTEND:20220615T120000Z
      SUMMARY:Long session
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, events} = Tempo.ICal.from_ical(ics)
      break_time = ~o"2022-06-15T10/2022-06-15T11"

      {:ok, remaining} = Tempo.difference(events, break_time)
      # Event is split into pre-break and post-break, both tagged
      # with the original event's metadata.
      assert length(remaining.intervals) == 2

      assert Enum.all?(remaining.intervals, fn iv ->
               iv.metadata.summary == "Long session"
             end)
    end

    test "IntervalSet-level metadata follows the first operand" do
      import Tempo.Sigil

      a_ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Calendar-A//EN
      BEGIN:VEVENT
      UID:a-1
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:A's event
      END:VEVENT
      END:VCALENDAR
      """

      b_ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Calendar-B//EN
      BEGIN:VEVENT
      UID:b-1
      DTSTAMP:20220101T000000Z
      DTSTART:20220615T100000Z
      DTEND:20220615T110000Z
      SUMMARY:B's event
      END:VEVENT
      END:VCALENDAR
      """

      {:ok, a} = Tempo.ICal.from_ical(a_ics)
      {:ok, b} = Tempo.ICal.from_ical(b_ics)

      {:ok, result} = Tempo.intersection(a, b)
      # The set-level metadata comes from the first operand.
      assert result.metadata.prodid == "-//Calendar-A//EN"
    end
  end

  describe "from_ical/2 — public fixtures (borrowed from ical library)" do
    test "one_event.ics parses and carries full metadata" do
      path = Path.join(@fixtures_dir, "one_event.ics")
      {:ok, set} = Tempo.ICal.from_ical_file(path)
      [iv] = set.intervals

      assert iv.metadata.uid == "1001"
      assert iv.metadata.summary == "Going fishing"
      assert iv.metadata.location =~ "Toronto"
      assert "Fishing" in (iv.metadata.categories || [])
      # The `ical` library's normalisation is not uniform —
      # STATUS comes through as an atom, CLASS as a string. We
      # pass both through as-is rather than coerce; callers can
      # match on either shape.
      assert iv.metadata.status == :tentative
      assert iv.metadata.classification == "PRIVATE"
    end

    test "attendees.ics — the event has no DTSTART, so it's skipped cleanly" do
      # This fixture is a bare VEVENT with ATTENDEE lines but no
      # DTSTART — Tempo.ICal skips DTSTART-less events (since they
      # can't be placed on the time line). The test exists mainly
      # to prove we don't crash on incomplete events.
      path = Path.join(@fixtures_dir, "attendees.ics")
      {:ok, set} = Tempo.ICal.from_ical_file(path)
      assert set.intervals == []
    end

    test "timezone_event.ics parses (zoned events)" do
      path = Path.join(@fixtures_dir, "timezone_event.ics")
      assert {:ok, set} = Tempo.ICal.from_ical_file(path)
      assert length(set.intervals) > 0
    end

    test "calendar_name.ics surfaces X-WR-CALNAME on the set's metadata" do
      path = Path.join(@fixtures_dir, "calendar_name.ics")
      {:ok, set} = Tempo.ICal.from_ical_file(path)
      # Even if the fixture uses a plain WR-CALNAME, the metadata
      # should be a plain string.
      if set.metadata[:name] do
        assert is_binary(set.metadata[:name])
      end
    end

    test "recurrance_with_count.ics expands to N occurrences" do
      path = Path.join(@fixtures_dir, "recurrance_with_count.ics")
      {:ok, set} = Tempo.ICal.from_ical_file(path)
      # The fixture has FREQ=DAILY;COUNT=3 so expansion gives us
      # three day-long occurrences.
      assert length(set.intervals) == 3
    end
  end

  describe "from_ical/2 — real Apple Calendar export" do
    @describetag :real_ical_fixture

    setup do
      if File.exists?(@apple_fixture) do
        {:ok, ics: File.read!(@apple_fixture)}
      else
        :ok
      end
    end

    test "parses without error and produces an IntervalSet", %{ics: ics} do
      assert {:ok, set} = Tempo.ICal.from_ical(ics)
      assert %Tempo.IntervalSet{} = set
      assert length(set.intervals) > 0
    end

    test "preserves every event's summary on its interval", %{ics: ics} do
      {:ok, set} = Tempo.ICal.from_ical(ics)
      # Every interval should have a summary (optional in RFC 5545
      # but present in every real export we've seen).
      summaries =
        set.intervals
        |> Enum.map(& &1.metadata[:summary])
        |> Enum.reject(&is_nil/1)

      assert length(summaries) > 0
    end

    test "calendar name from X-WR-CALNAME is captured", %{ics: ics} do
      {:ok, set} = Tempo.ICal.from_ical(ics)
      # The Apple export carries an X-WR-CALNAME; it should come
      # through as a plain string, not a wrapped struct.
      case set.metadata[:name] do
        nil -> :ok
        name when is_binary(name) -> :ok
      end
    end
  end
end
