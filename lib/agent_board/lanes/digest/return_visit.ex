defmodule AgentBoard.Lanes.Digest.ReturnVisit do
  @moduledoc "Present observed changes and distinguish a quiet board from a sync that never completed."
  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Lanes.Digest
  alias AgentBoard.Lanes.Digest.{ChangePhrases, Visit}
  alias AgentBoard.Time

  @doc "Assemble a sentence from known facts using the reader's visit time and sync evidence."
  @spec build([Digest.change()], map() | nil, Visit.t()) :: map()
  def build(facts, review, visit) do
    segments =
      case ChangePhrases.segments(facts, review) do
        [] ->
          text =
            if visit.sync == :unconfirmed,
              do: gettext("we do not know what changed"),
              else: gettext("nothing changed")

          [%{text: text, role: :plain}]

        segments ->
          segments
      end

    %{
      prefix: prefix(visit),
      segments: segments,
      suffix: suffix(visit.sync),
      now: visit.now
    }
  end

  defp prefix(%{sync: {:through, at}, offset: offset}),
    do: gettext("Until %{time},", time: Time.local_time(at, offset)) <> " "

  defp prefix(%{sync: :unconfirmed}),
    do: gettext("Without a completed sync,") <> " "

  defp prefix(%{sync: :live} = visit),
    do:
      gettext("Since %{since}",
        since: Time.since_label(visit.last_visit, visit.offset, visit.now)
      ) <> " "

  defp suffix({:through, _at}), do: ". " <> gettext("After that, we do not know.")
  defp suffix(_sync), do: "."
end
