defmodule Tempo.RRule.WkstAndEdgesTest do
  use ExUnit.Case, async: true
  import Tempo.Sigil

  alias Tempo.RRule.Expander
  alias Tempo.RRule.Rule

  # Phase E — WKST, leap year, DST, and other edges.
  #
  # WKST changes how FREQ=WEEKLY+BYDAY partitions occurrences
  # into weeks. With the default WKST=MO (1), the week is
  # Mon..Sun; with WKST=SU (7), the week is Sun..Sat. For most
  # BYDAY expansions at the per-week level the set of dates
  # produced in a month or year is identical — only the
  # *grouping* into weeks differs. That grouping matters when
  # BYSETPOS picks the Nth element of a per-week candidate set.

  describe "WKST — week boundaries for FREQ=WEEKLY+BYDAY" do
    test "FREQ=WEEKLY;BYDAY=SU at a Sunday DTSTART with default WKST=MO" do
      # DTSTART=Sun 2022-06-05. With WKST=MO, the week containing
      # DTSTART is Mon May 30..Sun Jun 5. The only Sunday in
      # that week is Jun 5 (= DTSTART). Next iteration advances
      # one week to Jun 12 (next Sunday).
      rule = %Rule{freq: :week, interval: 1, byday: [{nil, 7}], count: 3}
      {:ok, occ} = Expander.expand(rule, ~o"2022-06-05")

      days = Enum.map(occ, & &1.from.time[:day])
      assert days == [5, 12, 19]
    end

    test "FREQ=WEEKLY;BYDAY=SU;WKST=SU shifts week boundaries to Sunday-first" do
      # Same dates because BYDAY=SU picks one day per week
      # regardless of boundary. The interesting difference is
      # in BYSETPOS interactions (see next test).
      rule = %Rule{freq: :week, interval: 1, byday: [{nil, 7}], wkst: 7, count: 3}
      {:ok, occ} = Expander.expand(rule, ~o"2022-06-05")

      days = Enum.map(occ, & &1.from.time[:day])
      assert days == [5, 12, 19]
    end

    test "FREQ=WEEKLY;BYDAY=MO,SU with WKST=MO vs WKST=SU" do
      # DTSTART=Sat 2022-06-04 (dow=6). With WKST=MO, the week
      # is Mon May 30..Sun Jun 5 → Monday=May 30, Sunday=Jun 5.
      # With WKST=SU, the week is Sun May 29..Sat Jun 4 → Sunday=May 29, Monday=May 30.
      # Both emit different date sets for the first week.
      rule_mo = %Rule{freq: :week, interval: 1, byday: [{nil, 1}, {nil, 7}], wkst: 1, count: 2}
      rule_su = %Rule{freq: :week, interval: 1, byday: [{nil, 1}, {nil, 7}], wkst: 7, count: 2}

      {:ok, mo_occ} = Expander.expand(rule_mo, ~o"2022-06-04")
      {:ok, su_occ} = Expander.expand(rule_su, ~o"2022-06-04")

      mo_days =
        Enum.map(mo_occ, fn iv -> {iv.from.time[:month], iv.from.time[:day]} end) |> Enum.sort()

      su_days =
        Enum.map(su_occ, fn iv -> {iv.from.time[:month], iv.from.time[:day]} end) |> Enum.sort()

      # MO-week first includes Mon May 30 and Sun Jun 5 (in-week).
      assert {5, 30} in mo_days or {6, 5} in mo_days

      # SU-week first includes Sun May 29 (start of that week).
      assert {5, 29} in su_days
    end
  end

  describe "leap year edges" do
    test "BYMONTHDAY=29 in a non-leap February silently skips" do
      # FREQ=YEARLY with DTSTART on 2020-02-29 (leap year) and
      # BYMONTH=2;BYMONTHDAY=29: 2020 matches, 2021/2022/2023 get
      # no match, 2024 matches. COUNT=3 sees 2020, 2024, 2028.
      rule = %Rule{
        freq: :year,
        interval: 1,
        bymonth: [2],
        bymonthday: [29],
        count: 3
      }

      {:ok, occ} = Expander.expand(rule, ~o"2020-02-29")

      years = Enum.map(occ, & &1.from.time[:year])
      assert years == [2020, 2024, 2028]
    end

    test "BYYEARDAY=366 in a non-leap year produces nothing that year" do
      # FREQ=YEARLY;BYYEARDAY=366 — only leap years have day 366.
      rule = %Rule{freq: :year, interval: 1, byyearday: [366], count: 2}
      {:ok, occ} = Expander.expand(rule, ~o"2020-12-31")

      # 2020 and 2024 are leap years; 2021-23 are not.
      years = Enum.map(occ, & &1.from.time[:year])
      assert years == [2020, 2024]
    end

    test "BYMONTHDAY=31 in 30-day months silently skips" do
      # FREQ=MONTHLY;BYMONTHDAY=31 — only Jan, Mar, May, Jul,
      # Aug, Oct, Dec have a 31st.
      rule = %Rule{freq: :month, interval: 1, bymonthday: [31], count: 4}
      {:ok, occ} = Expander.expand(rule, ~o"2022-01-31")

      pairs =
        Enum.map(occ, fn iv -> {iv.from.time[:year], iv.from.time[:month]} end)

      # Jan, Mar, May, Jul — first four 31-day months of 2022.
      assert pairs == [{2022, 1}, {2022, 3}, {2022, 5}, {2022, 7}]
    end
  end

  describe "WKST in the AST" do
    test "non-default WKST round-trips through parse/encode" do
      {:ok, ast} = Tempo.RRule.parse("FREQ=WEEKLY;BYDAY=SU;WKST=SU;COUNT=3")
      assert ast.repeat_rule.time == [selection: [day_of_week: 7, wkst: 7]]

      # Re-emit and reparse to ensure round-trip stability.
      {:ok, encoded} = Tempo.to_rrule(ast)
      assert encoded =~ "WKST=SU"
      assert encoded =~ "BYDAY=SU"

      {:ok, reparsed} = Tempo.RRule.parse(encoded)
      assert reparsed.repeat_rule.time == ast.repeat_rule.time
    end

    test "default WKST=MO is elided from the AST" do
      # Explicit WKST=MO is redundant with the default; we don't
      # emit the token since it would bloat every AST.
      {:ok, ast} = Tempo.RRule.parse("FREQ=WEEKLY;BYDAY=SU;WKST=MO;COUNT=1")
      refute Keyword.has_key?(ast.repeat_rule.time[:selection] || [], :wkst)
    end
  end
end
