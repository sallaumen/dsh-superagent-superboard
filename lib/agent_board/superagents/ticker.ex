defmodule AgentBoard.Superagents.Ticker do
  @moduledoc """
  Polls the registered superagents through the manager on a schedule. The
  GenServer only launches the work; the HTTP reads run in tasks so a slow
  panel never blocks the board.
  """
  use GenServer
  require Logger

  alias AgentBoard.{AgentAccess, Superagents}

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, interval())
    if interval != :manual, do: Process.send_after(self(), :tick, 1_000)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:tick, state) do
    if state.interval != :manual, do: Process.send_after(self(), :tick, state.interval)

    state =
      try do
        Superagents.tick()
        announce_access(state)
      rescue
        exception ->
          Logger.warning("superagent access read failed: #{Exception.message(exception)}")
          state
      end

    {:noreply, reconcile(state)}
  end

  # Starting/stopping an agent can wait on the external manager for up to a
  # minute; never block the ticker (and the next status read) on it. A
  # reconcile acts on the list it read, so a second one is never started over
  # one still running: it would stop or start the same agent again.
  defp reconcile(state) do
    if is_pid(state[:reconcile]) and Process.alive?(state.reconcile) do
      state
    else
      {:ok, pid} =
        Task.Supervisor.start_child(AgentBoard.Superagents.TaskSupervisor, fn ->
          Superagents.reconcile()
        end)

      Map.put(state, :reconcile, pid)
    end
  rescue
    exception ->
      Logger.warning("superagent tick failed: #{Exception.message(exception)}")
      state
  end

  # A refused mention reaches the board only through this read: nothing in
  # the agent tells the board, so the ticker compares and announces.
  defp announce_access(state) do
    Map.put(
      state,
      :access_fingerprint,
      AgentAccess.announce_if_changed(Map.get(state, :access_fingerprint))
    )
  end

  defp interval, do: Application.get_env(:agent_board, :superagent_tick_interval, 30_000)
end
