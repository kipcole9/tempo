defmodule Tempo.Duration do
  @moduledoc """
  A calendar-relative duration — a list of `{unit, amount}`
  pairs such as `[year: 1, month: 6]`. Produced by the ISO 8601
  parser (`P1Y6M`), the RRULE encoder (as the `FREQ + INTERVAL`
  cadence), and arithmetic helpers in `Tempo.Math`.
  """

  @type unit ::
          :year
          | :month
          | :week
          | :day
          | :hour
          | :minute
          | :second
          | :day_of_year
          | :day_of_week

  @type t :: %__MODULE__{
          time: [{unit(), integer()}]
        }

  defstruct [:time]

  @valid_units [:year, :month, :week, :day, :hour, :minute, :second, :day_of_year, :day_of_week]
  @canonical_unit_order [
    :year,
    :month,
    :week,
    :day,
    :day_of_year,
    :day_of_week,
    :hour,
    :minute,
    :second
  ]

  @doc """
  Construct a `t:Tempo.Duration.t/0` from a keyword list of
  `{unit, amount}` pairs.

  Components can be passed in any order; `new/1` reorders them
  coarse-to-fine before building the struct.

  ### Arguments

  * `components` is a keyword list of duration units.

  ### Options

  Every value must be an integer. Negative values are permitted
  (reverse-direction duration).

  * `:year` is the year count.

  * `:month` is the month count.

  * `:week` is the week count.

  * `:day` is the day count.

  * `:day_of_year` is a day-of-year offset (used by RRULE expansion).

  * `:day_of_week` is a day-of-week offset (used by RRULE expansion).

  * `:hour` is the hour count.

  * `:minute` is the minute count.

  * `:second` is the second count.

  ### Returns

  * `{:ok, t()}` on success.

  * `{:error, reason}` when a key is unknown or a value is not an
    integer.

  ### Examples

      iex> {:ok, d} = Tempo.Duration.new(year: 1, month: 6)
      iex> d.time
      [year: 1, month: 6]

      iex> {:ok, d} = Tempo.Duration.new(month: 6, year: 1)
      iex> d.time
      [year: 1, month: 6]

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(components) when is_list(components) do
    with :ok <- ensure_keyword(components),
         :ok <- validate_components(components) do
      ordered =
        Enum.sort_by(components, fn {unit, _v} ->
          Enum.find_index(@canonical_unit_order, &(&1 == unit))
        end)

      {:ok, %__MODULE__{time: ordered}}
    end
  end

  @doc """
  Bang variant of `new/1`.
  """
  @spec new!(keyword()) :: t()
  def new!(components) when is_list(components) do
    case new(components) do
      {:ok, d} -> d
      {:error, exception} when is_exception(exception) -> raise exception
      {:error, reason} -> raise ArgumentError, "Tempo.Duration.new!/1 failed: #{inspect(reason)}"
    end
  end

  @doc false
  # Internal constructor — accepts token-shaped input from the
  # parser without validation. Use `new/1` for developer-facing
  # construction.
  def build(tokens) do
    %__MODULE__{time: tokens}
  end

  defp ensure_keyword(components) do
    if Keyword.keyword?(components) do
      :ok
    else
      {:error,
       ArgumentError.exception(
         "Tempo.Duration.new/1 expects a keyword list. Got: #{inspect(components)}"
       )}
    end
  end

  defp validate_components([]) do
    {:error, ArgumentError.exception("Tempo.Duration.new/1 requires at least one component.")}
  end

  defp validate_components(components) do
    Enum.reduce_while(components, :ok, fn {unit, value}, :ok ->
      cond do
        unit not in @valid_units ->
          {:halt,
           {:error,
            ArgumentError.exception(
              "Tempo.Duration.new/1 does not recognise component #{inspect(unit)}. " <>
                "Valid components: #{inspect(@valid_units)}"
            )}}

        not is_integer(value) ->
          {:halt,
           {:error,
            ArgumentError.exception(
              "Tempo.Duration component #{inspect(unit)} must be an integer, got #{inspect(value)}"
            )}}

        true ->
          {:cont, :ok}
      end
    end)
  end
end
