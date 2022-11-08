# Tempo

> “Time has no divisions to mark its passage, there is never a thunderstorm or blare of trumpets to announce the beginning of a new month or year. Even when a new century begins it is only we mortals who ring bells and fire off pistols.” Thomas Mann, The Magic Mountain, ch. 5, “Whims of Mercurius,” (1924), trans. by Helen T. Lowe-Porter (1928).

A Time library based upon conceptualizing time as intervals rather than instants.  A blog of the ideas behind this library is at [https://kipcole9.github.io/tempo/](https://kipcole9.github.io/tempo/).

**There is not much to see here yet, the current work is on implementing full support for ISO8601 dates/times (both part 1 and part 2).**

## ElixirConf 22 Video on Time Algebra

A talk that introduces a unified time type and builds on the idea of time as intervals is [now on Youtube](https://www.youtube.com/watch?v=4VfPvCI901c).

## Project status

Whilst the commit volume is currently low, the mental effort going into the conceptual model is high. Expect more active progress in this repo during December 2022.  The primary effort for the next updates will be time math (which is important for calculating explicit intervals and time differences) and time comparison (which is creating a very active discussion on the [elixir-lang core mailing list](https://groups.google.com/g/elixir-lang-core/c/W2TeQm5r1H4)).

## Installation

Tempo is not yet available for installation from `hex.pm`. And since it has basically no functional utility at the moment, installing it would only be for experimentation and amusement.

```elixir
def deps do
  [
    {:tempo, "~> 0.1.0", github: "kipcole9/tempo"}
  ]
end
```

The docs will be found at [https://hexdocs.pm/tempo](https://hexdocs.pm/tempo).

