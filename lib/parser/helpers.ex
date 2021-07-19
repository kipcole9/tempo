defmodule Tempo.Iso8601.Parser.Helpers do
  import NimbleParsec

  def recur([]), do: :infinity
  def recur([other]), do: other

  # Used parsing implicit forms
  def integer_or_unknown(combinator \\ empty(), opts)

  def integer_or_unknown(combinator, n) when is_integer(n) do
    combinator
    |> choice([
      integer(n),
      ascii_char([?0..?9, ?X]) |> times(n)
    ])
    |> reduce(:detect_unknown)
    |> label("integer with maybe unknown digits")
  end

  # Used for implicit forms
  def integer_or_unknown(combinator, opts) do
    combinator
    |> choice([
      integer(opts),
      string("X*"),
      ascii_char([?0..?9, ?X]) |> times(opts)
    ])
    |> reduce(:detect_unknown)
    |> label("integer with maybe unknown digits")
  end

  # Used parsing explicit forms
  def maybe_negative_integer_or_unknown(combinator \\ empty(), opts)

  # Its either `n` digit integer or a combination of 0..9 and X
  # representing "unknown"
  def maybe_negative_integer_or_unknown(combinator, n) when is_integer(n) do
    combinator
    |> choice([
      maybe_negative_integer(n),
      ascii_char([?0..?9, ?X]) |> times(n)
    ])
    |> reduce(:detect_unknown)
    |> label("potentially negative integer with maybe unknown digits")
  end

  def maybe_negative_integer_or_unknown(combinator, opts) do
    combinator
    |> choice([
      string("X*"),
      optional(ascii_char([?-])) |> times(ascii_char([?0..?9, ?X]), opts)
    ])
    |> reduce(:detect_unknown)
    |> label("potentially negative integer with maybe unknown digits")
  end

  def integer_or_unknown_year(combinator \\ empty(), opts) do
    combinator
    |> choice([
      maybe_exponent_integer(opts),
      string("X*"),
      ascii_char([?0..?9, ?X]) |> times(opts)
    ])
    |> reduce(:detect_unknown)
    |> label("potentially negative year with maybe unknown digits")
  end

  def maybe_exponent_integer(combinator \\ empty(), opts) do
    combinator
    |> optional(negative())
    |> ascii_char([?0..?9, ?X]) |> times(opts)
    |> optional(string("E") |> integer(min: 1))
    |> optional(string("S") |> integer(min: 1))
    |> reduce(:form_exponent_integer)
    |> label("integer with exponent")
  end

  def maybe_negative_integer(opts \\ [min: 1]) do
    optional(negative())
    |> integer(opts)
    |> reduce(:form_integer)
    |> label("potentially negative integer")
  end

  def form_integer([?-, int]) do
    -int
  end

  def form_integer([int]) do
    int
  end

  def fraction do
    ignore(decimal_separator()) |> times(ascii_char([?0..?9]), min: 1)
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:fraction)
    |> label("fraction")
  end

  def decimal_separator do
    ascii_char([?,, ?.])
  end

  def negative do
    ascii_char([?-])
  end

  # Convert a charlist to an integer if all the character
  # are integers, otherwise if they have unknowns leave it
  # unchanged.  Then detect

  def form_exponent_integer([?- | [_|_] = number]) do
    if Enum.any?(number, &(&1 in [?X, ?S, ?E)) do

    else
      List.to_integer(number)
    end
  end

    case form_exponent_integer(number) do
      int when is_integer(int) -> -int
      {int, significance} -> {-int, significance}
    end
  end

  def form_exponent_integer([int, "E", exp]) do
    int * :math.pow(10, exp) |> trunc
  end

  def form_exponent_integer([int, "S", significance]) do
    {int, significance}
  end

  def form_exponent_integer([int, "E", exp, "S", significance]) do
    {int * :math.pow(10, exp) |> trunc, significance}
  end

  # In many cases an integer can also have "placeholders"
  # represented by one or more `X`'s and these need to be
  # detected

  def detect_unknown(["X*"]) do
    :unspecified
  end

  def detect_unknown([integer]) when is_integer(integer) do
    integer
  end

  def detect_unknown([tuple]) when is_tuple(tuple) do
    tuple
  end

  def detect_unknown(chars) when is_list(chars) do
    Enum.map chars, fn
      char when char in ?0..?9 -> char - ?0
      ?X -> :unspecified
      ?- -> :negative
    end
  end

  def convert_bc([int, "B"]) do
    -(int - 1)
  end

  def convert_bc([other]) do
    other
  end

  def sign do
    ascii_char([?+, ?-])
    |> unwrap_and_tag(:sign)
  end

  def zulu do
    ascii_char([?Z])
  end

  def colon do
    ascii_char([?:])
  end

  def dash do
    ascii_char([?-])
  end

  def time_or_eos(combinator \\ empty()) do
    combinator
    |> choice([
      ascii_char([?T, ?/]),
      eos()
    ])
    |> lookahead
  end
end