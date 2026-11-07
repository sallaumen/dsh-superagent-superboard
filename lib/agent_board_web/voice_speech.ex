defmodule AgentBoardWeb.VoiceSpeech do
  @moduledoc "The URL the browser plays to hear a text in the agent's ElevenLabs voice, streamed."

  alias AgentBoard.Voice.Speakable

  @doc "`/api/voice/stream?text=...&voice=...`"
  def url(text, voice_id) do
    "/api/voice/stream?text=" <>
      URI.encode_www_form(text(text)) <> "&voice=" <> URI.encode_www_form(voice_id)
  end

  @doc "The text as it should be read out loud (see `AgentBoard.Voice.Speakable`)."
  def text(text), do: Speakable.clean(text)
end
