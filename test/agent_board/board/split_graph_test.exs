defmodule AgentBoard.Board.SplitGraphTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.{SplitGraph, Task}

  test "independent tasks are only sub-issues of the objective" do
    tasks = [%Task{number: 11}, %Task{number: 12}]
    ids = %{11 => 1011, 12 => 1012}

    assert SplitGraph.mirror_links(13, tasks, [], ids) == [
             {:sub_issue, 13, 1011},
             {:sub_issue, 13, 1012}
           ]
  end

  test "the blocked issue number links to the blocker's GitHub ID after the sub-issues" do
    blocker = %Task{number: 11}
    blocked = %Task{number: 12}
    ids = %{11 => 1011, 12 => 1012}

    assert SplitGraph.mirror_links(13, [blocked, blocker], [{blocked, blocker}], ids) == [
             {:sub_issue, 13, 1012},
             {:sub_issue, 13, 1011},
             {:blocked_by, 12, 1011}
           ]
  end

  test "a newly created task can depend on a receipt from a previous attempt" do
    a = %Task{id: 1}
    b = %Task{id: 2}

    results = [
      {%{key: "b", depends_on: ["a"]}, {:ok, b, :created}},
      {%{key: "a"}, {:ok, a, :existing}}
    ]

    assert SplitGraph.edges(results) == [{b, a}]
  end

  test "missing and failed blockers do not discard a valid edge" do
    a = %Task{id: 1}
    b = %Task{id: 2}

    results = [
      {%{key: "a"}, {:ok, a, :created}},
      {%{key: "b", depends_on: ["missing", "failed", "a"]}, {:ok, b, :created}},
      {%{key: "failed"}, {:error, :dependency_failed}}
    ]

    assert SplitGraph.edges(results) == [{b, a}]
  end

  test "different request keys resolving to the same task ID produce no self-link" do
    results = [
      {%{key: "original"}, {:ok, %Task{id: 7, state: "queued"}, :created}},
      {%{key: "repeat", depends_on: ["original"]}, {:ok, %Task{id: 7, state: "done"}, :existing}}
    ]

    assert SplitGraph.edges(results) == []
  end
end
