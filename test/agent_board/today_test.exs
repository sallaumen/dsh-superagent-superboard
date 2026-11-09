defmodule AgentBoard.TodayTest do
  @moduledoc "A leitura da visão Hoje: os dois repositórios numa lista só, com o repositório em cada item."
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Overview, Repo}
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

    today = Overview.today()

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

    assert Overview.today().needs == []
    assert Repo.get!(Task, task.id).state == "ready"
  end

  test "the rail's per-repository summary is the same read" do
    {:ok, repo} = Board.add_repository("fixture", "rail")
    task(repo, 8, "question")
    task(repo, 9, "blocked")

    today = Overview.today()
    overview = Map.fetch!(today.repos, repo.id)

    assert overview.name == "fixture/rail"
    assert overview.you == 1
    assert overview.halt == 1
  end

  test "local day metrics and seven-day trend use stored times, including the midnight boundary" do
    {:ok, arena} = Board.add_repository("fixture", "arena-day")
    {:ok, colmex} = Board.add_repository("fixture", "colmex-day")
    now = ~U[2026-11-09 02:30:00Z]

    seen = task(arena, 20, "queued")
    task(colmex, 21, "queued", %{stopped: true})
    task(colmex, 22, "blocked")

    # At UTC 02:00 the owner's day (UTC-3) is still November 8.
    Repo.update_all(from(t in Task, where: t.id == ^seen.id),
      set: [inserted_at: ~U[2026-11-09 02:00:00Z]]
    )

    for {repo, number, at} <- [
          {arena, 30, ~U[2026-11-09 02:00:00Z]},
          {colmex, 31, ~U[2026-11-08 02:00:00Z]},
          {arena, 32, ~U[2026-11-02 02:00:00Z]}
        ] do
      %PullRequest{}
      |> PullRequest.changeset(%{
        repository_id: repo.id,
        number: number,
        title: "PR #{number}",
        state: "merged",
        merged_at: at
      })
      |> Repo.insert!()
    end

    today = Overview.today(180, now)

    assert today.merged_today == 1
    assert today.seen_today == 1
    assert Enum.map(today.trend, & &1.count) == [0, 0, 0, 0, 0, 1, 1]
    assert Enum.map(today.trend, & &1.date) |> List.last() == ~D[2026-11-08]
    assert Enum.map(today.queue, & &1.id) == [seen.id]

    arena_day = Enum.find(today.projects, &(&1.name == "fixture/arena-day"))
    colmex_day = Enum.find(today.projects, &(&1.name == "fixture/colmex-day"))
    assert %{queued: 1, merged: 1, seen: 1, unknown: true} = arena_day
    assert %{queued: 0, merged: 0, needs: 1, unknown: true} = colmex_day
  end
end
