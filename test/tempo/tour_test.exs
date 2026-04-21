defmodule Tempo.TourTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  # `Tempo.tour/0` is the first-contact demo: it evaluates eight
  # examples live and prints them. The tests below verify that
  # the tour returns `:ok`, runs without raising, and contains the
  # key lines we advertise in the guides. If any of these break,
  # the README and market-readiness plan's claims are no longer
  # true.

  test "tour/0 returns :ok" do
    parent = self()
    _output = capture_io(fn -> send(parent, {:tour_result, Tempo.tour()}) end)
    assert_received {:tour_result, :ok}
  end

  test "tour/0 exercises the eight numbered steps" do
    output = capture_io(fn -> Tempo.tour() end)

    for n <- 1..8 do
      assert output =~ "[#{n}]", "step [#{n}] missing from tour output"
    end
  end

  test "tour/0 shows the real results of every example" do
    output = capture_io(fn -> Tempo.tour() end)

    # Step 2: Enum.count(~o"2026-06") == 30 days in June.
    assert output =~ "#=> 30"

    # Step 3: the 1560s enumerate to 1560..1569.
    assert output =~ "1560"
    assert output =~ "1569"

    # Step 4: union of 2022Y and 2023Y coalesces into 1 interval.
    assert output =~ "#=> 1"

    # Step 5: Hebrew ∩ Gregorian returns a boolean.
    assert output =~ "#=> true" or output =~ "#=> false"

    # Step 6: June 2026 has 22 workdays in the default locale.
    assert output =~ "#=> 22"

    # Step 7: leap second detected as interval metadata.
    assert output =~ "spans_leap_second?"
    assert output =~ "true"

    # Step 8: Allen's algebra — June meets July.
    assert output =~ ":meets"
  end

  test "tour/0 resets the step counter across invocations" do
    first = capture_io(fn -> Tempo.tour() end)
    second = capture_io(fn -> Tempo.tour() end)

    # Both runs should include [1] and [8] — not [9] and [16].
    assert first =~ "[1]"
    assert first =~ "[8]"
    assert second =~ "[1]"
    assert second =~ "[8]"
    refute second =~ "[9]"
  end
end
