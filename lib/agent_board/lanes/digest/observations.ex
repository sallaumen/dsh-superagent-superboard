defmodule AgentBoard.Lanes.Digest.Observations do
  @moduledoc "Read the repository changes used by a returning visitor's digest."

  import Ecto.Query

  alias AgentBoard.Board.{PullRequest, Task}
  alias AgentBoard.Repo

  @doc "Count changes at or after the visit and find the newest PR from the same open-review set."
  @spec since(map(), DateTime.t()) :: %{counts: map(), latest_review: PullRequest.t() | nil}
  def since(repository, last_visit) do
    merged = merged_count(repository, last_visit)
    {reviews, latest_review} = review_summary(repository, last_visit)

    counts = %{
      merged: merged,
      reviews: reviews,
      questions: question_count(repository, last_visit),
      queue_new: queue_new_count(repository, last_visit)
    }

    %{counts: counts, latest_review: latest_review}
  end

  defp merged_count(repository, last_visit) do
    Repo.aggregate(
      from(p in PullRequest,
        where:
          p.repository_id == ^repository.id and p.state == "merged" and
            p.merged_at >= ^last_visit
      ),
      :count
    )
  end

  # Count the full review set before limiting the result to its newest link.
  defp review_summary(repository, last_visit) do
    query =
      from p in PullRequest,
        where:
          p.repository_id == ^repository.id and p.state == "open" and p.opened_at >= ^last_visit,
        order_by: [desc: p.opened_at, desc: p.id],
        limit: 1,
        select: {over(count(p.id)), p}

    Repo.one(query) || {0, nil}
  end

  defp question_count(repository, last_visit) do
    Repo.aggregate(
      from(t in Task,
        where:
          t.repository_id == ^repository.id and t.state == "question" and
            t.state_changed_at >= ^last_visit
      ),
      :count
    )
  end

  defp queue_new_count(repository, last_visit) do
    Repo.aggregate(
      from(t in Task,
        where:
          t.repository_id == ^repository.id and t.state == "queued" and
            t.inserted_at >= ^last_visit
      ),
      :count
    )
  end
end
