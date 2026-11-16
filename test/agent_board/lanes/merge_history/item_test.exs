defmodule AgentBoard.Lanes.MergeHistory.ItemTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.PullRequest
  alias AgentBoard.Lanes.MergeHistory.Item

  @pull %PullRequest{
    id: 15,
    number: 9,
    title: "Fix schedule",
    url: "https://example.org/pull/9",
    closes_issues: [2, 7],
    checks_state: "success",
    review_state: "approved",
    merged_at: ~U[2026-01-01 01:02:00Z]
  }

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  test "one row keeps its identity, issue order, observed cost and local failure" do
    cost = [%{source: "codex", executions: 1, cost: nil, unpriced: 1}]
    local = %{state: :fail, detail: "1 failure"}

    assert Item.build(@pull, 180, local, cost) == %{
             id: 15,
             number: 9,
             title: "Fix schedule",
             url: "https://example.org/pull/9",
             closes: [2, 7],
             ci: "fail",
             ciNote: "Local CI failed",
             ciTitle: "Local CI failed: 1 failure",
             ciLocal: false,
             review: "approved",
             at: "22:02",
             cost: cost
           }
  end

  test "missing issue and cost evidence stay absent and a remote pass is not local" do
    for {state, label} <- [
          {"changes_requested", "changes requested"},
          {"pending", "review pending"},
          {nil, "no review"}
        ] do
      assert %{closes: [], cost: nil, ci: "pass", ciLocal: false, review: ^label} =
               Item.build(%{@pull | closes_issues: nil, review_state: state}, 0, nil, nil)
    end
  end
end
