defmodule Tempo.Iso8601.Tokenizer.Numbers do
  @moduledoc """
  Numbers aren't just numbers in ISO8601 when considering
  the extension formats. In some situations they may:

  * Have exponents
  * Have precision
  * Have unspecified digits

  And how these are formed varies by whether the
  number is being parsed for an implicit form,
  extended form or explicit form.

  ## Implicit form

  * Numbers are always positive with no sign
  except when its the year in which case it may have
  a negative sign.

  * Numbers are always a positive integer, or a the
    "unspecified" symbol `X` in any digit location. Numbers
    are either 2, 3 or 4 digits wide (decades are three
    digits) and this implementation does not currently
    support more than 4 digits for years.

  * Significant digits are not supported.

  ** Extended form

  * Same as the Implicit Form

  ## Explicit form

  * Numbers may be positive of negative

  * The "unspecified" symbol `X` may appear in
    any digit location.

  * The symbol `X*` means the entire
    field is unspecified.

  * Exponent and significant digits are supported,
    but only if the number is an integer (ie does
    not have unspecified digits).

  """
  import NimbleParsec
  import Tempo.Iso8601.Tokenizer.Helpers

  def positive_number(combinator \\ empty(), opts)

  def positive_number(combinator, n) when is_integer(n) do
    combinator
    |> choice([
      integer(n)
      |> optional(fraction())
      |> optional(exponent())
      |> optional(significant())
      |> optional(error_range())
      |> lookahead_not(unspecified_or_set())
      |> reduce(:form_number),
      all_unspecified()
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask),
      digit_or_unspecified()
      |> times(n)
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask)
    ])
    |> label("positive number")
  end

  def positive_number(combinator, opts) do
    combinator
    |> choice([
      integer(opts)
      |> optional(fraction())
      |> optional(exponent())
      |> optional(significant())
      |> optional(error_range())
      |> lookahead_not(unspecified_or_set())
      |> reduce(:form_number),
      all_unspecified()
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask),
      digit_or_unspecified()
      |> times(opts)
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask)
    ])
    |> reduce(:form_number)
    |> label("positive number")
  end

  def positive_integer(combinator \\ empty(), opts)

  def positive_integer(combinator, n) when is_integer(n) do
    combinator
    |> choice([
      integer(n)
      |> optional(exponent())
      |> optional(significant())
      |> optional(error_range())
      |> lookahead_not(unspecified_or_set())
      |> reduce(:form_number),
      all_unspecified()
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask),
      digit_or_unspecified()
      |> times(n)
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask)
    ])
    |> label("positive integer")
  end

  def positive_integer(combinator, opts) do
    combinator
    |> choice([
      integer(opts)
      |> lookahead_not(unspecified())
      |> optional(exponent())
      |> optional(significant())
      |> optional(error_range())
      |> lookahead_not(unspecified_or_set())
      |> reduce(:form_number),
      all_unspecified()
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask),
      digit_or_unspecified()
      |> times(opts)
      |> reduce(:normalize_mask)
      |> unwrap_and_tag(:mask)
    ])
    |> label("positive integer")
  end

  def maybe_negative_number(combinator \\ empty(), opts) do
    combinator
    |> optional(negative())
    |> positive_number(opts)
    |> reduce(:form_number)
    |> label("maybe negative number")
  end

  def maybe_negative_integer(combinator \\ empty(), opts) do
    combinator
    |> optional(negative())
    |> positive_integer(opts)
    |> reduce(:form_number)
    |> label("maybe negative integer")
  end

  def positive_number_or_integer_set(indicator, tag, opts) do
    choice([
      parsec(:integer_set_all),
      positive_number(opts)
    ])
    |> ignore(string(indicator))
    |> unwrap_and_tag(tag)
  end

  def positive_number_or_integer_set(tag, opts) do
    choice([
      parsec(:integer_set_all),
      positive_number(opts)
    ])
    |> unwrap_and_tag(tag)
  end

  def maybe_negative_number_or_integer_set(indicator, tag, opts) do
    choice([
      parsec(:integer_set_all),
      maybe_negative_number(opts)
    ])
    |> ignore(string(indicator))
    |> unwrap_and_tag(tag)
  end

  def positive_integer_or_integer_set(tag, opts) do
    choice([
      parsec(:integer_set_all),
      positive_integer(opts)
    ])
    |> unwrap_and_tag(tag)
  end

  def positive_integer_or_integer_set(indicator, tag, opts) do
    choice([
      parsec(:integer_set_all),
      positive_integer(opts)
    ])
    |> ignore(string(indicator))
    |> unwrap_and_tag(tag)
  end

  def maybe_negative_integer_or_integer_set(indicator, tag, opts) do
    choice([
      parsec(:integer_set_all),
      maybe_negative_integer(opts)
    ])
    |> ignore(string(indicator))
    |> unwrap_and_tag(tag)
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

  def fraction do
    ignore(decimal_separator())
    |> times(ascii_char([?0..?9]), min: 1)
    |> lookahead_not(number_separator())
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:fraction)
  end

  def number_separator do
    choice([
      dash(),
      decimal_separator(),
      ascii_char([?], ?}])
    ])
  end

  def error_range do
    ignore(string("±"))
    |> integer(min: 1)
    |> optional(exponent())
    |> reduce(:form_number)
    |> unwrap_and_tag(:margin_of_error)
  end

  def digit_or_unspecified do
    choice([
      digit(),
      unspecified(),
      parsec(:integer_set_all)
    ])
  end

  def unspecified_or_set() do
    choice([
      unspecified(),
      ascii_char([?{])
    ])
  end

  def form_number([number]) when is_number(number) do
    number
  end

  def form_number([?-, integer, {:fraction, fraction} | rest])
      when is_integer(integer) and is_integer(fraction) do
    digits = Cldr.Digits.number_of_integer_digits(fraction)
    number = integer + fraction / :math.pow(10, digits)
    form_number([-number | rest])
  end

  def form_number([?-, integer | rest]) when is_integer(integer) do
    form_number([-integer | rest])
  end

  def form_number([?-, {integer, options} | rest]) when is_integer(integer) do
    form_number([{-integer, options} | rest])
  end

  def form_number([integer, {:fraction, fraction} | rest])
      when is_integer(integer) and is_integer(fraction) do
    digits = Cldr.Digits.number_of_integer_digits(fraction)
    number = integer + fraction / :math.pow(10, digits)
    form_number([number | rest])
  end

  def form_number([integer, {:exponent, exponent} | rest]) do
    form_number([(integer * :math.pow(10, exponent)) |> trunc | rest])
  end

  def form_number([integer, {:significant, significant}]) do
    {integer, significant_digits: significant}
  end

  def form_number([integer, {:margin_of_error, error}]) do
    {integer, margin_of_error: error}
  end

  def form_number([integer, {:significant, significant}, {:margin_of_error, error}]) do
    {integer, significant_digits: significant, margin_of_error: error}
  end

  def form_number([tuple]) when is_tuple(tuple) do
    tuple
  end

  def form_number(other) do
    other
  end

  def apply_fraction([{unit, value}, {:fraction, fraction} | rest]) do
    value = form_number([value, {:fraction, fraction}])
    [{unit, value} | apply_fraction(rest)]
  end

  def apply_fraction([first | rest]) do
    [first | apply_fraction(rest)]
  end

  def apply_fraction(other) do
    other
  end

  def normalize_mask([]) do
    []
  end

  def normalize_mask([{:all_of, list} | t]) do
    [list | normalize_mask(t)]
  end

  def normalize_mask([?X | t]) do
    [:X | normalize_mask(t)]
  end

  def normalize_mask([:"X*"]) do
    :"X*"
  end

  def normalize_mask([digit | t]) when digit in ?0..?9 do
    [digit - ?0 | normalize_mask(t)]
  end
end
