defmodule Tempo.Iso8601.Tokenizer do
  @moduledoc """
  Tokenizes an ISO 8601 (parts 1 and 2) or IXDTF string into a
  list of tagged tokens that the internal parser then converts
  into a `t:Tempo.t/0` struct.

  `tokenize/1` returns a 2-tuple `{tokens, extended_info}` where
  `extended_info` is either `nil` or a map of parsed
  [IXDTF](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html)
  suffix information.  See `Tempo.Iso8601.Tokenizer.Extended` for
  the shape of the extended map.

  """

  import NimbleParsec
  import Tempo.Iso8601.Tokenizer.Grammar

  alias Tempo.Iso8601.Tokenizer.Extended
  alias Tempo.ParseError

  # Guard against pathological input. Legitimate ISO 8601 / IXDTF
  # strings are short; a multi-kilobyte string is almost certainly
  # adversarial, and a long digit run costs super-linear time to
  # tokenize. Reject over-long input up front rather than let the
  # parser chew on it.
  @max_input_bytes 8_192

  # Bracket-nesting (`{…}` / `[…]`) is the parser's one exponential
  # axis: each level multiplies the combinator alternatives tried,
  # so deep nesting (or an unbalanced run of openers) costs
  # exponential time. Legitimate ISO 8601-2 sets and groups nest at
  # most two or three deep, so a small cap rejects the pathological
  # cases up front while leaving every real value untouched.
  @max_nesting_depth 6

  @doc """
  Tokenize an ISO 8601 or IXDTF string.

  ### Arguments

  * `string` is any ISO 8601 formatted string, optionally with an
    [IXDTF](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html)
    suffix (such as `[Europe/Paris][u-ca=hebrew]`).

  ### Returns

  * `{:ok, {tokens, extended_info}}` where `tokens` is the list of
    ISO 8601 tokens produced by the parser and `extended_info` is
    either `nil` (when no IXDTF suffix was present) or a map with
    keys `:calendar`, `:zone_id`, `:zone_offset` and `:tags`.

  * `{:error, reason}` when the string cannot be parsed or a
    critical IXDTF suffix is unrecognised.

  """
  def tokenize(string) when byte_size(string) > @max_input_bytes do
    {:error,
     ParseError.exception(
       input: binary_part(string, 0, 64) <> "…",
       reason: "Input of #{byte_size(string)} bytes exceeds the #{@max_input_bytes}-byte limit"
     )}
  end

  def tokenize(string) do
    if nesting_exceeds_limit?(string) do
      {:error,
       ParseError.exception(
         input: string,
         reason: "Set/group nesting exceeds the depth limit of #{@max_nesting_depth}"
       )}
    else
      string
      |> iso8601()
      |> return(string)
    end
  end

  # Walk the string once, tracking `{`/`[` open-bracket depth, and
  # report whether it ever exceeds the limit (an unbalanced run of
  # openers keeps climbing and is caught the same way).
  defp nesting_exceeds_limit?(string) do
    string
    |> :binary.bin_to_list()
    |> Enum.reduce_while(0, fn
      char, depth when char in [?{, ?[] ->
        if depth + 1 > @max_nesting_depth, do: {:halt, :exceeded}, else: {:cont, depth + 1}

      char, depth when char in [?}, ?]] ->
        {:cont, max(depth - 1, 0)}

      _char, depth ->
        {:cont, depth}
    end) == :exceeded
  end

  defp return(result, string) do
    case result do
      {:ok, tokens, "", %{}, {_, _}, _} ->
        Extended.split_extended(tokens)

      {:ok, _tokens, remaining, _, {_line, _}, _char} ->
        {:error,
         ParseError.exception(
           input: string,
           reason: "Could not parse #{inspect(string)}. Error detected at #{inspect(remaining)}"
         )}

      {:error, message, detected_at, _, _, _} ->
        {:error,
         ParseError.exception(
           input: string,
           reason: String.capitalize(message) <> ". Error detected at #{inspect(detected_at)}"
         )}
    end
  end

  # The single true entry point, called directly by `tokenize/1`. Every
  # other parser is internal — referenced only via `parsec/1` — and lives
  # in one of the sibling tokenizer modules (`.Date`, `.Time`, `.Set`) so
  # `mix` compiles them concurrently. NimbleParsec resolves a
  # `parsec({Module, :name})` reference against that module's exported
  # combinator, so the grammar is split across modules without changing
  # behaviour.
  defparsec :iso8601, iso8601_tokenizer()

  # `set` and `datetime_or_date_or_time` stay here but are now referenced
  # from the sibling modules, so they are exported combinators. Their inner
  # `parsec/1` references are qualified to each parser's home module.
  defcombinator :set,
                choice([
                  parsec({Tempo.Iso8601.Tokenizer.Set, :set_all}),
                  parsec({Tempo.Iso8601.Tokenizer.Set, :set_one}),
                  parsec({Tempo.Iso8601.Tokenizer.Set, :interval_parser}),
                  parsec({Tempo.Iso8601.Tokenizer, :datetime_or_date_or_time})
                ]),
                export_combinator: true

  defcombinator :datetime_or_date_or_time,
                choice([
                  parsec({Tempo.Iso8601.Tokenizer.Date, :datetime_parser}),
                  parsec({Tempo.Iso8601.Tokenizer.Date, :date_parser}),
                  parsec({Tempo.Iso8601.Tokenizer.Time, :time_parser})
                ])
                |> label("datetime_or_date_or_time"),
                export_combinator: true
end
