defmodule AgentBoardWeb.VoiceMutationsTest do
  @moduledoc "Voice requests to change task state are parsed, never acted on."
  use AgentBoardWeb.ConnCase, async: true

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task
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

  test "prepares only an active task in the selected repository, then detects changes" do
    {:ok, repo} = Board.add_repository("fixture", "voice-actions")
    {:ok, other} = Board.add_repository("fixture", "other")

    task =
      %Task{}
      |> Task.changeset(%{repository_id: repo.id, number: 42, title: "Keep history"})
      |> Repo.insert!()

    assert {:ok, intent} = VoiceMutations.prepare("archive task #42", repo)
    assert intent.repository == "fixture/voice-actions"
    assert intent.title == "Keep history"
    assert {:ok, %Task{id: task_id}} = VoiceMutations.current_task(intent, repo)
    assert task_id == task.id
    assert {:error, :changed} = VoiceMutations.current_task(intent, other)
    assert {:error, _} = VoiceMutations.prepare("stop task #42", other)

    task |> Task.changeset(%{state: "ready"}) |> Repo.update!()
    assert {:error, :changed} = VoiceMutations.current_task(intent, repo)
  end

  test "stopped and archived tasks cannot be prepared again" do
    {:ok, repo} = Board.add_repository("fixture", "inactive-actions")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      number: 3,
      title: "Already stopped",
      state: "stopped",
      stopped: true
    })
    |> Repo.insert!()

    assert {:error, _} = VoiceMutations.prepare("stop task 3", repo)
    assert {:error, _} = VoiceMutations.prepare("archive task 3", repo)
  end
end
