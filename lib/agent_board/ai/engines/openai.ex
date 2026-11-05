defmodule AgentBoard.AI.Engines.OpenAI do
  @moduledoc """
  One adapter for every OpenAI-compatible provider.

  The provider (DeepSeek, Gemini, OpenAI) supplies the base URL, the key and
  the model per tier; this module supplies the request shape, the JSON decode
  and the honest failure. No retry: a retried paid request is a second charge.
  """

  @behaviour AgentBoard.AI.Engine

  alias AgentBoard.AI.{Providers, Request, Result}

  @impl true
  def run(%Request{} = request) do
    started = System.monotonic_time(:millisecond)

    with {:ok, provider_id} <- provider_id(request),
         :ok <- configured?(provider_id),
         {:ok, provider} <- Providers.fetch(provider_id),
         {:ok, body} <- post(provider_id, provider, request) do
      decode(body, request, System.monotonic_time(:millisecond) - started)
    end
  end

  @impl true
  def status do
    if Providers.configured(), do: :logged_in, else: :not_configured
  end

  defp provider_id(%Request{provider: id}) when not is_nil(id), do: {:ok, id}
  defp provider_id(_request), do: {:error, :no_provider}

  defp configured?(id) do
    if Providers.configured?(id), do: :ok, else: {:error, :not_configured}
  end

  defp post(provider_id, provider, request) do
    case Req.post(client(provider_id, provider), url: "/chat/completions", json: body(request)) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: 401}} -> {:error, :auth_expired}
      {:ok, %Req.Response{status: status}} when status in [402, 429] -> {:error, :usage_limit}
      {:ok, %Req.Response{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # A structured call is a forced function tool with `strict: true`: plain
  # `json_object` only promises syntactically valid JSON, and the model will
  # happily invent its own field names. The schema is the contract.
  defp body(%Request{json_schema: nil} = request) do
    %{
      model: request.model,
      messages: messages(request),
      max_tokens: request.max_output_tokens,
      response_format: %{type: "json_object"}
    }
  end

  defp body(%Request{json_schema: schema} = request) do
    %{
      model: request.model,
      messages: messages(request),
      max_tokens: request.max_output_tokens,
      tools: [
        %{type: "function", function: %{name: "respond", parameters: schema, strict: true}}
      ],
      tool_choice: %{type: "function", function: %{name: "respond"}}
    }
  end

  defp messages(%Request{system: nil, prompt: prompt}), do: [%{role: "user", content: prompt}]

  defp messages(%Request{system: system, prompt: prompt}) do
    [%{role: "system", content: system}, %{role: "user", content: prompt}]
  end

  defp decode(
         %{"choices" => [%{"message" => %{"tool_calls" => [call | _]}} | _]} = body,
         request,
         elapsed
       ) do
    case get_in(call, ["function", "arguments"]) do
      args when is_binary(args) -> answered(args, body, request, elapsed)
      _ -> {:error, :malformed_output}
    end
  end

  defp decode(
         %{"choices" => [%{"message" => %{"content" => content}} | _]} = body,
         request,
         elapsed
       )
       when is_binary(content) do
    answered(content, body, request, elapsed)
  end

  defp decode(_body, _request, _elapsed), do: {:error, :malformed_output}

  defp answered(content, body, request, elapsed) do
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
       engine: request.provider,
       parse_state: if(json, do: :complete, else: :partial)
     }}
  end

  defp decode_json(content) do
    case Jason.decode(content) do
      {:ok, json} when is_map(json) -> json
      _ -> nil
    end
  end

  defp client(provider_id, provider) do
    case Application.get_env(:agent_board, :ai_client) do
      nil -> build(provider_id, provider)
      fun -> fun.()
    end
  end

  @doc false
  def build(provider_id, provider) do
    Req.new(
      base_url: provider.base_url,
      headers: [
        {"accept", "application/json"},
        {"authorization", "Bearer #{Providers.key(provider_id)}"}
      ],
      retry: false
    )
  end
end
