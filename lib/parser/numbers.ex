defmodule Tempo.Iso8601.Parser.Numbers do
  @moduledoc """
  Numbers aren't just numbers in ISO8601 when considering
  the extension formats. In some situations they may:

  * Have exponents
  * Have precision
  * Have unknown digits

  And how these are formed varies by whether the
  number is being parsed for an implicit form,
  extended form or explicit form.

  ## Implicit form

  * Numbers are always positive with no sign
  except when its the year in which case it may have
  a negative sign

  * Numbers are always a positive integer, or a the
    "unknown" symbol `X` in any digit location. Numbers
    are either 2, 3 or 4 digits wide (decades are three
    digits) and this implementation does not currently
    support more than 4 digits for years.

  * Neither exponent or significant digits are supported

  ** Extended form

  * Same as the Implicit Form

  ## Explicit form

  * Numbers may be positive of negative

  * The "unknown" symbol `X` may appear in
    any digit location.

  * The symbol `X*` means the entire
    field is unspecified.

  * Exponent and significant digits are supported,
    but only if the number is an integer (ie does
    not have unknown digits)

  """
  import NimbleParsec
  import Tempo.Iso8601.Parser.Helpers

  def positive_number(combinator \\ empty(), opts)

  def positive_number(combinator, n) when is_integer(n) do
    combinator
    |> choice([
      integer(n) |> optional(exponent()) |> optional(significant()),
      digit_or_unknown() |> times(n)
    ])
    |> reduce(:form_number)
    |> label("positive number")
  end

  def positive_number(combinator, opts) do
    combinator
    |> choice([
      integer(opts) |> lookahead_not(unknown()) |> optional(exponent()) |> optional(significant()),
      digit_or_unknown() |> times(opts)
    ])
    |> reduce(:form_number)
    |> label("positive number")
  end

  def maybe_negative_number(combinator \\ empty(), opts) do
    combinator
    |> optional(negative())
    |> positive_number(opts)
    |> reduce(:form_number)
    |> label("maybe negative number")
  end

  def exponent do
    ignore(string("E"))
    |> integer(min: 1)
    |> unwrap_and_tag(:exponent)
  end

  def significant do
    ignore(string("S"))
    |> integer(min: 1)
    |> unwrap_and_tag(:significant)
  end

  def form_number([integer]) when is_integer(integer) do
    integer
  end

  def form_number([?-, integer | rest]) when is_integer(integer) do
    form_number([-integer | rest])
  end

  def form_number([integer, {:exponent, exponent} | rest]) do
    form_number([integer * :math.pow(10, exponent) |> trunc | rest])
  end

  def form_number([integer, {:significant, significant}]) do
    {integer, significant}
  end

  def form_number([tuple]) when is_tuple(tuple) do
    tuple
  end

  def form_number([list]) when is_list(list) do
    list
  end

  def form_number(other) do
    other
  end

  def fraction do
    ignore(decimal_separator()) |> times(ascii_char([?0..?9]), min: 1)
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:fraction)
    |> label("fraction")
  end

end