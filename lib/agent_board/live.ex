defmodule AgentBoard.Live do
  @moduledoc """
  The live poll: reads the agent's tickets (the runner's state) and pushes the
  board when a ticket changed — the real-time shortcut, not only the 1 min sync.

  It overlays the ticket state on the tasks and broadcasts to the LiveView.
  """
  use GenServer

  import Ecto.Query, warn: false

  alias AgentBoard.{Board, Sync}
  alias AgentBoard.Board.{Repository, Task}
  alias AgentBoard.Repo

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:poll, state) do
    # init/1 schedules the first tick; the handler must schedule the next one,
    # otherwise the poller runs exactly once.
    schedule()
    {:noreply, poll(state)}
  end

  # The interval is a knob: the test environment stretches it so the
  # supervised poller never touches the sandboxed database mid-suite.
  defp schedule, do: Process.send_after(self(), :poll, interval())

  defp interval, do: Application.get_env(:agent_board, :live_poll_interval, 10_000)

  @doc "One poll: overlay the tickets on the tasks and broadcast when the hash changed."
  def poll(state \\ %{}) do
    poll_tickets(state)
  rescue
    # The runner's sqlite can be absent or corrupt; the poller must survive it
    # and the GenServer must keep its schedule.
    _exception -> state
  end

  defp poll_tickets(state) do
    tickets = Sync.normalized_tickets()

    Repo.all(Repository)
    |> Enum.reduce(state, fn repo, acc ->
      overlay_tasks(repo, tickets)
      hash = :erlang.phash2({repo.id, tickets})

      if Map.get(acc, repo.id) != hash do
        Board.broadcast(repo.id)
        Map.put(acc, repo.id, hash)
      else
        acc
      end
    end)
  end

  defp overlay_tasks(repo, tickets) do
    Enum.each(tickets, fn ticket ->
      case Sync.ticket_state(ticket) do
        nil ->
          :ok

        overlay ->
          Enum.each(ticket["numbers"], &overlay_number(repo, &1, overlay))
      end
    end)
  end

  defp overlay_number(repo, raw, overlay) do
    number = if is_binary(raw), do: String.to_integer(raw), else: raw

    Repo.update_all(
      from(t in Task,
        where:
          t.repository_id == ^repo.id and t.number == ^number and
            not t.stopped and not t.archived
      ),
      set: [state: overlay, updated_at: DateTime.utc_now()]
    )
  end
end
