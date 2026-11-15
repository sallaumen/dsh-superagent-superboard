defmodule AgentBoardWeb.BoardComponents.ObjectiveTree.LayoutTest do
  use ExUnit.Case, async: true

  alias AgentBoardWeb.BoardComponents.ObjectiveTree.Layout

  test "a task sits one column after the deepest task it waits for" do
    tasks = for id <- 1..4, do: %{id: id, number: id, title: "t", state: "queued"}
    layout = Layout.build(tasks, [{2, 1}, {3, 2}, {4, 1}, {4, 3}])

    assert Map.new(layout.nodes, &{&1.id, &1.column}) == %{1 => 0, 2 => 1, 3 => 2, 4 => 3}
    assert length(layout.edges) == 4
    assert layout.width > layout.height
  end

  test "tasks that wait for nothing share the first column, one under the other" do
    tasks = for id <- 1..2, do: %{id: id, number: id, title: "t", state: "queued"}
    assert [%{column: 0, y: 0}, %{column: 0, y: y}] = Layout.build(tasks, []).nodes
    assert y > 0
  end

  test "an edge to a task outside the group is left out" do
    tasks = [%{id: 1, number: 1, title: "t", state: "queued"}]
    assert %{edges: [], nodes: [%{column: 0}]} = Layout.build(tasks, [{1, 99}])
  end
end
