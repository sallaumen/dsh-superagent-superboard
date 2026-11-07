defmodule AgentBoardWeb.BoardComponents.VoiceActivityFeedTest do
  @moduledoc "The voice feed's summary says what ElevenLabs cost today."
  use AgentBoard.DataCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.ElevenLabs.Usage
  alias AgentBoardWeb.BoardComponents.VoiceActivityFeed

  defp day(fields), do: Map.merge(Usage.today(), Map.new(fields))

  test "the usage line shows characters against the cap, minutes and cache hits" do
    line =
      VoiceActivityFeed.usage(
        day(tts_characters: 3420, stt_seconds: 72.0, cache_hits: 18),
        20_000
      )

    assert line == "hoje: 3.420 de 20.000 caracteres · 1,2 min transcritos · 18 do cache"
  end

  test "without a cap, minutes or hits the line is only the characters" do
    assert VoiceActivityFeed.usage(day([]), 0) == "hoje: 0 caracteres"
  end

  test "the rendered feed reads today's ledger" do
    Usage.record_tts(1500, :paid)
    Usage.record_tts(0, :cache)

    html = render_component(&VoiceActivityFeed.feed/1, events: [])
    assert html =~ "voice-usage-today"
    assert html =~ "hoje: 1.500 de 20.000 caracteres · 1 do cache"
  end
end
