---
layout: post
categories: [cldr, i18n, l10n]
title: Making Localisation Simple
---

With simplication in mind, since [ex_cldr 2.14.0](https://hex.pm/packages/ex_cldr/2.14) the `Cldr.Chars` protocol is provided to make it super simple to localise common data representations. In this post we look at the simplest possible way to localise data using the default formats and options for a given locale.  At the most basic level, changing existing calls to `to_string/1` into `Cldr.to_string/1` will produce localised output for a given data type.

`Cldr.to_string/1` will produce localised output for:

* Integers, floats and decimals
* Date, NaiveDateTime, DateTime and Time
* Units of measure (the `Cldr.Unit` struct)

It is deliberately modelled after the `String.Chars` protocol that is part of core Elixir.

### Number formatting examples

```elixir
# In the default locale. For this example it's "en"
iex> Cldr.to_string 1234
"1,234"
iex> Cldr.to_string 1234.567
"1,234.567"
iex> Cldr.to_string Decimal.new(1234)
"1,234"

# In the "fr" locale
iex> Cldr.put_locale "fr"
iex> Cldr.to_string 1234
"1 234"
```

### Date, Time and DateTime examples

```elixir
iex> Cldr.to_string Date.utc_today
"Nov 3, 2020"
iex> Cldr.to_string Time.utc_now
"5:37:26 AM"
iex> Cldr.to_string DateTime.utc_now
"Nov 3, 2020, 5:37:32 AM"

# In the "ja" locale
iex> Cldr.put_locale "ja"
iex> Cldr.to_string Date.utc_today
"2020/11/03"
iex> Cldr.to_string Time.utc_now
"5:38:08"
iex> Cldr.to_string DateTime.utc_now
"2020/11/03 5:38:10"
```

### Units of Measure

This is probably my favourite. From [CLDR 37](http://cldr.unicode.org/index/downloads/cldr-37) and [ex_cldr 2.14](https://hex.pm/packages/ex_cldr/2.14.0) there is a good data to support units of measure, unit conversion and localed unit preferences.

```elixir
iex> Cldr.to_string Cldr.Unit.new!(3, :foot)
"3 feet"
iex> Cldr.to_string Cldr.Unit.new!(1, :foot)
"1 foot"
iex> Cldr.to_string Cldr.Unit.new!(3, :foot)
"3 feet"
iex> Cldr.to_string Cldr.Unit.new!(3, :gallon)
"3 gallons"
iex> Cldr.to_string Cldr.Unit.new!(3, :meter)
"3 meters"

# Very flexible compound units can be interpreted
iex> Cldr.to_string Cldr.Unit.new!(3, "light_year_per_cubic_meter")
"3 light years per cubic meter"

# And localised too, of course
iex> Cldr.put_locale "ja"
iex> Cldr.to_string Cldr.Unit.new!(3, "light_year_per_cubic_meter")
"3 光年毎 立方メートル"

# For specific uses
iex> Cldr.to_string Cldr.Unit.new!(2, :meter, usage: :person_height)
"2 meters"

iex> Cldr.put_locale "ja"
iex> Cldr.to_string Cldr.Unit.new!(2, :meter, usage: :person_height)
"2 メートル"

# Of course units can be localised
# This example converts meters to feet and inches which is the
# preference for "en-US"
iex> Cldr.Unit.localize height, locale: "en-US"
[#Cldr.Unit<:foot, 6>,
 #Cldr.Unit<:inch, 37008780297879768 <|> 5490788665690109>]
iex> localised_height = Cldr.Unit.localize height, locale: "en-US"
[#Cldr.Unit<:foot, 6>,
 #Cldr.Unit<:inch, 37008780297879768 <|> 5490788665690109>]
iex> Cldr.to_string localised_height
"6 feet and 6.74 inches"
```

### Lists

In the previous example, the list `[#Cldr.Unit<:foot, 6>, #Cldr.Unit<:inch, 37008780297879768 <|> 5490788665690109>]` was output by `Cldr.to_string/1` as `6 feet and 6.74 inches`. This is because CLDR specifies rules for how to combine lists into a localised string.  The process is quite simple: map each element of the list with `Cldr.to_string/1` and then combine the list elements in a locale-specific fashion. For example:

```elixir
iex> Cldr.to_string ["a", "b"]
"a and b"
iex> Cldr.to_string ["a", "b", "c"]
"a, b, and c"

iex> Cldr.put_locale "fr"
iex> Cldr.to_string ["a", "b"]
"a et b"
iex> Cldr.to_string ["a", "b", "c"]
"a, b et c"
```

### Summary of simple localisation

Localisation for common data types is easily accomplished by calling `Cldr.to_string/1` on the data item. Sensible formatting defaults are applied in a locale-specific fashion.

Of course more control over the formatting process is available by calling `to_string/2` on the specific formatter for a given data type. We'll cover these examples in the next few posts.

