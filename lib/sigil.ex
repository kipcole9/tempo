defmodule Tempo.Sigils do
  @moduledoc """
  Sigils for constructing `%Tempo{}` values at compile time.

  Provides `~o` (and its verbose alias `~TEMPO`) to turn an ISO 8601
  / ISO 8601-2 / IXDTF / EDTF string into a `%Tempo{}`, `%Tempo.Interval{}`,
  `%Tempo.Duration{}`, or `%Tempo.Set{}` struct.

  ```elixir
  import Tempo.Sigils

  ~o"2026-06-15"            #=> %Tempo{…}
  ~o"2026-06-15T10:30:00Z"  #=> zoned datetime
  ~o"1984?/2004~"           #=> qualified interval
  ~o"2026Y"w                #=> ISO week calendar (w modifier)
  ```

  ### Why a module just for sigils

  The module exposes **only** the sigil macros so `import Tempo.Sigils`
  in application code adds exactly `sigil_o/2` and `sigil_TEMPO/2` to
  the caller's scope — no helper functions leak into the caller's
  namespace. Helpers used by the sigils at expansion time live in
  `Tempo.Sigils.Options`; they are implementation details.

  ### Modifiers

  * No modifier — Gregorian calendar (the common case).

  * `w` — ISO Week calendar (`Calendrical.ISOWeek`). Use when the
    input is in a week-based form you want parsed under ISO week
    semantics explicitly.

  """

  alias Tempo.Sigils.Options

  @doc """
  Parse an ISO 8601 / EDTF / IXDTF string at compile time.

  The value is fully resolved to its `%Tempo{}` / `%Tempo.Interval{}` /
  `%Tempo.Duration{}` / `%Tempo.Set{}` form by the parser and escaped
  as a compile-time literal, so there is no runtime parse cost at the
  call site.

  """
  defmacro sigil_o({:<<>>, _meta, [string]}, opts) do
    calendar = Options.calendar_from(opts)

    case Tempo.from_iso8601(string, calendar) do
      {:ok, tempo} -> Macro.escape(tempo)
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Verbose alias for `sigil_o`. Use when `~o` might be confused with
  another sigil in scope, or when you want the three-letter form
  for readability in dense code.
  """
  defmacro sigil_TEMPO({:<<>>, _meta, [string]}, opts) do
    calendar = Options.calendar_from(opts)

    case Tempo.from_iso8601(string, calendar) do
      {:ok, tempo} -> Macro.escape(tempo)
      {:error, exception} -> raise exception
    end
  end
end

defmodule Tempo.Sigil do
  @moduledoc """
  Deprecated — use `Tempo.Sigils` (plural).

  The pluralised module exposes only the sigil macros, so
  `import Tempo.Sigils` leaves the caller's namespace free of helper
  functions. Old `Tempo.Sigil` is kept as a thin compatibility shim
  that re-exports the macros. It will be removed in a future major
  version.

  """

  # Re-export the macros so existing `import Tempo.Sigil` call sites
  # continue to work during the deprecation window.
  defmacro sigil_o(string, opts),
    do: quote(do: Tempo.Sigils.sigil_o(unquote(string), unquote(opts)))

  defmacro sigil_TEMPO(string, opts),
    do: quote(do: Tempo.Sigils.sigil_TEMPO(unquote(string), unquote(opts)))
end

defmodule Tempo.Sigils.Options do
  @moduledoc false

  # Maps the sigil modifier character list to a calendar module.
  # Kept out of `Tempo.Sigils` so `import Tempo.Sigils` does not
  # bring `calendar_from/1` into the caller's scope.

  def calendar_from([?W]), do: Calendrical.ISOWeek
  def calendar_from([]), do: Calendrical.Gregorian
end
