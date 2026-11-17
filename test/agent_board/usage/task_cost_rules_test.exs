defmodule AgentBoard.Usage.TaskCostRulesTest do
  use ExUnit.Case, async: true
  alias AgentBoard.Usage.TaskCosts

  test "pull costs follow the first tracked issue, including when its cost is unknown" do
    entries = [%{source: "codex", executions: 1, unpriced: 1, cost: nil}]

    pulls = [
      %{number: 7, closes_issues: [99, 12, 8]},
      %{number: 9, closes_issues: [8, 12]},
      %{number: 10, closes_issues: [99]},
      %{number: 11, closes_issues: nil}
    ]

    assert TaskCosts.pull_entries(pulls, %{12 => 120, 8 => 80}, %{120 => entries}) == %{
             7 => entries
           }

    assert TaskCosts.pull_entries([], %{}, %{}) == %{}
    assert TaskCosts.pull_entries(pulls, %{12 => 120}, %{}) == %{}
  end

  test "executor sums, missing prices and partial observations remain independent" do
    complete = %{source: "claude_code", cost: %{micros: 20, complete?: true}}
    partial = %{complete | cost: %{micros: 7, complete?: false}}
    unknown = %{complete | cost: nil}

    assert TaskCosts.entries([
             %{source: "codex", cost: nil},
             complete,
             partial,
             unknown,
             %{source: "dsh", cost: %{micros: 0, complete?: true}}
           ]) == [
             %{source: "dsh", executions: 1, unpriced: 0, cost: %{micros: 0, complete?: true}},
             %{
               source: "claude_code",
               executions: 3,
               unpriced: 1,
               cost: %{micros: 27, complete?: false}
             },
             %{source: "codex", executions: 1, unpriced: 1, cost: nil}
           ]

    assert TaskCosts.entries([unknown]) == [
             %{source: "claude_code", executions: 1, unpriced: 1, cost: nil}
           ]

    assert TaskCosts.entries([]) == []
  end
end
