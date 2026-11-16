defmodule AgentBoard.Lanes.Attention.ReportNotice do
  @moduledoc "What the board can say from a recorded question or blockage and the ticket report."
  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Lanes.ReportQuote

  @doc "Describe the question when one can be quoted, or direct the owner to the conversation."
  @spec question(String.t() | nil, String.t() | nil) :: String.t()
  def question(recorded, summary) do
    case ReportQuote.question(recorded, summary) do
      nil ->
        gettext("**The agent is waiting for your answer.** Open the conversation and reply.")

      quote ->
        gettext("**The agent asked:** %{question}", question: quote)
    end
  end

  @doc "Describe a reported blockage without inventing a reason when evidence is missing."
  @spec blockage(String.t() | nil, String.t() | nil) :: String.t()
  def blockage(recorded, summary) do
    case ReportQuote.blockage(recorded, summary) do
      nil ->
        gettext("**Blocked**, with no reason in the agent's report. Open the details.")

      quote ->
        gettext("**Blocked:** %{reason}", reason: quote)
    end
  end
end
