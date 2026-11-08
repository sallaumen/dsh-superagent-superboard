defmodule AgentBoard.TodayTest do
  @moduledoc "A leitura da visão Hoje: os dois repositórios numa lista só, com o repositório em cada item."
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{PullRequest, Task}

  defp task(repo, number, state, attrs \\ %{}) do
    %Task{}
    |> Task.changeset(
      Map.merge(
        %{
          repository_id: repo.id,
          kind: "issue",
          number: number,
          title: "Tarefa #{number}",
          state: state
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  test "needs and running come from both repositories, one item each, with the repository" do
    {:ok, arena} = Board.add_repository("fixture", "arena")
    {:ok, colmex} = Board.add_repository("fixture", "colmex")

    blocked = task(arena, 1, "blocked")
    question = task(arena, 2, "question")
    ready = task(colmex, 3, "ready")
    running = task(colmex, 4, "running")
    _stopped = task(arena, 5, "blocked", %{stopped: true})
    _archived = task(colmex, 6, "blocked", %{archived: true})

    today = Board.today()

    assert Enum.map(today.needs, & &1.id) == [blocked.id, question.id, ready.id]

    assert Enum.map(today.needs, & &1.repo) == [
             "fixture/arena",
             "fixture/arena",
             "fixture/colmex"
           ]

    assert [%{id: running_id, repo: "fixture/colmex"}] = today.running
    assert running_id == running.id
  end

  test "a ready task whose PR already merged is done, not waiting" do
    {:ok, repo} = Board.add_repository("fixture", "resolved")
    task = task(repo, 7, "ready", %{body: "https://github.com/fixture/resolved/pull/2"})

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 2,
      title: "Tarefa 7",
      state: "merged",
      merged_at: DateTime.utc_now() |> DateTime.truncate(:second),
      closes_issues: [7]
    })
    |> Repo.insert!()

    assert Board.today().needs == []
    assert Repo.get!(Task, task.id).state == "ready"
  end

  test "the rail's per-repository summary is the same read" do
    {:ok, repo} = Board.add_repository("fixture", "rail")
    task(repo, 8, "question")
    task(repo, 9, "blocked")

    today = Board.today()
    overview = Map.fetch!(today.repos, repo.id)

    assert overview.name == "fixture/rail"
    assert overview.you == 1
    assert overview.halt == 1
  end
end
