defmodule AgentBoard.Overview do
  @moduledoc """
  The cross-repository "Hoje" read model: what needs the owner, what runs and
  the rail's per-repository summary.

  It is a read over the Board tables, not a Board operation: the repository
  context stays scoped to one repository, while this module answers "in all
  of them, now". `Lanes` does the same for one repository's lanes; `Overview`
  does it for the screen the owner opens first.
  """

  import Ecto.Query, warn: false

  alias AgentBoard.{Board, Freshness, Repo}
  alias AgentBoard.Board.{Event, PullRequest, Repository, Task}

  @today_states ~w(blocked question ready running queued)
  @need_rank %{"blocked" => 0, "question" => 1, "ready" => 2}

  @doc """
  One row per repository for the rail: the counts that need a decision and
  whether the saved data is old enough to be untrusted.
  """
  def repo_overview do
    states = Enum.map(Board.task_states(), &Atom.to_string/1)

    counts =
      Repo.all(
        from t in Task,
          where: t.state in ^states,
          group_by: [t.repository_id, t.state],
          select: {t.repository_id, t.state, count(t.id)}
      )
      |> Enum.reduce(%{}, fn {repository_id, state, count}, acc ->
        Map.update(acc, repository_id, %{state => count}, &Map.put(&1, state, count))
      end)

    # The newest sync (or error) of each repository, without a global limit:
    # a repository whose last sync is old still reads its own event.
    syncs =
      Repo.all(
        from e in Event,
          where: e.kind in ["sync", "sync_error"],
          distinct: e.repository_id,
          order_by: [asc: e.repository_id, desc: e.inserted_at, desc: e.id]
      )
      |> Map.new(&{&1.repository_id, &1})

    ready_by_repository =
      Repo.all(from t in Task, where: t.state == "ready", preload: [:repository])
      |> then(fn ready ->
        resolved = Board.resolved_task_ids(ready)

        ready
        |> Enum.reject(&MapSet.member?(resolved, &1.id))
        |> Enum.frequencies_by(& &1.repository_id)
      end)

    now = DateTime.utc_now()

    Board.list_repositories()
    |> Map.new(fn repository ->
      by_state = Map.get(counts, repository.id, %{})
      sync = syncs[repository.id]

      unknown =
        is_nil(sync) or sync.kind == "sync_error" or
          DateTime.diff(now, sync.inserted_at, :second) > Freshness.stale_ttl()

      {repository.id,
       %{
         id: repository.id,
         name: "#{repository.owner}/#{repository.name}",
         owner: repository.owner,
         running: Map.get(by_state, "running", 0),
         you: Map.get(ready_by_repository, repository.id, 0) + Map.get(by_state, "question", 0),
         halt: Map.get(by_state, "blocked", 0),
         unknown: unknown,
         last_sync: sync
       }}
    end)
  end

  @doc """
  What needs the owner and what runs, in every repository at once, plus the
  rail's per-repository summary. One read for the "Hoje" view
  (`docs/research/alfred.md`, F2.1): the same load, no query per render.
  """
  @spec today(integer(), DateTime.t()) :: map()
  def today(offset \\ 0, now \\ DateTime.utc_now()) do
    tasks =
      Repo.all(
        from t in Task,
          join: r in Repository,
          on: r.id == t.repository_id,
          where: t.state in ^@today_states and t.stopped == false and t.archived == false,
          order_by: [asc: t.state_changed_at, asc: t.id],
          preload: [repository: r]
      )

    resolved = tasks |> Enum.filter(&(&1.state == "ready")) |> Board.resolved_task_ids()

    needs =
      tasks
      |> Enum.filter(
        &(&1.state in ["blocked", "question", "ready"] and
            not MapSet.member?(resolved, &1.id))
      )
      |> Enum.sort_by(&{Map.get(@need_rank, &1.state, 9), &1.state_changed_at || &1.updated_at})

    running = Enum.filter(tasks, &(&1.state == "running"))
    queued = Enum.filter(tasks, &(&1.state == "queued"))
    repos = repo_overview()

    local_day = AgentBoard.Time.local_date(now, offset)
    first_day = Date.add(local_day, -6)
    start_at = day_start(first_day, offset)
    tomorrow_at = day_start(Date.add(local_day, 1), offset)

    merges =
      Repo.all(
        from p in PullRequest,
          where: p.state == "merged" and p.merged_at >= ^start_at and p.merged_at < ^tomorrow_at,
          select: {p.repository_id, p.merged_at}
      )

    merge_counts =
      Enum.frequencies_by(merges, fn {repository_id, at} ->
        {repository_id, AgentBoard.Time.local_date(at, offset)}
      end)

    daily_merges =
      Enum.frequencies_by(merges, fn {_repository_id, at} ->
        AgentBoard.Time.local_date(at, offset)
      end)

    seen_today =
      Repo.all(
        from t in Task,
          where:
            t.kind == "issue" and t.inserted_at >= ^day_start(local_day, offset) and
              t.inserted_at < ^tomorrow_at,
          group_by: t.repository_id,
          select: {t.repository_id, count(t.id)}
      )
      |> Map.new()

    active_needs = Enum.map(needs, &today_item/1)
    active_running = Enum.map(running, &today_item/1)
    active_queue = Enum.map(queued, &today_item/1)

    projects =
      repos
      |> Map.values()
      |> Enum.sort_by(& &1.name)
      |> Enum.map(fn repo ->
        %{
          id: repo.id,
          name: repo.name,
          unknown: repo.unknown,
          last_sync: repo.last_sync,
          needs: Enum.count(active_needs, &(&1.repository_id == repo.id)),
          running: Enum.count(active_running, &(&1.repository_id == repo.id)),
          queued: Enum.count(active_queue, &(&1.repository_id == repo.id)),
          merged: Map.get(merge_counts, {repo.id, local_day}, 0),
          seen: Map.get(seen_today, repo.id, 0)
        }
      end)

    trend =
      Enum.map(0..6, fn day ->
        date = Date.add(first_day, day)

        %{date: date, count: Map.get(daily_merges, date, 0)}
      end)

    %{
      repos: repos,
      needs: active_needs,
      running: active_running,
      queue: active_queue,
      projects: projects,
      merged_today: Map.get(daily_merges, local_day, 0),
      seen_today: seen_today |> Map.values() |> Enum.sum(),
      trend: trend
    }
  end

  defp day_start(date, offset) do
    date
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.add(offset * 60, :second)
  end

  defp today_item(task) do
    %{
      id: task.id,
      number: task.number,
      title: task.title,
      state: task.state,
      url: task.url,
      repository_id: task.repository_id,
      repo: "#{task.repository.owner}/#{task.repository.name}",
      started_at: task.started_at,
      at: today_time(task.state_changed_at || task.updated_at)
    }
  end

  defp today_time(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp today_time(%DateTime{} = at), do: at
  defp today_time(_at), do: nil
end
