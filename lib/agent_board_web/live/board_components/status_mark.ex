defmodule AgentBoardWeb.BoardComponents.StatusMark do
  @moduledoc """
  A state is a shape plus a word.

  The color confirms the meaning; it never carries it alone. `agent` and
  `halt` have similar lightness, so a screen reader and a person both get the
  glyph and the word.
  """
  use AgentBoardWeb, :html

  @statuses %{
    run: %{glyph: "run", tone: "run"},
    retrying: %{glyph: "queue", tone: "run"},
    agent_down: %{glyph: "halt", tone: "halt"},
    review: %{glyph: "you", tone: "you"},
    question: %{glyph: "you", tone: "you"},
    blocked: %{glyph: "halt", tone: "halt"},
    cifail: %{glyph: "halt", tone: "halt"},
    stalled: %{glyph: "halt", tone: "halt"},
    unanswered: %{glyph: "halt", tone: "halt"},
    queue: %{glyph: "queue", tone: "queue"},
    done: %{glyph: "done", tone: "done"},
    stale: %{glyph: "stale", tone: "stale"},
    unknown: %{glyph: "unknown", tone: "queue"}
  }

  attr :kind, :atom, required: true
  attr :word, :string, default: nil
  attr :live, :boolean, default: false

  def status_mark(assigns) do
    status = Map.get(@statuses, assigns.kind, @statuses.unknown)
    assigns = assign(assigns, :tone, status.tone)

    ~H"""
    <span class={"ab-status ab-status--#{@tone}"}>
      <.glyph kind={@kind} live={@live} />
      {@word || word(@kind)}
    </span>
    """
  end

  attr :kind, :atom, required: true
  attr :live, :boolean, default: false

  def glyph(assigns) do
    status = Map.get(@statuses, assigns.kind, @statuses.unknown)
    assigns = assign(assigns, :glyph, status.glyph)

    ~H"""
    <i
      class={"ab-g ab-g--#{@glyph}" <> if(@live, do: " is-live", else: "")}
      aria-hidden="true"
    ></i>
    """
  end

  defp word(:run), do: pgettext("status", "Running")
  defp word(:retrying), do: pgettext("status", "New attempt")
  defp word(:agent_down), do: pgettext("status", "Agent offline")
  defp word(:review), do: pgettext("status", "To review")
  defp word(:question), do: pgettext("status", "Question")
  defp word(:blocked), do: pgettext("status", "Blocked")
  defp word(:cifail), do: pgettext("status", "CI failed")
  defp word(:stalled), do: pgettext("status", "No signal")
  defp word(:unanswered), do: pgettext("status", "No answer")
  defp word(:queue), do: pgettext("status", "Queued")
  defp word(:done), do: pgettext("status", "Merged")
  defp word(:stale), do: pgettext("status", "Old data")
  defp word(_unknown), do: pgettext("status", "Unknown")
end
