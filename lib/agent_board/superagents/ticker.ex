defmodule AgentBoard.Superagents.Ticker do
  @moduledoc """
  Polls the registered superagents through the manager on a schedule. The
  GenServer only launches the work; the HTTP reads run in tasks so a slow
  panel never blocks the board.
  """
  use GenServer
  require Logger

  alias AgentBoard.Superagents

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

    try do
      Superagents.tick()

      # Starting/stopping an agent can wait on the external manager for up to
      # a minute; never block the ticker (and the next status read) on it.
      Task.Supervisor.start_child(AgentBoard.Superagents.TaskSupervisor, fn ->
        Superagents.reconcile()
      end)
    rescue
      exception -> Logger.warning("superagent tick failed: #{Exception.message(exception)}")
    end

    {:noreply, state}
  end

  defp interval, do: Application.get_env(:agent_board, :superagent_tick_interval, 30_000)
end
