* Don't allow group in time shifts

* Note doesn't support qualifications (section 8)

* Note doesn't support expanded year

* Find a way to express:
  * Astro events (Easter, New Moon, ....)
  * Workdays versus Weekends (different per locale)

* Resolve the tension in `Enumerable.Tempo.IntervalSet` semantics. An
  IntervalSet can sensibly be enumerated two ways, and we currently
  expose both behind separate names:

  1. **Sub-point walking** (current `Enumerable` default) — consistent
     with `Enumerable.Tempo` and `Enumerable.Tempo.Interval`: every
     Tempo value is a span; iterating walks the sub-points at the
     next-finer resolution. Good for calendar rendering and free/busy
     scans at minute/hour resolution.
  2. **Member-interval walking** via `Tempo.IntervalSet.to_list/1` —
     returns `[%Tempo.Interval{}]` that can be piped into `Enum` for
     scheduling, filtering, and counting use cases. Mirrors
     `Map.to_list/1` / `MapSet.to_list/1`.

  Works today but feels slightly asymmetric — users writing scheduling
  code have to remember to pipe through `to_list/1`. Options to revisit:

  * Leave as-is (preserves philosophical consistency — a Tempo value is
    always iterated as its span's sub-points; the "give me the members"
    view is a named helper).
  * Flip the default — `Enumerable` yields intervals, a named
    `to_points_stream/1` helper exposes the walk.
  * Protocol split — `Enumerable` stays as is; a separate
    `Tempo.Walkable` protocol explicitly expresses "walk the span."

  The right answer depends on which use case dominates in practice;
  defer until we have more real-world examples.

