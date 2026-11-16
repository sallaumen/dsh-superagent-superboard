defmodule AgentBoard.Sync.PullReviews do
  @moduledoc "Effective GitHub reviews and the one-time repair of previously cached verdicts."
  import Ecto.Query
  alias AgentBoard.{Board, GitHub, Repo}
  alias AgentBoard.Board.PullRequest

  # GitHub lists reviews chronologically. Comments and unsubmitted reviews
  # don't change a decision. A reviewer can supersede only their own vote.
  def rollup([]), do: "none"

  def rollup(reviews) do
    votes =
      reviews
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {review, index}, votes ->
        voter = voter(review["user"], index)

        case review["state"] do
          "CHANGES_REQUESTED" -> Map.put(votes, voter, :blocked)
          "APPROVED" -> Map.put(votes, voter, :approved)
          "DISMISSED" -> Map.delete(votes, voter)
          _ -> votes
        end
      end)
      |> Map.values()

    cond do
      :blocked in votes -> "changes_requested"
      :approved in votes -> "approved"
      true -> "pending"
    end
  end

  defp voter(%{"id" => id}, _) when is_integer(id), do: id
  defp voter(%{"login" => login}, _) when is_binary(login), do: String.downcase(login)
  defp voter(_, index), do: {:unknown, index}

  # The migration marks only legacy merged blockers. Fetch at most one PR's
  # reviews per repository cycle, even outside the normal pull-list window.
  def repair_one(client, repo) do
    now = DateTime.utc_now()

    due =
      from p in PullRequest,
        where:
          p.repository_id == ^repo.id and p.state == "merged" and p.review_refresh_at <= ^now,
        order_by: [asc: p.review_refresh_at, desc: p.merged_at, asc: p.id],
        limit: 1

    if pull = Repo.one(due), do: repair(client, repo, pull, now)
  end

  defp repair(client, repo, pull, now) do
    row = from p in PullRequest, where: p.id == ^pull.id and p.state == "merged"

    state = client |> GitHub.reviews(repo.owner, repo.name, pull.number) |> rollup()
    Repo.update_all(row, set: [review_state: state, review_refresh_at: nil])
  rescue
    error in GitHub.RateLimited ->
      reraise error, __STACKTRACE__

    error in [GitHub.HTTPError, Req.TransportError] ->
      # Preserve the last verdict and let other due PRs through on the next cycle.
      retry_at = DateTime.add(now, 1, :hour)

      Repo.update_all(from(p in PullRequest, where: p.id == ^pull.id),
        set: [review_refresh_at: retry_at]
      )

      Board.log_event(repo.id, "review_error", "##{pull.number}", %{
        "reason" => Exception.message(error)
      })
  end
end
