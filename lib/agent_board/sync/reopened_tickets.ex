defmodule AgentBoard.Sync.ReopenedTickets do
  @moduledoc """
  An open issue with an ended, merged ticket may be rework, or simply an
  issue mentioned by a merged PR. Only a native reopen establishes the
  boundary. Never infer one from a comment or from the board's local clock.
  """
  import Ecto.Query
  require Logger
  alias AgentBoard.Board.Task
  alias AgentBoard.{GitHub, Repo}

  def reconcile(client, repo, issues, tickets) do
    # Legacy number-only tickets cannot establish which repository was merged.
    candidates =
      for {n,
           %{"ended_outcome" => "merged", "ended_at" => %DateTime{} = ended, "repository" => slug}} <-
            tickets,
          is_binary(slug),
          %{"state" => "open"} <- [issues[n]],
          into: %{},
          do: {n, ended}

    if map_size(candidates) > 0, do: verify(client, repo, candidates)
  end

  defp verify(client, repo, candidates) do
    numbers = Map.keys(candidates)

    from(t in Task,
      where:
        t.repository_id == ^repo.id and t.kind == "issue" and t.number in ^numbers and
          not t.stopped and not t.archived,
      select: {t.number, t.github_reopened_at}
    )
    |> Repo.all()
    |> Enum.reject(fn {n, at} -> at && DateTime.compare(at, candidates[n]) in [:eq, :gt] end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.chunk_every(12)
    |> Enum.each(fn batch ->
      data = GitHub.issue_closures(client, repo, batch)
      Enum.each(batch, &record(repo, &1, candidates[&1], data["i#{&1}"]))
    end)
  rescue
    e in [GitHub.HTTPError, Req.TransportError, Req.HTTPError] ->
      Logger.warning(
        "Reopen history unavailable for #{repo.owner}/#{repo.name}: #{inspect(e.__struct__)}"
      )
  end

  defp record(repo, n, ended, %{
         "number" => n,
         "state" => "OPEN",
         "timelineItems" => %{"nodes" => [%{"__typename" => "ReopenedEvent", "createdAt" => raw}]}
       })
       when is_binary(raw) do
    with {:ok, at, _} <- DateTime.from_iso8601(raw),
         false <- DateTime.before?(at, ended) do
      now = DateTime.utc_now()

      from(t in Task,
        where:
          t.repository_id == ^repo.id and t.kind == "issue" and t.number == ^n and not t.stopped and
            not t.archived and (is_nil(t.github_reopened_at) or t.github_reopened_at < ^at)
      )
      |> Repo.update_all(
        set: [github_reopened_at: at, state: "queued", state_changed_at: now, updated_at: now]
      )
    end
  end

  defp record(_, _, _, _), do: :ok
end
