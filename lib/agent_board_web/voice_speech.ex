defmodule AgentBoardWeb.VoiceSpeech do
  @moduledoc """
  Where the agent's voice comes from, decided in one place.

  `push/3` answers the LiveView event and payload for a text through ElevenLabs,
  or returns `nil` when paid speech is unavailable. The kind decides length:

    * `:call` - a call for attention or the coding agent's reply.
    * `:reply` - the conversation's free answer; with `short` replies only
      its first sentence is spoken (the whole text is written).
    * `:confirm` - a proposal, confirmation or requested status, spoken whole.

  Without an ElevenLabs key or available credits, the written response remains
  visible and nothing speaks.
  """

  alias AgentBoard.ElevenLabs.{Account, Usage}
  alias AgentBoard.Voice.Speakable

  @doc "`/api/voice/stream?text=...&voice=...`"
  def url(text, voice_id, language) do
    "/api/voice/stream?" <>
      URI.encode_query([{"text", text(text)}, {"voice", voice_id}, {"language", language}])
  end

  @doc "The text as it should be read out loud (see `AgentBoard.Voice.Speakable`)."
  def text(text), do: Speakable.clean(text)

  @doc """
  The event and payload that speak `text` with the owner's voice settings
  (`voice` is the LiveView's voice assign). Options: `:kind` (default
  `:confirm`) and `:listen` (reopen the input after the reply).
  """
  @spec push(map(), String.t(), keyword()) :: {String.t(), map()} | nil
  def push(voice, text, opts \\ []) do
    kind = Keyword.get(opts, :kind, :confirm)
    listen = Keyword.get(opts, :listen, false)
    spoken = spoken(text, kind, Map.get(voice, :replies, "short"))

    if elevenlabs?(voice, kind) do
      {"voice_play", %{url: url(spoken, voice.id, voice.language), listen: listen, text: text}}
    else
      nil
    end
  end

  @doc "Whether ElevenLabs can speak right now."
  def elevenlabs?(voice, _kind),
    do: Map.get(voice, :configured, false) and not over_cap?() and not Account.spent?()

  @doc "The part of a reply that is spoken: the first sentence of a short reply."
  def spoken(text, :reply, "short"), do: first_sentences(text)
  def spoken(text, _kind, _replies), do: text

  # A very short first sentence ("Oi!") takes the next one along.
  defp first_sentences(text) do
    case Regex.split(~r/(?<=[.!?…])\s+/u, String.trim(text), parts: 3) do
      [one, two | _] when byte_size(one) < 25 -> one <> " " <> two
      [one | _] -> one
    end
  end

  # Past the daily cap or when plan credits are spent, stay silent.
  defp over_cap?, do: Usage.over_cap?()
end
