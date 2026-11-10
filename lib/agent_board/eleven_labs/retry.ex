defmodule AgentBoard.ElevenLabs.Retry do
  @moduledoc """
  When an ElevenLabs request is tried again, and how.

  Only failures that produced nothing to pay for are retried: a transport
  error where the connection never opened (refused, unknown host, no
  route), a 429 (rate
  limited, honoring `retry-after` up to two seconds) and a 500/502/503/504.
  A 4xx about the key, the voice or the text is final: repeating it cannot
  succeed. A stream is retried only before its first chunk reached the
  listener; after that a retry would splice two recordings together. A
  timeout or a closed connection is final: the request may already have
  reached ElevenLabs and been billed.

  At most `:voice_max_retries` retries (default 2) with a growing delay
  (`:voice_retry_base_ms`, default 300 ms: about 0.3 s, then 0.9 s). Every
  retry is an `AgentBoard.Voice.Activity` event, so the log and the board
  show it as it happens.
  """

  alias AgentBoard.Voice.Activity

  @retry_statuses [429, 500, 502, 503, 504]
  @never_connected [:econnrefused, :nxdomain, :ehostunreach, :enetunreach]
  @max_delay_ms 2_000
  @streamed_key :elevenlabs_streamed

  @doc "The Req options that apply this policy to one request of `stage`."
  @spec options(atom()) :: keyword()
  def options(stage) do
    [retry: &decide(stage, &1, &2), max_retries: max_retries(), retry_log_level: false]
  end

  @doc "Marks that this process's stream already delivered audio."
  def mark_streamed, do: Process.put(@streamed_key, true)

  @doc "Clears the stream mark before a new request."
  def reset_streamed, do: Process.delete(@streamed_key)

  @doc false
  def decide(stage, request, response_or_exception) do
    retries = Req.Request.get_private(request, :req_retry_count, 0)

    cond do
      retries >= max_retries() ->
        false

      Process.get(@streamed_key) ->
        false

      retryable?(response_or_exception) ->
        delay = delay(retries, response_or_exception)

        Activity.record(stage, :retry, "retrying in #{delay} ms",
          attempt: retries + 2,
          reason: reason(response_or_exception)
        )

        {:delay, delay}

      true ->
        false
    end
  end

  @doc "Whether a failure is one that is worth (and safe) to try again."
  def retryable?(%Req.Response{status: status}), do: status in @retry_statuses
  def retryable?(%Req.TransportError{reason: reason}), do: reason in @never_connected
  def retryable?(_other), do: false

  defp delay(retries, %Req.Response{status: 429} = response) do
    case Req.Response.get_header(response, "retry-after") do
      [value | _] ->
        case Integer.parse(value) do
          {seconds, _} when seconds >= 0 -> min(seconds * 1000, @max_delay_ms)
          _ -> backoff(retries)
        end

      [] ->
        backoff(retries)
    end
  end

  defp delay(retries, _failure), do: backoff(retries)

  defp backoff(retries) do
    base = base_ms()
    jitter = if base > 0, do: :rand.uniform(max(div(base, 3), 1)), else: 0
    min(base * Integer.pow(3, retries) + jitter, @max_delay_ms)
  end

  defp reason(%Req.Response{status: status}), do: {:http, status}
  defp reason(%Req.TransportError{reason: reason}), do: reason
  defp reason(other), do: other

  defp max_retries, do: Application.get_env(:agent_board, :voice_max_retries, 2)
  defp base_ms, do: Application.get_env(:agent_board, :voice_retry_base_ms, 300)
end
