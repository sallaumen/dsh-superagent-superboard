defmodule AgentBoard.Board.SplitGraphTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.{SplitGraph, Task}

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
