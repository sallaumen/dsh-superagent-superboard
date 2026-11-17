defmodule AgentBoard.Lanes.Retry do
  @moduledoc "The Now row for an automatic retry, using the already observed failure explanation."
  use Gettext, backend: AgentBoardWeb.Gettext

  @doc "Keep task identity and the supplied explanation; missing evidence gives no invented retry time."
  @spec build(map(), map() | nil) :: map()
  def build(task, block) do
    %{
      id: task.id,
      number: task.number,
      title: task.title,
      line: (block && block.line) || gettext("**Automatic retry.** Waiting for the agent.")
    }
  end
end
