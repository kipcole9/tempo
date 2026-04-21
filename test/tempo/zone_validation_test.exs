defmodule Tempo.ZoneValidationTest do
  use ExUnit.Case, async: true

  # Parse-time validation of zoned wall times: during a DST
  # spring-forward, an hour of local time doesn't exist. ISO 8601
  # permits the syntax; Tempo rejects the semantics so downstream
  # operations never encounter a phantom value.
  #
  # The test fixtures use America/New_York because its DST
  # schedule is well-defined in Tzdata and stable:
  #
  #   * Spring forward: second Sunday of March at 02:00 →  03:00.
  #     2024-03-10 02:00..03:00 local doesn't exist.
  #
  #   * Fall back: first Sunday of November at 02:00 → 01:00.
  #     2024-11-03 01:00..02:00 local exists twice (ambiguous).

  describe "zone-gap rejection (DST spring-forward)" do
    test "2024-03-10 02:30 America/New_York is rejected" do
      assert {:error, message} =
               Tempo.from_iso8601("2024-03-10T02:30:00[America/New_York]")

      assert message =~ "does not exist"
      assert message =~ "America/New_York"
    end

    test "every minute in the gap is rejected" do
      for minute <- [0, 15, 30, 45, 59] do
        assert {:error, _} =
                 Tempo.from_iso8601("2024-03-10T02:#{pad(minute)}:00[America/New_York]"),
               "Expected 2024-03-10T02:#{pad(minute)} to be rejected"
      end
    end

    test "the error message points at the zone name" do
      assert {:error, message} =
               Tempo.from_iso8601("2024-03-10T02:30:00[America/New_York]")

      assert message =~ "\"America/New_York\""
    end
  end

  describe "valid zoned wall times (adjacent to DST gap)" do
    test "01:30 (one minute before the gap) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T01:30:00[America/New_York]")
    end

    test "01:59:59 (immediately before) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T01:59:59[America/New_York]")
    end

    test "03:00 (first valid instant after the gap) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T03:00:00[America/New_York]")
    end

    test "03:30 (in the post-DST hour) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T03:30:00[America/New_York]")
    end
  end

  describe "DST fall-back ambiguity" do
    # Nov 3 2024 at 01:30 exists twice in America/New_York — once
    # at UTC-4 (EDT) before the fall-back, once at UTC-5 (EST)
    # after. Without an explicit disambiguator, Tempo picks the
    # first period (EDT); an explicit offset via `±HH:MM[zone]`
    # picks the matching period per RFC 9557 §4.5.

    test "2024-11-03 01:30 America/New_York parses" do
      assert {:ok, _} = Tempo.from_iso8601("2024-11-03T01:30:00[America/New_York]")
    end

    test "explicit -04:00 picks the EDT (pre-fall-back) period" do
      pre_fb = Tempo.from_iso8601!("2024-11-03T01:30:00-04:00[America/New_York]")
      plain = Tempo.from_iso8601!("2024-11-03T01:30:00[America/New_York]")

      # Same UTC instant as the no-offset default (which also
      # picks EDT as the first period).
      assert Tempo.Compare.to_utc_seconds(pre_fb) == Tempo.Compare.to_utc_seconds(plain)
    end

    test "explicit -05:00 picks the EST (post-fall-back) period" do
      post_fb = Tempo.from_iso8601!("2024-11-03T01:30:00-05:00[America/New_York]")
      pre_fb = Tempo.from_iso8601!("2024-11-03T01:30:00-04:00[America/New_York]")

      # One hour later in UTC — the repeated hour.
      assert Tempo.Compare.to_utc_seconds(post_fb) -
               Tempo.Compare.to_utc_seconds(pre_fb) == 3600
    end

    test "an offset that matches no period falls back to the first" do
      # +00:00 is neither EDT (-04) nor EST (-05); Tempo falls
      # back to the first period (EDT).
      ambiguous = Tempo.from_iso8601!("2024-11-03T01:30:00+00:00[America/New_York]")
      default = Tempo.from_iso8601!("2024-11-03T01:30:00[America/New_York]")

      assert Tempo.Compare.to_utc_seconds(ambiguous) ==
               Tempo.Compare.to_utc_seconds(default)
    end
  end

  describe "check is inert when not applicable" do
    test "no zone → no check" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T02:30:00")
    end

    test "coarser than minute-resolution → no check even if zone present" do
      # `2024-03-10T02[America/New_York]` spans the entire 02:00
      # hour, which includes both valid and gap minutes. Since the
      # value represents the hour as a whole (resolution :hour),
      # there's no single wall time to validate.
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T02[America/New_York]")
    end

    test "date-only with zone → no check (no time component)" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10[America/New_York]")
    end

    test "numeric-offset zones (not IANA) → no check" do
      # `+05:30` isn't an IANA zone — no Tzdata lookup possible,
      # and the offset is a first-class wall-clock shift.
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T02:30:00+05:30")
    end
  end

  describe "IANA backward-compat aliases" do
    # Tzdata carries the `backward` alias file which maps
    # retired/renamed zone names to their modern equivalents.
    # Tempo accepts these transparently — the alias label is
    # preserved on the struct; `to_utc_seconds/1` resolves via
    # Tzdata using the alias's canonical zone.

    test "US/Pacific parses and round-trips" do
      assert {:ok, tempo} = Tempo.from_iso8601("2024-06-15T12:00:00[US/Pacific]")
      assert tempo.extended.zone_id == "US/Pacific"
      # Offset matches America/Los_Angeles (the canonical zone).
      assert is_integer(Tempo.Compare.to_utc_seconds(tempo))
    end

    test "Asia/Calcutta (renamed to Asia/Kolkata) parses" do
      assert {:ok, _} = Tempo.from_iso8601("2024-06-15T12:00:00[Asia/Calcutta]")
    end

    test "Pacific/Kanton (renamed from Pacific/Enderbury) parses" do
      assert {:ok, _} = Tempo.from_iso8601("2024-06-15T12:00:00[Pacific/Kanton]")
    end
  end

  describe "historical zone offsets" do
    test "Europe/London during British Double Summer Time (1941) projects to UTC+2" do
      # BDST applied 1941-05-04 to 1945-07-15 — clocks ran 2h
      # ahead of UTC instead of the usual 1h summer offset. A
      # correct implementation must consult Tzdata's historical
      # period table rather than today's offset.
      {:ok, london} = Tempo.from_iso8601("1941-06-15T12:00:00[Europe/London]")
      {:ok, utc} = Tempo.from_iso8601("1941-06-15T12:00:00Z")

      # London wall = UTC wall + 2h, so London's UTC projection
      # is 2h earlier than the same wall-clock at UTC.
      diff = Tempo.Compare.to_utc_seconds(utc) - Tempo.Compare.to_utc_seconds(london)
      assert diff == 7200
    end
  end

  describe "exact DST gap boundary seconds" do
    test "02:00:00 (first instant of the gap) is rejected" do
      assert {:error, _} = Tempo.from_iso8601("2024-03-10T02:00:00[America/New_York]")
    end

    test "02:59:59 (last instant of the gap) is rejected" do
      assert {:error, _} = Tempo.from_iso8601("2024-03-10T02:59:59[America/New_York]")
    end

    test "01:59:59 (last valid instant before the gap) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T01:59:59[America/New_York]")
    end

    test "03:00:00 (first valid instant after the gap) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T03:00:00[America/New_York]")
    end
  end

  describe "numeric offset bounds — reject nonsensical offsets" do
    # Real UTC offsets are bounded. The widest modern zone is
    # +14:00 (Pacific/Kiritimati) and the narrowest is −12:00
    # (Pacific/Midway until 2011, and a few others).  ±24h is a
    # permissive bound that rejects clear nonsense like +25:00.

    test "+25:00 inline is rejected" do
      assert {:error, message} = Tempo.from_iso8601("2024-03-10T12:00:00+25:00")
      assert message =~ "out of range"
    end

    test "-25:00 inline is rejected" do
      assert {:error, message} = Tempo.from_iso8601("2024-03-10T12:00:00-25:00")
      assert message =~ "out of range"
    end

    test "+14:00 inline (Pacific/Kiritimati) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T12:00:00+14:00")
    end

    test "-12:00 inline is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T12:00:00-12:00")
    end

    test "+24:00 (the boundary) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T12:00:00+24:00")
    end

    test "Z (UTC) is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T12:00:00Z")
    end

    test "IXDTF [+25:00] is rejected" do
      assert {:error, message} = Tempo.from_iso8601("2024-03-10T12:00:00[+25:00]")
      assert message =~ "out of range"
    end

    test "IXDTF [+14:00] is accepted" do
      assert {:ok, _} = Tempo.from_iso8601("2024-03-10T12:00:00[+14:00]")
    end
  end

  describe "zone-gap check applies recursively to intervals" do
    test "interval with gap endpoint is rejected" do
      assert {:error, _} =
               Tempo.from_iso8601(
                 "2024-03-10T02:30:00[America/New_York]/2024-03-10T05:00:00[America/New_York]"
               )
    end

    test "interval with both valid endpoints is accepted" do
      assert {:ok, _} =
               Tempo.from_iso8601(
                 "2024-03-10T01:30:00[America/New_York]/2024-03-10T05:00:00[America/New_York]"
               )
    end
  end

  describe "duration correctness across DST (no bug to fix; guard test)" do
    # These tests assert that `Tempo.Interval.duration/1` already
    # accounts for DST transitions via `to_utc_seconds/1` —
    # protecting against future regressions.

    test "24 wall-clock hours across spring-forward = 23 real hours" do
      from = Tempo.from_iso8601!("2024-03-09T12:00:00[America/New_York]")
      to = Tempo.from_iso8601!("2024-03-10T12:00:00[America/New_York]")
      iv = %Tempo.Interval{from: from, to: to}

      # 23h = 82800s. The hour between 02:00 and 03:00 was skipped.
      assert Tempo.Interval.duration(iv) == %Tempo.Duration{time: [second: 82800]}
    end

    test "24 wall-clock hours across fall-back = 25 real hours" do
      from = Tempo.from_iso8601!("2024-11-02T12:00:00[America/New_York]")
      to = Tempo.from_iso8601!("2024-11-03T12:00:00[America/New_York]")
      iv = %Tempo.Interval{from: from, to: to}

      # 25h = 90000s. The hour between 01:00 and 02:00 was repeated.
      assert Tempo.Interval.duration(iv) == %Tempo.Duration{time: [second: 90000]}
    end

    test "24 wall-clock hours outside any transition = 24 real hours" do
      from = Tempo.from_iso8601!("2024-06-15T12:00:00[America/New_York]")
      to = Tempo.from_iso8601!("2024-06-16T12:00:00[America/New_York]")
      iv = %Tempo.Interval{from: from, to: to}

      assert Tempo.Interval.duration(iv) == %Tempo.Duration{time: [second: 86400]}
    end

    test "unzoned interval ignores zone math" do
      from = Tempo.from_iso8601!("2024-03-09T12:00:00")
      to = Tempo.from_iso8601!("2024-03-10T12:00:00")
      iv = %Tempo.Interval{from: from, to: to}

      # No zone → plain wall-clock delta of 24h.
      assert Tempo.Interval.duration(iv) == %Tempo.Duration{time: [second: 86400]}
    end
  end

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"
end
