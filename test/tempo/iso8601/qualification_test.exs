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

  describe "component-level qualification (EDTF Level 2)" do
    # Per EDTF Level 2, a qualifier adjacent to a specific component
    # applies to that component, not the whole expression. The
    # qualification ends up on the `:qualifications` map keyed by
    # unit rather than on the expression-level `:qualification`.

    test "year-month post-suffix qualifies the month" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06?")
      assert tempo.qualification == nil
      assert tempo.qualifications == %{month: :uncertain}
      assert Keyword.get(tempo.time, :month) == 6
    end

    test "year-month-day post-suffix qualifies the day" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06-15?")
      assert tempo.qualification == nil
      assert tempo.qualifications == %{day: :uncertain}
    end

    test "~ on the day component" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06-15~")
      assert tempo.qualifications == %{day: :approximate}
    end

    test "pre-qualifier on month" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-?06-15")
      assert tempo.qualifications == %{month: :uncertain}
    end

    test "pre-qualifier on day" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06-?15")
      assert tempo.qualifications == %{day: :uncertain}
    end

    test "multiple components qualified independently" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022?-?06-%15")

      assert tempo.qualifications == %{
               year: :uncertain,
               month: :uncertain,
               day: :uncertain_and_approximate
             }
    end

    test "leading prefix qualifies the whole expression" do
      assert {:ok, tempo} = Tempo.from_iso8601("?2022-06-15")
      assert tempo.qualification == :uncertain
      assert tempo.qualifications == nil
    end

    test "leading prefix plus trailing component qualifier" do
      assert {:ok, tempo} = Tempo.from_iso8601("?2022-06-15~")
      assert tempo.qualification == :uncertain
      assert tempo.qualifications == %{day: :approximate}
    end
  end

  describe "interaction with other features" do
    test "no qualification leaves both fields nil" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06-15")
      assert tempo.qualification == nil
      assert tempo.qualifications == nil
    end

    test "component qualification followed by an IXDTF suffix" do
      assert {:ok, tempo} = Tempo.from_iso8601("2022-06-15?[u-ca=hebrew]")
      assert tempo.qualifications == %{day: :uncertain}
      assert tempo.extended.calendar == :hebrew
    end

    test "per-endpoint qualification in an interval" do
      # A qualifier immediately after an endpoint applies to that
      # endpoint only. The two endpoints of an interval may carry
      # different qualifications.
      assert {:ok, interval} = Tempo.from_iso8601("2022/2023?")
      assert interval.__struct__ == Tempo.Interval
      assert interval.from.qualification == nil
      assert interval.to.qualification == :uncertain

      assert {:ok, interval2} = Tempo.from_iso8601("1984?/2004-06~")
      assert interval2.from.qualification == :uncertain
      assert interval2.to.qualifications == %{month: :approximate}
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
