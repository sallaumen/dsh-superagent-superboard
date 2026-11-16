defmodule AgentBoard.Lanes.Attention.Outage do
  @moduledoc "The single attention card for work waiting on an unavailable orchestrator."

  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Superagents.Superagent

  @doc "Describe how much work waits and carry the repository's observed agent into the restart action."
  @spec card(non_neg_integer(), Superagent.t() | nil) :: map()
  def card(waiting, superagent) do
    tail =
      case waiting do
        0 ->
          gettext("Nothing moves until it is back.")

        n ->
          ngettext(
            "%{count} task waits for it to come back; network failures are retried on their own.",
            "%{count} tasks wait for it to come back; network failures are retried on their own.",
            n
          )
      end

    %{
      key: "agent-down",
      id: nil,
      number: nil,
      kind: :agent_down,
      title: gettext("No new task starts until it is back"),
      why: gettext("**The orchestrator is not responding.**") <> " " <> tail,
      ci: nil,
      age_seconds: nil,
      is_new: false,
      waiting: waiting,
      actions: [
        %{label: gettext("Restart the agent"), restart_agent: true, superagent: superagent}
      ]
    }
  end
end
