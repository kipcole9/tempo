defmodule Tempo.Visualizer.Render do
  @moduledoc false

  # Shared HTML helpers. Pure functions, no templates, iodata in /
  # iodata out. All literal markup is written as double-quoted
  # strings so it's immune to Elixir's sigil-vs-keyword edge cases.

  @doc "HTML-escapes a binary or iodata."
  @spec escape(iodata()) :: iodata()
  def escape(iodata) when is_list(iodata), do: Enum.map(iodata, &escape/1)

  def escape(binary) when is_binary(binary) do
    binary
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  def escape(other), do: escape(to_string(other))

  @doc """
  Wraps the supplied body iodata in the full HTML page chrome.

  ### Options

  * `:title` — page title (required).

  * `:body` — iodata for the page body (required).

  * `:base` — base URL prefix (e.g. `""` or `"/visualize"`) used to
    resolve asset and form links (required).

  * `:input` — the current ISO 8601 input string for the top form
    (defaults to `""`).

  """
  def page(assigns) do
    title = Keyword.fetch!(assigns, :title)
    body = Keyword.fetch!(assigns, :body)
    base = Keyword.fetch!(assigns, :base)
    input = Keyword.get(assigns, :input, "")

    [
      "<!doctype html><html lang=\"en\"><head>",
      "<meta charset=\"utf-8\">",
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
      "<title>",
      escape(title),
      " — Tempo ISO 8601 Visualizer</title>",
      "<link rel=\"stylesheet\" href=\"",
      escape(base),
      "/assets/style.css\">",
      "</head><body>",
      header(base, input),
      "<main class=\"vz-main\">",
      body,
      footer(),
      "</main></body></html>"
    ]
  end

  defp header(base, input) do
    [
      "<header class=\"vz-header\">",
      "<a class=\"vz-brand\" href=\"",
      escape(base),
      "/\">",
      logo_svg(),
      "<h1>Tempo</h1>",
      "<span class=\"vz-subtitle\">ISO 8601 Visualizer</span>",
      "</a>",
      "<form class=\"vz-form\" method=\"get\" action=\"",
      escape(base),
      "/\">",
      "<label class=\"vz-input-label\" for=\"vz-iso-input\">",
      "Enter an ISO 8601 or EDTF string",
      "</label>",
      "<input id=\"vz-iso-input\" class=\"vz-input\" type=\"text\" name=\"iso\" ",
      "value=\"",
      escape(input),
      "\" placeholder=\"2022-06-15 or 1984?/2004~ or 2022-11-20T10:30:00Z[Europe/Paris]\" ",
      "autocomplete=\"off\" spellcheck=\"false\" autofocus>",
      "<button type=\"submit\">Parse</button>",
      "</form>",
      "</header>"
    ]
  end

  defp footer do
    [
      "<div class=\"vz-footer\">",
      "Powered by ",
      "<a href=\"https://hexdocs.pm/tempo\">Tempo</a>",
      " — ISO 8601 Parts 1 &amp; 2 and ",
      "<a href=\"https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html\">IXDTF</a>",
      "</div>"
    ]
  end

  # Inlined Tempo mark. `currentColor` lets it inherit the brand
  # anchor's colour so it matches the wordmark without a separate
  # asset round-trip.
  defp logo_svg do
    """
    <svg class="vz-logo" viewBox="0 0 256 256" aria-hidden="true"
         fill="none" stroke="currentColor" stroke-width="24"
         stroke-linecap="round" stroke-linejoin="round">
      <path d="M 88 56 H 56 V 200 H 88"/>
      <circle cx="128" cy="128" r="18" fill="currentColor" stroke="none"/>
      <path d="M 168 56 Q 212 128 168 200"/>
    </svg>
    """
  end
end
