defmodule AgentBoard.Lanes.Attention.Item do
  @moduledoc "Assemble a task attention card from its content and the board's observations."

  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Board.PullRequest
  alias AgentBoard.Lanes.{Attention, CI}
  alias AgentBoard.Time

  @doc """
  Build a selected task card from the evidence the lane has already observed.

  A blocked candidate carries its ticket explanation in `:block` (possibly
  nil); its recorded fallback is keyed by repository and issue in the context.
  """
  @spec build(map(), map()) :: map()
  def build(%{task: task, kind: kind} = candidate, context) do
    pull = context.pulls[task.id]
    build(task, kind, pull, content(candidate, pull, context), context)
  end

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

  defp content(%{kind: :unanswered, task: task, problem: problem}, _pull, context),
    do: Attention.CallNotice.content(problem, task, context)

  defp content(%{kind: :blocked, task: task, block: block}, _pull, context) do
    recorded = get_in(context.blockages, [task.repository_id, task.number])
    Attention.Blocked.content(task, block, recorded, summary(task, context))
  end

  defp content(%{kind: :review, task: task}, pull, context),
    do: Attention.Review.content(task.id, pull, summary(task, context))

  defp content(%{kind: :question, task: task}, _pull, context) do
    Attention.Question.content(task.id, context.questions[task.number], summary(task, context))
  end

  defp content(%{kind: :stalled, task: task}, _pull, context) do
    why =
      Attention.RunNotice.stalled(Map.fetch!(context.silences, task.number), context.tz_offset)

    {why, details(task)}
  end

  defp content(%{kind: :slow, task: task}, _pull, context) do
    why =
      Attention.RunNotice.slow(
        task,
        context.silences[task.number],
        context.now,
        context.tz_offset
      )

    {why, details(task)}
  end

  defp details(task), do: [%{label: gettext("View details"), task_id: task.id}]
  defp summary(task, context), do: get_in(context.tickets, [task.number, "report_summary"])
end
