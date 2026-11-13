defmodule AgentBoard.Sync.BlockedMerges do
  @moduledoc """
  Resolve a stale block without waiting for the next full mirror or a Harness poll.
  The bot's report is historical: only GitHub can establish that this issue was
  actually closed by this ticket's merged PR. Never mutate the agent's SQLite.
  """
  use Oban.Worker,
    queue: :sync,
    max_attempts: 2,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  require Logger
  import Ecto.Query
  alias AgentBoard.{AgentState, Board, GitHub, Repo, Tickets}
  alias AgentBoard.Board.{Repository, Task}

  @impl true
  def perform(%Oban.Job{scheduled_at: at}) do
    if GitHub.configured?() && (is_nil(at) || DateTime.diff(DateTime.utc_now(), at) < 120),
      do: check(GitHub.client(), AgentState.tickets()),
      else: :ok
  end

  @doc false
  def check(client, tickets, now \\ DateTime.utc_now()) do
    tasks =
      Repo.all(
        from t in Task,
          join: r in Repository,
          on: r.id == t.repository_id,
          where:
            r.active and t.kind == "issue" and t.state == "blocked" and not t.stopped and
              not t.archived,
          select: {r, t},
          order_by: t.id
      )

    tasks
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.each(fn {repo, rows} -> check_repo(client, repo, rows, tickets, now) end)

    :ok
  rescue
    e in GitHub.RateLimited -> {:snooze, max(60, e.retry_after || 60)}
  end

  defp check_repo(client, repo, rows, tickets, now) do
    by_number =
      tickets
      |> Enum.filter(&(&1["repository"] && AgentState.same_repository?(&1, repo)))
      |> Tickets.by_number()

    candidates = Enum.flat_map(rows, &candidate(&1, by_number[&1.number]))

    # One request/repo/minute, rotating pages rather than starving older blocks.
    pages = Enum.chunk_every(candidates, 12)

    unless pages == [] do
      batch = Enum.at(pages, rem(div(DateTime.to_unix(now), 60), length(pages)))
      data = GitHub.issue_closures(client, repo, Enum.map(batch, fn {t, _} -> t.number end))

      Enum.each(batch, fn {task, ticket} ->
        resolve(repo, task, ticket, data["i#{task.number}"], now)
      end)
    end
  rescue
    e in [GitHub.HTTPError, Req.TransportError, Req.HTTPError] ->
      Logger.warning(
        "Issue closure check unavailable for #{repo.owner}/#{repo.name}: #{inspect(e.__struct__)}"
      )
  end

  defp candidate(
         task,
         %{"report" => "blocked", "ended_at" => nil, "own_threads" => [_ | _]} = ticket
       ) do
    if Tickets.state(ticket) == "blocked", do: [{task, ticket}], else: []
  end

  defp candidate(_, _), do: []

  defp resolve(
         repo,
         %{number: n} = task,
         ticket,
         %{
           "number" => n,
           "state" => "CLOSED",
           "timelineItems" => %{
             "nodes" => [
               %{
                 "__typename" => "ClosedEvent",
                 "closer" => %{
                   "__typename" => "PullRequest",
                   "number" => pr,
                   "mergedAt" => at,
                   "repository" => %{"nameWithOwner" => slug}
                 }
               }
             ]
           }
         },
         now
       )
       when is_binary(at) and is_binary(slug) do
    with true <- String.downcase(slug) == String.downcase("#{repo.owner}/#{repo.name}"),
         true <- pr in ticket["own_threads"],
         {:ok, merged, _} <- DateTime.from_iso8601(at),
         %DateTime{} = start <- ticket["started_at"],
         false <- DateTime.before?(merged, start) do
      mark_done(repo, task, ticket, pr, now)
    end
  end

  defp resolve(_, _, _, _, _), do: :ok

  defp mark_done(repo, task, ticket, pr, now) do
    # A stop, archive or newer state observed while GitHub answered wins.
    query =
      from t in Task,
        where:
          t.id == ^task.id and t.state == "blocked" and
            t.updated_at == ^task.updated_at and not t.stopped and not t.archived

    result =
      Repo.transact(fn ->
        case Repo.update_all(query, set: [state: "done", updated_at: now, state_changed_at: now]) do
          {1, _} ->
            Board.log_event(repo.id, "blocked_issue_merged", "##{task.number}", %{
              "pull" => pr,
              "ticket" => ticket["id"]
            })

          _ ->
            {:ok, nil}
        end
      end)

    if match?({:ok, %{}}, result), do: Board.broadcast(repo.id)
  end
end
