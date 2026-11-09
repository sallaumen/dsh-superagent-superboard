defmodule AgentBoardWeb.BoardComponents.VoiceActivityFeedTest do
  @moduledoc "The voice feed's summary says what ElevenLabs cost today."
  use AgentBoard.DataCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.ElevenLabs.Usage
  alias AgentBoardWeb.BoardComponents.VoiceActivityFeed

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "pt_BR")
    :ok
  end

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

  test "English usage uses English labels and number separators" do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")

    assert VoiceActivityFeed.usage(
             day(tts_characters: 3420, stt_seconds: 72.0, cache_hits: 18),
             20_000
           ) == "today: 3,420 of 20,000 characters · 1.2 min transcribed · 18 from cache"
  end

  test "the rendered feed reads today's ledger" do
    Usage.record_tts(1500, :paid)
    Usage.record_tts(0, :cache)

    html = render_component(&VoiceActivityFeed.feed/1, events: [])
    assert html =~ "voice-usage-today"
    assert html =~ "hoje: 1.500 de 20.000 caracteres · 1 do cache"
  end

  test "an event's clock is the browser's, not UTC" do
    event = %{at: ~U[2026-11-09 14:15:30Z], stage: :tts, status: :ok, detail: "ok", ms: nil}

    html = render_component(&VoiceActivityFeed.feed/1, events: [event], tz_offset: 180)

    assert html =~ "11:15:30"
    refute html =~ "14:15:30<"
  end
end
