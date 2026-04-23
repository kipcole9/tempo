defmodule Tempo.IntervalRegressionTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  # Regressions for two bugs surfaced by the RRule AST-validation
  # spike (see docs/rrule-ast-validation.md).

  describe "Tempo.Interval.new/1 shape coverage" do
    test "date/date interval with a repeat rule (formerly crashed)" do
      # Before the fix the 3-arg clause pattern-matched the literal
      # atom `:to` for the second element, but the tokenizer emits
      # `:date`-tagged tuples. This combination crashed with
      # FunctionClauseError.
      assert {:ok, %Tempo.Interval{} = interval} =
               Tempo.from_iso8601("R/2022-01-01/2022-12-31/F2022-11-24")

      assert interval.recurrence == :infinity
      assert interval.from == ~o"2022-01-01"
      assert interval.to == ~o"2022-12-31"
      assert interval.repeat_rule == ~o"2022-11-24"
    end

    test "datetime/datetime interval with a repeat rule" do
      # Same fix covers datetime endpoints.
      assert {:ok, %Tempo.Interval{}} =
               Tempo.from_iso8601(
                 "R5/2022-01-01T10:00:00/2022-01-01T18:00:00/F2022-01-01T12:00:00"
               )
    end

    test "duration/date interval no longer misclassifies the duration as a date" do
      # Before the fix the wildcard `[{_from, time}, {_to, to}]`
      # clause swallowed the `{:duration, ...}` token and built an
      # interval with a date-shaped "from" of `[day: 1]`, producing
      # `~o"1D/2022Y1M1D"`. After the fix the duration is carried
      # on the `:duration` field.
      assert {:ok, interval} = Tempo.from_iso8601("P1D/2022-01-01")
      assert interval.from == :undefined
      assert interval.to == ~o"2022-01-01"
      assert interval.duration == %Tempo.Duration{time: [day: 1]}
    end

    test "duration/date interval with a repeat rule" do
      assert {:ok, %Tempo.Interval{} = interval} =
               Tempo.from_iso8601("P1D/2022-06-30/F2022-06-15")

      assert interval.duration == %Tempo.Duration{time: [day: 1]}
      assert interval.to == ~o"2022-06-30"
      assert interval.repeat_rule == ~o"2022-06-15"
    end
  end

  describe "Tempo.Inspect for intervals with nil endpoints" do
    test "Interval with nil from and count-bounded recurrence renders as R<n>/../P<dur>" do
      # RRULE parsers (and any future caller building an interval
      # directly without a DTSTART) produce a struct with from: nil.
      # Before the fix this crashed Inspect with BadMapError on
      # `nil.time`.
      interval = %Tempo.Interval{
        recurrence: 10,
        duration: %Tempo.Duration{time: [day: 1]},
        from: nil,
        to: nil
      }

      assert inspect(interval) == ~S|~o"R10/../P1D"|
    end

    test "Interval with nil from and a bounded to renders with both anchors" do
      interval = %Tempo.Interval{
        recurrence: :infinity,
        duration: %Tempo.Duration{time: [week: 1]},
        from: nil,
        to: ~o"2022-12-31"
      }

      assert inspect(interval) == ~S|~o"R/../2022Y12M31D/P1W"|
    end

    test "Interval with nil from and a repeat rule" do
      interval = %Tempo.Interval{
        recurrence: :infinity,
        duration: %Tempo.Duration{time: [month: 1]},
        from: nil,
        to: nil,
        repeat_rule: %Tempo{time: [selection: [day_of_week: 5, instance: -1]]}
      }

      # Shape is `R/../P1M/FL-1I5KN` — the selection inspects to
      # `L-1I5KN` per the existing selection grammar.
      rendered = inspect(interval)
      assert rendered =~ "R/../P1M/F"
      assert rendered =~ "L"
      assert rendered =~ "K"
    end

    test "open-ended interval (existing behaviour) still renders as ../.." do
      assert {:ok, interval} = Tempo.from_iso8601("../..")
      assert inspect(interval) == ~S|~o"../.."|
    end

    test "duration/date interval inspects without crashing" do
      # Requires both the Interval.new fix (to build the right
      # struct) and a corresponding inspect clause for
      # `from: :undefined, to: %Tempo{}, duration: %Duration{}`.
      assert {:ok, interval} = Tempo.from_iso8601("P1D/2022-01-01")
      assert inspect(interval) == ~S|~o"P1D/2022Y1M1D"|
    end
  end
end
