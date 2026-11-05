defmodule AgentBoard.AI do
  @moduledoc """
  The door to a language model: registered calls only, every one a row.

  A call must exist in `AgentBoard.AI.Registry`; the prompt comes from code,
  never from the caller. The row in `ai_calls` carries the engine, the model,
  the tokens, the latency and the parse state -- so the panel shows what was
  paid for and a failure is visible instead of silent.
  """

  import Ecto.Query

  alias AgentBoard.AI.{Budget, Call, Registry, Request, Result}
  alias AgentBoard.Repo

  @doc "Runs one registered call and records it, success or failure."
  @spec call(atom(), map(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def call(name, inputs, _opts \\ []) do
    with {:ok, spec} <- Registry.fetch(name),
         :ok <- Budget.check(spec.tier) do
      request = Request.build(spec, inputs)
      started = System.monotonic_time(:millisecond)

      case engine().run(request) do
        {:ok, result} ->
          record(name, spec, result, elapsed(started), :ok, nil)
          {:ok, result}

        {:error, reason} ->
          record(name, spec, %Result{}, elapsed(started), :error, inspect(reason))
          {:error, reason}
      end
    end
  end

  @doc "The last calls, newest first -- what the panel shows."
  @spec recent(pos_integer()) :: [Call.t()]
  def recent(limit \\ 20) do
    Repo.all(from c in Call, order_by: [desc: c.inserted_at, desc: c.id], limit: ^limit)
  end

  @doc "Whether the engine is configured."
  @spec status() :: AgentBoard.AI.Engine.status()
  def status, do: engine().status()

  defp elapsed(started), do: System.monotonic_time(:millisecond) - started

  defp engine, do: Application.get_env(:agent_board, :ai_engine, AgentBoard.AI.Engines.DeepSeek)

  defp record(name, spec, result, elapsed, status, error) do
    %Call{}
    |> Call.changeset(%{
      name: to_string(name),
      engine: to_string(result.engine || :deepseek),
      model: result.model || spec.model,
      tier: to_string(spec.tier),
      status: to_string(status),
      input_tokens: result.input_tokens,
      output_tokens: result.output_tokens,
      cost_micros: 0,
      duration_ms: elapsed,
      parse_state: result.parse_state && to_string(result.parse_state),
      json: result.json,
      error: error
    })
    |> Repo.insert()
  end
end
