defmodule Tempo.ScheduleTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  doctest Tempo.Schedule

  alias Tempo.Schedule

  # design(2d) → build(3d), design → docs(1d), build+docs → ship(2d),
  # anchored at 2026-06-01, ship due 2026-06-08.
  defp plan do
    {:ok, plan} =
      Schedule.new()
      |> Schedule.task(:design, duration: ~o"P2D", start: ~o"2026-06-01")
      |> Schedule.task(:build, duration: ~o"P3D", after: :design)
      |> Schedule.task(:docs, duration: ~o"P1D", after: :design)
      |> Schedule.task(:ship, duration: ~o"P2D", after: [:build, :docs], deadline: ~o"2026-06-08")
      |> Schedule.solve()

    plan
  end

  describe "solve/1 — the schedule" do
    test "each task is placed at its earliest feasible position" do
      plan = plan()
      assert plan[:design].start == ~o"2026-06-01"
      assert plan[:design].finish == ~o"2026-06-03"
      assert plan[:build].start == ~o"2026-06-03"
      assert plan[:build].finish == ~o"2026-06-06"
      assert plan[:docs].start == ~o"2026-06-03"
      assert plan[:ship].start == ~o"2026-06-06"
      assert plan[:ship].finish == ~o"2026-06-08"
    end

    test "a finish-to-start dependency may leave a gap, not just abut" do
      # docs (1 day) finishes 06-04 but ship can't start until build
      # finishes 06-06 — a two-day gap after docs.
      plan = plan()
      assert plan[:docs].finish == ~o"2026-06-04"
      assert plan[:ship].start == ~o"2026-06-06"
    end
  end

  describe "critical path and slack" do
    test "the critical path is the zero-slack chain in start order" do
      assert Schedule.critical_path(plan()) == [:design, :build, :ship]
    end

    test "a task off the critical path has slack (early < late start)" do
      docs = plan()[:docs]
      refute docs.critical?
      # docs can start as late as 06-05 (so it still finishes by the
      # time ship needs it) yet schedules early at 06-03.
      assert docs.start == ~o"2026-06-03"
      assert docs.latest_start == ~o"2026-06-05"
    end

    test "critical tasks have coincident early and late starts" do
      build = plan()[:build]
      assert build.critical?
      assert build.start == build.latest_start
    end
  end

  describe "span/1" do
    test "covers the whole project from earliest start to latest finish" do
      span = Schedule.span(plan())
      assert span.from == ~o"2026-06-01"
      assert span.to == ~o"2026-06-08"
    end
  end

  describe "bounds and feasibility" do
    test "an over-tight deadline is infeasible" do
      result =
        Schedule.new()
        |> Schedule.task(:a, duration: ~o"P5D", start: ~o"2026-06-01", deadline: ~o"2026-06-03")
        |> Schedule.solve()

      assert result == {:error, :infeasible}
    end

    test ":earliest holds a task back" do
      {:ok, plan} =
        Schedule.new()
        |> Schedule.task(:a, duration: ~o"P1D", earliest: ~o"2026-06-10")
        |> Schedule.solve()

      assert plan[:a].start == ~o"2026-06-10"
    end

    test ":within bounds both ends" do
      {:ok, plan} =
        Schedule.new()
        |> Schedule.task(:a, duration: ~o"P2D", within: {~o"2026-06-01", ~o"2026-06-10"})
        |> Schedule.solve()

      assert plan[:a].start == ~o"2026-06-01"
      assert plan[:a].latest_finish == ~o"2026-06-10"
    end

    test "an anchored task is critical (pinned); a downstream task with no deadline is undetermined" do
      # An anchored task has zero slack — it cannot move. A task whose
      # latest start nothing bounds (no deadline downstream) reports nil.
      {:ok, plan} =
        Schedule.new()
        |> Schedule.task(:a, duration: ~o"P2D", start: ~o"2026-06-01")
        |> Schedule.task(:b, duration: ~o"P3D", after: :a)
        |> Schedule.solve()

      assert plan[:a].critical? == true
      assert plan[:b].critical? == nil
      assert Schedule.critical_path(plan) == [:a]
    end

    test "a relative schedule of day-length tasks measures in days (not the year axis)" do
      # With no dates at all the network's durations fix the axis, so a
      # 3-task day chain spans the right number of days.
      {:ok, plan} =
        Schedule.new()
        |> Schedule.task(:a, duration: ~o"P2D", start: ~o"2026-06-01")
        |> Schedule.task(:b, duration: ~o"P2D", after: :a)
        |> Schedule.task(:c, duration: ~o"P2D", after: :b)
        |> Schedule.solve()

      assert plan[:c].finish == ~o"2026-06-07"
    end

    test "a cyclic dependency is infeasible" do
      result =
        Schedule.new()
        |> Schedule.task(:a, duration: ~o"P1D", start: ~o"2026-06-01", after: :b)
        |> Schedule.task(:b, duration: ~o"P1D", after: :a)
        |> Schedule.solve()

      assert result == {:error, :infeasible}
    end
  end
end
