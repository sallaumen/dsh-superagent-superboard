defmodule AgentBoardWeb.BoardComponents.VoicePresenceTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AgentBoardWeb.BoardComponents.VoicePresence

  # VoicePresence (JS) writes each voice phase into the title; assistive
  # technology hears it only because the title is a live region.
  test "the title is the live region the voice phases are announced through" do
    html = render_component(&VoicePresence.stage/1, id: "voice-presence-board")

    assert html =~ ~s(id="voice-presence-board-title" class="voice-presence-title" role="status")
    refute html =~ "voice-feedback"
  end
end
