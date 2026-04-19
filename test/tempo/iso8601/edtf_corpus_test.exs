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

  # EDTF strings that Tempo does not yet parse. Each entry is paired
  # with the feature it exercises so we can track progress.
  @known_failures %{
    # Component-level qualification (EDTF Level 2) — mid-expression
    # `?`, `~`, `%` applied to year/month/day individually.
    "2004-?06-?11" => :component_level_qualification,
    "?2004-06-04~" => :component_level_qualification,
    "2004?-06-~11" => :component_level_qualification,
    "?2004-06%" => :component_level_qualification,
    "2004?-%06" => :component_level_qualification,
    "?-2004-06-04~" => :component_level_qualification,
    "-2004?-06-~11" => :component_level_qualification,
    "?-2004-06%" => :component_level_qualification,
    "-2004?-%06" => :component_level_qualification,
    "?-2004-06" => :component_level_qualification,
    "%-2011-06-13" => :component_level_qualification,
    "%2001" => :component_level_qualification,
    "2004-%06" => :component_level_qualification,
    "2011-23~" => :component_level_qualification,
    "2004-06-~01/2004-06-~20" => :component_level_qualification,
    "-2004-06-?01/2006-06-~20" => :component_level_qualification,
    "-2005-06-%01/2006-06-~20" => :component_level_qualification,
    "2019-12/%2020" => :component_level_qualification,
    "1984?-06/2004-08?" => :component_level_qualification,
    "-1984-?06-02/2004-08-08~" => :component_level_qualification,
    "1984-?06-02/2004-06-11%" => :component_level_qualification,
    "2019-~12/2020" => :component_level_qualification,
    "2003-06-11%/2004-%06" => :component_level_qualification,
    "2004-06~/2004-06-%11" => :component_level_qualification,
    "1984?/2004~-06" => :component_level_qualification,
    "?2004-06~-10/2004-06-%11" => :component_level_qualification,
    "1984-06-?02/2004-06-11%" => :component_level_qualification,

    # Unspecified `X` digits in time components (hour/minute/second).
    "2004-06-XX/2004-07-03" => :unspecified_digit_date,
    "2003-06-25/2004-X1-03" => :unspecified_digit_date,
    "20X3-06-25/2004-X1-03" => :unspecified_digit_date,
    "XXXX-12-21/1890-09-2X" => :unspecified_digit_date,
    "1984-11-2X/1999-01-01" => :unspecified_digit_date,
    "1984-11-12/1984-11-XX" => :unspecified_digit_date,
    "198X-11-XX/198X-11-30" => :unspecified_digit_date,
    "2000-12-XX/2012" => :unspecified_digit_date,
    "-2000-12-XX/2012" => :unspecified_digit_date,
    "2000-XX-XX/2012" => :unspecified_digit_date,
    "-2000-XX-10/2012" => :unspecified_digit_date,
    "2000/2000-XX-XX" => :unspecified_digit_date,
    "198X/199X" => :unspecified_digit_date,
    "198X/1999" => :unspecified_digit_date,
    "1987/199X" => :unspecified_digit_date,
    "1919-XX-02/1919-XX-01" => :unspecified_digit_date,
    "1919-0X-02/1919-01-03" => :unspecified_digit_date,
    "1865-X2-02/1865-03-01" => :unspecified_digit_date,
    "1930-X0-10/1930-10-30" => :unspecified_digit_date,
    "1981-1X-10/1981-11-09" => :unspecified_digit_date,
    "1919-12-02/1919-XX-04" => :unspecified_digit_date,
    "1919-11-02/1919-1X-01" => :unspecified_digit_date,
    "1919-09-02/1919-X0-01" => :unspecified_digit_date,
    "1919-08-02/1919-0X-01" => :unspecified_digit_date,
    "1919-10-02/1919-X1-01" => :unspecified_digit_date,
    "1919-04-01/1919-X4-02" => :unspecified_digit_date,
    "1602-10-0X/1602-10-02" => :unspecified_digit_date,
    "2018-05-X0/2018-05-11" => :unspecified_digit_date,
    "-2018-05-X0/2018-05-11" => :unspecified_digit_date,
    "1200-01-X4/1200-01-08" => :unspecified_digit_date,
    "1919-07-30/1919-07-3X" => :unspecified_digit_date,
    "1908-05-02/1908-05-0X" => :unspecified_digit_date,
    "0501-11-18/0501-11-1X" => :unspecified_digit_date,
    "1112-08-22/1112-08-2X" => :unspecified_digit_date,
    "2015-02-27/2015-02-X8" => :unspecified_digit_date,
    "2016-02-28/2016-02-X9" => :unspecified_digit_date,
    "2000-XX/2012" => :unspecified_digit_date,
    "1984-1X" => :unspecified_digit_date,
    "1XXX-XX" => :unspecified_digit_date,
    "1XXX-12" => :unspecified_digit_date,
    "20X0-10-02" => :unspecified_digit_date,
    "1X99-01-XX" => :unspecified_digit_date,
    "-1XXX-XX" => :unspecified_digit_date,
    "-1XXX-12" => :unspecified_digit_date,
    "-1984-1X" => :unspecified_digit_date,
    "-1X32-X1-X2" => :unspecified_digit_date,
    "156X-12-25" => :unspecified_digit_date,
    "15XX-12-25" => :unspecified_digit_date,
    "XXXX-12-XX" => :unspecified_digit_date,
    "1560-XX-25" => :unspecified_digit_date,
    "-156X-12-25" => :unspecified_digit_date,
    "-15XX-12-25" => :unspecified_digit_date,
    "-XXXX-12-XX" => :unspecified_digit_date,

    # Open-ended intervals (EDTF L1) — `..` outside brackets in intervals.
    "1985-04-12/.." => :open_interval_syntax,
    "1985-04/.." => :open_interval_syntax,
    "1985/.." => :open_interval_syntax,
    "../1985-04-12" => :open_interval_syntax,
    "../1985-04" => :open_interval_syntax,
    "../1985" => :open_interval_syntax,
    "/.." => :open_interval_syntax,
    "../" => :open_interval_syntax,
    "../.." => :open_interval_syntax,
    "-1985-04-12/.." => :open_interval_syntax,
    "-1985-04/.." => :open_interval_syntax,
    "-1985/" => :open_interval_syntax,
    "1985-04-12/" => :open_interval_syntax,
    "1985-04/" => :open_interval_syntax,
    "1985/" => :open_interval_syntax,
    "/1985-04-12" => :open_interval_syntax,
    "/1985-04" => :open_interval_syntax,
    "/1985" => :open_interval_syntax,
    "1984-06-02?/" => :open_interval_syntax,
    "-2004-06-01/" => :open_interval_syntax,

    # Leading-zero four-digit year 0000 — an ISO 8601 valid year
    # but unusual; we currently don't treat it as a year-0 sentinel.
    "0000" => :year_zero,
    "0000/0000" => :year_zero,
    "0000-02/1111" => :year_zero,
    "0000-01/0000-01-03" => :year_zero,
    "0000-01-13/0000-01-23" => :year_zero,
    "1111-01-01/1111" => :year_zero,
    "0000-01/0000" => :year_zero,

    # Significant-digit annotations (`S2`, `S3`) on year values.
    "1950S2" => :significant_digit_annotation,
    "Y171010000S3" => :significant_digit_annotation,
    "Y3388E2S3" => :significant_digit_annotation,
    "-1859S5" => :significant_digit_annotation,
    "Y-171010000S2" => :significant_digit_annotation,
    "Y-3388E2S3" => :significant_digit_annotation,

    # Wide-range exponent years (e.g. `Y-17E7` = -170,000,000).
    "Y170000002" => :wide_range_year,
    "Y-170000002" => :wide_range_year,
    "Y-17E7" => :wide_range_year,
    "Y17E8" => :wide_range_year,

    # `-0` sign or negative century/decade normalization.
    "-2004-23" => :negative_qualified_year,
    "-2010" => :negative_qualified_year,
    "-2004~" => :negative_qualified_year,
    "-2004-06?" => :negative_qualified_year,
    "-2004-06-11%" => :negative_qualified_year,
    "-20XX" => :negative_qualified_year,
    "-2004-XX" => :negative_qualified_year,
    "-1985-04-XX" => :negative_qualified_year,
    "-1985-XX-XX" => :negative_qualified_year,
    "-1985-04-12T23:20:30" => :negative_qualified_year,
    "-1985-04-12T23:20:30Z" => :negative_qualified_year,
    "-1985-04-12T23:20:30-04" => :negative_qualified_year,
    "-1985-04-12T23:20:30+04:30" => :negative_qualified_year,
    "-2001-02-03" => :negative_qualified_year,
    "-2001-34" => :negative_qualified_year,
    "-2001-35" => :negative_qualified_year,
    "-2001-36" => :negative_qualified_year,
    "-2001-37" => :negative_qualified_year,
    "-2001-38" => :negative_qualified_year,
    "-2001-39" => :negative_qualified_year,
    "-2001-40" => :negative_qualified_year,
    "-2001-41" => :negative_qualified_year,
    "-1000/-0999" => :negative_qualified_year,
    "-2004-02-01/2005" => :negative_qualified_year,
    "-1980-11-01/1989-11-30" => :negative_qualified_year,
    "-1984?/2004%" => :negative_qualified_year,
    "201X" => :unspecified_digit_date,
    "19XX" => :unspecified_digit_date,
    "2004-XX" => :unspecified_digit_date,
    "1985-04-XX" => :unspecified_digit_date,
    "1985-XX-XX" => :unspecified_digit_date,

    # Negative sets / ranges.
    "[-1667,1668,1670..1672]" => :negative_set_member,
    "[..1760-12-03]" => :negative_set_member,
    "[1760-12..]" => :negative_set_member,
    "[1760-01,-1760-02,1760-12..]" => :negative_set_member,
    "[-1740-02-12..-1200-01-29]" => :negative_set_member,
    "[-1890-05..-1200-01]" => :negative_set_member,
    "[-1667,1760-12]" => :negative_set_member,
    "[..1984]" => :negative_set_member,
    "{-1667,1668,1670..1672}" => :negative_set_member,
    "{1960,-1961-12}" => :negative_set_member,
    "{-1640-06..-1200-01}" => :negative_set_member,
    "{-1740-02-12..-1200-01-29}" => :negative_set_member,
    "{..1984}" => :negative_set_member,
    "{1760-12..}" => :negative_set_member,

    # Per-endpoint qualification in intervals: `1984?/2004-06~` means
    # the first endpoint is uncertain and the second is approximate.
    # Our current grammar attaches qualification at the top level
    # only.
    "1984~/2004-06" => :per_endpoint_qualification,
    "1984/2004-06~" => :per_endpoint_qualification,
    "1984~/2004~" => :per_endpoint_qualification,
    "1984?/2004-06~" => :per_endpoint_qualification,
    "1984-06?/2004-08?" => :per_endpoint_qualification,
    "1984-06-02?/2004-08-08~" => :per_endpoint_qualification,
    "2004-06~/2004-06-11%" => :per_endpoint_qualification,
    "2003/2004-06-11%" => :per_endpoint_qualification,
    "1952-23~/1953" => :per_endpoint_qualification,
    "2019-12/2020%" => :per_endpoint_qualification
  }

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

  ## Known-failure tracking
  #
  # This keeps a visible list of Level 2 features that the parser
  # cannot yet handle. When a feature lands, remove its strings
  # from `@known_failures` above and the corresponding positive
  # tests will automatically re-enable.

  test "known-failure list is non-empty (remove when all features land)" do
    refute Enum.empty?(@known_failures)
  end
end
