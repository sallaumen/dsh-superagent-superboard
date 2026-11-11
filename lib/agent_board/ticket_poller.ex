defmodule AgentBoard.TicketPoller do
  @moduledoc """
  The ticket poll: reads the runner's tickets and pushes the board when a
  ticket or its active worktree changes — the real-time shortcut, not only
  the five-minute sync.

  It applies the ticket overlay to the tasks and broadcasts to the LiveView.
  """
  use GenServer
  require Logger

  alias AgentBoard.{AgentState, AgentWorktree, Board, TicketOverlay, Tickets}
  alias AgentBoard.Board.Repository
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
    # otherwise the poller runs exactly once. The work comes first so the
    # interval runs between polls: a slow poll does not queue the next tick.
    state = poll(state)
    schedule()
    {:noreply, state}
  end

  # The interval is a knob: the test environment stretches it so the
  # supervised poller never touches the sandboxed database mid-suite.
  defp schedule, do: Process.send_after(self(), :poll, interval())

  defp interval, do: Application.get_env(:agent_board, :ticket_poll_interval, 10_000)

  @doc "One poll: overlay the tickets on the tasks and broadcast when a visible signal changed."
  def poll(state \\ %{}) do
    poll_tickets(state)
  rescue
    # A missing or corrupt sqlite already reads as no tickets (AgentState); what
    # lands here is a regression in the overlay path, so it is said, and the
    # GenServer keeps its schedule.
    exception ->
      Logger.warning("ticket poll failed: #{Exception.message(exception)}")
      state
  end

  defp poll_tickets(state) do
    tickets = AgentState.tickets()

    Repo.all(Repository)
    |> Enum.reduce(state, fn repo, acc ->
      # Only this repository's tickets: another one's change reloads its own tabs.
      own = Enum.filter(tickets, &AgentState.same_repository?(&1, repo))
      # The overlays are computed every poll (they read comments, not only
      # tickets) but written only when something changed: an unchanged poll
      # writes nothing. A restart's empty state writes them all once.
      overlays = overlays(repo, own)
      hash = :erlang.phash2({repo.id, own, overlays, active_worktrees(repo, own)})

      if Map.get(acc, repo.id) != hash do
        apply_overlays(repo, overlays)
        Board.broadcast(repo.id)
        Map.put(acc, repo.id, hash)
      else
        acc
      end
    end)
  end

  defp active_worktrees(repo, tickets) do
    for ticket <- tickets,
        ticket["assignment"] == "running",
        is_nil(ticket["ended_at"]),
        AgentState.same_repository?(ticket, repo) do
      {ticket["id"], AgentWorktree.observe(ticket)}
    end
  end

  # The workpad and the question check read the conversation only for a
  # waiting ticket: Tickets.state calls them lazily.
  defp overlays(repo, tickets) do
    for {number, ticket} <- Tickets.by_number(tickets),
        overlay =
          Tickets.state(ticket,
            workpad: fn -> Board.agent_workpad(repo.id, number) end,
            asked?: fn -> Board.agent_asked?(repo.id, number) end
          ),
        overlay != nil,
        do: {number, overlay, ticket["started_at"]}
  end

  defp apply_overlays(repo, overlays) do
    for {number, overlay, started_at} <- overlays,
        do: TicketOverlay.apply(repo, number, overlay, started_at)
  end
end
