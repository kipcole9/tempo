defmodule Tempo.Iso8601.UnspecifiedDigit.Test do
  use ExUnit.Case, async: true

  # Unspecified digits (`X`) in date components are a core ISO 8601-2
  # / EDTF feature. Archaeologists and historians routinely write
  # `156X` ("sometime in the 1560s"), `1XXX` ("the first millennium"),
  # or `1985-XX-XX` ("sometime in 1985") when full precision isn't
  # available.

  describe "positive years" do
    test "one unspecified digit (`156X`)" do
      assert {:ok, _} = Tempo.from_iso8601("156X")
    end

    test "two unspecified digits (`15XX`)" do
      assert {:ok, _} = Tempo.from_iso8601("15XX")
    end

    test "three unspecified digits (`1XXX`)" do
      assert {:ok, _} = Tempo.from_iso8601("1XXX")
    end

    test "all four digits unspecified (`XXXX`)" do
      assert {:ok, _} = Tempo.from_iso8601("XXXX")
    end

    test "internal unspecified (`1X99`)" do
      assert {:ok, _} = Tempo.from_iso8601("1X99")
    end
  end

  describe "negative years" do
    # Negative years with unspecified digits used to crash the parser.
    # Fixed by adding a `form_number` clause that tags the mask with
    # a leading `:negative` sentinel.

    test "negative year with trailing unspecified" do
      assert {:ok, _} = Tempo.from_iso8601("-156X")
    end

    test "negative fully-unspecified year" do
      assert {:ok, _} = Tempo.from_iso8601("-XXXX")
    end

    test "negative year with unspecified month-day" do
      assert {:ok, _} = Tempo.from_iso8601("-1XXX-XX")
    end

    test "negative year with all-unspecified month-day" do
      assert {:ok, _} = Tempo.from_iso8601("-XXXX-12-XX")
    end

    test "negative year, month and day all with unspecified digits" do
      assert {:ok, _} = Tempo.from_iso8601("-1X32-X1-X2")
    end
  end

  describe "month and day" do
    test "unspecified month (`2022-XX`)" do
      assert {:ok, _} = Tempo.from_iso8601("2022-XX")
    end

    test "unspecified day (`2022-06-XX`)" do
      assert {:ok, _} = Tempo.from_iso8601("2022-06-XX")
    end

    test "partial month digit (`2022-1X`)" do
      assert {:ok, _} = Tempo.from_iso8601("2022-1X")
    end

    test "everything unspecified below year (`2022-XX-XX`)" do
      assert {:ok, _} = Tempo.from_iso8601("2022-XX-XX")
    end
  end

  describe "intervals with unspecified digits" do
    test "both endpoints partially unspecified" do
      assert {:ok, %Tempo.Interval{}} = Tempo.from_iso8601("198X/199X")
    end

    test "one endpoint fully unspecified" do
      assert {:ok, %Tempo.Interval{}} = Tempo.from_iso8601("2000-XX-XX/2012")
    end

    test "negative endpoint with unspecified" do
      assert {:ok, %Tempo.Interval{}} = Tempo.from_iso8601("-2000-XX-10/2012")
    end
  end

  describe "roundtrip via sigil" do
    # The inspect protocol formats masks back to their EDTF syntax,
    # preserving the leading `-` for negative years.
    test "negative year with unspecified roundtrips" do
      {:ok, tempo} = Tempo.from_iso8601("-1XXX-XX")
      assert inspect(tempo) =~ "-1XXX"
    end
  end
end
