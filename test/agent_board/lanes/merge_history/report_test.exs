defmodule AgentBoard.Lanes.MergeHistory.ReportTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.PullRequest
  alias AgentBoard.Lanes.MergeHistory
  alias AgentBoard.Lanes.MergeHistory.{Calendar, Report}

  @at ~U[2026-01-01 12:00:00Z]

  test "the full week supplies counts, newest-first pages use each PR's own evidence" do
    window = MergeHistory.window(@at, 180)

    base = %PullRequest{
      id: 20,
      number: 20,
      merged_at: @at,
      title: "Yesterday",
      checks_state: "success",
      closes_issues: [7]
    }

    yesterday = %{base | merged_at: DateTime.add(@at, -1, :day)}

    today =
      for n <- 1..9,
          do: %{base | id: n, number: n, closes_issues: if(n == 9, do: [42], else: [7])}

    ci = %{
      2 => %{state: :fail, detail: "failed"},
      20 => %{state: :pass, remote_blocked: false, detail: "passed"}
    }

    cost = [%{source: "codex", executions: 1, cost: nil, unpriced: 1}]
    calendar = Calendar.build(today ++ [yesterday], window, ci)

    assert %{days: days, groups: [newest, older], total: 10, issues: 2} =
             Report.build(calendar, ci, %{2 => cost})

    assert Enum.map(days, & &1.date) == Enum.to_list(window.dates)
    assert %{n: 9, fail: 1, issues: 2} = List.last(days)
    assert %{date: ~D[2026-01-01], n: 9, more: 6, more_wide: 1} = newest
    assert %{date: ~D[2025-12-31], n: 1, items: [%{number: 20, ciLocal: true, cost: nil}]} = older

    assert [
             %{number: 1, cost: nil, ci: "pass"},
             %{number: 2, cost: ^cost, ci: "fail"},
             %{number: 3}
           ] = newest.items

    assert Enum.map(newest.extra, & &1.number) == Enum.to_list(4..8)
  end

  test "an empty week keeps seven day summaries and no detail groups" do
    calendar = Calendar.build([], MergeHistory.window(@at, 0), %{})
    assert %{days: days, groups: [], total: 0, issues: 0} = Report.build(calendar, %{}, %{})
    assert length(days) == 7
    assert Enum.all?(days, &(&1.n == 0))
  end
end
