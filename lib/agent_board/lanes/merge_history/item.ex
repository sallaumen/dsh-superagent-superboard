defmodule AgentBoard.Lanes.MergeHistory.Item do
  @moduledoc "One visible merge in the board's history, in the reader's locale."

  alias AgentBoard.Lanes.Review

  alias AgentBoard.Board.PullRequest
  alias AgentBoard.Lanes.CI
  alias AgentBoard.Time
  alias AgentBoard.Usage.TaskCosts

  @doc "Present one PR with the supplied evidence. An unobserved cost stays nil."
  @spec build(PullRequest.t(), integer(), map() | nil, [TaskCosts.entry()] | nil) :: map()
  def build(pull, offset, local, cost) do
    badge = CI.Badge.describe(pull, local)

    %{
      id: pull.id,
      number: pull.number,
      title: pull.title,
      url: pull.url,
      closes: pull.closes_issues || [],
      ci: badge.state,
      ciNote: badge.note,
      ciTitle: badge.title,
      ciLocal: badge.local,
      review: Review.label(pull),
      evidence_pull: pull,
      at: Time.local_time(pull.merged_at, offset),
      cost: cost
    }
  end
end
