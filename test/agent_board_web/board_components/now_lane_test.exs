defmodule AgentBoardWeb.BoardComponents.NowLaneTest do
  @moduledoc "The running card's step line."
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AgentBoardWeb.BoardComponents.NowLane

  # A commit subject can be 80 characters: the note may shrink to the card,
  # cut with an ellipsis, and keeps the whole subject in its title.
  test "a long commit subject shrinks inside the card and keeps its whole text" do
    subject = String.duplicate("Ajusta o placar e o HUD ", 4)

    task = %{
      id: 1,
      number: 7,
      title: "Placar",
      elapsed: nil,
      agent: nil,
      stalled: false,
      step: %{kind: :commit, code: "44653e8", note: subject},
      phases: []
    }

    html = render_component(&NowLane.now_lane/1, running: [task])

    assert html =~ ~s(class="ab-meta ab-run__note")
    assert html =~ ~s(title="#{subject}")
  end
end
