defmodule Tempo.RRule.Rule do
  @moduledoc """
  A canonical, typed representation of an RFC 5545 RRULE.

  This is the input to `Tempo.RRule.Expander.expand/3`. Every
  parser (`Tempo.RRule.parse/2`, the `ical` library's
  `%ICal.Recurrence{}`, hand-built rules for tests) converts to
  this shape before expansion runs. Keeping a single struct means
  the expander has one input vocabulary to match against, and all
  `BY*` fields carry their RFC-typed form: lists of integers with
  negative values permitted where the RFC allows.

  ### Fields

  * `:freq` — one of `:second`, `:minute`, `:hour`, `:day`,
    `:week`, `:month`, `:year`. Required.

  * `:interval` — positive integer multiplier for the frequency.
    Default `1`.

  * `:count` — terminate after this many occurrences. Mutually
    exclusive with `:until` per RFC 5545.

  * `:until` — terminate at or before this `t:Tempo.t/0`. Mutually
    exclusive with `:count`.

  * `:wkst` — week-start day as an integer 1–7 (Monday–Sunday, ISO
    convention). Default `1`. Affects `:byweekno` calculations.

  * `:bymonth` — list of integers 1–12. Limit.

  * `:bymonthday` — list of integers -31..31 (negatives count from
    the end of the month). Limit or expand per FREQ.

  * `:byyearday` — list of integers -366..366. Limit or expand
    per FREQ.

  * `:byweekno` — list of integers -53..53. Used only with
    `:yearly` FREQ. Limit or expand.

  * `:byday` — list of `{ordinal_or_nil, weekday_1_to_7}` tuples.
    With MONTHLY / YEARLY and no BYWEEKNO, ordinals select the
    Nth/-Nth weekday within the period. With other FREQs,
    ordinals are ignored (filter only).

  * `:byhour` / `:byminute` / `:bysecond` — lists of integers.
    Limit or expand per FREQ.

  * `:bysetpos` — list of integers; applied last to pick the Nth
    element of the per-period candidate set.

  """

  @type frequency :: :second | :minute | :hour | :day | :week | :month | :year
  @type weekday :: 1..7
  @type byday_entry :: {integer() | nil, weekday()}

  @type t :: %__MODULE__{
          freq: frequency(),
          interval: pos_integer(),
          count: pos_integer() | nil,
          until: Tempo.t() | nil,
          wkst: weekday(),
          bymonth: [integer()] | nil,
          bymonthday: [integer()] | nil,
          byyearday: [integer()] | nil,
          byweekno: [integer()] | nil,
          byday: [byday_entry()] | nil,
          byhour: [non_neg_integer()] | nil,
          byminute: [non_neg_integer()] | nil,
          bysecond: [non_neg_integer()] | nil,
          bysetpos: [integer()] | nil
        }

  defstruct freq: nil,
            interval: 1,
            count: nil,
            until: nil,
            wkst: 1,
            bymonth: nil,
            bymonthday: nil,
            byyearday: nil,
            byweekno: nil,
            byday: nil,
            byhour: nil,
            byminute: nil,
            bysecond: nil,
            bysetpos: nil

  @doc """
  Does the rule include any `BY*` modifier?

  `true` when any `BY*` field is non-nil. Used by the expander to
  skip the BY-rule pipeline entirely for simple FREQ-only rules.

  ### Examples

      iex> Tempo.RRule.Rule.has_by_rules?(%Tempo.RRule.Rule{freq: :weekly})
      false

      iex> Tempo.RRule.Rule.has_by_rules?(%Tempo.RRule.Rule{freq: :weekly, byday: [{nil, 1}]})
      true

  """
  @spec has_by_rules?(t()) :: boolean()
  def has_by_rules?(%__MODULE__{} = rule) do
    Enum.any?(
      [
        rule.bymonth,
        rule.bymonthday,
        rule.byyearday,
        rule.byweekno,
        rule.byday,
        rule.byhour,
        rule.byminute,
        rule.bysecond,
        rule.bysetpos
      ],
      &(&1 != nil)
    )
  end
end
