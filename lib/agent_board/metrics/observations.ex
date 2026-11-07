defmodule AgentBoard.Metrics.Observations do
  @moduledoc """
  What the board has actually recorded for one repository, read for the
  throughput block: timestamps from the tables, the agent's ended tickets and
  the orchestrator's load. `AgentBoard.Metrics.throughput/3` does the
  arithmetic; this module only reads.

  Each source answers `{:ok, timestamps}` or `{:unknown, reason}`: a table that
  was never filled is unknown, not empty.
  """
  import Ecto.Query, warn: false

  alias AgentBoard.{Board, Orchestrator, Repo}
  alias AgentBoard.Board.{Commit, PullRequest, Repository, Task}

  @week 7 * 86_400

  @doc """
  The observations for a repository. `agent` is `AgentBoard.AgentState.snapshot/0`
  (its `ok` says whether the ticket database answered). Options: `:now` and
  `:load` (the orchestrator's answer; read live when absent).
  """
  @spec read(Repository.t(), map(), keyword()) :: map()
  def read(%Repository{} = repository, agent, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    since = DateTime.add(now, -@week, :second)
    tickets = repository_tickets(repository, agent.tickets)

    %{
      done: {:ok, done_at(repository, since)},
      opened: {:ok, opened_at(repository, since)},
      merged: {:ok, merged_at(repository, since)},
      commits: commits(repository, since),
      tickets: tickets_ended(agent, tickets, since),
      queue: queue_spans(repository, since),
      cycles: cycles(repository, tickets),
      load: Keyword.get_lazy(opts, :load, &Orchestrator.load/0)
    }
  end

  # Tasks the board marked done, by the instant it observed the change.
  defp done_at(repository, since) do
    Repo.all(
      from t in Task,
        where:
          t.repository_id == ^repository.id and t.state == "done" and
            t.state_changed_at >= ^since,
        select: t.state_changed_at
    )
  end

  # Issues by the instant the board first saw them.
  defp opened_at(repository, since) do
    Repo.all(
      from t in Task,
        where:
          t.repository_id == ^repository.id and t.kind == "issue" and t.inserted_at >= ^since,
        select: t.inserted_at
    )
  end

  defp merged_at(repository, since) do
    Repo.all(
      from p in PullRequest,
        where: p.repository_id == ^repository.id and p.merged_at >= ^since,
        select: p.merged_at
    )
  end

  # Rows prove the branch was read. Without rows, the latest completed sync
  # must carry the "commits" count (zero included); otherwise nothing was read.
  defp commits(repository, since) do
    rows =
      Repo.all(
        from c in Commit,
          where: c.repository_id == ^repository.id and c.committed_at >= ^since,
          select: c.committed_at
      )

    cond do
      rows != [] -> {:ok, rows}
      commits_read?(repository) -> {:ok, []}
      true -> {:unknown, :never_synced}
    end
  end

  defp commits_read?(repository) do
    case Board.latest_sync(repository) do
      %{kind: "sync", payload: %{"commits" => n}} when is_integer(n) -> true
      _ -> false
    end
  end

  # The agent's tickets that worked this repository: the ones whose channel
  # is one of its issues. A ticket without a channel URL is nobody's.
  defp repository_tickets(repository, tickets) do
    marker = "github.com/#{repository.owner}/#{repository.name}/"

    Enum.filter(tickets, fn ticket ->
      Enum.any?(ticket["channel_urls"] || [], &String.contains?(&1, marker))
    end)
  end

  @ended_outcomes ["merged", "completed"]

  defp tickets_ended(%{ok: false}, _tickets, _since), do: {:unknown, :agent_unavailable}

  defp tickets_ended(_agent, tickets, since) do
    ended =
      for ticket <- tickets,
          ticket["ended_outcome"] in @ended_outcomes,
          %DateTime{} = at <- [ticket["ended_at"]],
          DateTime.compare(at, since) != :lt,
          do: at

    {:ok, ended}
  end

  # A task is queued from the instant the board saw it until it started
  # (`started_at`, the ticket's own clock) or, failing that, until its state
  # changed. A task that left the queue at an unknown instant is left out.
  defp queue_spans(repository, since) do
    Repo.all(
      from t in Task,
        where:
          t.repository_id == ^repository.id and
            (t.state == "queued" or t.started_at >= ^since or t.state_changed_at >= ^since),
        select: {t.inserted_at, t.state, t.started_at, t.state_changed_at}
    )
    |> Enum.flat_map(fn {inserted_at, state, started_at, changed_at} ->
      case left_queue_at(state, started_at, changed_at) do
        :unknown -> []
        left_at -> [{inserted_at, left_at}]
      end
    end)
  end

  defp left_queue_at("queued", _started_at, _changed_at), do: nil
  defp left_queue_at(_state, %DateTime{} = started_at, _changed_at), do: started_at
  defp left_queue_at(_state, nil, %DateTime{} = changed_at), do: changed_at
  defp left_queue_at(_state, nil, nil), do: :unknown

  # One cycle per ticket that ended merged: the issue the board first saw
  # (its channel numbers), the PR the ticket opened itself (`own_threads`,
  # the newest) and that PR's merge.
  defp cycles(repository, tickets) do
    merged = Enum.filter(tickets, &(&1["ended_outcome"] == "merged"))

    issue_numbers = merged |> Enum.flat_map(&(&1["numbers"] || [])) |> Enum.uniq()
    pr_numbers = merged |> Enum.flat_map(&(&1["own_threads"] || [])) |> Enum.uniq()

    issues =
      Repo.all(
        from t in Task,
          where: t.repository_id == ^repository.id and t.number in ^issue_numbers,
          select: {t.number, t.inserted_at}
      )
      |> Map.new()

    pulls =
      Repo.all(
        from p in PullRequest,
          where: p.repository_id == ^repository.id and p.number in ^pr_numbers,
          select: {p.number, {p.opened_at, p.merged_at}}
      )
      |> Map.new()

    Enum.flat_map(merged, &cycle(&1, issues, pulls))
  end

  defp cycle(ticket, issues, pulls) do
    issue_at =
      (ticket["numbers"] || [])
      |> Enum.map(&Map.get(issues, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.min(DateTime, fn -> nil end)

    with pr_number when not is_nil(pr_number) <-
           Enum.max(ticket["own_threads"] || [], fn -> nil end),
         {opened_at, merged_at} <- Map.get(pulls, pr_number) do
      [%{issue_at: issue_at, pr_at: opened_at, merged_at: merged_at}]
    else
      _ -> []
    end
  end
end
