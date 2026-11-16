defmodule AgentBoard.Lanes.Digest.SentenceTest do
  use ExUnit.Case, async: true
  alias AgentBoard.Lanes.Digest.Sentence

  @review %{role: :you, text: "review", url: "/pull/12"}
  @running %{role: :agent, text: "running", task_id: 7}

  test "zero or one segment needs no separator" do
    assert Sentence.join([], "and") == []
    assert Sentence.join([@review], "and") == [@review]
  end

  test "only the separators are plain; links and role stay on the original segments" do
    blocked = %{role: :halt, text: "bloqueada", task_id: 9}

    assert Sentence.join([@review, @running], "e") == [
             @review,
             %{text: " e ", role: :plain},
             @running
           ]

    assert Sentence.join([@review, @running, blocked], "and") == [
             @review,
             %{text: ", ", role: :plain},
             @running,
             %{text: " and ", role: :plain},
             blocked
           ]
  end
end
