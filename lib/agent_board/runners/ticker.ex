defmodule AgentBoard.Runners.Ticker do
  @moduledoc """
  Reads the active runners' status files on a schedule. The process is a
  read of files the board owns; it never waits for an execution.
  """
  use GenServer
  require Logger

  alias AgentBoard.Runners

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    schedule(Keyword.get(opts, :interval, interval()))
    {:ok, %{interval: Keyword.get(opts, :interval, interval())}}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule(state.interval)

    try do
      Runners.tick()
    rescue
      exception -> Logger.warning("runner tick failed: #{Exception.message(exception)}")
    end

    {:noreply, state}
  end

  defp schedule(:manual), do: :ok
  defp schedule(ms), do: Process.send_after(self(), :tick, ms)
  defp interval, do: Application.get_env(:agent_board, :runner_tick_interval, 15_000)
end
