defmodule AgentBoard.Board.ObjectiveTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.{Objective, Task}

  describe "group_task_ids/1" do
    test "an empty list is not a group" do
      assert Objective.group_task_ids([]) == {:error, :not_a_group}
    end

    test "a single task is not a group" do
      assert Objective.group_task_ids([7]) == {:error, :not_a_group}
    end

    test "repeated occurrences of the same task are not a group" do
      assert Objective.group_task_ids([7, 7, 7]) == {:error, :not_a_group}
    end

    test "two distinct tasks retain their first-seen order" do
      assert Objective.group_task_ids([12, 7, 12]) == {:ok, [12, 7]}
    end
  end

  describe "progress/1" do
    test "an empty objective is not done" do
      assert Objective.progress([]) == %{total: 0, merged: 0, done?: false}
    end

    test "one done and one queued task give partial progress" do
      tasks = [%Task{state: "done"}, %Task{state: "queued"}]
      assert Objective.progress(tasks) == %{total: 2, merged: 1, done?: false}
    end

    test "two done tasks complete the objective" do
      tasks = [%Task{state: "done"}, %Task{state: "done"}]
      assert Objective.progress(tasks) == %{total: 2, merged: 2, done?: true}
    end
  end

  test "a dependency belongs to the objective of the blocked task" do
    tasks = [%Task{id: 12}]

    assert Objective.dependency_edges(tasks, [{12, 7}, {7, 12}]) == [{12, 7}]
  end

  test "the board summary contains task details, progress and the objective's edges" do
    released_at = ~U[2026-01-08 12:00:00Z]

    objective = %Objective{
      id: 3,
      title: "Release",
      done_criterion: "Both tasks merged",
      issue_url: "https://example.org/issues/30",
      tasks: [
        %Task{id: 12, number: 42, title: "Ship", state: "queued", held: true},
        %Task{id: 15, number: 45, title: "Build", state: "done", released_at: released_at}
      ]
    }

    assert Objective.summary(objective, [{12, 7}]) == %{
             id: 3,
             title: "Release",
             done_criterion: "Both tasks merged",
             issue_url: "https://example.org/issues/30",
             total: 2,
             merged: 1,
             done?: false,
             tasks: [
               %{
                 id: 12,
                 number: 42,
                 title: "Ship",
                 state: "queued",
                 held: true,
                 released_at: nil
               },
               %{
                 id: 15,
                 number: 45,
                 title: "Build",
                 state: "done",
                 held: false,
                 released_at: released_at
               }
             ],
             edges: [{12, 7}]
           }
  end
end
