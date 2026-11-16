defmodule AgentBoard.Lanes.Digest.ChangePhrases do
  @moduledoc "Translate returning-visit facts into segments with their roles and links."
  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Lanes.Digest
  alias AgentBoard.Lanes.Digest.Sentence

  @doc "Keep facts in reading order; only review phrases receive the observed PR link."
  @spec segments([Digest.change()], map() | nil) :: [map()]
  def segments(facts, latest_review) do
    facts |> Enum.map(&phrase(&1, latest_review)) |> Sentence.join(gettext("and"))
  end

  defp phrase({:questions, n}, _pr) do
    %{text: ngettext("it asked %{count} question", "it asked %{count} questions", n), role: :you}
  end

  defp phrase({:queue_new, n}, _pr) do
    %{text: ngettext("%{count} new in the queue", "%{count} new in the queue", n), role: :agent}
  end

  defp phrase({:merged, merged}, _pr) do
    text = ngettext("the agent merged %{count} PR", "the agent merged %{count} PRs", merged)
    %{text: text, role: :agent}
  end

  defp phrase({:reviews, n}, pr) do
    %{
      text: ngettext("it opened %{count} PR for review", "it opened %{count} PRs for review", n),
      role: :you,
      url: pr && pr.url
    }
  end

  defp phrase({:running, {:task, id, number}}, _pr) do
    %{
      text: gettext("it is working on #%{number}", number: number),
      role: :agent,
      task_id: id
    }
  end

  defp phrase({:running, n}, _pr) do
    %{text: gettext("it is working on %{count} tasks", count: n), role: :agent}
  end

  defp phrase({:blocked, {:task, id, number}}, _pr) do
    %{
      text: gettext("#%{number} is still blocked", number: number),
      role: :halt,
      task_id: id
    }
  end

  defp phrase({:blocked, n}, _pr) do
    %{text: gettext("%{count} are still blocked", count: n), role: :halt}
  end
end
