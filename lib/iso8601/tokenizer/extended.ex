defmodule Tempo.Iso8601.Tokenizer.Extended do
  @moduledoc """
  Tokenizer combinators and post-processing for the
  Internet Extended Date/Time Format (IXDTF) defined in
  [draft-ietf-sedate-datetime-extended-09](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html).

  An IXDTF suffix follows a normal RFC 3339 / ISO 8601 date-time
  and consists of:

  * An optional time zone in square brackets such as
    `[Europe/Paris]` or `[+08:45]`.

  * Zero or more tagged suffixes such as `[u-ca=hebrew]` or
    `[_experimental=value]`.

  Any bracketed segment may be prefixed with `!` to mark it as
  **critical**.  Critical segments that are not recognised by
  the parser cause the parse to fail.  Elective (non-critical)
  segments that are not recognised are retained verbatim under
  the `:tags` key of the extended map.

  Calendar identifiers under the `u-ca` key are validated with
  `Localize.validate_calendar/1`.  Time zone names are validated
  with `Tzdata.zone_exists?/1`.

  """

  import NimbleParsec
  import Tempo.Iso8601.Tokenizer.Helpers, only: [digit: 0, colon: 0]

  ## Combinators

  @doc """
  Combinator that parses the IXDTF suffix.

  Produces a single token of the form `{:extended, raw_segments}`
  where each raw segment is a keyword list describing one
  bracket pair.

  """
  def extended_suffix(combinator \\ empty()) do
    combinator
    |> times(extended_segment(), min: 1)
    |> tag(:extended)
  end

  defp extended_segment do
    ignore(ascii_char([?[]))
    |> optional(ascii_char([?!]) |> replace(true) |> unwrap_and_tag(:critical))
    |> choice([
      tagged_suffix(),
      numeric_offset(),
      zone_name()
    ])
    |> ignore(ascii_char([?]]))
    |> wrap()
  end

  # `key=value-value-...`
  defp tagged_suffix do
    key_start =
      ascii_char([?a..?z, ?_])

    key_rest =
      ascii_char([?a..?z, ?0..?9, ?-, ?_])

    key =
      key_start
      |> repeat(key_rest)
      |> reduce({List, :to_string, []})
      |> unwrap_and_tag(:key)

    value_part =
      ascii_char([?a..?z, ?A..?Z, ?0..?9])
      |> times(min: 1)
      |> reduce({List, :to_string, []})

    values =
      value_part
      |> repeat(ignore(ascii_char([?-])) |> concat(value_part))
      |> wrap()
      |> unwrap_and_tag(:values)

    key
    |> ignore(ascii_char([?=]))
    |> concat(values)
    |> tag(:tag)
  end

  # A numeric offset such as `+08:45` or `-03:00` appearing
  # inside the time-zone brackets. The leading sign is
  # mandatory so we don't accidentally consume a zone name
  # whose initial character is alphabetic.
  defp numeric_offset do
    sign_char = ascii_char([?+, ?-])

    sign_char
    |> choice([
      digit() |> times(2) |> ignore(colon()) |> concat(digit() |> times(2)),
      digit() |> times(4),
      digit() |> times(2)
    ])
    |> reduce({__MODULE__, :to_offset, []})
    |> unwrap_and_tag(:offset)
  end

  # Zone names are ALPHA / "." / "_" initial then
  # ALPHA / DIGIT / "-" / "+" / "." / "_" / "/"
  defp zone_name do
    initial = ascii_char([?A..?Z, ?a..?z, ?., ?_])
    cont = ascii_char([?A..?Z, ?a..?z, ?0..?9, ?-, ?+, ?., ?_, ?/])

    initial
    |> repeat(cont)
    |> reduce({List, :to_string, []})
    |> unwrap_and_tag(:zone)
  end

  @doc false
  def to_offset([sign | digits]) do
    {hours, minutes} =
      case digits do
        [h1, h2] -> {[h1, h2], [?0, ?0]}
        [h1, h2, m1, m2] -> {[h1, h2], [m1, m2]}
      end

    hours = List.to_integer(hours)
    minutes = List.to_integer(minutes)
    magnitude = hours * 60 + minutes

    case sign do
      ?+ -> magnitude
      ?- -> -magnitude
    end
  end

  ## Post-processing

  @doc """
  Split a raw token list into regular tokens and the parsed
  extended-information map.

  The tokenizer emits an `{:extended, segments}` entry as the last
  element of the token list when an IXDTF suffix is present.  This
  function unpacks those segments into a validated map and returns
  the remaining tokens.

  ### Arguments

  * `tokens` is the raw token list produced by the tokenizer.

  ### Returns

  * `{:ok, {regular_tokens, extended_info_or_nil}}` on success
    where `extended_info_or_nil` is `nil` when no IXDTF suffix
    was parsed or a map with keys `:calendar`, `:zone_id`,
    `:zone_offset` and `:tags`.

  * `{:error, reason}` when a critical suffix is unrecognised
    or fails validation.

  ### Examples

      iex> {:ok, {_, extended}} =
      ...>   Tempo.Iso8601.Tokenizer.Extended.split_extended(
      ...>     [{:datetime, []}, {:extended, [[zone: "Europe/Paris"]]}])
      iex> extended.zone_id
      "Europe/Paris"

  """
  def split_extended(tokens) do
    with {:ok, tokens} <- validate_embedded_extended(tokens) do
      case List.pop_at(tokens, -1) do
        {{:extended, segments}, rest} ->
          with {:ok, extended} <- build_extended(segments) do
            {:ok, {rest, extended}}
          end

        _ ->
          {:ok, {tokens, nil}}
      end
    end
  end

  # Interval endpoints produced by `qualified_endpoint` may carry
  # per-endpoint `{:extended, raw_segments}` entries embedded in
  # their inner lists. Walk the token tree, validate each embedded
  # segment via `build_extended/1`, and replace the raw entry with a
  # validated map. Errors (critical unknown zone, etc.) bubble up.
  #
  # The top-level `{:extended, _}` remains untouched here — it is
  # handled by the List.pop_at branch above.

  defp validate_embedded_extended(tokens) when is_list(tokens) do
    reduce_while_ok(tokens, &validate_token/1)
  end

  defp validate_embedded_extended(other) do
    {:ok, other}
  end

  defp validate_token({:interval, inner}) when is_list(inner) do
    with {:ok, inner} <- reduce_while_ok(inner, &validate_interval_part/1) do
      {:ok, {:interval, inner}}
    end
  end

  defp validate_token(other) do
    {:ok, other}
  end

  defp validate_interval_part({tag, inner}) when tag in [:date, :datetime, :time_of_day] do
    case List.keytake(inner, :extended, 0) do
      nil ->
        {:ok, {tag, inner}}

      {{:extended, segments}, rest} ->
        with {:ok, extended} <- build_extended(segments) do
          {:ok, {tag, rest ++ [extended: extended]}}
        end
    end
  end

  defp validate_interval_part(other) do
    {:ok, other}
  end

  defp reduce_while_ok(list, fun) do
    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, _} = err -> err
    end
  end

  @empty_extended %{
    calendar: nil,
    zone_id: nil,
    zone_offset: nil,
    tags: %{}
  }

  defp build_extended(segments) do
    build_extended(segments, @empty_extended, 0)
  end

  # The first segment is the time-zone position: either a bare
  # zone name, a numeric offset, or a tagged suffix.  Once that
  # position is consumed subsequent segments must be tagged
  # suffixes.

  defp build_extended([], acc, _index), do: {:ok, acc}

  defp build_extended([segment | rest], acc, index) do
    {critical, payload} = split_critical(segment)

    with {:ok, acc} <- apply_payload(payload, critical, acc, index) do
      build_extended(rest, acc, index + 1)
    end
  end

  defp split_critical([{:critical, critical} | rest]) do
    {critical, unwrap_payload(rest)}
  end

  defp split_critical(rest) do
    {false, unwrap_payload(rest)}
  end

  defp unwrap_payload([{:tag, fields}]), do: {:tag, fields}
  defp unwrap_payload([{:zone, zone}]), do: {:zone, zone}
  defp unwrap_payload([{:offset, offset}]), do: {:offset, offset}

  # First segment: bare zone name is the time zone.
  defp apply_payload({:zone, zone}, critical, acc, 0) do
    apply_zone(zone, critical, acc)
  end

  # First segment: numeric offset is the time zone.
  defp apply_payload({:offset, offset}, _critical, acc, 0) do
    {:ok, %{acc | zone_offset: offset}}
  end

  # Tagged suffix at any position.
  defp apply_payload({:tag, [key: key, values: values]}, critical, acc, _index) do
    apply_tag(key, values, critical, acc)
  end

  # Additional zone name beyond the first position is not a valid
  # IXDTF construction.  We reject critical duplicates and ignore
  # elective ones.
  defp apply_payload({:zone, zone}, true, _acc, _index) do
    {:error, "Only one time zone may appear in an IXDTF suffix, got duplicate #{inspect(zone)}"}
  end

  defp apply_payload({:zone, _zone}, false, acc, _index) do
    {:ok, acc}
  end

  defp apply_payload({:offset, _}, true, _acc, _index) do
    {:error, "Only one time zone may appear in an IXDTF suffix, got duplicate offset"}
  end

  defp apply_payload({:offset, _}, false, acc, _index) do
    {:ok, acc}
  end

  defp apply_zone(zone, critical, acc) do
    if valid_zone?(zone) do
      {:ok, %{acc | zone_id: zone}}
    else
      if critical do
        {:error, "Unknown IANA time zone: #{inspect(zone)}"}
      else
        # Retain the string verbatim so callers can round-trip it,
        # but leave `:zone_id` signalled as unknown via the tags map.
        {:ok, put_in(acc, [:tags, "unknown_zone"], [zone])}
      end
    end
  end

  @u_ca "u-ca"

  # Calendar identifier.
  #
  # BCP 47 / CLDR calendar identifiers may be multi-segment —
  # `islamic-umalqura`, `islamic-civil`, `ethiopic-amete-alem`.
  # The tokenizer splits on `-` so multi-segment identifiers
  # arrive as a list of parts (`["islamic", "umalqura"]`). We
  # rejoin with `_` to match the atom form
  # `Localize.validate_calendar/1` recognises
  # (`:islamic_umalqura`, `:ethiopic_amete_alem`).
  defp apply_tag(@u_ca, values, critical, acc) when is_list(values) do
    normalised = Enum.join(values, "_")

    case Localize.validate_calendar(normalised) do
      {:ok, calendar} ->
        {:ok, %{acc | calendar: calendar}}

      {:error, _} when critical ->
        {:error,
         "Unknown calendar identifier #{inspect(Enum.join(values, "-"))} in extended suffix"}

      {:error, _} ->
        {:ok, acc}
    end
  end

  defp apply_tag(_key, _values, true, _acc) do
    {:error, "Unrecognised critical extended suffix"}
  end

  defp apply_tag(key, values, false, acc) do
    {:ok, put_in(acc, [:tags, key], values)}
  end

  defp valid_zone?(zone) do
    Tzdata.zone_exists?(zone)
  end
end
