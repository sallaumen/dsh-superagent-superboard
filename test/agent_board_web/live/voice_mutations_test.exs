defmodule AgentBoardWeb.VoiceMutationsTest do
  @moduledoc "Voice requests to change task state are parsed, never acted on."
  use ExUnit.Case, async: true

  alias AgentBoardWeb.VoiceMutations

  test "accepts an exact, numbered stop or archive request in either language" do
    assert {:ok, %{action: :stop, number: 42}} = VoiceMutations.parse("stop task #42")
    assert {:ok, %{action: :stop, number: 42}} = VoiceMutations.parse("Pare a tarefa 42.")
    assert {:ok, %{action: :archive, number: 7}} = VoiceMutations.parse("archive issue 7")
    assert {:ok, %{action: :archive, number: 7}} = VoiceMutations.parse("Arquive a tarefa #7")
  end

  test "never treats assent, a PR, a vague request, or unbounded input as a mutation" do
    for text <- [
          "yes",
          "sim",
          "stop PR #42",
          "stop task",
          "archive task 0",
          "Can you stop task 42?",
          String.duplicate("x", 501)
        ] do
      assert VoiceMutations.parse(text) == :not_mutation
    end
  end
end
