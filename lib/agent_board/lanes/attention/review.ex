defmodule AgentBoard.Lanes.Attention.Review do
  @moduledoc "The explanation and destinations on a ready-for-review card."
  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Board.PullRequest
  alias AgentBoard.Lanes.ReportQuote

  @doc "Always offer the task. Offer a PR destination only when the linked pull supplies a URL."
  @spec content(integer(), PullRequest.t() | nil, String.t() | nil) :: {String.t(), [map()]}
  def content(task_id, pull, summary) do
    task_action = %{label: gettext("Review"), task_id: task_id}

    actions =
      case pull do
        %PullRequest{url: url, number: number} when is_binary(url) ->
          [task_action, %{label: gettext("Open PR #%{number}", number: number), url: url}]

        _ ->
          [task_action]
      end

    {why(pull, summary), actions}
  end

  @doc "Prefer the linked PR; otherwise use a bounded report summary or leave the PR unidentified."
  @spec subject(PullRequest.t() | nil, String.t() | nil) ::
          {:pull, integer()} | {:summary, String.t()} | :unidentified
  def subject(%PullRequest{number: number}, _summary), do: {:pull, number}

  def subject(nil, summary) do
    case ReportQuote.summary(summary) do
      summary when is_binary(summary) -> {:summary, summary}
      _ -> :unidentified
    end
  end

  defp why(pull, summary) do
    case subject(pull, summary) do
      {:pull, number} ->
        gettext("**PR #%{number} ready for review**", number: number)

      {:summary, summary} ->
        gettext("**Ready for review**, PR not identified. The agent said: %{summary}",
          summary: summary
        )

      :unidentified ->
        gettext("**Ready for review**, PR not identified by the board. Open the conversation.")
    end
  end
end
