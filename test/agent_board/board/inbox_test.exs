defmodule AgentBoard.Board.InboxTest do
  use AgentBoard.DataCase, async: false

  alias AgentBoard.Board
  alias AgentBoard.Board.Task

  test "recent replies form one conversation per task across projects" do
    {:ok, first} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, second} = Board.add_repository("sallaumen", "o_colmex")
    a = task(first, 11, "First task", "queued")
    b = task(second, 12, "Second task", "blocked")

    comment(a, 101, "First answer")
    comment(a, 102, "## Relatório do agente\n### Pergunta\nQual opção você prefere?")
    comment(b, 103, "Other project answer")

    inbox = Board.inbox()

    assert Enum.map(inbox.messages, & &1.task_id) == [b.id, a.id]
    assert Enum.find(inbox.messages, &(&1.task_id == a.id)).preview == "Qual opção você prefere?"
    assert Enum.map(inbox.messages, & &1.repo) == ["sallaumen/o_colmex", "sallaumen/arena-rogue"]
    assert [%{task_id: id, state: "blocked"}] = inbox.alerts
    assert id == b.id
  end

  defp task(repository, number, title, state) do
    %Task{}
    |> Task.changeset(%{
      repository_id: repository.id,
      kind: "issue",
      number: number,
      title: title,
      state: state
    })
    |> Repo.insert!()
  end

  defp comment(task, id, body) do
    Board.upsert_comment(
      task,
      %{"id" => id, "body" => body, "user" => %{"login" => "sallaumen-agent"}},
      "sallaumen-agent"
    )
  end
end
