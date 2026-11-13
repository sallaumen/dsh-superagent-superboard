defmodule AgentBoard.Superagents.RuntimeSync do
  @moduledoc """
  Serializes operator-requested maintenance on this board. Work survives the
  browser; every Settings page sees the same in-progress and last result.
  Only registered local profiles are candidates. The helper rechecks live
  repository, state, manager PID and load under a per-profile file lock.
  """
  use GenServer
  alias AgentBoard.Superagents
  alias AgentBoard.Superagents.DshManager

  @idle %{running: false, rows: %{}}
  @statuses ~w(updated current paused busy changed identity unavailable in_progress failed)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, @idle, name: __MODULE__)
  def status, do: GenServer.call(__MODULE__, :status)
  def start(targets), do: GenServer.call(__MODULE__, {:start, targets})

  # Owner controls and the ticker share this lock with the handoff. In
  # particular, an explicit pause must never be undone by sync's final resume.
  def exclusive(id, fun) do
    case :global.trans({{__MODULE__, id}, self()}, fun, [node()], 0) do
      :aborted -> {:error, :control_in_progress}
      result -> result
    end
  end

  def targets(agents), do: Map.new(agents, &{&1.id, slug(&1)})
  defp slug(agent), do: agent.repository.owner <> "/" <> agent.repository.name

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:status, _from, state), do: {:reply, Map.take(state, [:running, :rows]), state}

  def handle_call({:start, _}, _from, %{running: true} = state),
    do: {:reply, {:error, :in_progress}, state}

  def handle_call({:start, targets}, _from, _state) do
    owner = self()

    task =
      Task.Supervisor.async_nolink(AgentBoard.Superagents.TaskSupervisor, fn ->
        Enum.each(targets, fn {id, repo} -> send(owner, {:row, id, sync(id, repo)}) end)
      end)

    state = %{
      running: true,
      rows: Map.new(targets, fn {id, _} -> {id, "waiting"} end),
      ref: task.ref
    }

    announce()
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:row, id, result}, state) do
    state = put_in(state.rows[id], result)
    announce()
    {:noreply, state}
  end

  def handle_info({ref, _}, %{ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    finish(state)
  end

  def handle_info({:DOWN, ref, _, _, _}, %{ref: ref} = state), do: finish(state)

  defp finish(state) do
    rows = Map.new(state.rows, fn {k, v} -> {k, if(v == "waiting", do: "failed", else: v)} end)
    announce()
    {:noreply, %{running: false, rows: rows}}
  end

  defp announce,
    do: Phoenix.PubSub.broadcast(AgentBoard.PubSub, "superagents", :runtime_sync_changed)

  defp sync(id, expected) do
    case exclusive(id, fn -> sync_registered(id, expected) end) do
      {:error, :control_in_progress} -> "in_progress"
      result -> result
    end
  rescue
    _ -> "failed"
  end

  defp sync_registered(id, expected) do
    case Superagents.get(id) do
      %{desired_state: "running", provision_failed_at: nil} = agent ->
        if slug(agent) == expected, do: run(agent, expected), else: "identity"

      %{desired_state: "paused"} ->
        "paused"

      _ ->
        "unavailable"
    end
  end

  defp run(agent, repo) do
    script = Application.app_dir(:agent_board, "priv/agent/sync_runtime.py")

    args = [
      script,
      "--profile",
      agent.profile,
      "--manager",
      DshManager.script(),
      "--port",
      Integer.to_string(agent.port),
      "--repo",
      repo,
      "--state",
      agent.state_dir
    ]

    case System.cmd("python3", args, stderr_to_stdout: true) do
      {output, 0} ->
        result = String.trim(output)
        if result in @statuses, do: result, else: "failed"

      _ ->
        "failed"
    end
  end
end
