defmodule AgentBoard.Lanes.RetryTest do
  use ExUnit.Case, async: true
  alias AgentBoard.Lanes
  alias AgentBoard.Lanes.Retry

  test "the row keeps its identity and explanation, without inventing a time when unavailable" do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    task = %{id: 4, number: 12, title: "Build", hidden: :unused}

    assert Retry.build(task, %{line: "Retry at 14:30"}) ==
             %{id: 4, number: 12, title: "Build", line: "Retry at 14:30"}

    expected = %{
      id: 4,
      number: 12,
      title: "Build",
      line: "**Automatic retry.** Waiting for the agent."
    }

    assert Retry.build(task, nil) == expected
    assert Lanes.retrying(%{retrying: [task]}, now: ~U[2026-11-17 12:00:00Z]) == [expected]
    assert Lanes.retrying(%{}, now: ~U[2026-11-17 12:00:00Z]) == []
  end
end
