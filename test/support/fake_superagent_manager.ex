defmodule AgentBoard.Superagents.FakeManager do
  @moduledoc "Test adapter: an Agent holds the observed state per superagent id."
  @behaviour AgentBoard.Superagents.Manager

  def start do
    case Agent.start_link(fn -> %{} end, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  def put(id, state) do
    Agent.update(__MODULE__, &Map.put(&1, id, state))
  end

  def status(%{id: id}) do
    case Agent.get(__MODULE__, &Map.get(&1, id)) do
      nil -> {:error, :not_configured}
      %{state: _state} = observation -> {:ok, observation}
      state when is_binary(state) -> {:ok, %{state: state}}
    end
  end

  def start(%{id: id}) do
    Agent.update(__MODULE__, &Map.put(&1, id, %{state: "ready"}))
    :ok
  end

  def stop(%{id: id}) do
    Agent.update(__MODULE__, &Map.put(&1, id, %{state: "stopped"}))
    :ok
  end

  def pause(%{id: id}, paused) do
    state = if paused, do: "paused", else: "ready"
    Agent.update(__MODULE__, &Map.put(&1, id, %{state: state}))
    :ok
  end

  def scale(%{id: id}, workers) do
    Agent.update(__MODULE__, fn current ->
      Map.put(current, id, Map.put(current[id] || %{state: "ready"}, :max_workers, workers))
    end)

    :ok
  end
end
