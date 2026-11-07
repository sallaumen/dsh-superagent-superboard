defmodule AgentBoard.ElevenLabs do
  @moduledoc """
  The ElevenLabs voice client: text to speech, speech to text and voices.

  The key is read from `ELEVENLABS_API_KEY` -- loaded from `.env.local` by
  `config/runtime.exs`, never from code. A 4xx/5xx is a reason, not a body:
  every function returns `{:ok, ...}` or `{:error, reason}`, so a caller
  survives every failure and no raise reaches it. A failure that produced
  nothing to pay for (connection error, 429, 5xx) is retried a bounded number
  of times by `AgentBoard.ElevenLabs.Retry`; a 4xx about the request is final.
  """

  alias AgentBoard.ElevenLabs.Retry

  @base_url "https://api.elevenlabs.io"

  # George: male, narrative. The account's voice is picked in the UI or with
  # ELEVENLABS_VOICE_ID.
  @default_voice "JBFqnCBsd6RMkjVDRZzb"
  # ~75ms latency, the model for interactive feedback (v4 is the quality
  # option; both are a pick in the UI or a key away in the environment).
  @default_tts_model "eleven_flash_v2_5"
  @default_stt_model "scribe_v2"
  @default_output_format "mp3_44100_128"

  # The pickers offer these; an id not in the catalog is refused, so the
  # saved value can never grow into a wrong request.
  @tts_models [
    %{id: "eleven_flash_v2_5", name: "Flash v2.5", note: "rápido, ~75 ms"},
    %{id: "eleven_v4", name: "v4", note: "maior qualidade"},
    %{id: "eleven_multilingual_v2", name: "Multilingual v2", note: "estável, textos longos"}
  ]

  @max_voice_id 64
  @max_text 5_000

  @doc "A client bound to the API and the configured key, if any."
  def client do
    case Application.get_env(:agent_board, :elevenlabs_client) do
      nil -> build()
      builder -> builder.()
    end
  end

  @doc false
  def build do
    headers = [{"accept", "application/json"}]

    headers =
      if key() in [nil, ""], do: headers, else: [{"xi-api-key", key()} | headers]

    Req.new(base_url: @base_url, headers: headers, retry: false)
  end

  @doc "Whether a key is configured."
  def configured?, do: key() not in [nil, ""]

  @doc "The health of the integration."
  def status, do: if(configured?(), do: :logged_in, else: :not_configured)

  @doc "Whether a voice id looks like one, before it reaches the API or the settings."
  def valid_voice_id?(id) when is_binary(id) do
    trimmed = String.trim(id)
    trimmed != "" and byte_size(trimmed) <= @max_voice_id
  end

  def valid_voice_id?(_id), do: false

  @doc "Whether a text is short enough for one speech request."
  def valid_text?(text) when is_binary(text), do: byte_size(text) <= @max_text
  def valid_text?(_text), do: false

  @doc "The voice the board speaks with."
  def voice_id do
    config(:elevenlabs_voice_id, saved_voice() || @default_voice)
  end

  @doc """
  Where the voice comes from: `:environment` (ELEVENLABS_VOICE_ID), `:saved`
  (picked in the UI) or `:default`.
  """
  def voice_source do
    cond do
      not is_nil(config(:elevenlabs_voice_id, nil)) -> :environment
      not is_nil(saved_voice()) -> :saved
      true -> :default
    end
  end

  @doc "The text-to-speech model."
  def tts_model do
    config(:elevenlabs_tts_model, saved_tts_model() || @default_tts_model)
  end

  @doc "Where the TTS model comes from: `:environment`, `:saved` or `:default`."
  def tts_source do
    cond do
      not is_nil(config(:elevenlabs_tts_model, nil)) -> :environment
      not is_nil(saved_tts_model()) -> :saved
      true -> :default
    end
  end

  @doc "The speech-to-text model."
  def stt_model do
    config(:elevenlabs_stt_model, @default_stt_model)
  end

  @doc "The TTS models the picker offers."
  def tts_models, do: @tts_models

  @doc "Whether a TTS model id is one of the offered models."
  def valid_tts_model?(id), do: id in Enum.map(@tts_models, & &1.id)

  defp saved_voice, do: AgentBoard.Settings.get("elevenlabs_voice_id")
  defp saved_tts_model, do: AgentBoard.Settings.get("elevenlabs_tts_model")

  @doc """
  Speak a text: `{:ok, result}` with the audio bytes, or `{:error, reason}`.

  The result is `%{audio: binary, format: format, characters: n | nil,
  request_id: id | nil}` -- `characters` is what the request cost.

  ## Options

    * `:voice` - the voice id; defaults to `voice_id/0`
    * `:model` - the model id; defaults to `tts_model/0`
    * `:stability` - 0..1, default 0.5
    * `:similarity_boost` - 0..1, default 0.75
    * `:output_format` - an ElevenLabs format, default "mp3_44100_128"
    * `:latency` - 0..4; asks ElevenLabs for a faster first byte at a small
      quality cost, default 3 (the value for interactive feedback)
    * `:language` - an ISO 639-1 code (`pt`, `en`). Sent as `language_code`
      only to the models that enforce it (Flash v2.5), so the text is read
      and normalized in that language instead of the voice's own; other
      models infer the language from the text.
    * `:speed` - 0.7..1.2, the speaking rate; omitted keeps the voice's own
  """
  def speech(text, opts \\ []) when is_binary(text) do
    if configured?() do
      format = Keyword.get(opts, :output_format, @default_output_format)

      case Req.post(
             client(),
             [
               url: "/v1/text-to-speech/#{Keyword.get(opts, :voice, voice_id())}",
               params: speech_params(format, opts),
               json: speech_body(text, opts),
               decode_body: false
             ] ++ Retry.options(:tts)
           ) do
        {:ok, %Req.Response{status: 200, body: audio, headers: headers}} ->
          {:ok,
           %{
             audio: audio,
             format: format,
             characters: header_number(headers, "x-character-count"),
             request_id: header_string(headers, "request-id")
           }}

        {:ok, %Req.Response{status: 401}} ->
          {:error, :auth_expired}

        {:ok, %Req.Response{status: 429}} ->
          {:error, :usage_limit}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:http, status}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_configured}
    end
  end

  @doc """
  Speak a text as a stream: `on_chunk` receives each piece of mp3 as it
  arrives (the first one about half a second after the request, against a
  second or more for the whole file) and answers `:ok` to continue or `:halt`
  when the listener went away. Returns `:ok` or `{:error, reason}`; a failure
  status arrives before any chunk, so a caller can still answer it cleanly.
  Same options as `speech/2`. Retried by `Retry` only before the first chunk.
  """
  @spec speech_stream(String.t(), keyword(), (binary() -> :ok | :halt)) :: :ok | {:error, term()}
  def speech_stream(text, opts, on_chunk) when is_binary(text) and is_function(on_chunk, 1) do
    if configured?() do
      format = Keyword.get(opts, :output_format, @default_output_format)

      Retry.reset_streamed()

      Req.post(
        client(),
        [
          url: "/v1/text-to-speech/#{Keyword.get(opts, :voice, voice_id())}/stream",
          params: speech_params(format, opts),
          json: speech_body(text, opts),
          decode_body: false,
          into: stream_into(on_chunk)
        ] ++ Retry.options(:tts)
      )
      |> tap(fn _ -> Retry.reset_streamed() end)
      |> stream_result()
    else
      {:error, :not_configured}
    end
  end

  # Only a 200 reaches the listener; an error body is dropped and the status
  # becomes the reason.
  defp stream_into(on_chunk) do
    fn
      {:data, data}, {req, %Req.Response{status: 200} = resp} ->
        # From here on a retry would splice two recordings: the policy stops.
        Retry.mark_streamed()
        if on_chunk.(data) == :ok, do: {:cont, {req, resp}}, else: {:halt, {req, resp}}

      {:data, _data}, acc ->
        {:cont, acc}
    end
  end

  defp stream_result({:ok, %Req.Response{status: 200}}), do: :ok
  defp stream_result({:ok, %Req.Response{status: 401}}), do: {:error, :auth_expired}
  defp stream_result({:ok, %Req.Response{status: 429}}), do: {:error, :usage_limit}
  defp stream_result({:ok, %Req.Response{status: status}}), do: {:error, {:http, status}}
  defp stream_result({:error, reason}), do: {:error, reason}

  defp speech_params(format, opts) do
    [output_format: format, optimize_streaming_latency: Keyword.get(opts, :latency, 3)]
  end

  defp speech_body(text, opts) do
    model = Keyword.get(opts, :model, tts_model())

    settings =
      %{
        stability: Keyword.get(opts, :stability, 0.5),
        similarity_boost: Keyword.get(opts, :similarity_boost, 0.75)
      }
      |> then(fn s -> if opts[:speed], do: Map.put(s, :speed, opts[:speed]), else: s end)

    %{text: text, model_id: model, voice_settings: settings}
    |> put_language(model, opts[:language])
  end

  # Only these models accept `language_code`; another one answers 400.
  @language_models ["eleven_flash_v2_5", "eleven_turbo_v2_5"]

  defp put_language(body, model, code)
       when model in @language_models and is_binary(code) and byte_size(code) == 2,
       do: Map.put(body, :language_code, code)

  defp put_language(body, _model, _code), do: body

  @doc """
  Transcribe audio bytes: `{:ok, transcript}` or `{:error, reason}`.

  The transcript is `%{text: binary, language_code: code | nil,
  language_probability: n | nil, audio_duration_secs: n | nil}`.

  ## Options

    * `:model` - the model id; defaults to `stt_model/0` (`scribe_v2`)
    * `:language` - an optional ISO 639-1 or 639-3 hint (`pt`, `eng`, ...)
    * `:timestamps_granularity` - `none` (default), `word` or `character`
    * `:keyterms` - a list of terms to bias recognition
  """
  def transcribe(data, filename, opts \\ [])
      when is_binary(data) and is_binary(filename) do
    if configured?() do
      form =
        [
          {"model_id", Keyword.get(opts, :model, stt_model())},
          {:file, {data, [filename: filename]}},
          {"timestamps_granularity", Keyword.get(opts, :timestamps_granularity, "none")}
        ] ++
          maybe_field("language_code", opts[:language]) ++
          repeated_field("keyterms", opts[:keyterms])

      case Req.post(
             client(),
             [url: "/v1/speech-to-text", form_multipart: form] ++ Retry.options(:transcribe)
           ) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          {:ok, transcript(body)}

        {:ok, %Req.Response{status: 401}} ->
          {:error, :auth_expired}

        {:ok, %Req.Response{status: 429}} ->
          {:error, :usage_limit}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:http, status}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_configured}
    end
  end

  @doc "The voices available to the account: `{:ok, [%{id: id, name: name}]}`."
  def voices do
    if configured?(), do: voice_list(), else: {:error, :not_configured}
  end

  @doc "Whether board events are spoken automatically (the settings default is on)."
  def speak_events?, do: AgentBoard.Settings.get("elevenlabs_speak_events") != "0"

  defp voice_list do
    case cached_voices() do
      {:ok, voices} -> {:ok, voices}
      :miss -> fetched_voices()
    end
  end

  defp fetched_voices do
    case fetch_voices() do
      {:ok, voices} ->
        # Only a positive ttl writes: with the cache disabled the persistent
        # term stays clean instead of leaking stale lists.
        if voices_ttl() > 0, do: cache_voices(voices)
        {:ok, voices}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The account's voices change rarely; a browse should not pay a request
  # every time. The TTL is the `:voice_voices_ttl` knob (0 disables the
  # cache, which the tests use).
  defp voices_ttl, do: Application.get_env(:agent_board, :voice_voices_ttl, 300_000)

  defp cached_voices do
    if voices_ttl() <= 0, do: :miss, else: fresh?(read_cached_voices())
  end

  defp read_cached_voices, do: :persistent_term.get({__MODULE__, :voices}, nil)

  defp fresh?({fetched_at, voices}) when is_list(voices) do
    if System.monotonic_time(:millisecond) - fetched_at < voices_ttl(),
      do: {:ok, voices},
      else: :miss
  end

  defp fresh?(_cached), do: :miss

  defp cache_voices(voices) do
    :persistent_term.put({__MODULE__, :voices}, {System.monotonic_time(:millisecond), voices})
  end

  defp fetch_voices do
    case Req.get(
           client(),
           [url: "/v1/voices", params: [page_size: 100]] ++ Retry.options(:voices)
         ) do
      {:ok, %Req.Response{status: 200, body: %{"voices" => list}}} ->
        {:ok, Enum.map(list, &%{id: &1["voice_id"], name: &1["name"]})}

      {:ok, %Req.Response{status: 401}} ->
        {:error, :auth_expired}

      {:ok, %Req.Response{status: 429}} ->
        {:error, :usage_limit}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp transcript(body) when is_map(body) do
    %{
      text: Map.get(body, "text", ""),
      language_code: body["language_code"],
      language_probability: body["language_probability"],
      audio_duration_secs: body["audio_duration_secs"]
    }
  end

  # get_env/3 only falls back when the key is MISSING; a key set to nil
  # (a test that deleted it mid-run) would crash the header list.
  defp key do
    case Application.fetch_env(:agent_board, :elevenlabs_api_key) do
      {:ok, value} when is_binary(value) -> value
      _ -> System.get_env("ELEVENLABS_API_KEY", "")
    end
  end

  # The same trap, for the voice and model settings: a nil app key must fall
  # back to the default instead of shadowing it.
  defp config(key, default) do
    case Application.fetch_env(:agent_board, key) do
      {:ok, value} when is_binary(value) and value != "" -> value
      _ -> default
    end
  end

  defp maybe_field(_name, nil), do: []
  defp maybe_field(name, value), do: [{name, to_string(value)}]

  defp repeated_field(_name, nil), do: []

  defp repeated_field(name, terms) when is_list(terms),
    do: Enum.map(terms, &{name, to_string(&1)})

  defp repeated_field(name, term), do: [{name, to_string(term)}]

  defp header_string(headers, name) do
    case Map.get(headers, name) do
      [value | _] -> value
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp header_number(headers, name) do
    with value when is_binary(value) <- header_string(headers, name),
         {number, ""} <- Integer.parse(value) do
      number
    else
      _ -> nil
    end
  end
end
