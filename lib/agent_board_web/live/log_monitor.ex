defmodule AgentBoardWeb.LogMonitor do
  @moduledoc """
  The log buffer and timer for Settings → Logs.

  The section owns a timer only while it is visible. Opening
  reads once from the tail of each source; every tick reads at most 64 KiB
  per source and schedules the next tick only after the read returns, so a
  slow file never queues work. Closing cancels the timer; a tick that arrives
  after leaving the section is ignored by its token. The presentation is
  `AgentBoardWeb.BoardComponents.Settings.Logs`; the reading, the offset state
  and the cap are `AgentBoard.Logs`.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, push_patch: 2]

  alias AgentBoard.Logs
  alias AgentBoardWeb.BoardNavigation

  @doc "The assigns a socket holds before the section is first opened."
  def mount(socket) do
    assign(socket,
      logs_open: false,
      logs_filters: %{},
      logs_sources: [],
      logs_entries: [],
      logs_state: Logs.empty_state(),
      logs_status: %{},
      logs_timer: nil,
      logs_paused: false
    )
  end

  @doc "Follow the URL: read only while Settings → Logs is the current section."
  def sync(%{assigns: %{panel: "settings", settings_section: "logs"}} = socket, params) do
    socket = if socket.assigns.logs_open, do: socket, else: open(socket)
    assign(socket, :logs_filters, filters(params, socket.assigns.logs_sources))
  end

  def sync(%{assigns: %{logs_open: true}} = socket, _params), do: close(socket)
  def sync(socket, _params), do: socket

  @doc "Only known source IDs and levels enter the URL; source paths are server owned."
  def filter(%{assigns: %{logs_open: true}} = socket, params) do
    values = filters(params, socket.assigns.logs_sources)
    push_patch(socket, to: BoardNavigation.settings_path(socket.assigns.repo, "logs", values))
  end

  def filter(socket, _params), do: socket

  defp filters(params, sources) do
    %{}
    |> put_filter("source", params["source"], Enum.map(sources, & &1.id))
    |> put_filter("level", params["level"], ~w(warning error))
  end

  defp put_filter(map, key, value, allowed) do
    if value in allowed, do: Map.put(map, key, value), else: map
  end

  @doc "Read one batch now, including while paused, without changing the timer."
  def refresh(%{assigns: %{logs_open: true}} = socket), do: read_once(socket)
  def refresh(socket), do: socket

  @doc "The panel was closed by the owner: stop the timer."
  def close(socket) do
    cancel_timer(socket)
    assign(socket, logs_open: false, logs_timer: nil, logs_paused: false)
  end

  @doc """
  The superagents changed: a new profile becomes a new source while the section
  is open; the old entries stay in the buffer and the new file is read from
  its tail.
  """
  def sources_changed(%{assigns: %{logs_open: true}} = socket) do
    sources = Logs.sources(socket.assigns.superagents)

    socket =
      assign(socket,
        logs_sources: sources,
        logs_filters: filters(socket.assigns.logs_filters, sources)
      )

    if socket.assigns.logs_paused, do: socket, else: read_once(socket)
  end

  def sources_changed(socket), do: socket

  @doc "A `{:logs_tick, token}` message: read and reschedule only for the live timer."
  def tick(socket, token) do
    current = socket.assigns.logs_timer

    if socket.assigns.logs_open and not socket.assigns.logs_paused and
         match?(%{token: ^token}, current) do
      socket |> read_once() |> schedule_tick()
    else
      socket
    end
  end

  @doc "Clear the visible buffer without moving the read offset. An inactive section ignores it."
  def clear(%{assigns: %{logs_open: true}} = socket), do: assign(socket, :logs_entries, [])
  def clear(socket), do: socket

  @doc "Pause the timer. An inactive section ignores it."
  def pause(%{assigns: %{logs_open: true}} = socket) do
    cancel_timer(socket)
    assign(socket, logs_timer: nil, logs_paused: true)
  end

  def pause(socket), do: socket

  @doc "Resume the timer: read now and schedule again. An inactive section ignores it."
  def resume(%{assigns: %{logs_open: true}} = socket) do
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
        logs_open: true,
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
