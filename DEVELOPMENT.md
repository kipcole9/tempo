## Notes

### On Implicit and Explicit intervals

An implicit interval, such as `2022` is equalivent to the explicit interval `2022-01/12`. The transformation proceeds as follows:

1. Enumeration for implicit intervals occurs at the next highest zoom level (greater resolution). In this case is is months.
2. The end of the interval is a closed at month 12.
3. Therefore we can say the implicit interval is closed and equivalent to the set `{2022-01, 2022-02, ..., 2022-12}`

### On conversion between explicit and implicit intervals

* Implicit intervals can always be converted to explicit intervals or a set of explicit intervals
* Not all explicit intervals can be converted to implicit ones.
* The explicit interval for `2022` is `2022/2022` since it is a closed interval of `[2022]`

### Explicit intervals

* Parsing should extend the end of the interval with the units of lower resolution in the beginning of the interval
* Both parts of the interval should have the same resolution. When they are different, what is the treatment????  Looks like the standard says that the interval end inherits the higher resolution time units from the interval start.  But what if the interval end has higher resolution? The standard appears silent on the topic so we will extend the interval start with higher resolution units from the interval end, but with initial values (ie 1 or 0)

### Timezones

A [proposed extension](https://datatracker.ietf.org/doc/draft-ietf-sedate-datetime-extended/) to [rfc3339](https://www.rfc-editor.org/rfc/rfc3339) specifies a mechanism to add metadata, including timezones, to a RFC3339 datetime.  RFC3339 is a profile of ISO8601 that is largely the "extended" syntax of ISO8601 limited to the capability of Part 1.  Therefore ISO8601 is a superset of RFC3339.

The ABNF of the extension mechanism is described as follows and will be used for implementation in Tempo.  Since a timezone offset and a timezone extension name may be in conflict, the "Critical" flag is used to raise an exception if the explicit offset and the implicit offset (of the timezone name) do not match.

If the Critical flag is not provided, then the policy will be that the time zone name will take precedence. The extension proposal explicitly calls out that the policy to apply is implementation dependent, hence the clarity required here.

### Handling ambiguous times

There are ambiguities when changing to an from daylight savings. When jumping forward there is a discontinuity in the hours (typically jumping from 1:59am to 3:59am). And when moving back, there are two time occurences with the same hour (typicaly 2am).  How can we resolve this in Tempo?  Python [PEP 495](https://peps.python.org/pep-0495/#proposal) proposed adding a `fold` attribute to datetimes to disambiguate and Tempo will follow a similar approach when enumerating discontinuous or ambiguous time ranges.

### Masks

Masks are a way of expressing integer values with unspecified digits.

The unspecified value character "X" is used to indicate unspecified digits or values in time scale components.
In explicit forms of time scale components:
* the unspecified value character followed by a "*" ("X*") indicates that the entire value is unspecified;
* the unspecified value character "X" is used as a replacement for any digit in a time scale component value to indicate that the digit is unspecified.

#### Examples

* `195XY` expresses an unspecified calendar year in the 1950s.
* `1390YXXM` expresses a two-digit calendar month in 1390.
* `2052Y1MX*D` expresses some calendar day in January 2052.
* `XXXYX*MXD` expresses a one-digit calendar day of a calendar month in a three-digit calendar year. 
* `X*Y12M28D` expresses December 28th of an unspecified calendar year.

### Extensions

The [RFC3339 proposed extensions mechanism](https://datatracker.ietf.org/doc/draft-ietf-sedate-datetime-extended/) also allows additional metadata to be attached to a date time. The key `u-ca` is based upon BCP47 "U" extension tag and is therefore aligned with the [CLDR locale extension](http://www.unicode.org/reports/tr35/#Locale_Extension_Key_and_Type_Data).

For Tempo we extend this somewhat in the following way:

1. The entire BCP47 "U" syntax can be supplied as an extension. It can therefore convey more than just the calendar (for example, number system).
2. The 'u-ca`  calendar must follow the CLDR calendar syntax which cannot represent the arbitrary calendars that can be defined in Elixir.
3. Therefore we introduce an additional suffix key `calendar` which can carry any Elixir module name as a string that represents an Elixir calendar representation.

### Relationship to ex_cldr

In the case where no calendar is specified by an extension, the calendar specified by `Cldr.get_locale/0` will be used. This is most commonly `Cldr.Calendar.Gregorian` which is a proleptic Gregorian calendar that is compatible with the Elixir standard `Calendar.ISO`.

In effect, we merge the current locale (`Cldr.get_locale/`) with the data derived from the extensions, into an "effective locale" used for this date/time.

### Extension ABNF syntax

```
time-zone-initial = ALPHA / "." / "_"
time-zone-char    = time-zone-initial / DIGIT / "-" / "+"
time-zone-part    = time-zone-initial *13(time-zone-char)
                   ; but not "." or ".."
time-zone-name    = time-zone-part *("/" time-zone-part)
time-zone         = "[" critical-flag
                       time-zone-name / time-numoffset "]"

key-initial       = ALPHA / "_"
key-char          = key-initial / DIGIT / "-"
suffix-key        = key-initial *key-char

suffix-value      = 1*alphanum
suffix-values     = suffix-value *("-" suffix-value)
suffix-tag        = "[" critical-flag
                       suffix-key "=" suffix-values "]"
suffix            = [time-zone] *suffix-tag

date-time-ext     = date-time suffix

critical-flag     = [ "!" ]

alphanum          = ALPHA / DIGIT
```

