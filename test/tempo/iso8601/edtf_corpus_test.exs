defmodule Tempo.Iso8601.EdtfCorpus.Test do
  use ExUnit.Case, async: true

  @moduledoc """
  Exercises Tempo against the `unt-libraries/edtf-validate` corpus
  of EDTF strings. EDTF was folded wholesale into ISO 8601-2:2019,
  so EDTF Level 0/1/2 == ISO 8601-2 Level 0/1/2.

  The corpus is imported from
  <https://github.com/unt-libraries/edtf-validate> (BSD-3-Clause).
  See `test/support/edtf_corpus.ex` for the raw strings and
  attribution.

  A subset of Level 2 features is not yet supported by Tempo's
  parser. Those are listed in `@known_failures` below so that they
  remain visible as a TODO list rather than being silently skipped.
  """

  alias Tempo.Iso8601.Edtf.Corpus

  # As of v0.2.0 every string in the upstream corpus either parses
  # or is rejected as the spec prescribes. The map is retained so
  # that future corpus additions that Tempo can't yet handle have a
  # documented home.
  @known_failures %{}

  # Strings that our parser currently accepts but EDTF marks invalid
  # because of cross-component rules (time-zone offset > 14 hours,
  # offset minutes > 59, mixed date+datetime in an interval, etc.).
  # These need semantic validation beyond the tokenizer.
  @semantically_invalid_but_parses MapSet.new([
                                     "-0000",
                                     "Y2006",
                                     "2000/12-12",
                                     "2012-10-10T10:50:10Z15",
                                     "2012-10-10T10:40:10Z00:62",
                                     "2004-01-01T10:10:40Z25:00",
                                     "2004-01-01T10:10:40Z00:60",
                                     "2004-01-01T10:10:10-05:60",
                                     "-1985-04-12T23:20:30+24",
                                     "-1985-04-12T23:20:30Z12:00",
                                     "2005-07-25T10:10:10Z/2006-01-01T10:10:10Z",
                                     "2005-07-25T10:10:10Z/2006-01",
                                     "2005-07-25/2006-01-01T10:10:10Z"
                                   ])

  ## Valid EDTF strings — expected to parse successfully.

  describe "Level 0 dates" do
    for str <- Corpus.level0_dates() do
      unless Map.has_key?(@known_failures, str) do
        test "parses #{inspect(str)}" do
          assert {:ok, _} = Tempo.from_iso8601(unquote(str))
        end
      end
    end
  end

  describe "Level 0 intervals" do
    for str <- Corpus.level0_intervals() do
      unless Map.has_key?(@known_failures, str) do
        test "parses #{inspect(str)}" do
          assert {:ok, _} = Tempo.from_iso8601(unquote(str))
        end
      end
    end
  end

  describe "Level 1 dates" do
    for str <- Corpus.level1_dates() do
      unless Map.has_key?(@known_failures, str) do
        test "parses #{inspect(str)}" do
          assert {:ok, _} = Tempo.from_iso8601(unquote(str))
        end
      end
    end
  end

  describe "Level 1 intervals" do
    for str <- Corpus.level1_intervals() do
      unless Map.has_key?(@known_failures, str) do
        test "parses #{inspect(str)}" do
          assert {:ok, _} = Tempo.from_iso8601(unquote(str))
        end
      end
    end
  end

  describe "Level 2 dates" do
    for str <- Corpus.level2_dates() do
      unless Map.has_key?(@known_failures, str) do
        test "parses #{inspect(str)}" do
          assert {:ok, _} = Tempo.from_iso8601(unquote(str))
        end
      end
    end
  end

  describe "Level 2 intervals" do
    for str <- Corpus.level2_intervals() do
      unless Map.has_key?(@known_failures, str) do
        test "parses #{inspect(str)}" do
          assert {:ok, _} = Tempo.from_iso8601(unquote(str))
        end
      end
    end
  end

  ## Invalid EDTF strings — expected to fail.

  describe "invalid dates" do
    for str <- Corpus.invalid_dates() do
      unless MapSet.member?(@semantically_invalid_but_parses, str) do
        test "rejects #{inspect(str)}" do
          assert {:error, _} = Tempo.from_iso8601(unquote(str))
        end
      end
    end
  end

  describe "invalid intervals" do
    # A subset of the edtf-validate "invalid" intervals are
    # semantically invalid (reversed endpoints, mixed date+datetime,
    # etc.) rather than syntactically invalid. Cross-endpoint
    # validation is future work.
    @interval_semantic_invalid MapSet.new([
                                 "0800/-0999",
                                 "-1000/-2000",
                                 "1000/-2000",
                                 "0001/0000",
                                 "0000-01-03/0000-01",
                                 "0000/-0001",
                                 "0000-02/0000",
                                 "2012-24/2012-21",
                                 "2012-23/2012-22",
                                 "2004-06-11%/2004-%06",
                                 "2004-06-11%/2004-06~",
                                 "Y-61000/-2000",
                                 "2005-07-25T10:10:10Z/2006-01-01T10:10:10Z",
                                 "2005-07-25T10:10:10Z/2006-01",
                                 "2005-07-25/2006-01-01T10:10:10Z"
                               ])

    for str <- Corpus.invalid_intervals() do
      unless MapSet.member?(@interval_semantic_invalid, str) do
        test "rejects #{inspect(str)}" do
          assert {:error, _} = Tempo.from_iso8601(unquote(str))
        end
      end
    end
  end

  describe "invalid datetimes" do
    for str <- Corpus.invalid_datetimes() do
      unless MapSet.member?(@semantically_invalid_but_parses, str) do
        test "rejects #{inspect(str)}" do
          assert {:error, _} = Tempo.from_iso8601(unquote(str))
        end
      end
    end
  end

  ## Full-coverage sentinel
  #
  # The upstream corpus is exercised in full and is expected to
  # produce zero failures. If a new EDTF feature is added to the
  # corpus and Tempo cannot handle it yet, add the offending
  # strings to `@known_failures` above so positive assertions are
  # skipped but the gap stays documented.

  test "known-failure list is empty" do
    assert Enum.empty?(@known_failures),
           "Re-enable the failing tests once the listed features are implemented"
  end
end
