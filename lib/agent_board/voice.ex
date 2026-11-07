defmodule AgentBoard.Voice do
  @moduledoc """
  The voice: what the agent says and how loud, in which language.

  The texts are generated here, in plain functions, so they can be tested
  without a browser. The words themselves live in `AgentBoard.Voice.Phrases`;
  this module reads the owner's voice settings (`AgentBoard.Settings`):

    * `voice_language` - `pt-BR` (default) or `en-US`
    * `voice_volume` - 0..100 (default 100)
    * `voice_attention` - `"0"` silences the calls for attention
    * `voice_speed` - the speaking rate, 0.8..1.2 (default 1.0)
    * `voice_style` - the intonation: `steady`, `natural` (default) or
      `expressive`, an ElevenLabs stability of 0.7, 0.5 or 0.3
    * `voice_pause` - how long a silence ends a spoken turn: `short`,
      `normal` (default) or `long`
    * `voice_earcons` - `"0"` silences the sounds that mark the microphone
      opening and closing
    * `voice_input` - how the owner's speech becomes text: `wispr` (default:
      the owner's WisprFlow app types into the board, no transcription cost)
      or `microphone` (the board records and ElevenLabs Scribe transcribes)
    * `voice_engine` - who speaks: `browser` (default, free), `mixed`
      (ElevenLabs for the calls for attention and the coding agent's
      replies, the browser for the rest) or `elevenlabs` (everything)
    * `voice_replies` - `short` (default: the first sentence of a reply is
      spoken, the whole reply is written) or `full`
    * `voice_narrate` - `"1"` narrates the rest of the board (a task
      starting, the queue, the sync, confirmations); off by default
  """

  alias AgentBoard.Settings
  alias AgentBoard.Voice.Phrases

  @language_key "voice_language"
  @volume_key "voice_volume"
  @attention_key "voice_attention"
  @default_volume 100
  @speed_key "voice_speed"
  @style_key "voice_style"
  @pause_key "voice_pause"
  @styles %{"steady" => 0.7, "natural" => 0.5, "expressive" => 0.3}
  @pauses %{"short" => 800, "normal" => 1200, "long" => 1800}
  @summary_order [:question, :blocked, :ready, :running, :queued, :merged]

  @doc "The language the agent speaks (a saved pick, or the default)."
  @spec language() :: String.t()
  def language do
    lang = Settings.get(@language_key)
    if Phrases.valid_language?(lang), do: lang, else: Phrases.default_language()
  end

  @doc "Saves the voice language; only an offered language is accepted."
  def put_language(lang) when is_binary(lang) do
    lang = String.trim(lang)

    if Phrases.valid_language?(lang),
      do: Settings.put(@language_key, lang),
      else: {:error, :invalid_language}
  end

  def put_language(_lang), do: {:error, :invalid_language}

  @doc "The playback volume, 0..100."
  @spec volume() :: 0..100
  def volume do
    case parse_volume(Settings.get(@volume_key)) do
      {:ok, n} -> n
      :error -> @default_volume
    end
  end

  @doc "Saves the playback volume; a value outside 0..100 is refused."
  def put_volume(value) do
    case parse_volume(value) do
      {:ok, n} -> Settings.put(@volume_key, Integer.to_string(n))
      :error -> {:error, :invalid_volume}
    end
  end

  defp parse_volume(n) when is_integer(n) and n in 0..100, do: {:ok, n}

  defp parse_volume(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} when n in 0..100 -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_volume(_value), do: :error

  @doc "The speaking rate, 0.8..1.2."
  @spec speed() :: float()
  def speed do
    case parse_speed(Settings.get(@speed_key)) do
      {:ok, n} -> n
      :error -> 1.0
    end
  end

  @doc "Saves the speaking rate; outside 0.8..1.2 is refused."
  def put_speed(value) do
    case parse_speed(value) do
      {:ok, n} -> Settings.put(@speed_key, :erlang.float_to_binary(n, decimals: 2))
      :error -> {:error, :invalid_speed}
    end
  end

  defp parse_speed(n) when is_number(n) and n >= 0.8 and n <= 1.2,
    do: {:ok, Float.round(n * 1.0, 2)}

  defp parse_speed(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {n, ""} -> parse_speed(n)
      _ -> :error
    end
  end

  defp parse_speed(_value), do: :error

  @doc "The intonation preset: `steady`, `natural` or `expressive`."
  def style do
    style = Settings.get(@style_key)
    if Map.has_key?(@styles, style), do: style, else: "natural"
  end

  @doc "The ElevenLabs stability of the intonation preset."
  def stability, do: Map.fetch!(@styles, style())

  @doc "Saves the intonation preset."
  def put_style(style) when is_binary(style) do
    if Map.has_key?(@styles, style),
      do: Settings.put(@style_key, style),
      else: {:error, :invalid_style}
  end

  def put_style(_style), do: {:error, :invalid_style}

  @doc "The pause preset that ends a spoken turn."
  def pause do
    pause = Settings.get(@pause_key)
    if Map.has_key?(@pauses, pause), do: pause, else: "normal"
  end

  @doc "The silence, in milliseconds, that ends a spoken turn."
  def pause_ms, do: Map.fetch!(@pauses, pause())

  @doc "Saves the pause preset."
  def put_pause(pause) when is_binary(pause) do
    if Map.has_key?(@pauses, pause),
      do: Settings.put(@pause_key, pause),
      else: {:error, :invalid_pause}
  end

  def put_pause(_pause), do: {:error, :invalid_pause}

  @doc "Whether a soft sound marks the microphone opening and closing (default on)."
  def earcons?, do: Settings.get("voice_earcons") != "0"

  @doc "Turns the microphone sounds on or off."
  def put_earcons(on?) when is_boolean(on?),
    do: Settings.put("voice_earcons", if(on?, do: "", else: "0"))

  @inputs ~w(wispr microphone)
  @engines ~w(browser mixed elevenlabs)
  @replies ~w(short full)

  @doc "How the owner's speech becomes text: `wispr` (default) or `microphone`."
  def input, do: choice("voice_input", @inputs, "wispr")

  @doc "Saves the input method."
  def put_input(value), do: put_choice("voice_input", @inputs, value, :invalid_input)

  @doc "Who speaks: `browser` (default), `mixed` or `elevenlabs`."
  def engine, do: choice("voice_engine", @engines, "browser")

  @doc "Saves the voice engine."
  def put_engine(value), do: put_choice("voice_engine", @engines, value, :invalid_engine)

  @doc "How much of a reply is spoken: `short` (default) or `full`."
  def replies, do: choice("voice_replies", @replies, "short")

  @doc "Saves the spoken reply length."
  def put_replies(value), do: put_choice("voice_replies", @replies, value, :invalid_replies)

  @doc "Whether the rest of the board is narrated (default off: it costs voice)."
  def narrate?, do: Settings.get("voice_narrate") == "1"

  @doc "Turns the narration on or off."
  def put_narrate(on?) when is_boolean(on?),
    do: Settings.put("voice_narrate", if(on?, do: "1", else: ""))

  defp choice(key, allowed, default) do
    value = Settings.get(key)
    if value in allowed, do: value, else: default
  end

  defp put_choice(key, allowed, value, error) do
    if value in allowed, do: Settings.put(key, value), else: {:error, error}
  end

  @doc "Whether the agent calls the owner when a task needs them (default on)."
  def attention?, do: Settings.get(@attention_key) != "0"

  @doc "Turns the calls for attention on or off."
  def put_attention(on?) when is_boolean(on?),
    do: Settings.put(@attention_key, if(on?, do: "", else: "0"))

  @doc """
  A spoken status: what needs the owner, what is running and what merged.

  From the model when it can answer, in the voice language; the template is
  still the fallback, because a voice that says nothing is worse than a
  plain sentence. Options: `:language`, `:now` (UTC) and `:tz_offset`
  (minutes west of UTC, as the browser reports it).
  """
  @spec spoken(map(), keyword()) :: String.t()
  def spoken(board, opts \\ []) do
    lang = Keyword.get_lazy(opts, :language, &language/0)
    template = summary(board, Keyword.put(opts, :language, lang))

    case AgentBoard.AI.call(:summarize_board, %{state: template, language: lang}) do
      {:ok, %{json: %{"summary" => text}}} when is_binary(text) and text != "" -> text
      _ -> template
    end
  end

  @doc "The template summary; see `spoken/2` for the options."
  def summary(board, opts \\ []) do
    lang = Keyword.get_lazy(opts, :language, &language/0)

    hour =
      local_hour(Keyword.get(opts, :now, DateTime.utc_now()), Keyword.get(opts, :tz_offset, 0))

    parts =
      for key <- @summary_order, (n = count(board, key)) > 0, do: Phrases.count(lang, key, n)

    Phrases.summary(lang, Phrases.greeting(lang, hour), parts)
  end

  @doc "The one-line confirmation spoken when a task is acted on."
  def task_summary(title, action, lang \\ nil),
    do: Phrases.task_action(lang || language(), title, action)

  @doc "The hour on the owner's clock (`tz_offset` is minutes west of UTC)."
  def local_hour(%DateTime{} = now, tz_offset) when is_integer(tz_offset),
    do: DateTime.add(now, -tz_offset * 60, :second).hour

  defp count(board, key), do: length(Map.get(board, key) || [])
end
