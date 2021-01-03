defmodule Tempo.Iso8601.Parser.Helpers do
  import NimbleParsec

  def integer_or_unknown(combinator \\ empty(), opts)

  # Used parsing implicit forms
  def integer_or_unknown(combinator, n) when is_integer(n) do
    combinator
    |> choice([
      integer(n) |> reduce(:detect_sign),
      ascii_char([?0..?9, ?X]) |> times(n)
    ])
    |> reduce(:detect_unknown)
  end

  # Used parsing explicit forms
  def integer_or_unknown(combinator, opts) do
    combinator
    |> choice([
      integer(opts) |> reduce(:detect_sign),
      string("X*"),
      ascii_char([?0..?9, ?X]) |> times(opts)
    ])
    |> reduce(:detect_unknown)
  end

  def integer_or_unknown_year(combinator \\ empty(), opts) do
    combinator
    |> choice([
      maybe_exponent_integer(opts),
      string("X*"),
      ascii_char([?0..?9, ?X]) |> times(opts)
    ])
    |> reduce(:detect_unknown)
  end

  def maybe_exponent_integer(opts) do
    optional(negative())
    |> integer(opts)
    |> optional(string("E") |> integer(min: 1))
    |> optional(string("S") |> integer(min: 1))
    |> reduce(:detect_sign)
  end

  def fraction do
    ignore(decimal_separator()) |> times(ascii_char([?0..?9]), min: 1)
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:fraction)
  end

  def decimal_separator do
    ascii_char([?,, ?.])
  end

  def negative do
    ascii_char([?-])
  end

  # Detect is a sign was presented in which case
  # apply it.

  def detect_sign([?-, integer]) do
    -integer
  end

  def detect_sign([?+, integer]) do
    integer
  end

  def detect_sign([integer]) when is_integer(integer) do
    integer
  end

  def detect_sign([?- | rest]) do
    case detect_sign(rest) do
      int when is_integer(int) -> -int
      {int, significance} -> {-int, significance}
    end
  end

  def detect_sign([int, "E", exp]) do
    int * :math.pow(10, exp) |> trunc
  end

  def detect_sign([int, "S", significance]) do
    {int, significance}
  end

  def detect_sign([int, "E", exp, "S", significance]) do
    {int * :math.pow(10, exp) |> trunc, significance}
  end

  # In many cases an integer can also have "placeholders"
  # represented by one or more `X`'s and these need to be
  # detected

  def detect_unknown(["X*"]) do
    [:undefined]
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
      ?X -> :undefined
    end
  end

  def convert_bc(["B", int]) do
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

  def time_or_eos do
    choice([
      ascii_char([?T, ?/]),
      eos()
    ])
  end
end