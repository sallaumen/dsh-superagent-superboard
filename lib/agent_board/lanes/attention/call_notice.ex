defmodule AgentBoard.Lanes.Attention.CallNotice do
  @moduledoc "Explain a queued call problem and offer the existing retry confirmation."
  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.{Actions, Release, Time}
  alias AgentBoardWeb.Locale

  @doc "Describe a failed or unanswered call from the verdict already used to select the card."
  @spec content(:failed | :unanswered, map(), map()) :: {String.t(), [map()]}
  def content(problem, task, context) do
    phrase =
      Actions.phrase(
        :release_task,
        %{task: task, repository: context.repository},
        Locale.language()
      )

    actions = [
      %{label: gettext("Call again"), release: phrase},
      %{label: gettext("View details"), task_id: task.id}
    ]

    {why(problem, task, context), actions}
  end

  defp why(:failed, %{released_at: at}, context) do
    gettext(
      "**The call to the agent did not complete.** The board tried %{since} and does not try again on its own.",
      since: Time.since_label(at, context.tz_offset, context.now)
    )
  end

  # What the board knows: it called, and no ticket names the issue. Why the
  # runner did not start is in the runner, so the item does not guess.
  defp why(:unanswered, task, context) do
    at = Release.called_at(task)

    gettext(
      "**Called %{ago} and the agent did not start.** The board posted the mention %{since} and no agent ticket names this issue.",
      ago: Time.ago(DateTime.diff(context.now, at)),
      since: Time.since_label(at, context.tz_offset, context.now)
    )
  end
end
