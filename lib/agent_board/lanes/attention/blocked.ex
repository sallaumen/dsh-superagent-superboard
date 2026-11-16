defmodule AgentBoard.Lanes.Attention.Blocked do
  @moduledoc "The actions available on a blocked task's attention card."
  use Gettext, backend: AgentBoardWeb.Gettext

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
