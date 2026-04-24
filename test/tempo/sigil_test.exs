defmodule Tempo.SigilMatchTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  # Phase ① behaviour of `~o[…]` used on the LHS of a match —
  # `match?/2`, `case`, function-head patterns. The sigil expands
  # to a `%Tempo{time: [{u1, v1}, …, {un, vn} | _]}` pattern,
  # leaving `calendar`, `shift`, `extended`, `qualification`, and
  # `qualifications` unconstrained.

  describe "match?/2 with ~o[...]" do
    test "year-only sigil matches any Tempo starting with that year" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)
      assert match?(~o[2026Y], today)
    end

    test "year-only sigil does not match a different year" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)
      refute match?(~o[2025Y], today)
    end

    test "year+month sigil rejects a Tempo with a different month" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)
      refute match?(~o[2026Y01M], today)
    end

    test "year+month sigil accepts a Tempo with the same month (extra units allowed)" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)
      assert match?(~o[2026Y4M], today)
    end

    test "full date sigil matches an exact value" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)
      assert match?(~o[2026Y4M24D], today)
    end

    test "full date sigil rejects a later finer value" do
      today = Tempo.new!(year: 2026, month: 4, day: 25)
      refute match?(~o[2026Y4M24D], today)
    end

    test "datetime sigil matches a Tempo with the same head" do
      point = Tempo.new!(year: 2026, month: 6, day: 15, hour: 14, minute: 30, second: 45)
      assert match?(~o[2026Y6M15DT14H], point)
      assert match?(~o[2026Y6M15DT14H30M], point)
      assert match?(~o[2026Y6M15DT14H30M45S], point)
    end

    test "sigil with a unit the target Tempo lacks does not match" do
      bare_year = Tempo.new!(year: 2026)
      refute match?(~o[2026Y4M], bare_year)
    end

    test "calendar of target is irrelevant — only `time` is constrained" do
      hebrew = Tempo.new!(year: 2026, month: 4, day: 24, calendar: Calendrical.Hebrew)
      assert match?(~o[2026Y], hebrew)
      assert match?(~o[2026Y4M], hebrew)
    end

    test "shift / zone metadata on the target does not prevent a match" do
      zoned = Tempo.new!(year: 2026, month: 4, day: 24, hour: 10, shift: [hour: 5])
      assert match?(~o[2026Y4M24D], zoned)
    end
  end

  describe "~o[...] inside a case expression" do
    test "dispatches to the first matching branch" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)

      result =
        case today do
          ~o[2025Y] -> :last_year
          ~o[2026Y01M] -> :january
          ~o[2026Y] -> :this_year
          _ -> :other
        end

      assert result == :this_year
    end

    test "falls through to the default branch when nothing matches" do
      today = Tempo.new!(year: 2026, month: 4, day: 24)

      result =
        case today do
          ~o[2025Y] -> :nope
          ~o[2027Y] -> :still_nope
          _ -> :default
        end

      assert result == :default
    end
  end

  describe "expansion-time errors" do
    test "raises ArgumentError when used in a guard" do
      # Guards are a stricter context than matches — the existing
      # guard clause rejects them outright, and phase ① leaves
      # that behaviour unchanged.
      assert_raise ArgumentError, ~r/invalid expression in guard/, fn ->
        Code.eval_string(
          """
          import Tempo.Sigils

          fn t when t == ~o[2026Y] -> :ok end
          """,
          []
        )
      end
    end
  end
end
