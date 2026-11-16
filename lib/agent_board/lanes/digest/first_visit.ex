defmodule AgentBoard.Lanes.Digest.FirstVisit do
  @moduledoc "Present the board facts known on a visitor's first visit."
  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Lanes.Digest.{Sentence, Visit}
  alias AgentBoard.Time

  @doc "An empty board has no first-visit digest, even if sync is interrupted."
  @spec build([{atom(), pos_integer()}], Visit.t()) :: map() | nil
  def build([], _visit), do: nil

  def build(facts, visit) do
    %{
      prefix: prefix(visit.sync, visit.offset),
      segments: facts |> Enum.map(&phrase/1) |> Sentence.join(gettext("and")),
      suffix:
        if(visit.sync != :live, do: " " <> gettext("After that, we do not know."), else: "."),
      now: visit.now
    }
  end

  defp phrase({:running, n}),
    do: %{text: gettext("%{count} running", count: n), role: :agent}

  defp phrase({:retrying, n}),
    do: %{text: gettext("%{count} in automatic retry", count: n), role: :agent}

  defp phrase({:waiting, n}),
    do: %{text: ngettext("%{count} waiting for you", "%{count} waiting for you", n), role: :you}

  defp phrase({:blocked, n}),
    do: %{text: pngettext("digest", "%{count} blocked", "%{count} blocked", n), role: :halt}

  defp phrase({:queued, n}),
    do: %{text: gettext("%{count} in the queue", count: n), role: :agent}

  defp prefix({:through, frozen_at}, offset),
    do: gettext("Until %{time}:", time: Time.local_time(frozen_at, offset)) <> " "

  defp prefix(:unconfirmed, _offset), do: gettext("Without a completed sync:") <> " "
  defp prefix(:live, _offset), do: gettext("First visit:") <> " "
end
