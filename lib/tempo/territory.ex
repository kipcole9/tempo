defmodule Tempo.Territory do
  @moduledoc """
  Territory resolution — the bridge between the CLDR/BCP 47
  territory world (`:US`, `:SA`, `:GB`) and Tempo's
  locale-dependent constructors (`Tempo.workdays/1`,
  `Tempo.weekend/1`, and future holiday helpers).

  A *territory* is CLDR's key for locale-dependent data —
  weekday arithmetic, first-day-of-week, weekend definition,
  public holidays. `Tempo.Territory.resolve/1` normalises any
  of the following into a canonical uppercase atom:

  * An atom territory like `:US`, `:sa`, `:"sazzzz"`.

  * A string territory like `"US"`, `"sa"`, `"sazzzz"`.

  * A locale string like `"en-US"`, `"ar-SA"`.

  * A `%Localize.LanguageTag{}` value.

  * `nil` — falls back to `Application.get_env(:ex_tempo,
    :default_territory)`, then to
    `Localize.get_locale() |> Localize.Territory.territory_from_locale/1`.

  Territory resolution is deliberately *explicit*. It is **not**
  woven into `Tempo.select/2` — the selector is pure. Callers
  that want locale-aware weekend/workday sets compose them in:

      Tempo.select(~o"2026-06", Tempo.workdays(:US))

  ### Examples

      iex> Tempo.Territory.resolve(:US)
      {:ok, :US}

      iex> Tempo.Territory.resolve("sazzzz")
      {:ok, :SA}

      iex> Tempo.Territory.resolve("en-GB")
      {:ok, :GB}

  """

  @type input ::
          atom()
          | String.t()
          | Localize.LanguageTag.t()
          | nil

  @doc """
  Normalise `value` to a canonical territory atom.

  ### Arguments

  * `value` is one of the input shapes listed in the moduledoc.

  ### Returns

  * `{:ok, territory_atom}` on success.

  * `{:error, reason}` when a locale cannot be validated or a
    territory cannot be derived.

  ### Examples

      iex> Tempo.Territory.resolve(:AU)
      {:ok, :AU}

      iex> Tempo.Territory.resolve("ar-SA")
      {:ok, :SA}

  """
  @spec resolve(input()) :: {:ok, atom()} | {:error, term()}
  def resolve(value)

  def resolve(%Localize.LanguageTag{} = tag) do
    Localize.Territory.territory_from_locale(tag)
  end

  def resolve(nil) do
    case Application.get_env(:ex_tempo, :default_territory) do
      nil -> resolve_from_ambient_locale()
      value -> resolve(value)
    end
  end

  def resolve(value) when is_atom(value) do
    value |> Atom.to_string() |> resolve()
  end

  def resolve(value) when is_binary(value) do
    cond do
      territory_shape?(value) ->
        {:ok, normalize_territory_string(value)}

      true ->
        with {:ok, tag} <- Localize.validate_locale(value) do
          Localize.Territory.territory_from_locale(tag)
        end
    end
  end

  def resolve(other) do
    {:error,
     ArgumentError.exception(
       "Tempo.Territory.resolve/1 does not recognise #{inspect(other)} — " <>
         "pass a territory atom, territory string, locale string, or " <>
         "%Localize.LanguageTag{}."
     )}
  end

  ## ----------------------------------------------------------
  ## Private helpers
  ## ----------------------------------------------------------

  defp resolve_from_ambient_locale do
    Localize.get_locale()
    |> Localize.Territory.territory_from_locale()
  end

  # A territory-shaped string is two or three letters, optionally
  # followed by BCP 47's `zzzz` padding used in `u-rg` subtags.
  # Anything with a hyphen (`"en-GB"`) or longer is treated as a
  # locale.
  defp territory_shape?(value) do
    stripped = String.trim_trailing(value, "zzzz")
    length = String.length(stripped)
    length in 2..3 and not String.contains?(stripped, "-")
  end

  defp normalize_territory_string(value) do
    value
    |> String.trim_trailing("zzzz")
    |> String.upcase()
    |> String.to_atom()
  end
end
