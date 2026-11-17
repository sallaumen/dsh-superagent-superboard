defmodule AgentBoard.Lanes.Attention.QuestionTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Attention.Question

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  test "the recorded question and response action stay attached to the supplied task" do
    assert Question.content(71, "Which release?", "Use v1?") ==
             {"**The agent asked:** Which release?", [%{label: "Respond", task_id: 71}]}
  end

  test "a question in the summary supplies the fallback with the same response action" do
    assert Question.content(71, nil, "Use v1?") ==
             {"**The agent asked:** Use v1?", [%{label: "Respond", task_id: 71}]}
  end

  test "without a usable question the neutral explanation still offers a response" do
    for summary <- [nil, "Waiting", " "] do
      assert Question.content(71, nil, summary) ==
               {"**The agent is waiting for your answer.** Open the conversation and reply.",
                [%{label: "Respond", task_id: 71}]}
    end
  end

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
