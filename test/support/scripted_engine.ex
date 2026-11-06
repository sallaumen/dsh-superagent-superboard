defmodule AgentBoard.AI.Engines.Scripted do
  @moduledoc """
  The test engine: answers from a function the test sets.

  `Application.put_env(:agent_board, :ai_script, fn request -> ... end)` and
  `Application.put_env(:agent_board, :ai_engine, AgentBoard.AI.Engines.Scripted)`
  make every registered call deterministic: a malformed answer, a refusal, a
  timeout or a slow model are one function away, without a key or a bill.
  """

  @behaviour AgentBoard.AI.Engine

  alias AgentBoard.AI.{Providers, Request, Result}

  @impl true
  def run(%Request{} = request) do
    case Application.get_env(:agent_board, :ai_script) do
      fun when is_function(fun, 1) -> fun.(request)
      _ -> {:error, :no_script}
    end
  end

  # The status mirrors the key, like the real engine: a test without a key
  # sees the board behave as not configured.
  @impl true
  def status do
    if Providers.configured(), do: :logged_in, else: :not_configured
  end

  @doc "A complete, schema-shaped answer."
  def answer(json) when is_map(json) do
    {:ok,
     %Result{
       text: Jason.encode!(json),
       json: json,
       input_tokens: 1,
       output_tokens: 1,
       duration_ms: 0,
       model: "scripted",
       engine: :scripted,
       parse_state: :complete
     }}
  end

  @doc "An answer the parser could not complete: the panel must say so."
  def malformed do
    {:ok,
     %Result{
       text: "{\"goal\": ",
       json: nil,
       input_tokens: 1,
       output_tokens: 1,
       duration_ms: 0,
       model: "scripted",
       engine: :scripted,
       parse_state: :partial
     }}
  end
end
