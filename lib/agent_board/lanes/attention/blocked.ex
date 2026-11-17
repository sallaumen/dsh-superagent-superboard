defmodule AgentBoard.Lanes.Attention.Blocked do
  @moduledoc "Evidence and actions for a blocked task's attention card."
  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Lanes.Attention.ReportNotice

  @doc "Use the explained failure for both text and actions, otherwise quote the recorded blockage or ticket summary."
  @spec content(map(), map() | nil, String.t() | nil, String.t() | nil) :: {String.t(), [map()]}
  def content(task, nil, recorded, summary),
    do: {ReportNotice.blockage(recorded, summary), actions(task, nil)}

  def content(task, block, _recorded, _summary), do: {block.line, actions(task, block)}

  @doc "Offer a retry before the task details only when both its label and ticket target were observed."
  @spec actions(map(), map() | nil) :: [map()]
  def actions(task, block) do
    detail = %{label: gettext("View details"), task_id: task.id}

    case block do
      %{retry: label, ticket_id: ticket_id} when is_binary(label) and is_binary(ticket_id) ->
        retry = %{ticket_id: ticket_id, repository_id: task.repository_id, number: task.number}
        [%{label: label, retry: retry}, detail]

      _no_retry ->
        [detail]
    end
  end
end
