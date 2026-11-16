defmodule AgentBoardWeb.BoardComponents.ObjectiveTree.DependencyStatusTest do
  use ExUnit.Case, async: true

  alias AgentBoardWeb.BoardComponents.ObjectiveTree.DependencyStatus

  @blockers [
    %{number: 2, state: "done"},
    %{number: 7, state: "running"},
    %{number: 9, state: "closed"},
    %{number: 12, state: "queued"}
  ]

  test "a held task waits for the open blockers" do
    node = %{state: "queued", held: true, waiting: @blockers}
    assert DependencyStatus.classify(node) == {:waiting_for, [7, 12]}
  end

  test "a running task depends on the same open blockers without waiting" do
    node = %{state: "running", held: false, waiting: @blockers}
    assert DependencyStatus.classify(node) == {:depends_on_open, [7, 12]}
  end

  test "a failed call takes priority even when the held task has open blockers" do
    node = %{
      state: "queued",
      held: true,
      released_at: ~U[2026-01-08 12:00:00Z],
      waiting: @blockers
    }

    assert DependencyStatus.classify(node) == :call_failed
  end
end
