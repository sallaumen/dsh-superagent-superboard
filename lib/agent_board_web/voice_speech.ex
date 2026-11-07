defmodule AgentBoardWeb.VoiceSpeech do
  @moduledoc "The URL the browser fetches to hear a text in the agent's ElevenLabs voice."

  @doc "`/api/voice/speech?text=...&voice=...`"
  def url(text, voice_id) do
    "/api/voice/speech?text=" <>
      URI.encode_www_form(text) <> "&voice=" <> URI.encode_www_form(voice_id)
  end
end
