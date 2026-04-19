defmodule Tempo.RRule do
  @moduledoc """
  Parses [iCalendar RFC 5545](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10)
  `RRULE` strings into Tempo AST (`%Tempo.Interval{}` with a
  `%Tempo.Duration{}` cadence and, where needed, a `repeat_rule`
  built from selection tokens).

  This module is intentionally small — it exists to validate that
  Tempo's AST is a sufficient target for recurrence rules expressed
  in formats other than ISO 8601-2. See
  `docs/rrule-ast-validation.md` for findings.

  ## Supported rule parts

  * `FREQ` — `SECONDLY` | `MINUTELY` | `HOURLY` | `DAILY` | `WEEKLY`
    | `MONTHLY` | `YEARLY`

  * `INTERVAL` — positive integer, default `1`

  * `COUNT` — positive integer (mutually exclusive with `UNTIL`)

  * `UNTIL` — basic-format ISO 8601 date or date-time

  * `BYMONTH`, `BYMONTHDAY`, `BYYEARDAY`, `BYWEEKNO`, `BYHOUR`,
    `BYMINUTE`, `BYSECOND` — comma-separated (optionally negative)
    integer list

  * `BYDAY` — comma-separated list where each entry is
    `[<sign><ordinal>]<weekday>` (e.g. `MO`, `-1FR`, `4TH`)

  * `BYSETPOS` — comma-separated integer list

  * `WKST` — weekday code

  ## Returns

  `{:ok, %Tempo.Interval{}}` on success.

  ## Examples

      iex> {:ok, %Tempo.Interval{} = i} = Tempo.RRule.parse("FREQ=DAILY;COUNT=10")
      iex> {i.recurrence, i.duration.time}
      {10, [day: 1]}

      iex> {:ok, i} = Tempo.RRule.parse("FREQ=WEEKLY;INTERVAL=2;UNTIL=20221231")
      iex> i.duration.time
      [week: 2]

  """

  @weekdays %{
    "MO" => 1,
    "TU" => 2,
    "WE" => 3,
    "TH" => 4,
    "FR" => 5,
    "SA" => 6,
    "SU" => 7
  }

  @freq_to_unit %{
    "SECONDLY" => :second,
    "MINUTELY" => :minute,
    "HOURLY" => :hour,
    "DAILY" => :day,
    "WEEKLY" => :week,
    "MONTHLY" => :month,
    "YEARLY" => :year
  }

  @doc """
  Parse an RRULE string into a `%Tempo.Interval{}` AST node.

  ### Arguments

  * `rrule` is a string in RRULE form (with or without the
    leading `RRULE:` prefix).

  ### Options

  * `:from` — a `%Tempo{}` anchor (DTSTART). Sets `Interval.from`
    so occurrence enumeration has a starting point. Optional;
    callers that intend to enumerate must supply this.

  ### Returns

  * `{:ok, %Tempo.Interval{}}` on success.

  * `{:error, reason}` on a malformed rule or unknown keyword.

  ### Examples

      iex> {:ok, i} = Tempo.RRule.parse("FREQ=DAILY;COUNT=10")
      iex> i.recurrence
      10

      iex> {:error, _} = Tempo.RRule.parse("FREQ=NOPE")

  """
  @spec parse(binary(), keyword()) :: {:ok, Tempo.Interval.t()} | {:error, term()}
  def parse(rrule, options \\ [])

  def parse("RRULE:" <> rest, options), do: parse(rest, options)

  def parse(rrule, options) when is_binary(rrule) do
    with {:ok, parts} <- parse_parts(rrule),
         {:ok, interval} <- build_interval(parts, options) do
      {:ok, interval}
    end
  end

  @doc """
  Bang variant of `parse/2`.
  """
  @spec parse!(binary(), keyword()) :: Tempo.Interval.t()
  def parse!(rrule, options \\ []) do
    case parse(rrule, options) do
      {:ok, interval} -> interval
      {:error, reason} -> raise ArgumentError, "Invalid RRULE: #{inspect(reason)}"
    end
  end

  ## Parsing: text → intermediate keyword list

  defp parse_parts(rrule) do
    rrule
    |> String.trim()
    |> String.split(";", trim: true)
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case parse_part(part) do
        {:ok, tuple} -> {:cont, {:ok, [tuple | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp parse_part(part) do
    case String.split(part, "=", parts: 2) do
      [key, value] -> parse_kv(String.upcase(key), value)
      _ -> {:error, {:malformed_part, part}}
    end
  end

  defp parse_kv("FREQ", value) do
    case Map.get(@freq_to_unit, String.upcase(value)) do
      nil -> {:error, {:unknown_freq, value}}
      unit -> {:ok, {:freq, unit}}
    end
  end

  defp parse_kv("INTERVAL", value), do: with_int(value, :interval)
  defp parse_kv("COUNT", value), do: with_int(value, :count)
  defp parse_kv("UNTIL", value), do: parse_until(value)

  defp parse_kv("BYMONTH", value), do: with_int_list(value, :bymonth)
  defp parse_kv("BYMONTHDAY", value), do: with_int_list(value, :bymonthday)
  defp parse_kv("BYYEARDAY", value), do: with_int_list(value, :byyearday)
  defp parse_kv("BYWEEKNO", value), do: with_int_list(value, :byweekno)
  defp parse_kv("BYHOUR", value), do: with_int_list(value, :byhour)
  defp parse_kv("BYMINUTE", value), do: with_int_list(value, :byminute)
  defp parse_kv("BYSECOND", value), do: with_int_list(value, :bysecond)
  defp parse_kv("BYSETPOS", value), do: with_int_list(value, :bysetpos)

  defp parse_kv("BYDAY", value) do
    parts =
      value
      |> String.split(",", trim: true)
      |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
        case parse_byday_entry(entry) do
          {:ok, tuple} -> {:cont, {:ok, [tuple | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case parts do
      {:ok, list} -> {:ok, {:byday, Enum.reverse(list)}}
      error -> error
    end
  end

  defp parse_kv("WKST", value) do
    case Map.get(@weekdays, String.upcase(value)) do
      nil -> {:error, {:unknown_wkst, value}}
      day -> {:ok, {:wkst, day}}
    end
  end

  defp parse_kv(key, _value), do: {:error, {:unknown_rule_part, key}}

  defp parse_byday_entry(entry) do
    with {ordinal, weekday} <- split_byday(entry),
         {:ok, day} <- lookup_weekday(weekday) do
      {:ok, {ordinal, day}}
    else
      :error -> {:error, {:invalid_byday, entry}}
    end
  end

  # Split "-1FR" into {-1, "FR"}, "MO" into {nil, "MO"}.
  defp split_byday(entry) do
    case Regex.run(~r/^(-?\d+)?([A-Za-z]{2})$/, entry) do
      [_, "", day] -> {nil, day}
      [_, ord, day] -> {String.to_integer(ord), day}
      _ -> :error
    end
  end

  defp lookup_weekday(code) do
    case Map.get(@weekdays, String.upcase(code)) do
      nil -> :error
      day -> {:ok, day}
    end
  end

  defp with_int(value, key) do
    case Integer.parse(value) do
      {n, ""} -> {:ok, {key, n}}
      _ -> {:error, {:invalid_integer, value, key}}
    end
  end

  defp with_int_list(value, key) do
    parsed =
      value
      |> String.split(",", trim: true)
      |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
        case Integer.parse(item) do
          {n, ""} -> {:cont, {:ok, [n | acc]}}
          _ -> {:halt, {:error, {:invalid_integer_in_list, item, key}}}
        end
      end)

    case parsed do
      {:ok, list} -> {:ok, {key, Enum.reverse(list)}}
      error -> error
    end
  end

  # UNTIL is basic-format ISO 8601: YYYYMMDD or YYYYMMDDTHHMMSSZ.
  # We round-trip it through `Tempo.from_iso8601/1` to get a proper
  # `%Tempo{}` struct.
  defp parse_until(value) do
    case Tempo.from_iso8601(value) do
      {:ok, tempo} -> {:ok, {:until, tempo}}
      {:error, reason} -> {:error, {:invalid_until, value, reason}}
    end
  end

  ## Building: intermediate list → %Tempo.Interval{}

  defp build_interval(parts, options) do
    case Keyword.fetch(parts, :freq) do
      {:ok, freq_unit} ->
        {:ok, do_build(freq_unit, parts, options)}

      :error ->
        {:error, :missing_freq}
    end
  end

  defp do_build(freq_unit, parts, options) do
    interval = Keyword.get(parts, :interval, 1)
    count = Keyword.get(parts, :count)
    until = Keyword.get(parts, :until)
    from = Keyword.get(options, :from)

    duration = %Tempo.Duration{time: [{freq_unit, interval}]}

    recurrence =
      cond do
        is_integer(count) -> count
        true -> :infinity
      end

    repeat_rule = build_repeat_rule(parts)

    %Tempo.Interval{
      from: from,
      to: until,
      duration: duration,
      recurrence: recurrence,
      repeat_rule: repeat_rule
    }
  end

  # A `repeat_rule` is a `%Tempo{}` whose `:time` keyword list holds
  # the selection tokens — matching the AST produced by the
  # ISO 8601-2 `L…N` selection grammar.
  #
  # When no BY* rules are present the repeat_rule is nil.
  defp build_repeat_rule(parts) do
    by_rules =
      []
      |> push_by(parts, :bymonth, :month)
      |> push_by(parts, :bymonthday, :day)
      |> push_by(parts, :byyearday, :day_of_year)
      |> push_by(parts, :byweekno, :week)
      |> push_by(parts, :byhour, :hour)
      |> push_by(parts, :byminute, :minute)
      |> push_by(parts, :bysecond, :second)
      |> push_by(parts, :bysetpos, :instance)
      |> push_byday(parts)

    case by_rules do
      [] ->
        nil

      rules ->
        %Tempo{
          time: [selection: Enum.reverse(rules)],
          calendar: Calendrical.Gregorian
        }
    end
  end

  defp push_by(acc, parts, rrule_key, unit) do
    case Keyword.get(parts, rrule_key) do
      nil -> acc
      [single] -> [{unit, single} | acc]
      list when is_list(list) -> [{unit, list} | acc]
    end
  end

  # BYDAY = list of {ordinal_or_nil, day_of_week_1_to_7}.
  # When every entry has a nil ordinal, it's just a day-of-week
  # filter. When any entry has an ordinal, we emit a paired
  # `day_of_week` + `instance` selector (Tempo's existing
  # selection-instance form).
  defp push_byday(acc, parts) do
    case Keyword.get(parts, :byday) do
      nil ->
        acc

      entries ->
        {ordinals, days} =
          Enum.reduce(entries, {[], []}, fn {ord, day}, {os, ds} ->
            {if(ord, do: [ord | os], else: os), [day | ds]}
          end)

        days = Enum.reverse(days)
        ordinals = Enum.reverse(ordinals)

        acc =
          case days do
            [single] -> [{:day_of_week, single} | acc]
            list -> [{:day_of_week, list} | acc]
          end

        case ordinals do
          [] -> acc
          [single] -> [{:instance, single} | acc]
          list -> [{:instance, list} | acc]
        end
    end
  end
end
