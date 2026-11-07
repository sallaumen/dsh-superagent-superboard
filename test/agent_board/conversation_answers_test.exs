defmodule AgentBoard.ConversationAnswersTest do
  @moduledoc "A question sent to a task's agent and the reply that answers it."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Board, Conversation, Repo}
  alias AgentBoard.Board.{Comment, Task}

  setup do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    task =
      %Task{}
      |> Task.changeset(%{repository_id: repo.id, number: 12, title: "Placar", kind: "issue"})
      |> Repo.insert!()

    {:ok, ask} =
      Conversation.record("agent", "Vou perguntar... Posso mandar?",
        proposal: %{"kind" => "ask_task", "task_id" => task.id, "number" => 12, "question" => "?"}
      )

    :ok = Conversation.settle(ask, "confirmed")
    %{task: task, ask: Repo.reload!(ask)}
  end

  defp comment(task, kind, body, at) do
    %Comment{}
    |> Comment.changeset(%{
      task_id: task.id,
      github_id: System.unique_integer([:positive]),
      kind: kind,
      body: body
    })
    |> Ecto.Changeset.force_change(:inserted_at, at)
    |> Repo.insert!()
  end

  defp later(ask, seconds),
    do: ask.updated_at |> DateTime.add(seconds) |> DateTime.truncate(:second)

  test "the first new agent comment that is not the workpad is the answer", %{
    task: task,
    ask: ask
  } do
    comment(task, "agent", "## Relatório do agente\n### Plano\n- testar", later(ask, 5))
    comment(task, "user", "outra coisa", later(ask, 6))
    assert Conversation.arrived_answers() == []

    reply = comment(task, "agent", "Sim, rodei os testes: todos passaram.", later(ask, 10))
    assert [{%{id: ask_id}, %{id: reply_id}}] = Conversation.arrived_answers()
    assert ask_id == ask.id and reply_id == reply.id
  end

  test "a comment from before the question is not its answer", %{task: task, ask: ask} do
    comment(task, "agent", "Comecei a tarefa.", later(ask, -60))
    assert Conversation.arrived_answers() == []
  end

  test "an answer is claimed once; a day-old question is no longer waited for", %{
    task: task,
    ask: ask
  } do
    comment(task, "agent", "Sim.", later(ask, 10))

    assert Conversation.mark_answered(ask) == :ok
    assert Conversation.mark_answered(ask) == :already_settled
    assert Conversation.arrived_answers() == []

    {:ok, old} =
      Conversation.record("agent", "Posso mandar?",
        proposal: %{"kind" => "ask_task", "task_id" => task.id, "number" => 12}
      )

    :ok = Conversation.settle(old, "confirmed")
    assert Conversation.arrived_answers(DateTime.add(DateTime.utc_now(), 2, :day)) == []
  end
end
