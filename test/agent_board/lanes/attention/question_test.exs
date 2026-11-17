defmodule AgentBoard.Lanes.Attention.QuestionTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Attention.Question

  test "only visible questions with integer issue numbers request reports" do
    assert Question.report_numbers([
             %{kind: :question, task: %{number: 12}},
             %{kind: :review, task: %{number: 7}},
             %{kind: :question, task: %{number: nil}},
             %{kind: :question, task: %{number: "9"}},
             %{kind: :blocked},
             %{kind: :question, task: %{}},
             %{kind: :question, task: %{number: 3}},
             %{kind: :question, task: %{number: 12}}
           ]) == [12, 3, 12]
  end

  test "no visible questions need no reports" do
    assert Question.report_numbers([]) == []
    assert Question.report_numbers([%{kind: :review}]) == []
  end
end
