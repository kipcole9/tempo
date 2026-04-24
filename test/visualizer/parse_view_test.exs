defmodule Tempo.Visualizer.ParseViewTest do
  @moduledoc """
  The annotated-segments grid must reproduce the input string
  character-for-character — no canonicalisation, no hyphen-vs-
  designator rewrite. These tests exercise every example the
  visualizer advertises plus the formats most likely to round-
  trip through unusual glyph shapes.
  """

  use ExUnit.Case, async: true

  # Only meaningful when Plug + Bandit are available — the
  # ParseView module is only compiled in that configuration.
  @moduletag skip: not Code.ensure_loaded?(Tempo.Visualizer.ParseView)

  @inputs [
    # Dates and datetimes
    "2022-06-15",
    "2022-W24-3",
    "2022-166",
    "2022-06-15T10:30:00Z",
    "2022-06-15T10:30:00+05:30",
    # Intervals / recurrence
    "2022-01-01/2022-06-30",
    "2022-01-01/P3M",
    "R5/2022-01-01/P1M",
    "1984?/2004~",
    # Alternate Tempo glyph forms that parse to the same AST as
    # above — these are the cases the old renderer lost because it
    # rebuilt from the AST.
    "2022Y11M20D",
    "2022Y6M",
    "2022Y1Q",
    # Seasons
    "2022-25",
    "2022-29"
  ]

  describe "annotated segments reproduce the input" do
    for input <- @inputs do
      @tag input: input
      test "input #{inspect(input)} renders segments whose glyphs rejoin to the input",
           %{input: input} do
        html = Tempo.Visualizer.ParseView.render(%{input: input}, "")
        segments_html = IO.iodata_to_binary(html)

        # Extract every `<div class="vz-glyph">…</div>` body,
        # strip nested spans, and rejoin. Together they must equal
        # the raw input.
        rejoined =
          Regex.scan(~r{<div class="vz-glyph">(.*?)</div>}s, segments_html)
          |> Enum.map(fn [_, inner] -> strip_html_tags(inner) end)
          |> Enum.join("")
          |> unescape_entities()

        assert rejoined == input,
               "Expected segments to rejoin to #{inspect(input)}, got #{inspect(rejoined)}"
      end
    end
  end

  defp strip_html_tags(html) do
    Regex.replace(~r{<[^>]+>}, html, "")
  end

  defp unescape_entities(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
  end
end
