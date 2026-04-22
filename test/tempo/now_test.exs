defmodule Tempo.NowTest do
  use ExUnit.Case, async: true

  # Save the application-wide clock setting and install
  # Tempo.Clock.Test for the duration of each test. async: true is
  # safe because Tempo.Clock.Test stores its pin in the calling
  # process's dictionary.
  setup do
    previous = Application.get_env(:ex_tempo, :clock)
    Application.put_env(:ex_tempo, :clock, Tempo.Clock.Test)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:ex_tempo, :clock)
        module -> Application.put_env(:ex_tempo, :clock, module)
      end
    end)

    :ok
  end

  describe "Tempo.utc_now/0" do
    test "returns a second-resolution Tempo in Etc/UTC" do
      Tempo.Clock.Test.put(~U[2026-06-15 14:30:00Z])

      tempo = Tempo.utc_now()

      assert Tempo.resolution(tempo) == {:second, 1}
      assert tempo.extended.zone_id == "Etc/UTC"

      assert tempo.time ==
               [year: 2026, month: 6, day: 15, hour: 14, minute: 30, second: 0]
    end
  end

  describe "Tempo.now/1" do
    test "defaults to Etc/UTC" do
      Tempo.Clock.Test.put(~U[2026-06-15 14:30:00Z])
      assert Tempo.now().extended.zone_id == "Etc/UTC"
    end

    test "projects the UTC instant into the requested zone" do
      # 14:30 UTC on 2026-06-15 is 16:30 in Paris (UTC+2 during DST).
      Tempo.Clock.Test.put(~U[2026-06-15 14:30:00Z])

      tempo = Tempo.now("Europe/Paris")

      assert tempo.extended.zone_id == "Europe/Paris"
      assert Keyword.take(tempo.time, [:hour, :minute]) == [hour: 16, minute: 30]
    end

    test "crosses the date line when the zone moves the wall date" do
      # 23:30 UTC on 2026-06-15 is 07:30 on the 16th in Tokyo (UTC+9).
      Tempo.Clock.Test.put(~U[2026-06-15 23:30:00Z])

      tempo = Tempo.now("Asia/Tokyo")

      assert Keyword.get(tempo.time, :day) == 16
      assert Keyword.get(tempo.time, :hour) == 8
    end
  end

  describe "Tempo.utc_today/0" do
    test "returns a day-resolution Tempo" do
      Tempo.Clock.Test.put(~U[2026-06-15 14:30:00Z])

      assert Tempo.utc_today() |> Tempo.resolution() == {:day, 1}
      assert Tempo.utc_today().time == [year: 2026, month: 6, day: 15]
    end
  end

  describe "Tempo.today/1" do
    test "returns the date in the given zone" do
      # 23:30 UTC on 2026-06-15 is already the 16th in Tokyo.
      Tempo.Clock.Test.put(~U[2026-06-15 23:30:00Z])

      tempo = Tempo.today("Asia/Tokyo")

      assert Tempo.resolution(tempo) == {:day, 1}
      assert tempo.time == [year: 2026, month: 6, day: 16]
    end
  end
end
