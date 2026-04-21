defmodule Tempo.Calendar do
  @moduledoc """
  Resolve a BCP 47 / CLDR calendar identifier (as captured by an
  IXDTF `[u-ca=NAME]` suffix) to a concrete `Calendrical.*`
  calendar module.

  Each Calendrical calendar module declares its CLDR identifier
  via `cldr_calendar_type/0`. We build the atom-to-module mapping
  at compile time by asking each known calendar module what CLDR
  name it claims — so the source of truth is the calendar module
  itself, not a hand-maintained table in Tempo.

  Adding support for a new Calendrical calendar is a one-line
  addition to `@candidate_modules` below. The atom it maps to is
  whatever that module returns from `cldr_calendar_type/0`.

  """

  # Calendrical calendar modules recognised by Tempo for IXDTF
  # `[u-ca=NAME]` resolution. Each module's CLDR calendar atom is
  # discovered via `cldr_calendar_type/0`.
  @candidate_modules [
    Calendrical.Gregorian,
    Calendrical.Buddhist,
    Calendrical.Chinese,
    Calendrical.Coptic,
    Calendrical.Ethiopic,
    Calendrical.Ethiopic.AmeteAlem,
    Calendrical.Hebrew,
    Calendrical.Indian,
    Calendrical.Islamic.Observational,
    Calendrical.Islamic.Civil,
    Calendrical.Islamic.Rgsa,
    Calendrical.Islamic.Tbla,
    Calendrical.Islamic.UmmAlQura,
    Calendrical.Japanese,
    Calendrical.Korean,
    Calendrical.Persian,
    Calendrical.Roc
  ]

  @mapping for module <- @candidate_modules,
               Code.ensure_loaded?(module),
               function_exported?(module, :cldr_calendar_type, 0),
               into: %{},
               do: {module.cldr_calendar_type(), module}

  @doc """
  Resolve a BCP 47 calendar atom to its `Calendrical.*` module.

  ### Arguments

  * `name` is a normalised calendar identifier atom (e.g.
    `:hebrew`, `:islamic_umalqura`, `:gregorian`) as produced by
    `Localize.validate_calendar/1`.

  ### Returns

  * `{:ok, module}` where `module` is a loaded `Calendrical.*`
    calendar module implementing the `Calendar` behaviour.

  * `{:error, reason}` when the identifier isn't recognised.

  ### Examples

      iex> Tempo.Calendar.module_from_name(:hebrew)
      {:ok, Calendrical.Hebrew}

      iex> Tempo.Calendar.module_from_name(:islamic_umalqura)
      {:ok, Calendrical.Islamic.UmmAlQura}

      iex> Tempo.Calendar.module_from_name(:gregorian)
      {:ok, Calendrical.Gregorian}

      iex> Tempo.Calendar.module_from_name(:not_a_calendar)
      {:error, "No Calendrical module for calendar identifier :not_a_calendar"}

  """
  @spec module_from_name(atom()) :: {:ok, module()} | {:error, String.t()}
  def module_from_name(name) when is_atom(name) do
    case Map.fetch(@mapping, name) do
      {:ok, module} ->
        {:ok, module}

      :error ->
        {:error, "No Calendrical module for calendar identifier #{inspect(name)}"}
    end
  end

  @doc """
  Return the list of supported CLDR calendar identifier atoms.

  ### Examples

      iex> :hebrew in Tempo.Calendar.supported_names()
      true

      iex> :gregorian in Tempo.Calendar.supported_names()
      true

  """
  @spec supported_names() :: [atom()]
  def supported_names, do: @mapping |> Map.keys() |> Enum.sort()
end
