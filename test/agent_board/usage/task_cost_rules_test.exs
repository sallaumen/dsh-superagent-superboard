defmodule AgentBoard.Usage.TaskCostRulesTest do
  use ExUnit.Case, async: true
  alias AgentBoard.Usage.TaskCosts

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
