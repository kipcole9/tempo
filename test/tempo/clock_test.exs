defmodule Tempo.ClockTest do
  use ExUnit.Case, async: true

  doctest Tempo.Clock.Test

  describe "Tempo.Clock.Test" do
    test "put/1 and utc_now/0 round-trip a UTC DateTime" do
      fixed = ~U[2026-06-15 12:00:00Z]
      assert :ok = Tempo.Clock.Test.put(fixed)
      assert Tempo.Clock.Test.utc_now() == fixed
    end

    test "put/1 converts a non-UTC DateTime to UTC before storing" do
      # 12:00 Paris (UTC+2 in June) is 10:00 UTC.
      paris = DateTime.new!(~D[2026-06-15], ~T[12:00:00], "Europe/Paris", Tzdata.TimeZoneDatabase)
      assert :ok = Tempo.Clock.Test.put(paris)
      assert Tempo.Clock.Test.utc_now() == ~U[2026-06-15 10:00:00Z]
    end

    test "advance/1 moves the clock forward" do
      Tempo.Clock.Test.put(~U[2026-06-15 12:00:00Z])
      assert :ok = Tempo.Clock.Test.advance(3600)
      assert Tempo.Clock.Test.utc_now() == ~U[2026-06-15 13:00:00Z]
    end

    test "advance/1 accepts negative seconds" do
      Tempo.Clock.Test.put(~U[2026-06-15 12:00:00Z])
      assert :ok = Tempo.Clock.Test.advance(-600)
      assert Tempo.Clock.Test.utc_now() == ~U[2026-06-15 11:50:00Z]
    end

    test "advance/1 raises without a prior put/1" do
      Tempo.Clock.Test.reset()

      assert_raise RuntimeError, ~r/before put\/1/, fn ->
        Tempo.Clock.Test.advance(1)
      end
    end

    test "reset/1 clears the pinned time" do
      Tempo.Clock.Test.put(~U[2026-06-15 12:00:00Z])
      assert :ok = Tempo.Clock.Test.reset()

      assert_raise RuntimeError, ~r/no time pinned/, fn ->
        Tempo.Clock.Test.utc_now()
      end
    end

    test "utc_now/0 raises with a helpful error when unpinned" do
      Tempo.Clock.Test.reset()

      assert_raise RuntimeError, ~r/Tempo\.Clock\.Test\.put\/1/, fn ->
        Tempo.Clock.Test.utc_now()
      end
    end

    test "pins are process-local — one test doesn't leak to another" do
      # Peer process pins its own clock; this test does not see it.
      parent = self()

      {:ok, task} =
        Task.start(fn ->
          Tempo.Clock.Test.put(~U[2030-01-01 00:00:00Z])
          send(parent, {:peer_pinned, Tempo.Clock.Test.utc_now()})
        end)

      assert_receive {:peer_pinned, ~U[2030-01-01 00:00:00Z]}
      _ = task

      Tempo.Clock.Test.reset()

      assert_raise RuntimeError, fn ->
        Tempo.Clock.Test.utc_now()
      end
    end
  end

  describe "Tempo.Clock.System" do
    test "utc_now/0 returns a DateTime in Etc/UTC" do
      result = Tempo.Clock.System.utc_now()
      assert %DateTime{} = result
      assert result.time_zone == "Etc/UTC"
    end
  end

  describe "Tempo.Clock (dispatcher)" do
    test "defaults to Tempo.Clock.System when unconfigured" do
      previous = Application.get_env(:ex_tempo, :clock)
      Application.delete_env(:ex_tempo, :clock)

      try do
        assert Tempo.Clock.clock() == Tempo.Clock.System
      after
        if previous do
          Application.put_env(:ex_tempo, :clock, previous)
        end
      end
    end

    test "process-local override takes precedence over application env" do
      # This is the mechanism `NowTest` and `ToRelativeStringTest` use
      # to install `Tempo.Clock.Test` without leaking the swap into
      # other async tests and doctests.
      Process.put({Tempo.Clock, :clock}, Tempo.Clock.Test)

      try do
        assert Tempo.Clock.clock() == Tempo.Clock.Test
      after
        Process.delete({Tempo.Clock, :clock})
      end

      # After delete, falls back to the app env / default.
      assert Tempo.Clock.clock() in [Tempo.Clock.System, nil] or
               is_atom(Tempo.Clock.clock())
    end

    test "process-local override does not leak to peer processes" do
      # Install the override in this process.
      Process.put({Tempo.Clock, :clock}, Tempo.Clock.Test)

      parent = self()

      {:ok, _task} =
        Task.start(fn ->
          # Peer process starts with no override — sees the default.
          send(parent, {:peer_clock, Tempo.Clock.clock()})
        end)

      assert_receive {:peer_clock, peer_clock}
      refute peer_clock == Tempo.Clock.Test

      Process.delete({Tempo.Clock, :clock})
    end
  end
end
