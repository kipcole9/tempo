defmodule Tempo.Iso8601.AST do
  @moduledoc false

  # Internal builder that converts tokenizer-emitted AST shapes into
  # `%Tempo{}` and `%Tempo.Interval{}` structs. This is NOT the public
  # constructor — see `Tempo.new/1` and `Tempo.Interval.new/1` for
  # the developer-facing keyword-based constructors, which validate
  # their input.
  #
  # `build/1,2` accepts whatever the tokenizer produces: plain keyword
  # lists, tagged-tuple shapes like `{:range, [first, last]}`, the
  # atom `:undefined`, and tokens containing groups / selections /
  # sets as component values. No validation happens here; the parser
  # is the validator of record for these shapes.

  alias Tempo.Duration
  alias Tempo.Interval

  @doc """
  Build a `%Tempo{}` from tokenizer output.

  Accepts:

    * a keyword list (possibly containing `:time_shift`,
      `:qualification`, `:extended`, and `:<unit>_qualification` keys
      that route to specific struct fields);

    * `{:range, [first_tokens, last_tokens]}` — produces a
      `%Tempo.Range{}` (via `Tempo.Range.new/3`);

    * `:undefined` — returned as-is (represents an open endpoint).

  """
  def build(tokens, calendar \\ Calendrical.Gregorian)

  def build({:range, [first, last]}, calendar) do
    Tempo.Range.new(first, last, calendar)
  end

  def build(:undefined, _calendar) do
    :undefined
  end

  def build(tokens, calendar) when is_list(tokens) do
    {shift, tokens} = Keyword.pop(tokens, :time_shift)
    {qualification, tokens} = Keyword.pop(tokens, :qualification)
    {extended, tokens} = Keyword.pop(tokens, :extended)
    {component_qualifications, time} = pop_component_qualifications(tokens)

    %Tempo{
      time: time,
      shift: shift,
      calendar: calendar,
      extended: extended,
      qualification: qualification,
      qualifications: component_qualifications
    }
  end

  @doc """
  Build a `%Tempo.Interval{}` from tokenizer output.

  Defers to `Tempo.Interval.build/1` (see that function for the
  clause-by-clause shape coverage). Kept here for symmetry — callers
  inside the parser pipeline go through `Tempo.Iso8601.AST` for both
  the Tempo and Interval construction paths.
  """
  def build_interval(tokens) do
    Interval.build(tokens)
  end

  @doc """
  Build a `%Tempo.Duration{}` from tokenizer output. Tokens are a
  keyword list of `{unit, amount}` pairs.
  """
  def build_duration(tokens) do
    Duration.build(tokens)
  end

  # Removes any `{<unit>_qualification, value}` entries from `tokens`
  # and returns them as a plain `%{unit => value}` map. Returns `nil`
  # for the map when no component-level qualifications were present
  # so that the `%Tempo{}` struct stays compact when the feature
  # isn't used.
  defp pop_component_qualifications(tokens) do
    {remaining, acc} =
      Enum.reduce(tokens, {[], %{}}, fn
        {key, value}, {rest, acc} when is_atom(key) ->
          case unit_from_qualification_key(key) do
            nil -> {[{key, value} | rest], acc}
            unit -> {rest, Map.put(acc, unit, value)}
          end

        other, {rest, acc} ->
          {[other | rest], acc}
      end)

    result = if map_size(acc) == 0, do: nil, else: acc
    {result, Enum.reverse(remaining)}
  end

  @qualification_suffix "_qualification"
  @qualification_suffix_size byte_size(@qualification_suffix)

  defp unit_from_qualification_key(key) do
    key_string = Atom.to_string(key)
    size = byte_size(key_string)

    if size > @qualification_suffix_size and
         binary_part(key_string, size - @qualification_suffix_size, @qualification_suffix_size) ==
           @qualification_suffix do
      key_string
      |> binary_part(0, size - @qualification_suffix_size)
      |> String.to_existing_atom()
    else
      nil
    end
  end
end
