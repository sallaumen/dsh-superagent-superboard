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
    comment(b, 103, "Done: [PR 199](https://github.com/o/r/pull/199) was merged")

    inbox = Board.inbox()

    assert Enum.map(inbox.messages, & &1.task_id) == [b.id, a.id]
    assert Enum.find(inbox.messages, &(&1.task_id == a.id)).preview == "Qual opção você prefere?"
    # A Markdown link reads as its text, not as its markup.
    assert Enum.find(inbox.messages, &(&1.task_id == b.id)).preview == "Done: PR 199 was merged"
    assert Enum.map(inbox.messages, & &1.repo) == ["sallaumen/o_colmex", "sallaumen/arena-rogue"]
    assert [%{task_id: id, state: "blocked"}] = inbox.alerts
    assert id == b.id
  end

  test "a running task enters the attention list only past the time its size allows" do
    {:ok, repo} = Board.add_repository("sallaumen", "long-runs")
    now = DateTime.utc_now(:second)
    limit_passed = DateTime.add(now, -21 * 60, :second)

    long = task(repo, 21, "Long", "running", %{size: "S", state_changed_at: limit_passed})

    task(repo, 22, "Within", "running", %{
      size: "L",
      state_changed_at: DateTime.add(now, -21 * 60, :second)
    })

    assert [%{task_id: id, state: "slow", at: at}] = Board.inbox().alerts
    assert id == long.id
    assert at == DateTime.add(limit_passed, 20 * 60, :second)
  end

  defp task(repository, number, title, state, attrs \\ %{}) do
    %Task{}
    |> Task.changeset(%{
      repository_id: repository.id,
      kind: "issue",
      number: number,
      title: title,
      state: state
    })
    |> Ecto.Changeset.change(attrs)
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
