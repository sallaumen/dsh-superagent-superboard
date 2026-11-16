defmodule AgentBoard.Lanes.Attention.Item do
  @moduledoc "Assemble a task attention card from its content and the board's observations."

  alias AgentBoard.Board.PullRequest
  alias AgentBoard.Lanes.{Attention, CI}
  alias AgentBoard.Time

  @doc "Use the attention start for both age and novelty, and the linked PR for CI evidence."
  @spec build(map(), atom(), PullRequest.t() | nil, {String.t(), [map()]}, map()) :: map()
  def build(task, kind, pull, {why, actions}, context) do
    at = Attention.started_at(task, kind, context)
    ci = pull && CI.Badge.describe(pull, Map.get(context.local_ci, pull.number))

    %{
      key: "task-#{task.id}",
      id: task.id,
      number: task.number,
      kind: kind,
      title: task.title,
      why: why,
      ci: ci,
      pull_number: pull && pull.number,
      age_seconds: Time.age_seconds(at, context.now),
      is_new: Time.new_since?(at, context.last_visit),
      actions: actions
    }
  end
end
