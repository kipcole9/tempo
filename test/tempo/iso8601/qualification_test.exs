defmodule Tempo.Iso8601.Qualification.Test do
  use ExUnit.Case, async: true

  # ISO 8601-2 / EDTF date qualification operators.
  #
  # `?` marks a date as uncertain (best guess).
  # `~` marks a date as approximate (e.g. "circa 1850").
  # `%` marks a date as both uncertain and approximate.
  #
  # At this stage only the top-level (expression-level) form is
  # supported. Component-level qualification (EDTF Level 2) is
  # not yet implemented.

  describe "year-level qualification" do
    test "uncertain year with ?" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022?")
      assert tempo.qualification == :uncertain
      assert Keyword.get(tempo.time, :year) == 2022
    end

    test "approximate year with ~" do
      assert {:ok, tempo} = Tempo.from_iso8601("1850~")
      assert tempo.qualification == :approximate
    end

    test "uncertain-and-approximate year with %" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022%")
      assert tempo.qualification == :uncertain_and_approximate
    end
  end

  describe "month- and day-level qualification" do
    test "year-month with ?" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06?")
      assert tempo.qualification == :uncertain
      assert Keyword.get(tempo.time, :month) == 6
    end

    test "full calendar date with ?" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06-15?")
      assert tempo.qualification == :uncertain
      assert Keyword.get(tempo.time, :day) == 15
    end

    test "full calendar date with ~" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06-15~")
      assert tempo.qualification == :approximate
    end
  end

  describe "interaction with other features" do
    test "no qualification leaves the field nil" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06-15")
      assert tempo.qualification == nil
    end

    test "qualification followed by an IXDTF suffix" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06-15?[u-ca=hebrew]")
      assert tempo.qualification == :uncertain
      assert tempo.extended.calendar == :hebrew
    end

    test "qualification on an interval endpoint propagates" do
      # The top-level qualification applies to the whole expression.
      # Individual endpoints of the interval inherit it.
      assert {:ok, interval} = Tempo.from_iso8601("2022/2023?")
      assert interval.__struct__ == Tempo.Interval
      assert interval.from.qualification == :uncertain
      assert interval.to.qualification == :uncertain
    end
  end

  describe "bounded interval semantics are unchanged" do
    # Qualification is metadata; it does not shift the interval bounds.
    test "uncertain year still spans the whole year" do
      {:ok, plain} = Tempo.from_iso8601("2022")
      {:ok, uncertain} = Tempo.from_iso8601("2022?")
      assert plain.time == uncertain.time
    end
  end
end
