---
layout: post
categories: [time]
title: Thinking differently about time in Elixir
---

Elixir, in common with many (most?, all?) programming languages considers `date` and `time` to be separate structures even though time is a continuum and both `date` and `time` are different representations of the same concept.

Additionally `date` and `time` are represented as a moment (or instant) in time:

* `date` represents a moment in time. That is, a `date` represents a unique moment on the timeline since the big bang.

* `time` represents a moment *within* any given `date`.  Therefore `time` is a set of moments on the universe's timeline; one moment occuring for each `date`.

So despite representing the same concepts - a moment in time - a `date` is a scalar and `time` is a set.

### What is a Date?

Your package from Amazon is scheduled to arrive on `~D[2021-01-10]`. What does that represent to you, as the receiver of the package?  I think you would say that you expect the package to arrive somewhere in the 24 hour period of January 10th, 2021.

That is, we think of a `date` as an interval of time. Does that mean that dates are enumerable?  Let's check:

```elixir
iex> Enum.map ~D[2021-01-01], &IO.puts/1
** (Protocol.UndefinedError) protocol Enumerable not implemented for ~D[2021-01-01] of type Date (a struct). This protocol is implemented for the following type(s): HashSet, Range, Map, Function, List, Stream, Date.Range, HashDict, GenEvent.Stream, MapSet, File.Stream, IO.Stream
    (elixir 1.11.2) lib/enum.ex:1: Enumerable.impl_for!/1
    (elixir 1.11.2) lib/enum.ex:141: Enumerable.reduce/3
    (elixir 1.11.2) lib/enum.ex:3461: Enum.map/2
```

No, `Date` is not enumerable in Elixir (and other languages). It's implemented as a scalar. It represents a moment in time with a precision of one day.

### What is a Time?

You have been invited to a call at `11:00` for 30 minutes. What does that signify to you? Mostly likely that the call will start at `11:00` (ignoring cultural expectations for "on time" for now).  Would you think differently is the call was scheduled for `11:00:00`?  Probably, because there is a higher precision being applied.

Depending on how the invitation was written, you may also need to ask the question "on which date"?

Since the call starts at `11:30` for 30 minutes can we enumerate those minutes?  Lets check:

```elixir
iex> Enum.map ~T[11:00], &IO.puts/1
** (ArgumentError) cannot parse "11:00" as Time for Calendar.ISO, reason: :invalid_format
    (elixir 1.11.2) lib/kernel.ex:5501: Kernel.maybe_raise!/4
    (elixir 1.11.2) lib/kernel.ex:5480: Kernel.parse_with_calendar!/3
    (elixir 1.11.2) expanding macro: Kernel.sigil_T/2
    iex:1: (file)
```

Oh, looks like we can't create a `Time` with minute precision, event though thats what we wanted. We have to specify the second and milliseconds even though thats not the precision we are after.

Let's try again:

```elixir
iex> Enum.map ~T[11:00:00], &IO.puts/1
** (Protocol.UndefinedError) protocol Enumerable not implemented for ~T[11:00:00] of type Time (a struct). This protocol is implemented for the following type(s): HashSet, Range, Map, Function, List, Stream, Date.Range, HashDict, GenEvent.Stream, MapSet, File.Stream, IO.Stream
    (elixir 1.11.2) lib/enum.ex:1: Enumerable.impl_for!/1
    (elixir 1.11.2) lib/enum.ex:141: Enumerable.reduce/3
    (elixir 1.11.2) lib/enum.ex:3461: Enum.map/2
```

No, can't do that either. `Time` is also a scalar.

### The story so far

In this short story we have considered that:

1. `Date` and `Time` are representations of the same idea - moments of time. Albeit with different levels of precision (date with a precision of day and time with a precision of milliseconds..microseconds in Elixir).

2. `Date` establishes a concrete moment in time, it is anchored on the universal timeline. `Time` establishes a moment of time within any `Date` and is therefore a set of moments.

3. `Date` and `Time` in Elixir (and other languages) are represented as moments of time. Humans are more likely to think of them as `periods of time` rather than `moments` of time.

### Introducing Tempo

I've started a new project, [Tempo](https://github.com/kipcole9/tempo) that is experimentally implementing a unified `Time` type with the following characteristics:

* `Time` is always an interval, with a given precision.  A date, therefore, is a a time interval with a precision of one day. `11:00` is a time interval with a precision of one minute.

* `Time` can be anchored or not anchored.  A date is anchored since it can be uniquely identified on the universal timeline. A time is not anchored since without knowing the date, we cannot position it on the timeline.

* `Time` is a unified structure able to represent the current Elixir `Date`, `Time` and `DateTime` structures. The differences are, after all, only two:  the precision of the time, and the anchor point of the time (dates being anchored, time being not anchored).

* `Time` can always be enumerated since it is an interval with a precision.

* Any form of time can be represented, not just `Date`, `Time` and `DateTime`. For example, it can represent "February 3rd" or even just "February". If you've made it this far then you may be thinking "hold on, you can't enumerate February without knowing if its a leap year or not!". True, `February` would first need to be composed with `2021` before enumeration.

* `Time`s can be composed.  So a time of `2021` (a year) can be composed with `February` to represent `February, 2021`.

`Tempo` will also include full support for `ISO8601-1` and `ISO8601-2` times; [interval algebra](https://en.wikipedia.org/wiki/Allen%27s_interval_algebra); recurring times and more.

It's quite a large undertaking expected to take most of 2021 to complete.  On this blog I'll update progress and experiments.

### References

* Considering time as an interval rather than a moment is not a new idea. I recommend watching [Exploring Time by Eric Evans](https://www.youtube.com/watch?v=Zm95cYAtAa8).

* Intervals in Elixir are partially implemented by [Date.Range](https://hexdocs.pm/elixir/Date.Range.html).

* The excellent [calendar_interval](https://github.com/wojtekmach/calendar_interval) library by [@wojtekmach](https://twitter.com/wojtekmach?lang=en) implements calendar intervals.

