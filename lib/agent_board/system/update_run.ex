defmodule AgentBoard.System.UpdateRun do
  @moduledoc """
  The update pipeline, owned by no page.

  The fast-forward changes `lib/`, so the dev live reloader refreshes the very
  page that asked for the update. Started from that LiveView, the pipeline was
  linked to it and died with the page: the checkout had moved, nothing was
  prepared and nothing restarted. A supervised task outlives the page, and
  every board follows it through `subscribe/0`.

  A fast-forward that touches `mix.lock` or a config file makes the dev code
  reloader refuse every request until the node restarts, and new migrations
  make `CheckRepoStatus` do the same. From the moment the pipeline starts the
  reload is held (`reload_held?/0`, read by `AgentBoardWeb.DevReload`), so the
  old node keeps serving what it has loaded. A failure after the pull keeps it
  held: the checkout stays ahead and the page must still open to reach
  "Reiniciar". A restart clears it.
  """

  alias AgentBoard.Actions

  require Logger

  @topic "system:update"
  @running {__MODULE__, :running}
  @held {__MODULE__, :reload_held}

  @doc "Follow the pipeline: `{:update_step, id, state}` and `{:update_finished, result}`."
  def subscribe, do: Phoenix.PubSub.subscribe(AgentBoard.PubSub, @topic)

  @doc "Whether a pipeline is running on this node."
  @spec running?() :: boolean()
  def running?, do: :persistent_term.get(@running, false)

  @doc "Whether the dev code reloader must leave requests alone."
  @spec reload_held?() :: boolean()
  def reload_held?, do: :persistent_term.get(@held, false)

  @doc false
  def release_reload, do: :persistent_term.erase(@held)

  @doc """
  Starts the pipeline for `actor`. A second start while one runs joins it: the
  caller is already subscribed and the new task leaves without doing anything.
  """
  @spec start(Actions.actor()) :: DynamicSupervisor.on_start_child()
  def start(actor) do
    Task.Supervisor.start_child(AgentBoard.System.TaskSupervisor, fn -> run(actor) end)
  end

  defp run(actor) do
    # :global grants a lock again to the same requester; each run is its own.
    lock = {__MODULE__, self()}

    if :global.set_lock(lock, [node()], 0) do
      :persistent_term.put(@running, true)
      :persistent_term.put(@held, true)

      try do
        actor |> pipeline() |> finish(actor)
      rescue
        exception ->
          Logger.error("update failed: #{Exception.message(exception)}")
          broadcast({:update_finished, {:error, Exception.message(exception)}})
      after
        :persistent_term.erase(@running)
        :global.del_lock(lock, [node()])
      end
    end
  end

  defp pipeline(actor) do
    config_mtimes = updater().freeze_config_files()

    case step(:fetch, fn -> pull(actor, config_mtimes) end) do
      {:ok, sha} ->
        prepare(sha, config_mtimes)

      # Nothing moved: the checkout still matches the running code.
      error ->
        release_reload()
        {:error, error}
    end
  end

  defp pull(actor, config_mtimes) do
    result = Actions.run(:update_board, %{}, actor)
    updater().restore_config_files(config_mtimes)
    result
  end

  defp prepare_dependencies(config_mtimes) do
    result = updater().prepare()
    updater().restore_config_files(config_mtimes)
    result
  end

  defp prepare(sha, config_mtimes) do
    with :ok <- step(:deps, fn -> prepare_dependencies(config_mtimes) end),
         :ok <- step(:compile, fn -> updater().prepare_build() end),
         :ok <- step(:assets, fn -> updater().prepare_assets() end),
         :ok <- step(:migrate, fn -> updater().migrate() end),
         :ok <- step(:ready, fn -> updater().mark_ready() end) do
      {:ok, sha}
    else
      error -> {:error, error}
    end
  end

  defp step(id, fun) do
    broadcast({:update_step, id, :running})
    result = fun.()
    broadcast({:update_step, id, if(succeeded?(result), do: :done, else: :error)})
    result
  end

  defp succeeded?(:ok), do: true
  defp succeeded?({:ok, _sha}), do: true
  defp succeeded?(_result), do: false

  defp finish({:ok, _sha} = result, actor) do
    broadcast({:update_finished, result})
    Actions.run(:restart_board, %{}, actor)
  end

  defp finish(result, _actor) do
    Logger.error("update stopped: #{inspect(result)}")
    broadcast({:update_finished, result})
  end

  defp broadcast(message), do: Phoenix.PubSub.broadcast(AgentBoard.PubSub, @topic, message)

  defp updater, do: Application.get_env(:agent_board, :updater, AgentBoard.System.Updater)
end
