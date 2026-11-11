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

  @doc "Who is cleared on one project; `{:error, reason}` makes the read fail."
  def put_access(id, access), do: Agent.update(__MODULE__, &Map.put(&1, {:access, id}, access))

  @doc "What the fake was asked to run again, oldest first."
  def requeued(id), do: Agent.get(__MODULE__, &Map.get(&1, {:requeued, id}, []))

  @doc "Make the next requeue answers this value for one project."
  def put_requeue_answer(id, answer),
    do: Agent.update(__MODULE__, &Map.put(&1, {:requeue_answer, id}, answer))

  def access(%{id: id}) do
    case Agent.get(__MODULE__, &Map.get(&1, {:access, id}, [])) do
      {:error, reason} -> {:error, reason}
      logins -> {:ok, %{allowed: Enum.map(logins, &%{login: &1, name: nil})}}
    end
  end

  def allow(%{id: id}, login), do: edit_access(id, &(&1 ++ [login]))
  def disallow(%{id: id}, login), do: edit_access(id, &List.delete(&1, login))

  defp edit_access(id, change) do
    case Agent.get(__MODULE__, &Map.get(&1, {:access, id}, [])) do
      {:error, reason} ->
        {:error, reason}

      logins ->
        Agent.update(__MODULE__, &Map.put(&1, {:access, id}, change.(logins)))
        :ok
    end
  end

  def requeue(%{id: id}, trigger_id) do
    Agent.update(__MODULE__, fn current ->
      Map.update(current, {:requeued, id}, [trigger_id], &(&1 ++ [trigger_id]))
    end)

    Agent.get(__MODULE__, &Map.get(&1, {:requeue_answer, id}, {:ok, true}))
  end

  @doc "Make `stop` answer this value for one project instead of :ok."
  def put_answer(id, command, answer) when command in [:stop],
    do: Agent.update(__MODULE__, &Map.put(&1, {command, id}, answer))

  defp answer(id, command), do: Agent.get(__MODULE__, &Map.get(&1, {command, id}, :ok))

  # An observation with `delay_ms` answers late, outside the Agent, so a
  # ticker that kills the read does not take the fake down with it.
  def status(%{id: id}) do
    case Agent.get(__MODULE__, &Map.get(&1, id)) do
      nil ->
        {:error, :not_configured}

      %{delay_ms: ms} = observation ->
        Process.sleep(ms)
        {:ok, Map.delete(observation, :delay_ms)}

      %{state: _state} = observation ->
        {:ok, observation}

      state when is_binary(state) ->
        {:ok, %{state: state}}
    end
  end

  def start(%{id: id}) do
    Agent.update(__MODULE__, &Map.put(&1, id, %{state: "ready"}))
    :ok
  end

  def stop(%{id: id}) do
    case answer(id, :stop) do
      :ok ->
        Agent.update(__MODULE__, &Map.put(&1, id, %{state: "stopped"}))
        :ok

      other ->
        other
    end
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
