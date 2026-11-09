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
  alias AgentBoard.Board.{Event, Repository, Task}

  @today_states ~w(blocked question ready running)
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
  @spec today() :: %{repos: map(), needs: [map()], running: [map()]}
  def today do
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

    %{
      repos: repo_overview(),
      needs: Enum.map(needs, &today_item/1),
      running: Enum.map(running, &today_item/1)
    }
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
