defmodule AgentBoard.AI do
  @moduledoc """
  The door to a language model: registered calls only, every one a row.

  A call must exist in `AgentBoard.AI.Registry`; the prompt comes from code,
  never from the caller. The row in `ai_calls` carries the engine, the model,
  the tokens, the latency and the parse state -- so the panel shows what was
  paid for and a failure is visible instead of silent.
  """

  import Ecto.Query
  require Logger

  alias AgentBoard.AI.{Budget, Cache, Call, Providers, Registry, Request, Result, Schema}
  alias AgentBoard.Repo

  @doc """
  Runs one registered call and records every attempt.

  When no provider is pinned, a refusal that says nothing about the prompt --
  an expired key, a spent quota -- moves to the next provider with a key
  instead of failing the panel. A content error (a malformed answer) does not
  move: another engine would answer the same wrong thing.
  """
  @spec call(atom(), map(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def call(name, inputs, opts \\ []) do
    with {:ok, spec} <- Registry.fetch(name) do
      providers = providers()
      cached_or_call(cached(name, spec, inputs, providers), name, spec, inputs, providers, opts)
    end
  end

  # A cached answer costs nothing, so the budget only gates the network.
  defp cached_or_call({:ok, json}, _name, _spec, _inputs, _providers, _opts),
    do: {:ok, %Result{json: json, engine: :cache, parse_state: :complete}}

  defp cached_or_call(:miss, name, spec, inputs, providers, opts) do
    with :ok <- Budget.check(spec.tier), do: attempt(name, spec, inputs, providers, opts)
  end

  defp cached(_name, _spec, _inputs, []), do: :miss

  defp cached(name, spec, inputs, [provider | _rest]) do
    case Cache.get(Cache.key(name, provider, Providers.model(provider, spec.tier), inputs, spec)) do
      {:ok, json} -> if Schema.valid?(spec.json_schema, json), do: {:ok, json}, else: :miss
      :miss -> :miss
    end
  end

  defp attempt(_name, _spec, _inputs, [], _opts), do: {:error, :no_provider}

  defp attempt(name, spec, inputs, [provider | rest], opts) do
    request = Request.build(spec, inputs, provider, Providers.model(provider, spec.tier))
    started = System.monotonic_time(:millisecond)

    case engine().run(request) do
      {:ok, %Result{} = result} ->
        record_answer(name, spec, request, inputs, result, elapsed(started), opts)

      {:error, reason} ->
        record_failure(name, spec, request, inputs, reason, rest, elapsed(started), opts)
    end
  end

  defp record_answer(name, spec, request, inputs, result, duration, opts) do
    if result.parse_state == :complete and Schema.valid?(spec.json_schema, result.json) do
      with :ok <-
             record(%{name: name, spec: spec}, request, inputs, result, duration, :ok, nil, opts) do
        {:ok, result}
      end
    else
      result = %{result | parse_state: :partial}

      with :ok <-
             record(
               %{name: name, spec: spec},
               request,
               inputs,
               result,
               duration,
               :error,
               "malformed_output",
               opts
             ) do
        {:error, :malformed_output}
      end
    end
  end

  defp record_failure(name, spec, request, inputs, reason, rest, duration, opts) do
    with :ok <-
           record(
             %{name: name, spec: spec},
             request,
             inputs,
             %Result{},
             duration,
             :error,
             reason_word(reason),
             opts
           ) do
      next_attempt(reason, name, spec, inputs, rest, opts)
    end
  end

  # The stored reason is a word the panel can say (`AgentBoardWeb.FailureText`).
  defp reason_word(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_word({:http, status}), do: "http #{status}"
  defp reason_word(%{__exception__: true} = exception), do: Exception.message(exception)

  defp next_attempt(reason, name, spec, inputs, rest, opts) do
    if fallback?(reason), do: attempt(name, spec, inputs, rest, opts), else: {:error, reason}
  end

  defp fallback?(reason),
    do: reason in [:auth_expired, :usage_limit, :not_configured, :no_provider]

  defp providers do
    # Rehearsal is a provider in its own right: it answers from fixtures and
    # must not depend on an API key being configured.
    if rehearsal?() do
      [:rehearsal]
    else
      case Application.get_env(:agent_board, :ai_provider) do
        nil -> Enum.filter(Providers.ids(), &Providers.configured?/1)
        id -> [id]
      end
    end
  end

  @doc """
  Who answers the board's own calls: the first provider with a key (or the
  one `AI_PROVIDER` pins), its fast model, and the rest in fallback order.
  """
  @spec answering() :: %{provider: atom() | nil, model: String.t() | nil, fallbacks: [atom()]}
  def answering do
    case providers() do
      [:rehearsal] -> %{provider: :rehearsal, model: nil, fallbacks: []}
      [] -> %{provider: nil, model: nil, fallbacks: []}
      [first | rest] -> %{provider: first, model: Providers.model(first, :fast), fallbacks: rest}
    end
  end

  @doc "The last calls, newest first -- what the panel shows."
  @spec recent(pos_integer()) :: [Call.t()]
  def recent(limit \\ 20) do
    Repo.all(from c in Call, order_by: [desc: c.inserted_at, desc: c.id], limit: ^limit)
  end

  @doc "The last calls attributed to one task, newest first."
  @spec recent_for_task(integer(), pos_integer()) :: [Call.t()]
  def recent_for_task(task_id, limit \\ 20) do
    Repo.all(
      from c in Call,
        where: c.task_id == ^task_id,
        order_by: [desc: c.inserted_at, desc: c.id],
        limit: ^limit
    )
  end

  @doc "How many calls one task has in all; `recent_for_task/2` shows the newest."
  @spec count_for_task(integer()) :: non_neg_integer()
  def count_for_task(task_id),
    do: Repo.aggregate(from(c in Call, where: c.task_id == ^task_id), :count)

  @doc "Whether the engine is configured."
  @spec status() :: AgentBoard.AI.Engine.status()
  def status, do: engine().status()

  defp elapsed(started), do: System.monotonic_time(:millisecond) - started

  defp engine do
    if rehearsal?() do
      AgentBoard.AI.Engines.Rehearsal
    else
      Application.get_env(:agent_board, :ai_engine, AgentBoard.AI.Engines.OpenAI)
    end
  end

  defp rehearsal?, do: Application.get_env(:agent_board, :ai_rehearsal, false) == true

  defp record(context, request, inputs, result, elapsed, status, error, opts) do
    %Call{}
    |> Call.changeset(%{
      name: to_string(context.name),
      engine: to_string(result.engine || request.provider),
      model: result.model,
      tier: to_string(context.spec.tier),
      status: to_string(status),
      input_hash: Cache.key(context.name, request.provider, request.model, inputs, context.spec),
      input_tokens: result.input_tokens,
      output_tokens: result.output_tokens,
      cost_micros: result.cost_micros,
      duration_ms: elapsed,
      parse_state: result.parse_state && to_string(result.parse_state),
      json: result.json,
      error: error,
      task_id: Keyword.get(opts, :task_id)
    })
    |> Repo.insert()
    |> case do
      {:ok, _call} -> :ok
      {:error, _changeset} -> audit_unavailable(context.name, request.provider)
    end
  rescue
    _error -> audit_unavailable(context.name, request.provider)
  end

  defp audit_unavailable(name, provider) do
    Logger.error("AI call audit unavailable for #{name} via #{provider}")
    {:error, :audit_unavailable}
  end
end
