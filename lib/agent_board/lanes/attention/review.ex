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

  defp why(%PullRequest{number: number}, _summary),
    do: gettext("**PR #%{number} ready for review**", number: number)

  defp why(nil, summary) do
    case ReportQuote.summary(summary) do
      summary when is_binary(summary) ->
        gettext("**Ready for review**, PR not identified. The agent said: %{summary}",
          summary: summary
        )

      _ ->
        gettext("**Ready for review**, PR not identified by the board. Open the conversation.")
    end
  end
end
