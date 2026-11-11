defmodule AgentBoardWeb.LogsSheet do
  @moduledoc """
  The LiveView side of the logs sheet: its assigns, its timer and its reads.

  The sheet owns a timer only while its panel is the routed one. Opening
  reads once from the tail of each source; every tick reads at most 64 KiB
  per source and schedules the next tick only after the read returns, so a
  slow file never queues work. Closing cancels the timer; a tick that arrives
  after the panel changed is ignored by its token. The presentation is
  `AgentBoardWeb.BoardComponents.LogsSheet`; the reading, the offset state
  and the cap are `AgentBoard.Logs`.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [connected?: 1]

  alias AgentBoard.Logs

  @doc "The assigns a socket holds before the sheet is first opened."
  def mount(socket) do
    assign(socket,
      logs_sources: [],
      logs_entries: [],
      logs_state: Logs.empty_state(),
      logs_status: %{},
      logs_timer: nil,
      logs_paused: false
    )
  end

  @doc "The routed panel changed from `previous`: open, close or leave the sheet."
  def sync(%{assigns: %{panel: "logs"}} = socket, "logs"), do: socket
  def sync(%{assigns: %{panel: "logs"}} = socket, _previous), do: open(socket)
  def sync(socket, "logs"), do: close(socket)
  def sync(socket, _previous), do: socket

  @doc "The panel was closed by the owner: stop the timer."
  def close(socket) do
    cancel_timer(socket)
    assign(socket, logs_timer: nil, logs_paused: false)
  end

  @doc """
  The superagents changed: a new profile becomes a new source while the sheet
  is open; the old entries stay in the buffer and the new file is read from
  its tail.
  """
  def sources_changed(%{assigns: %{panel: "logs"}} = socket) do
    socket = assign(socket, :logs_sources, Logs.sources(socket.assigns.superagents))
    if socket.assigns.logs_paused, do: socket, else: read_once(socket)
  end

  def sources_changed(socket), do: socket

  @doc "A `{:logs_tick, token}` message: read and reschedule only for the live timer."
  def tick(socket, token) do
    current = socket.assigns.logs_timer

    if socket.assigns.panel == "logs" and not socket.assigns.logs_paused and
         match?(%{token: ^token}, current) do
      socket |> read_once() |> schedule_tick()
    else
      socket
    end
  end

  @doc "Clear the visible buffer without moving the read offset. A closed sheet ignores it."
  def clear(%{assigns: %{panel: "logs"}} = socket), do: assign(socket, :logs_entries, [])
  def clear(socket), do: socket

  @doc "Pause the timer. A closed sheet ignores it."
  def pause(%{assigns: %{panel: "logs"}} = socket) do
    cancel_timer(socket)
    assign(socket, logs_timer: nil, logs_paused: true)
  end

  def pause(socket), do: socket

  @doc "Resume the timer: read now and schedule again. A closed sheet ignores it."
  def resume(%{assigns: %{panel: "logs"}} = socket) do
    socket = assign(socket, :logs_paused, false)

    if socket.assigns.logs_timer do
      socket
    else
      socket |> read_once() |> schedule_tick()
    end
  end

  def resume(socket), do: socket

  defp open(socket) do
    sources = Logs.sources(socket.assigns.superagents)

    socket =
      assign(socket,
        logs_sources: sources,
        logs_entries: [],
        logs_state: Logs.empty_state(),
        logs_status: %{},
        logs_paused: false
      )

    if connected?(socket) do
      socket
      |> read_once()
      |> schedule_tick()
    else
      socket
    end
  end

  defp read_once(socket) do
    %{entries: entries, state: state, statuses: statuses} =
      Logs.read(socket.assigns.logs_sources, socket.assigns.logs_state)

    assign(socket,
      logs_entries: Logs.append(socket.assigns.logs_entries, entries),
      logs_state: state,
      logs_status: statuses
    )
  rescue
    # The observer never takes the board down and never logs into the file it
    # is reading: the unreadable state is the whole failure surface.
    _exception ->
      assign(socket, logs_status: Map.new(socket.assigns.logs_sources, &{&1.id, :unreadable}))
  end

  defp schedule_tick(%{assigns: %{logs_paused: true}} = socket), do: socket

  defp schedule_tick(socket) do
    token = make_ref()
    ref = Process.send_after(self(), {:logs_tick, token}, tick_interval())
    assign(socket, :logs_timer, %{ref: ref, token: token})
  end

  defp cancel_timer(%{assigns: %{logs_timer: %{ref: ref}}}) when is_reference(ref),
    do: Process.cancel_timer(ref)

  defp cancel_timer(_socket), do: :ok

  defp tick_interval, do: Application.get_env(:agent_board, :logs_tick_interval, 2_000)
end
