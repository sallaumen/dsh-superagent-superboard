defmodule AgentBoard.WorkTest do
  @moduledoc "The reading lanes: order, freshness markers, duplicates and the digest."
  use AgentBoard.DataCase, async: true

  import Ecto.Query

  alias AgentBoard.{Board, Repo, Work}
  alias AgentBoard.Board.{PullRequest, Task}

  test "needs puts new items before old ones and follows the urgency order" do
    {:ok, repo} = Board.add_repository("fixture", "needs")
    now = ~U[2026-11-06 15:00:00Z]
    last_visit = DateTime.add(now, -3600, :second)

    old_review = task(repo, 1, "Old review", "ready", DateTime.add(now, -7200, :second))
    new_blocked = task(repo, 2, "New blocked", "blocked", DateTime.add(now, -60, :second))
    new_review = task(repo, 3, "New review", "ready", DateTime.add(now, -60, :second))
    failure = merged(repo, 4, "Main red", "failure", DateTime.add(now, -60, :second))

    board = %{ready: [old_review, new_review], blocked: [new_blocked], question: [], running: []}

    needs = Work.needs(repo, board, now: now, last_visit: last_visit)

    assert Enum.map(needs, & &1.title) == ["Main red", "New blocked", "New review", "Old review"]
    assert Enum.map(needs, & &1.kind) == [:cifail, :blocked, :review, :review]
    assert Enum.at(needs, 0).is_new
    refute Enum.at(needs, 3).is_new
    assert Enum.at(needs, 0).why =~ "CI falhou"
    assert Enum.at(needs, 0).why =~ "gates"
    assert Enum.at(needs, 0).actions |> hd() |> Map.fetch!(:url) == failure.url
  end

  test "queue keeps arrival order and warns about a merged duplicate" do
    {:ok, repo} = Board.add_repository("fixture", "queue")
    now = ~U[2026-11-06 15:00:00Z]

    merged(repo, 24, "Spread deterministic seed spawns across each arena edge", "success", now)

    later =
      task(repo, 22, "Spread deterministic seed spawns across each arena edge", "queued", now)

    earlier = task(repo, 20, "Unrelated work", "queued", DateTime.add(now, -3600, :second))

    queue = Work.queue(repo, %{}, now: now)

    assert Enum.map(queue.items, & &1.id) == [earlier.id, later.id]
    assert Enum.at(queue.items, 1).note == "Parece repetir #24, já mesclado"
    assert queue.counts.dupes == 1
  end

  test "the merge log groups the last seven days and counts every PR" do
    {:ok, repo} = Board.add_repository("fixture", "log")
    today = ~U[2026-11-06 15:00:00Z]

    merged(repo, 1, "Today", "success", today)
    merged(repo, 2, "Yesterday", "failure", DateTime.add(today, -86_400, :second))
    merged(repo, 3, "Old", "success", DateTime.add(today, -8 * 86_400, :second))

    log = Work.merge_log(repo, now: today, tz_offset: 0)

    assert log.total == 2
    assert List.last(log.days).n == 1
    assert Enum.find(log.days, &(&1.date == Date.add(Date.utc_today(), -1))).n == 1
    assert Enum.map(log.groups, & &1.label) == ["Hoje", "Ontem, 5 nov"]
    assert hd(log.groups).items |> hd() |> Map.fetch!(:ci) == "pass"
  end

  test "the digest counts what changed since the visit, not the whole board" do
    {:ok, repo} = Board.add_repository("fixture", "digest")
    now = ~U[2026-11-06 15:00:00Z]
    last_visit = DateTime.add(now, -3600, :second)

    merged(repo, 1, "Merged since", "failure", DateTime.add(now, -60, :second))
    task(repo, 2, "Queued now", "queued", now)
    task(repo, 3, "Was already here", "queued", DateTime.add(now, -7200, :second))

    board = %{running: [], question: [], ready: [], blocked: [], task_counts: %{queued: 2}}
    digest = Work.digest(repo, board, now: now, last_visit: last_visit, tz_offset: 0)

    text = Enum.map_join(digest.segments, "", & &1.text)
    assert text =~ "mesclou 1 PR com CI falhando"
    assert text =~ "1 nova na fila"
    refute text =~ "2 novas"
  end

  test "a first visit never claims a change time it does not have" do
    {:ok, repo} = Board.add_repository("fixture", "first")
    now = ~U[2026-11-06 15:00:00Z]
    task(repo, 2, "Queued now", "queued", now)

    board = %{running: [], question: [], ready: [], blocked: [], task_counts: %{queued: 1}}
    digest = Work.digest(repo, board, now: now, last_visit: nil, tz_offset: 0)

    assert digest.prefix == "Primeira visita: "
    assert Enum.map_join(digest.segments, "", & &1.text) =~ "1 na fila"
  end

  defp task(repo, number, title, state, at) do
    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: number,
        title: title,
        state: state,
        state_changed_at: at
      })
      |> Repo.insert!()

    # Ecto always writes the current inserted_at; the lane's arrival order is
    # tested by setting the stored time explicitly.
    Repo.update_all(from(t in Task, where: t.id == ^task.id), set: [inserted_at: at])
    %{task | inserted_at: at}
  end

  defp merged(repo, number, title, checks, at) do
    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: number,
      title: title,
      state: "merged",
      merged_at: at,
      checks_state: checks,
      checks_failed: if(checks == "failure", do: "gates", else: nil),
      url: "https://github.com/fixture/repo/pull/#{number}"
    })
    |> Repo.insert!()
  end
end
