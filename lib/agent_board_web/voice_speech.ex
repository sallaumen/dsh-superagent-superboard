defmodule AgentBoardWeb.VoiceSpeech do
  @moduledoc """
  Where the agent's voice comes from, decided in one place.

  `push/3` answers the LiveView event and payload for a text: the agent's
  ElevenLabs voice (`voice_play`, a stream URL, paid per character) or the
  browser's own voice (`speak`, free). The owner's engine setting decides,
  with the kind of utterance:

    * `:call` - a call for attention or the coding agent's reply; ElevenLabs
      in the `mixed` and `elevenlabs` engines.
    * `:reply` - the conversation's free answer; with `short` replies only
      its first sentence is spoken (the whole text is written).
    * `:confirm` - a proposal, a confirmation, a status the owner asked for:
      always spoken whole, ElevenLabs only in the `elevenlabs` engine.
    * `:narration` - the rest of the board, ElevenLabs only in `elevenlabs`.

  Without an ElevenLabs key, or once the day's character cap is reached,
  everything goes to the browser voice.
  """

  alias AgentBoard.ElevenLabs.Usage
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
  @spec push(map(), String.t(), keyword()) :: {String.t(), map()}
  def push(voice, text, opts \\ []) do
    kind = Keyword.get(opts, :kind, :confirm)
    listen = Keyword.get(opts, :listen, false)
    spoken = spoken(text, kind, Map.get(voice, :replies, "short"))

    if elevenlabs?(voice, kind) do
      {"voice_play", %{url: url(spoken, voice.id, voice.language), listen: listen, text: text}}
    else
      {"speak",
       %{
         text: text(spoken),
         display: text,
         lang: voice.language,
         rate: Map.get(voice, :speed, 1.0),
         listen: listen
       }}
    end
  end

  @doc "Whether this kind of utterance uses the paid ElevenLabs voice right now."
  def elevenlabs?(voice, kind) do
    wanted =
      case Map.get(voice, :engine, "browser") do
        "elevenlabs" -> true
        "mixed" -> kind == :call
        _ -> false
      end

    # The cap is a database read: only asked when the paid voice is wanted.
    wanted and Map.get(voice, :configured, false) and not over_cap?()
  end

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

  # Past the day's character cap (`ELEVENLABS_DAILY_CHAR_CAP`, the ledger
  # in `AgentBoard.ElevenLabs.Usage`) everything goes to the free voice.
  defp over_cap?, do: Usage.over_cap?()
end
