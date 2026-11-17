defmodule AgentBoard.Sync.PullEvidence do
  @moduledoc "Bounded comment-evidence refresh, independent of GitHub review/check rollups."
  import Ecto.Query
  alias AgentBoard.{Board, GitHub, Repo}
  alias AgentBoard.Board.PullRequest

  def refresh_at(nil, _pull, now), do: now

  def refresh_at(existing, pull, now) do
    at =
      case DateTime.from_iso8601(pull["updated_at"] || "") do
        {:ok, at, _} -> DateTime.truncate(at, :second)
        _ -> nil
      end

    if at != existing.evidence_source_updated_at or
         get_in(pull, ["head", "sha"]) != existing.head_sha,
       do: now,
       else: existing.evidence_refresh_at
  end

  def refresh_one(client, repository) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    cutoff = DateTime.add(now, -30, :day)

    due =
      from p in PullRequest,
        where: p.repository_id == ^repository.id and p.evidence_refresh_at <= ^now,
        where: p.state == "open" or p.merged_at >= ^cutoff,
        order_by: [desc_nulls_first: p.merged_at, asc: p.evidence_refresh_at, desc: p.id],
        limit: 1

    if pull = Repo.one(due), do: refresh(client, repository, pull, now)
  end

  defp refresh(client, repository, pull, now) do
    comments = GitHub.pull_comments(client, repository.owner, repository.name, pull.number)
    # Construct links from the endpoint we read; never render an arbitrary URL from a body.
    comments =
      Enum.map(comments, fn comment ->
        Map.put(
          comment,
          "html_url",
          "https://github.com/#{repository.owner}/#{repository.name}/pull/#{pull.number}#issuecomment-#{comment["id"]}"
        )
      end)

    evidence = AgentBoard.PullEvidence.parse(comments)

    Repo.update_all(from(p in PullRequest, where: p.id == ^pull.id),
      set: [reported_evidence: evidence, evidence_refresh_at: nil]
    )
  rescue
    error in GitHub.RateLimited ->
      reraise error, __STACKTRACE__

    error ->
      Repo.update_all(from(p in PullRequest, where: p.id == ^pull.id),
        set: [evidence_refresh_at: DateTime.add(now, 1, :hour)]
      )

      Board.log_event(repository.id, "pull_evidence_error", "##{pull.number}", %{
        "reason" => Exception.message(error)
      })
  end
end
