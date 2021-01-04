---
layout: post
categories: [cldr, i18n, l10n, locale, language_tag]
title: Localised formatting of datetimes in Elixir 1.11
---

[Elixir 1.11](https://elixir-lang.org/blog/2020/10/06/elixir-v1-11-0-released/) introduces `Calendar.strftime/3` which provides datetime formatting based on the strftime format. It provides an hook to return localised content for datetime formatting.

### Calendar.strftime/3

The datetime can be any of the Calendar types (Time, Date, NaiveDateTime, and
DateTime) or any map, as long as they contain all of the relevant fields
necessary for formatting. For example, if you use %Y to format the year, the
datetime must have the :year field. Therefore, if you pass a Time, or a map
without the :year field to a format that expects %Y, an error will be raised.

#### Options

  • :preferred_datetime - a string for the preferred format to show
    datetimes, it can't contain the %c format and defaults to "%Y-%m-%d
    %H:%M:%S" if the option is not received
  • :preferred_date - a string for the preferred format to show dates, it
    can't contain the %x format and defaults to "%Y-%m-%d" if the option is not
    received
  • :preferred_time - a string for the preferred format to show times, it
    can't contain the %X format and defaults to "%H:%M:%S" if the option is not
    received
  • :am_pm_names - a function that receives either :am or :pm and returns
    the name of the period of the day, if the option is not received it
    defaults to a function that returns "am" and "pm", respectively
  •  :month_names - a function that receives a number and returns the name
    of the corresponding month, if the option is not received it defaults to a
    function that returns the month names in English
  • :abbreviated_month_names - a function that receives a number and
    returns the abbreviated name of the corresponding month, if the option is
    not received it defaults to a function that returns the abbreviated month
    names in English
  • :day_of_week_names - a function that receives a number and returns the
    name of the corresponding day of week, if the option is not received it
    defaults to a function that returns the day of week names in English
  • :abbreviated_day_of_week_names - a function that receives a number and
    returns the abbreviated name of the corresponding day of week, if the
    option is not received it defaults to a function that returns the
    abbreviated day of week names in English

#### Formatting syntax

The formatting syntax for strftime is a sequence of characters in the following
format:

    %<padding><width><format>

where:

  • %: indicates the start of a formatted section
  • <padding>: set the padding (see below)
  • <width>: a number indicating the minimum size of the formatted section
  • <format>: the format itself (see below)

#### Accepted padding options

  • -: no padding, removes all padding from the format
  • _: pad with spaces
  • 0: pad with zeroes

#### Accepted formats

The accepted formats are:

Format | Description                                                   | Examples (in ISO)
------ | ------------------------------------------------------------- | ------------------
a      | Abbreviated name of day                                       | Mon
A      | Full name of day                                              | Monday
b      | Abbreviated month name                                        | Jan
B      | Full month name                                               | January
c      | Preferred date+time representation                            | 2018-10-17 12:34:56
d      | Day of the month                                              | 01, 12
f      | Microseconds (does not support width and padding modifiers)   | 000000, 999999, 0123
H      | Hour using a 24-hour clock                                    | 00, 23
I      | Hour using a 12-hour clock                                    | 01, 12
j      | Day of the year                                               | 001, 366
m      | Month                                                         | 01, 12
M      | Minute                                                        | 00, 59
p      | "AM" or "PM" (noon is "PM", midnight as "AM")                 | AM, PM
P      | "am" or "pm" (noon is "pm", midnight as "am")                 | am, pm
q      | Quarter                                                       | 1, 2, 3, 4
S      | Second                                                        | 00, 59, 60
u      | Day of the week                                               | 1 (Monday), 7 (Sunday)
x      | Preferred date (without time) representation                  | 2018-10-17
X      | Preferred time (without date) representation                  | 12:34:56
y      | Year as 2-digits                                              | 01, 01, 86, 18
Y      | Year                                                          | -0001, 0001, 1986
z      | +hhmm/-hhmm time zone offset from UTC (empty string if naive) | +0300, -0530
Z      | Time zone abbreviation (empty string if naive)                | CET, BRST
%      | Literal "%" character

#### Examples

Without options:

    iex> Calendar.strftime(~U[2019-08-26 13:52:06.0Z], "%y-%m-%d %I:%M:%S %p")
    "19-08-26 01:52:06 PM"

    iex> Calendar.strftime(~U[2019-08-26 13:52:06.0Z], "%a, %B %d %Y")
    "Mon, August 26 2019"

    iex> Calendar.strftime(~U[2019-08-26 13:52:06.0Z], "%c")
    "2019-08-26 13:52:06"

With options:

    iex> Calendar.strftime(~U[2019-08-26 13:52:06.0Z], "%c", preferred_datetime: "%H:%M:%S %d-%m-%y")
    "13:52:06 26-08-19"

### Localised Options

[ex_cldr_dates_times](https://hex.pm/packages/ex_cldr_dates_times) includes the function `strftime_options!/2` that returns a keyword list of options that can be given directly to `Calendar.strftime/3`.

#### Arguments

  • locale is any locale returned by `Cldr.known_locale_names/0`. The
    default is `Cldr.get_locale/0`

  • options is a set of keyword options. The default is []

#### Options

  • `:calendar` is the name of any known CLDR calendar. The default is
    `:gregorian`.

#### Example

    iex: MyApp.Cldr.Calendar.strftime_options!
    [
      am_pm_names: #Function<0.32021692/1 in MyApp.Cldr.Calendar.strftime_options/2>,
      month_names: #Function<1.32021692/1 in MyApp.Cldr.Calendar.strftime_options/2>,
      abbreviated_month_names: #Function<2.32021692/1 in MyApp.Cldr.Calendar.strftime_options/2>,
      day_of_week_names: #Function<3.32021692/1 in MyApp.Cldr.Calendar.strftime_options/2>,
      abbreviated_day_of_week_names: #Function<4.32021692/1 in MyApp.Cldr.Calendar.strftime_options/2>
    ]

##### Typical usage

    iex: NimbleStrftime.format(Date.today(), MyApp.Cldr.Calendar.strftime_options!())
