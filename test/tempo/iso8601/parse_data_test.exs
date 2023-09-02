defmodule Tempo.Iso8601.Parser.Data.Test do
  use ExUnit.Case, async: true

  @data "./test/support/data/date_test_values_iso.txt"

  @all_tests @data
  |> File.read!()
  |> String.split("\n")
  |> Enum.with_index()
  |> Enum.reject(&String.starts_with?(elem(&1,0), "#"))

  @time_tests @data
  |> File.read!()
  |> String.split("# Times")
  |> List.last()
  |> String.split("# Date-Times")
  |> List.first()
  |> String.split("\n")
  |> Enum.with_index()
  |> Enum.reject(&String.starts_with?(elem(&1,0), "#"))
  |> Enum.reject(&(elem(&1,0) == ""))

  @time_only_test [126, 136, 146, 159]

  for {test_date, line} <- @all_tests, line not in @time_only_test do
    test "line #{line}: parse #{inspect test_date}" do
      assert {:ok, _} = Tempo.from_iso8601(unquote(test_date))
    end
  end

  for {test_time, line} <- @time_tests do
    test "line #{line}: parse as time #{inspect test_time}" do
      assert {:ok, _, "", _, _, _} = Tempo.Iso8601.Tokenizer.time_parser(unquote(test_time))
    end
  end

end