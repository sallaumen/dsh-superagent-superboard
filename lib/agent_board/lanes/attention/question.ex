defmodule AgentBoard.Lanes.Attention.Question do
  @moduledoc "Evidence and content rules for visible question cards."

  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Lanes.Attention.ReportNotice

  @doc "Select visible question issue numbers, retaining their order and occurrences."
  @spec report_numbers([map()]) :: [integer()]
  def report_numbers(visible) do
    for %{kind: :question, task: %{number: number}} <- visible,
        is_integer(number),
        do: number
  end

  @doc "Keep the question explanation and its response action attached to the same task."
  @spec content(integer(), String.t() | nil, String.t() | nil) :: {String.t(), [map()]}
  def content(task_id, recorded, summary) do
    why = ReportNotice.question(recorded, summary)
    {why, [%{label: gettext("Respond"), task_id: task_id}]}
  end
end
