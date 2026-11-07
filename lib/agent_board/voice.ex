defmodule AgentBoard.Voice do
  @moduledoc """
  The voice: what the agent says and how loud, in which language.

  The texts are generated here, in plain functions, so they can be tested
  without a browser. The words themselves live in `AgentBoard.Voice.Phrases`;
  this module reads the owner's voice settings (`AgentBoard.Settings`):

    * `voice_language` - `pt-BR` (default) or `en-US`
    * `voice_volume` - 0..100 (default 100)
    * `voice_attention` - `"0"` silences the calls for attention
  """

  alias AgentBoard.Settings
  alias AgentBoard.Voice.Phrases

  @language_key "voice_language"
  @volume_key "voice_volume"
  @attention_key "voice_attention"
  @default_volume 100
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
