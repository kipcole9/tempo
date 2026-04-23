defmodule Tempo.RRuleTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.RRule

  # The purpose of this test suite is to validate that Tempo's
  # existing AST is a sufficient target for RFC 5545 RRULE
  # strings. If every assertion below passes without adding new
  # struct fields, the AST is validated as a shared target for
  # both ISO 8601-2 and RRULE. See docs/rrule-ast-validation.md
  # for the full findings.

  describe "core recurrence fields" do
    test "FREQ=DAILY is an infinite daily interval" do
      {:ok, i} = RRule.parse("FREQ=DAILY")
      assert i.recurrence == :infinity
      assert i.duration.time == [day: 1]
      assert i.to == nil
      assert i.repeat_rule == nil
    end

    test "COUNT sets recurrence" do
      {:ok, i} = RRule.parse("FREQ=DAILY;COUNT=10")
      assert i.recurrence == 10
      assert i.duration.time == [day: 1]
    end

    test "INTERVAL multiplies the duration" do
      {:ok, i} = RRule.parse("FREQ=DAILY;INTERVAL=3")
      assert i.duration.time == [day: 3]
      assert i.recurrence == :infinity
    end

    test "UNTIL sets the to bound and keeps recurrence infinite" do
      {:ok, i} = RRule.parse("FREQ=WEEKLY;UNTIL=20221231")
      assert i.duration.time == [week: 1]
      assert i.to == ~o"2022-12-31"
      assert i.recurrence == :infinity
    end

    test "RRULE: prefix is stripped" do
      {:ok, i} = RRule.parse("RRULE:FREQ=DAILY;COUNT=5")
      assert i.recurrence == 5
    end
  end

  describe "FREQ → duration unit mapping" do
    for {freq, unit} <- [
          {"SECONDLY", :second},
          {"MINUTELY", :minute},
          {"HOURLY", :hour},
          {"DAILY", :day},
          {"WEEKLY", :week},
          {"MONTHLY", :month},
          {"YEARLY", :year}
        ] do
      test "FREQ=#{freq} produces duration unit #{inspect(unit)}" do
        {:ok, i} = RRule.parse("FREQ=#{unquote(freq)}")
        assert i.duration.time == [{unquote(unit), 1}]
      end
    end
  end

  describe "BY* rules build a repeat_rule with selection tokens" do
    test "BYMONTHDAY becomes a day selection" do
      {:ok, i} = RRule.parse("FREQ=MONTHLY;BYMONTHDAY=15")
      assert i.repeat_rule.time == [selection: [day: 15]]
    end

    test "BYMONTH becomes a month selection" do
      {:ok, i} = RRule.parse("FREQ=YEARLY;BYMONTH=6")
      assert i.repeat_rule.time == [selection: [month: 6]]
    end

    test "multiple BYMONTH values become a list" do
      {:ok, i} = RRule.parse("FREQ=YEARLY;BYMONTH=6,7,8")
      assert i.repeat_rule.time == [selection: [month: [6, 7, 8]]]
    end

    test "BYDAY without ordinal becomes day_of_week selection" do
      {:ok, i} = RRule.parse("FREQ=WEEKLY;BYDAY=MO,WE,FR")
      assert i.repeat_rule.time == [selection: [day_of_week: [1, 3, 5]]]
    end

    test "BYDAY with positive ordinal becomes a :byday pair token" do
      # 4th Thursday of November — US Thanksgiving.
      {:ok, i} = RRule.parse("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH")

      # BYDAY-with-ordinal uses the `:byday` token which keeps
      # the (ordinal, weekday) pair intact. `:day_of_week` is
      # reserved for the no-ordinal form.
      assert i.repeat_rule.time ==
               [selection: [month: 11, byday: [{4, 4}]]]
    end

    test "BYDAY with negative ordinal" do
      # Last Friday of every month.
      {:ok, i} = RRule.parse("FREQ=MONTHLY;BYDAY=-1FR")

      assert i.repeat_rule.time ==
               [selection: [byday: [{-1, 5}]]]
    end

    test "BYHOUR, BYMINUTE, BYSECOND for time-of-day filters" do
      {:ok, i} = RRule.parse("FREQ=DAILY;BYHOUR=9;BYMINUTE=0,30")

      assert i.repeat_rule.time ==
               [selection: [hour: 9, minute: [0, 30]]]
    end

    test "BYSETPOS maps to a dedicated :set_position token" do
      {:ok, i} = RRule.parse("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1")

      # `:set_position` is distinct from the `:instance` token
      # used by Tempo's native ISO 8601-2 selection grammar. The
      # semantics differ: BYSETPOS operates on the per-period
      # candidate set AFTER all other BY-rules.
      assert i.repeat_rule.time ==
               [selection: [set_position: -1, day_of_week: [1, 2, 3, 4, 5]]]
    end
  end

  describe "DTSTART anchor via :from option" do
    test "supplies the interval's from endpoint" do
      anchor = ~o"2022-01-01"
      {:ok, i} = RRule.parse("FREQ=DAILY;COUNT=10", from: anchor)
      assert i.from == anchor
    end

    test "without :from the interval has nil anchor" do
      {:ok, i} = RRule.parse("FREQ=DAILY;COUNT=10")
      assert i.from == nil
    end
  end

  describe "errors" do
    test "missing FREQ is rejected" do
      assert {:error, :missing_freq} = RRule.parse("BYMONTH=6")
    end

    test "unknown FREQ is rejected" do
      assert {:error, {:unknown_freq, "NONSENSE"}} =
               RRule.parse("FREQ=NONSENSE")
    end

    test "unknown rule part is rejected" do
      assert {:error, {:unknown_rule_part, "BOGUS"}} =
               RRule.parse("FREQ=DAILY;BOGUS=7")
    end

    test "malformed BYDAY entry is rejected" do
      assert {:error, {:invalid_byday, "ZZ"}} =
               RRule.parse("FREQ=WEEKLY;BYDAY=ZZ")
    end

    test "non-integer UNTIL is rejected" do
      assert {:error, {:invalid_until, _, _}} =
               RRule.parse("FREQ=DAILY;UNTIL=notadate")
    end
  end

  describe "AST equivalence with ISO 8601-2 selection tokens" do
    # The whole point of this spike: an RRULE and an ISO 8601-2
    # expression that mean the same thing should land on the same
    # AST.

    test "MONTHLY;BYDAY=-1FR lands on the :byday pair token" do
      {:ok, rrule_ast} = RRule.parse("FREQ=MONTHLY;BYDAY=-1FR")

      assert rrule_ast.repeat_rule.time == [selection: [byday: [{-1, 5}]]]
    end

    test "YEARLY;BYMONTH=6 carries a month-only selection" do
      {:ok, rrule_ast} = RRule.parse("FREQ=YEARLY;BYMONTH=6")
      assert rrule_ast.repeat_rule.time == [selection: [month: 6]]
    end
  end
end
