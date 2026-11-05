defmodule AgentBoard.AI.Engines.DeepSeek do
  @moduledoc """
  DeepSeek through its OpenAI-compatible Chat Completions API, one metered
  request per call.

  No retry: a retried paid request is a second charge. The answer is decoded
  as JSON when possible; a text that is not JSON is kept as `partial`, never
  thrown away. `status/0` reads the configuration, never the network.
  """

  @behaviour AgentBoard.AI.Engine

  alias AgentBoard.AI.{Request, Result}

  @base_url "https://api.deepseek.com"

  @impl true
  def run(%Request{} = request) do
    started = System.monotonic_time(:millisecond)

    with :ok <- configured?(),
         {:ok, body} <- post(request) do
      decode(body, request, System.monotonic_time(:millisecond) - started)
    end
  end

  @impl true
  def status do
    case configured?() do
      :ok -> :logged_in
      {:error, :not_configured} -> :not_configured
    end
  end

  defp configured? do
    if api_key() in [nil, ""], do: {:error, :not_configured}, else: :ok
  end

  defp post(request) do
    body = %{
      model: request.model,
      messages: messages(request),
      max_tokens: request.max_output_tokens,
      response_format: %{type: "json_object"}
    }

    case Req.post(client(), url: "/chat/completions", json: body) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: 401}} -> {:error, :auth_expired}
      {:ok, %Req.Response{status: status}} when status in [402, 429] -> {:error, :usage_limit}
      {:ok, %Req.Response{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp messages(%Request{system: nil, prompt: prompt}), do: [%{role: "user", content: prompt}]

  defp messages(%Request{system: system, prompt: prompt}) do
    [%{role: "system", content: system}, %{role: "user", content: prompt}]
  end

  defp decode(
         %{"choices" => [%{"message" => %{"content" => content}} | _]} = body,
         request,
         elapsed
       )
       when is_binary(content) do
    usage = body["usage"] || %{}
    json = decode_json(content)

    {:ok,
     %Result{
       text: content,
       json: json,
       input_tokens: usage["prompt_tokens"] || 0,
       output_tokens: usage["completion_tokens"] || 0,
       duration_ms: elapsed,
       model: body["model"] || request.model,
       engine: :deepseek,
       parse_state: if(json, do: :complete, else: :partial)
     }}
  end

  defp decode(_body, _request, _elapsed), do: {:error, :malformed_output}

  defp decode_json(content) do
    case Jason.decode(content) do
      {:ok, json} when is_map(json) -> json
      _ -> nil
    end
  end

  defp client do
    builder = Application.get_env(:agent_board, :ai_client, &build_client/0)
    builder.()
  end

  @doc false
  def build_client do
    Req.new(
      base_url: @base_url,
      headers: [
        {"accept", "application/json"},
        {"authorization", "Bearer #{api_key()}"}
      ],
      retry: false
    )
  end

  defp api_key do
    Application.get_env(:agent_board, :ai_api_key, System.get_env("DEEPSEEK_API_KEY", ""))
  end
end
