defmodule AgentBoard.Routing.Signals do
  @moduledoc """
  What the router reads before it suggests, and the snapshot a decision
  keeps.

  Today only the DeepSeek runner can be read (`Orchestrator.dispatch_state/1`:
  the repository it watches, the pause, the load). Claude Code and Codex
  have no availability reader and no usage ledger yet: their state is
  `:unknown` and no executor has a cost, which the router shows as unknown,
  never as available or free.
  """

  alias AgentBoard.Orchestrator

  @doc "The signals for `AgentBoard.Routing.suggest/2`."
  @spec read((-> {:ok, map()} | {:error, term()})) :: AgentBoard.Routing.signals()
  def read(dispatch_state \\ &Orchestrator.dispatch_state/0) do
    dsh =
      case dispatch_state.() do
        {:ok, %{repository: repository, paused: paused, load: load}} ->
          %{repository: repository, state: if(paused, do: :paused, else: :ready), load: load}

        {:error, reason} ->
          %{repository: nil, state: {:unavailable, reason(reason)}}
      end

    %{"dsh" => dsh, "claude" => %{state: :unknown}, "codex" => %{state: :unknown}}
  end

  defp reason(:not_configured), do: "a API do orquestrador está desligada"
  defp reason(:unreachable), do: "o orquestrador não respondeu"
  defp reason(:malformed), do: "o orquestrador respondeu num formato inesperado"
  defp reason({:http, status}), do: "o orquestrador respondeu HTTP #{status}"
  defp reason(_other), do: "o orquestrador não respondeu"

  @doc "The signals as stored data: strings for every atom and tuple."
  @spec snapshot(AgentBoard.Routing.signals()) :: map()
  def snapshot(signals) do
    Map.new(signals, fn {executor, signal} -> {executor, Map.new(signal, &stored/1)} end)
  end

  defp stored({key, {:unavailable, why}}), do: {to_string(key), "unavailable: " <> why}

  defp stored({key, value}) when is_atom(value) and not is_nil(value) and not is_boolean(value),
    do: {to_string(key), to_string(value)}

  defp stored({key, %{} = value}), do: {to_string(key), Map.new(value, &stored/1)}
  defp stored({key, value}), do: {to_string(key), value}
end
