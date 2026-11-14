defmodule AgentBoard.Board.ObjectiveTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.Objective

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
end
