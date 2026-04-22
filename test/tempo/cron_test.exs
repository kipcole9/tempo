defmodule Tempo.CronTest do
  use ExUnit.Case, async: true

  doctest Tempo.Cron

  alias Tempo.Cron
  alias Tempo.RRule.Rule

  describe "pure-step shortcut (FREQ=unit, INTERVAL=n)" do
    test "`* * * * *` → every minute" do
      assert {:ok, %Rule{freq: :minute, interval: 1}} = Cron.parse("* * * * *")
    end

    test "`*/15 * * * *` → every 15 minutes" do
      assert {:ok, %Rule{freq: :minute, interval: 15, byminute: nil}} =
               Cron.parse("*/15 * * * *")
    end

    test "`* */2 * * *` → every 2 hours" do
      assert {:ok, %Rule{freq: :hour, interval: 2}} = Cron.parse("* */2 * * *")
    end

    test "6-field `* * * * * *` → every second" do
      assert {:ok, %Rule{freq: :second, interval: 1}} = Cron.parse("* * * * * *")
    end

    test "6-field `*/10 * * * * *` → every 10 seconds" do
      assert {:ok, %Rule{freq: :second, interval: 10}} = Cron.parse("*/10 * * * * *")
    end
  end

  describe "time-of-day filters (FREQ cascades)" do
    test "`0 9 * * *` → 9am daily" do
      assert {:ok, rule} = Cron.parse("0 9 * * *")
      assert rule.freq == :day
      assert rule.byhour == [9]
      assert rule.byminute == [0]
    end

    test "`30 9 * * *` → 9:30am daily" do
      assert {:ok, rule} = Cron.parse("30 9 * * *")
      assert rule.freq == :day
      assert rule.byhour == [9]
      assert rule.byminute == [30]
    end

    test "`0 9,12,17 * * *` → 9am, noon, 5pm" do
      assert {:ok, rule} = Cron.parse("0 9,12,17 * * *")
      assert rule.byhour == [9, 12, 17]
    end

    test "`0 9-17 * * *` → every hour 9..17" do
      assert {:ok, rule} = Cron.parse("0 9-17 * * *")
      assert rule.byhour == [9, 10, 11, 12, 13, 14, 15, 16, 17]
    end

    test "`0 9-17/2 * * *` → every 2 hours 9..17" do
      assert {:ok, rule} = Cron.parse("0 9-17/2 * * *")
      assert rule.byhour == [9, 11, 13, 15, 17]
    end
  end

  describe "weekly schedules (FREQ=WEEKLY)" do
    test "`0 9 * * 1-5` → 9am weekdays (RFC 5545 Mon=1..Fri=5)" do
      assert {:ok, rule} = Cron.parse("0 9 * * 1-5")
      assert rule.freq == :week
      assert rule.byday == [{nil, 1}, {nil, 2}, {nil, 3}, {nil, 4}, {nil, 5}]
      assert rule.byhour == [9]
      assert rule.byminute == [0]
    end

    test "`0 9 * * MON-FRI` same as numeric 1-5" do
      {:ok, named} = Cron.parse("0 9 * * MON-FRI")
      {:ok, numeric} = Cron.parse("0 9 * * 1-5")
      assert named.byday == numeric.byday
    end

    test "day-of-week 0 and 7 both map to RFC 5545 Sunday (7)" do
      {:ok, a} = Cron.parse("0 0 * * 0")
      {:ok, b} = Cron.parse("0 0 * * 7")
      assert a.byday == [{nil, 7}]
      assert b.byday == [{nil, 7}]
    end

    test "day-of-week names are case-insensitive" do
      {:ok, rule} = Cron.parse("0 0 * * mon,wed,fri")
      assert rule.byday == [{nil, 1}, {nil, 3}, {nil, 5}]
    end
  end

  describe "monthly and yearly schedules" do
    test "`0 0 1 * *` → midnight on the 1st" do
      assert {:ok, rule} = Cron.parse("0 0 1 * *")
      assert rule.freq == :month
      assert rule.bymonthday == [1]
      assert rule.byhour == [0]
      assert rule.byminute == [0]
    end

    test "`0 0 1 1 *` → midnight January 1st" do
      assert {:ok, rule} = Cron.parse("0 0 1 1 *")
      assert rule.freq == :year
      assert rule.bymonth == [1]
      assert rule.bymonthday == [1]
    end

    test "`0 0 * JAN-JUN *` → first half of year" do
      assert {:ok, rule} = Cron.parse("0 0 * JAN-JUN *")
      assert rule.freq == :year
      assert rule.bymonth == [1, 2, 3, 4, 5, 6]
    end
  end

  describe "aliases" do
    test "@yearly" do
      assert {:ok, rule} = Cron.parse("@yearly")
      assert rule.freq == :year
      assert rule.bymonth == [1]
      assert rule.bymonthday == [1]
      assert rule.byhour == [0]
      assert rule.byminute == [0]
    end

    test "@annually — synonym for @yearly" do
      {:ok, a} = Cron.parse("@yearly")
      {:ok, b} = Cron.parse("@annually")
      assert a == b
    end

    test "@monthly" do
      assert {:ok, rule} = Cron.parse("@monthly")
      assert rule.freq == :month
      assert rule.bymonthday == [1]
    end

    test "@weekly" do
      assert {:ok, rule} = Cron.parse("@weekly")
      assert rule.freq == :week
      assert rule.byday == [{nil, 7}]
    end

    test "@daily" do
      assert {:ok, rule} = Cron.parse("@daily")
      assert rule.freq == :day
      assert rule.byhour == [0]
      assert rule.byminute == [0]
    end

    test "@midnight — synonym for @daily" do
      {:ok, a} = Cron.parse("@daily")
      {:ok, b} = Cron.parse("@midnight")
      assert a == b
    end

    test "@hourly" do
      assert {:ok, rule} = Cron.parse("@hourly")
      assert rule.freq == :hour
      assert rule.byminute == [0]
    end

    test "aliases are case-insensitive" do
      {:ok, a} = Cron.parse("@Yearly")
      {:ok, b} = Cron.parse("@YEARLY")
      {:ok, c} = Cron.parse("@yearly")
      assert a == b
      assert b == c
    end
  end

  describe "Vixie-cron extensions" do
    test "`L` as day-of-month → last day of month" do
      assert {:ok, rule} = Cron.parse("0 0 L * *")
      assert rule.bymonthday == [-1]
    end

    test "`5L` as day-of-week → last Friday of month" do
      assert {:ok, rule} = Cron.parse("0 0 * * 5L")
      assert rule.byday == [{-1, 5}]
    end

    test "`5#2` → second Friday of month" do
      assert {:ok, rule} = Cron.parse("0 0 * * 5#2")
      assert rule.byday == [{2, 5}]
    end

    test "`FRI#2` — named second Friday" do
      {:ok, a} = Cron.parse("0 0 * * 5#2")
      {:ok, b} = Cron.parse("0 0 * * FRI#2")
      assert a.byday == b.byday
    end
  end

  describe "7-field cron with year" do
    test "single year becomes UNTIL" do
      assert {:ok, rule} = Cron.parse("0 0 0 1 1 * 2026")
      assert rule.freq == :year
      assert rule.until.time == [year: 2027]
    end
  end

  describe "error reporting" do
    test "not enough fields" do
      assert {:error, %Tempo.CronError{} = e} = Cron.parse("wibble")
      assert Exception.message(e) =~ "5, 6, or 7 fields"
    end

    test "value out of range" do
      assert {:error, %Tempo.CronError{field: :hour} = e} = Cron.parse("0 25 * * *")
      assert Exception.message(e) =~ "outside the valid range"
    end

    test "unsupported W (nearest-weekday)" do
      assert {:error, %Tempo.CronError{field: :day_of_month, reason: :unsupported_w}} =
               Cron.parse("0 0 15W * *")
    end

    test "invalid day-of-week name" do
      assert {:error, %Tempo.CronError{field: :day_of_week} = e} =
               Cron.parse("0 0 * * WIBBLE")

      assert Exception.message(e) =~ "Invalid day-of-week"
    end
  end

  describe "parse!/1 raises" do
    test "on invalid input" do
      assert_raise Tempo.CronError, fn -> Cron.parse!("wibble") end
    end

    test "returns the rule on success" do
      assert %Rule{freq: :day} = Cron.parse!("@daily")
    end
  end

  describe "materialisation via Tempo.to_interval/2" do
    # Smoke-test that a parsed cron rule can actually be expanded.
    test "every 15 minutes — materialises within an hour-resolution bound" do
      {:ok, rule} = Cron.parse("*/15 * * * *")

      {:ok, ast} =
        Tempo.RRule.Expander.to_ast(rule, Tempo.from_iso8601!("2026-06-15T10:00:00"))

      # Bound `~o"2026-06-15T10"` is the implicit one-hour span
      # `[10:00, 11:00)`; at 15-minute intervals that's 4 occurrences.
      {:ok, set} =
        Tempo.to_interval(ast,
          bound: Tempo.from_iso8601!("2026-06-15T10"),
          coalesce: false
        )

      # 10:00, 10:15, 10:30, 10:45.
      assert Tempo.IntervalSet.count(set) == 4
    end
  end
end
