defmodule Tempo.Cron do
  @moduledoc """
  Parser for cron expressions, producing the same
  `t:Tempo.RRule.Rule.t/0` AST that the ISO 8601 / RFC 5545 RRULE
  parser produces.

  Lets Tempo consume any cron-configured schedule (Oban, Quantum,
  system crontab) without rewriting the rule in another
  vocabulary. Once parsed, the rule can be materialised the same
  way any RRULE can — `Tempo.RRule.Expander.expand/2,3` or
  `Tempo.to_interval/2` with a `:bound`.

  ### Supported formats

  * **5-field POSIX**: `"minute hour day-of-month month day-of-week"`.

  * **6-field (seconds-first)**: `"second minute hour day-of-month month day-of-week"`.
    This is the variant used by Quantum and other Elixir
    schedulers.

  * **7-field (with year)**: `"second minute hour day-of-month month day-of-week year"`.
    A single concrete year is converted into an `UNTIL` limit;
    year lists or ranges are left as expansion-bound limits
    (see the "not supported" section).

  ### Field grammar

  Each field accepts:

  * `*` — every value in the field's range.

  * `N` — a single integer.

  * `N,M,O` — a list.

  * `N-M` — an inclusive range.

  * `*/S` — every `S` starting from the field's minimum.

  * `N-M/S` — every `S` within the range `N..M`.

  Day-of-week accepts `SUN`–`SAT` (case-insensitive) as synonyms for
  `0`–`6`. Sunday is both `0` and `7` (cron convention); internally
  converted to RFC 5545's `7` (Sunday last).

  Month accepts `JAN`–`DEC` (case-insensitive) as synonyms for `1`–`12`.

  ### Shortcut aliases

  Standard cron aliases are supported:

  | Alias                       | Expands to      |
  | --------------------------- | --------------- |
  | `@yearly`, `@annually`      | `0 0 1 1 *`     |
  | `@monthly`                  | `0 0 1 * *`     |
  | `@weekly`                   | `0 0 * * 0`     |
  | `@daily`, `@midnight`       | `0 0 * * *`     |
  | `@hourly`                   | `0 * * * *`     |

  `@reboot` is not supported — it is a system-startup hook, not a
  time expression.

  ### Vixie-cron extensions

  * `L` as day-of-month — last day of the month → `bymonthday: [-1]`.

  * `NL` as day-of-week (e.g. `5L`) — last weekday-N of the month →
    `byday: [{-1, N}]`.

  * `N#K` as day-of-week (e.g. `5#2`) — Kth weekday-N of the month →
    `byday: [{K, N}]`.

  ### Not supported (AST gaps)

  * **`W` (nearest weekday)** — e.g. `15W` meaning "nearest weekday
    to the 15th". RFC 5545 has no equivalent and the
    `Tempo.RRule.Rule` AST does not model this pattern. Parsing
    `W` returns `{:error, %Tempo.CronError{reason: :unsupported_w}}`.

  * **Year lists** — e.g. `"0 0 1 1 * 2025,2027,2029"`. A single
    concrete year becomes `until`; multi-year lists have no direct
    AST field (`byyear` does not exist) and the year constraint is
    effectively dropped. The caller should use a `:bound` at the
    materialisation site instead.

  * **POSIX day-of-month vs day-of-week OR semantics** — when both
    `dom` and `dow` are non-`*`, POSIX cron matches the union
    (either condition true). The AST AND-composes BY rules, so in
    this case the dow list is used and the dom list is folded into
    a `bysetpos`-style predicate approximation. Exact OR semantics
    would require a union operator in the AST.

  * **`@reboot`** — not a time expression.

  """

  alias Tempo.RRule.Rule

  @aliases %{
    "@yearly" => "0 0 1 1 *",
    "@annually" => "0 0 1 1 *",
    "@monthly" => "0 0 1 * *",
    "@weekly" => "0 0 * * 0",
    "@daily" => "0 0 * * *",
    "@midnight" => "0 0 * * *",
    "@hourly" => "0 * * * *"
  }

  @month_names %{
    "jan" => 1,
    "feb" => 2,
    "mar" => 3,
    "apr" => 4,
    "may" => 5,
    "jun" => 6,
    "jul" => 7,
    "aug" => 8,
    "sep" => 9,
    "oct" => 10,
    "nov" => 11,
    "dec" => 12
  }

  @dow_names %{
    "sun" => 0,
    "mon" => 1,
    "tue" => 2,
    "wed" => 3,
    "thu" => 4,
    "fri" => 5,
    "sat" => 6
  }

  @doc """
  Parse a cron expression into a `t:Tempo.RRule.Rule.t/0`.

  ### Arguments

  * `expression` is a cron string (5, 6, or 7 fields, or an alias).

  ### Returns

  * `{:ok, rule}` where `rule` is a `t:Tempo.RRule.Rule.t/0`.

  * `{:error, exception}` — typically a `t:Tempo.CronError.t/0`.

  ### Examples

      iex> {:ok, rule} = Tempo.Cron.parse("0 9 * * 1-5")
      iex> rule.freq
      :week
      iex> rule.byhour
      [9]
      iex> rule.byminute
      [0]
      iex> rule.byday
      [{nil, 1}, {nil, 2}, {nil, 3}, {nil, 4}, {nil, 5}]

      iex> {:ok, rule} = Tempo.Cron.parse("@daily")
      iex> rule.freq
      :day
      iex> {rule.byhour, rule.byminute}
      {[0], [0]}

      iex> {:ok, rule} = Tempo.Cron.parse("*/15 * * * *")
      iex> {rule.freq, rule.interval}
      {:minute, 15}

      iex> {:ok, rule} = Tempo.Cron.parse("* * * * *")
      iex> {rule.freq, rule.interval}
      {:minute, 1}

      iex> {:error, %Tempo.CronError{}} = Tempo.Cron.parse("not a cron")

  """
  @spec parse(String.t()) :: {:ok, Rule.t()} | {:error, Exception.t()}
  def parse(expression) when is_binary(expression) do
    trimmed = String.trim(expression)

    case Map.get(@aliases, String.downcase(trimmed)) do
      nil -> parse_fields(trimmed, expression)
      expanded -> parse_fields(expanded, expression)
    end
  end

  @doc """
  Raising version of `parse/1`.

  ### Examples

      iex> Tempo.Cron.parse!("@hourly").freq
      :hour

  """
  @spec parse!(String.t()) :: Rule.t()
  def parse!(expression) do
    case parse(expression) do
      {:ok, rule} -> rule
      {:error, exception} -> raise exception
    end
  end

  ## ---------------------------------------------------------
  ## Field dispatch — normalise raw strings into a shared map
  ## ---------------------------------------------------------

  # The internal representation of a parsed expression. Every
  # field is one of:
  #
  #   * `nil`           — the field was `*` (no BY constraint)
  #   * `{:list, [..]}` — specific values; becomes a BY* list
  #   * `{:step, n}`    — the field was `*/n`; candidate for INTERVAL
  #
  # Keeping the raw form on `:step` lets `choose_freq/1` decide
  # whether to collapse into FREQ=unit,INTERVAL=n (when every
  # other field is `*`) or to expand into a BY list.

  defp parse_fields(string, original) do
    parts = String.split(string, ~r/\s+/, trim: true)

    case parts do
      [min, hr, dom, mon, dow] ->
        build(nil, min, hr, dom, mon, dow, nil, original)

      [sec, min, hr, dom, mon, dow] ->
        build(sec, min, hr, dom, mon, dow, nil, original)

      [sec, min, hr, dom, mon, dow, year] ->
        build(sec, min, hr, dom, mon, dow, year, original)

      _other ->
        {:error,
         Tempo.CronError.exception(
           input: original,
           reason:
             "Cron expression must have 5, 6, or 7 fields (or be a supported @alias). " <>
               "Got #{length(parts)}."
         )}
    end
  end

  defp build(sec, min, hr, dom, mon, dow, year, _original) do
    with {:ok, n_sec} <- normalise(sec, :second, 0..59),
         {:ok, n_min} <- normalise(min, :minute, 0..59),
         {:ok, n_hr} <- normalise(hr, :hour, 0..23),
         {:ok, n_dom} <- normalise_monthday(dom),
         {:ok, n_mon} <- normalise_month(mon),
         {:ok, n_dow} <- normalise_dow(dow),
         {:ok, n_year} <- normalise(year, :year, 1970..9999) do
      fields = %{
        second: n_sec,
        minute: n_min,
        hour: n_hr,
        day_of_month: n_dom,
        month: n_mon,
        day_of_week: n_dow,
        year: n_year,
        has_seconds?: sec != nil
      }

      {:ok, choose_freq(fields) |> apply_year_limit(n_year)}
    end
  end

  ## ---------------------------------------------------------
  ## FREQ selection
  ## ---------------------------------------------------------

  # Build the final Rule. Two shapes of input:
  #
  #  (A) "Pure step" shortcut. The finest non-`*` field is a
  #      `{:step, n}` and every coarser field is `nil` (was `*`).
  #      Collapse to `FREQ=unit, INTERVAL=n`, no BY rules.
  #
  #  (B) Cascade. Pick FREQ from the *coarsest* non-`*` field; all
  #      finer non-`*` fields become BY rules. Step patterns at
  #      non-finest levels expand into BY lists.
  defp choose_freq(fields) do
    case pure_step(fields) do
      {:ok, freq, interval} -> %Rule{freq: freq, interval: interval}
      :no -> cascade(fields)
    end
  end

  defp pure_step(fields) do
    # Walk finest → coarsest looking for the first non-nil field.
    # If it's `{:step, n}` AND everything coarser is nil, we win.
    order = [:second, :minute, :hour, :day_of_month, :month, :day_of_week, :year]

    case Enum.find(order, fn k -> Map.get(fields, k) != nil end) do
      nil ->
        # Every field was `*`. FREQ is minute (or second if 6-field).
        if fields.has_seconds?, do: {:ok, :second, 1}, else: {:ok, :minute, 1}

      finest ->
        case Map.get(fields, finest) do
          {:step, n} ->
            if coarser_all_nil?(fields, finest, order) do
              {:ok, field_to_freq(finest), n}
            else
              :no
            end

          _ ->
            :no
        end
    end
  end

  defp coarser_all_nil?(fields, finest, order) do
    order
    |> Enum.drop_while(&(&1 != finest))
    |> Enum.drop(1)
    |> Enum.all?(fn k -> Map.get(fields, k) == nil end)
  end

  defp field_to_freq(:second), do: :second
  defp field_to_freq(:minute), do: :minute
  defp field_to_freq(:hour), do: :hour
  defp field_to_freq(:day_of_month), do: :month
  defp field_to_freq(:month), do: :year
  defp field_to_freq(:day_of_week), do: :week
  defp field_to_freq(:year), do: :year

  # Cascade: pick FREQ from coarsest specified field; everything
  # finer becomes a BY rule list.
  defp cascade(fields) do
    cond do
      not nil?(fields.year) ->
        rule = %Rule{freq: :year, interval: 1}
        rule |> put_by_list(:bymonth, fields.month) |> add_finer_by(fields, :month)

      not nil?(fields.month) ->
        rule = %Rule{freq: :year, interval: 1}
        rule |> put_by_list(:bymonth, fields.month) |> add_finer_by(fields, :month)

      not nil?(fields.day_of_week) ->
        rule = %Rule{freq: :week, interval: 1}
        rule = rule |> put_by_list(:byday, fields.day_of_week)
        rule = maybe_add_bymonthday(rule, fields.day_of_month)
        rule |> add_finer_by(fields, :day_of_week)

      not nil?(fields.day_of_month) ->
        rule = %Rule{freq: :month, interval: 1}

        rule
        |> put_by_list(:bymonthday, fields.day_of_month)
        |> add_finer_by(fields, :day_of_month)

      not nil?(fields.hour) ->
        rule = %Rule{freq: :day, interval: 1}
        rule |> put_by_list(:byhour, fields.hour) |> add_finer_by(fields, :hour)

      not nil?(fields.minute) ->
        rule = %Rule{freq: :hour, interval: 1}
        rule |> put_by_list(:byminute, fields.minute) |> add_finer_by(fields, :minute)

      not nil?(fields.second) ->
        rule = %Rule{freq: :minute, interval: 1}
        rule |> put_by_list(:bysecond, fields.second)

      true ->
        if fields.has_seconds?,
          do: %Rule{freq: :second, interval: 1},
          else: %Rule{freq: :minute, interval: 1}
    end
  end

  defp nil?(nil), do: true
  defp nil?(_), do: false

  # Add BY rules for every field finer than `coarsest` that is not
  # nil.
  defp add_finer_by(rule, fields, coarsest) do
    order = [:year, :month, :day_of_week, :day_of_month, :hour, :minute, :second]

    order
    |> Enum.drop_while(&(&1 != coarsest))
    |> Enum.drop(1)
    |> Enum.reduce(rule, fn field, acc ->
      by_key = field_to_by_key(field)
      put_by_list(acc, by_key, Map.get(fields, field))
    end)
  end

  defp field_to_by_key(:month), do: :bymonth
  defp field_to_by_key(:day_of_month), do: :bymonthday
  defp field_to_by_key(:day_of_week), do: :byday
  defp field_to_by_key(:hour), do: :byhour
  defp field_to_by_key(:minute), do: :byminute
  defp field_to_by_key(:second), do: :bysecond
  defp field_to_by_key(:year), do: :__year__

  # Convert normalised form into a list of integers (or keep byday
  # tuples as-is). `nil` means "skip this BY rule".
  defp put_by_list(rule, :__year__, _), do: rule
  defp put_by_list(rule, _key, nil), do: rule
  defp put_by_list(rule, key, {:list, values}), do: Map.put(rule, key, values)
  defp put_by_list(rule, key, {:step, _n}), do: rule |> Map.put(key, step_expand(key, rule))

  # When dow is specified and dom is ALSO specified, add bymonthday.
  # POSIX OR semantics would need more; see module docs.
  defp maybe_add_bymonthday(rule, nil), do: rule
  defp maybe_add_bymonthday(rule, {:list, list}), do: Map.put(rule, :bymonthday, list)
  defp maybe_add_bymonthday(rule, _), do: rule

  # Expand a `{:step, n}` into the relevant BY list. Rare case:
  # only hit when a step appears alongside other constraints.
  defp step_expand(:bymonth, _rule), do: Enum.to_list(1..12)
  defp step_expand(:bymonthday, _rule), do: Enum.to_list(1..31)
  defp step_expand(:byhour, _rule), do: Enum.to_list(0..23)
  defp step_expand(:byminute, _rule), do: Enum.to_list(0..59)
  defp step_expand(:bysecond, _rule), do: Enum.to_list(0..59)
  defp step_expand(:byday, _rule), do: Enum.map(1..7, &{nil, &1})

  # Year-as-UNTIL: a single concrete year becomes `until`.
  defp apply_year_limit(rule, nil), do: rule

  defp apply_year_limit(rule, {:list, [year]}) do
    %{rule | until: %Tempo{calendar: Calendrical.Gregorian, time: [year: year + 1]}}
  end

  defp apply_year_limit(rule, _multiple), do: rule

  ## ---------------------------------------------------------
  ## Field normalisers
  ## ---------------------------------------------------------

  defp normalise(nil, _field, _range), do: {:ok, nil}
  defp normalise("*", _field, _range), do: {:ok, nil}

  defp normalise("*/" <> step_str, field, range) do
    with {:ok, step} <- parse_int(step_str, field, 1..(range.last - range.first + 1)) do
      {:ok, {:step, step}}
    end
  end

  defp normalise(string, field, range) do
    with {:ok, values} <- parse_list(string, field, range) do
      {:ok, {:list, values}}
    end
  end

  defp normalise_month("*"), do: {:ok, nil}

  defp normalise_month(string) do
    with {:ok, values} <- parse_list_with_names(string, :month, 1..12, @month_names) do
      {:ok, {:list, values}}
    end
  end

  defp normalise_monthday("*"), do: {:ok, nil}
  defp normalise_monthday("L"), do: {:ok, {:list, [-1]}}

  defp normalise_monthday(string) do
    if String.contains?(string, "W") do
      {:error,
       Tempo.CronError.exception(
         field: :day_of_month,
         value: string,
         reason: :unsupported_w
       )}
    else
      normalise(string, :day_of_month, 1..31)
    end
  end

  defp normalise_dow("*"), do: {:ok, nil}

  defp normalise_dow(string) do
    with {:ok, entries} <- parse_dow(string) do
      {:ok, {:list, entries}}
    end
  end

  ## ---------------------------------------------------------
  ## List / range / name parsers
  ## ---------------------------------------------------------

  defp parse_list(string, field, range) do
    string
    |> String.split(",", trim: true)
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case parse_part(part, field, range) do
        {:ok, list} -> {:cont, {:ok, acc ++ list}}
        err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, []} ->
        {:error, Tempo.CronError.exception(field: field, value: string, reason: "empty field")}

      {:ok, list} ->
        {:ok, list |> Enum.uniq() |> Enum.sort()}

      err ->
        err
    end
  end

  defp parse_list_with_names(string, field, range, names) do
    string
    |> String.split(",", trim: true)
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case parse_part_with_names(part, field, range, names) do
        {:ok, list} -> {:cont, {:ok, acc ++ list}}
        err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, list |> Enum.uniq() |> Enum.sort()}
      err -> err
    end
  end

  defp parse_part_with_names(part, field, range, names) do
    cond do
      Map.has_key?(names, String.downcase(part)) ->
        {:ok, [Map.fetch!(names, String.downcase(part))]}

      String.contains?(part, "-") and not step?(part) ->
        case String.split(part, "-", parts: 2) do
          [a, b] ->
            with {:ok, from} <- name_or_int(a, names, field, range),
                 {:ok, to} <- name_or_int(b, names, field, range) do
              {:ok, Enum.to_list(from..to)}
            end

          _ ->
            parse_part(part, field, range)
        end

      true ->
        parse_part(part, field, range)
    end
  end

  defp step?(part), do: String.contains?(part, "/")

  defp name_or_int(string, names, field, range) do
    down = String.downcase(string)

    case Map.fetch(names, down) do
      {:ok, int} -> {:ok, int}
      :error -> parse_int(string, field, range)
    end
  end

  # Parse one comma-separated part: `N`, `N-M`, `*/S`, `N-M/S`, `*`.
  defp parse_part(part, field, range) do
    case String.split(part, "/") do
      [spec] ->
        parse_range(spec, field, range)

      [spec, step_str] ->
        with {:ok, base} <- parse_step_lhs(spec, field, range),
             {:ok, step} <- parse_int(step_str, field, 1..(range.last - range.first + 1)) do
          {:ok, Enum.take_every(base, step)}
        end

      _other ->
        {:error,
         Tempo.CronError.exception(
           field: field,
           value: part,
           reason: "Malformed field (multiple `/`): #{inspect(part)}"
         )}
    end
  end

  defp parse_step_lhs("*", _field, range), do: {:ok, Enum.to_list(range)}

  defp parse_step_lhs(spec, field, range) do
    if String.contains?(spec, "-") do
      parse_range(spec, field, range)
    else
      with {:ok, [n]} <- parse_range(spec, field, range) do
        {:ok, Enum.to_list(n..range.last)}
      end
    end
  end

  defp parse_range(spec, field, range) do
    case String.split(spec, "-", parts: 2) do
      [only] ->
        with {:ok, int} <- parse_int(only, field, range), do: {:ok, [int]}

      [a, b] ->
        with {:ok, from} <- parse_int(a, field, range),
             {:ok, to} <- parse_int(b, field, range) do
          if from <= to do
            {:ok, Enum.to_list(from..to)}
          else
            # Wrap-around range — common cron dialect.
            {:ok, Enum.to_list(from..range.last) ++ Enum.to_list(range.first..to)}
          end
        end
    end
  end

  defp parse_int(string, field, range) do
    case Integer.parse(string) do
      {int, ""} ->
        if int in range do
          {:ok, int}
        else
          {:error,
           Tempo.CronError.exception(
             field: field,
             value: string,
             reason: "Value #{int} is outside the valid range #{inspect(range)} for #{field}"
           )}
        end

      _ ->
        {:error,
         Tempo.CronError.exception(
           field: field,
           value: string,
           reason: "Expected an integer for #{field}, got #{inspect(string)}"
         )}
    end
  end

  ## ---------------------------------------------------------
  ## Day-of-week parsing — names, L, #, ranges
  ## ---------------------------------------------------------

  defp parse_dow(string) do
    string
    |> String.split(",", trim: true)
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case parse_dow_part(part) do
        {:ok, entries} -> {:cont, {:ok, acc ++ entries}}
        err -> {:halt, err}
      end
    end)
  end

  defp parse_dow_part(part) do
    cond do
      # `5L` → last Friday
      String.ends_with?(part, "L") and part != "L" ->
        prefix = String.slice(part, 0..-2//1)

        with {:ok, day} <- dow_to_rfc(prefix, part), do: {:ok, [{-1, day}]}

      # `5#2` → second Friday
      String.contains?(part, "#") ->
        case String.split(part, "#") do
          [day_str, ord_str] ->
            with {:ok, day} <- dow_to_rfc(day_str, part),
                 {:ok, ordinal} <- parse_int(ord_str, :day_of_week, -53..53) do
              {:ok, [{ordinal, day}]}
            end

          _ ->
            {:error,
             Tempo.CronError.exception(
               field: :day_of_week,
               value: part,
               reason: "Malformed `#`: #{inspect(part)}"
             )}
        end

      # Step with name range on LHS, e.g. `MON-FRI/2`
      String.contains?(part, "/") ->
        [lhs, step_str] = String.split(part, "/", parts: 2)

        with {:ok, base} <- dow_step_lhs(lhs),
             {:ok, step} <- parse_int(step_str, :day_of_week, 1..7) do
          entries = base |> Enum.take_every(step) |> Enum.map(&{nil, &1})
          {:ok, entries}
        end

      # Range: `MON-FRI` or `1-5`
      String.contains?(part, "-") ->
        [a, b] = String.split(part, "-", parts: 2)

        with {:ok, from} <- dow_to_rfc(a, part),
             {:ok, to} <- dow_to_rfc(b, part) do
          days = if from <= to, do: Enum.to_list(from..to), else: Enum.to_list(from..7)
          {:ok, Enum.map(days, &{nil, &1})}
        end

      true ->
        with {:ok, day} <- dow_to_rfc(part, part), do: {:ok, [{nil, day}]}
    end
  end

  defp dow_step_lhs("*"), do: {:ok, Enum.to_list(1..7)}

  defp dow_step_lhs(lhs) do
    if String.contains?(lhs, "-") do
      [a, b] = String.split(lhs, "-", parts: 2)

      with {:ok, from} <- dow_to_rfc(a, lhs),
           {:ok, to} <- dow_to_rfc(b, lhs) do
        {:ok, Enum.to_list(from..to)}
      end
    else
      with {:ok, day} <- dow_to_rfc(lhs, lhs), do: {:ok, Enum.to_list(day..7)}
    end
  end

  # Cron: 0 = Sunday, 1..6 = Mon..Sat, 7 = Sunday. Also SUN..SAT.
  # RFC 5545: 1..7 = Mon..Sun.
  defp dow_to_rfc(string, orig) do
    down = String.downcase(string)

    cond do
      Map.has_key?(@dow_names, down) ->
        {:ok, cron_to_rfc(Map.fetch!(@dow_names, down))}

      true ->
        case Integer.parse(string) do
          {int, ""} when int in 0..7 ->
            {:ok, cron_to_rfc(int)}

          _ ->
            {:error,
             Tempo.CronError.exception(
               field: :day_of_week,
               value: orig,
               reason: "Invalid day-of-week: #{inspect(orig)}"
             )}
        end
    end
  end

  defp cron_to_rfc(0), do: 7
  defp cron_to_rfc(7), do: 7
  defp cron_to_rfc(n) when n in 1..6, do: n
end
