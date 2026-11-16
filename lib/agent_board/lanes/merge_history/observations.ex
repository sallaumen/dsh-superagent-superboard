defmodule AgentBoard.Lanes.MergeHistory.Observations do
  @moduledoc "The repository merges observed in the history window."
  import Ecto.Query

  alias AgentBoard.Board.{PullRequest, Repository}
  alias AgentBoard.Lanes.MergeHistory
  alias AgentBoard.Repo

  @doc "Read only merged PRs in the window, newest merge first with id as a stable tie-breaker."
  @spec in_window(Repository.t(), MergeHistory.window()) :: [PullRequest.t()]
  def in_window(repository, %{since: since, until: until}) do
    Repo.all(
      from p in PullRequest,
        where:
          p.repository_id == ^repository.id and p.state == "merged" and
            p.merged_at >= ^since and p.merged_at < ^until,
        order_by: [desc: p.merged_at, desc: p.id]
    )
  end
end
