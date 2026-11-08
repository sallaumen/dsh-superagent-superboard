defmodule AgentBoard.Superagents do
  @moduledoc """
  The board's registry of DeepSeek superagents: one per repository, with the
  profile, port and state directory the external DSH manager uses. The board
  never starts a process from a LiveView; the manager and ticker are the
  effects (see `docs/research/superagents.md`).
  """
  import Ecto.Query, warn: false

  alias AgentBoard.Repo
  alias AgentBoard.Superagents.{Manager, Superagent, SuperagentEvent}

  @topic "superagents"

  @doc "Subscribe to `{:superagents_changed}`."
  def subscribe, do: Phoenix.PubSub.subscribe(AgentBoard.PubSub, @topic)

  @doc "Every registered superagent, newest first, with its repository."
  def list do
    Repo.all(from s in Superagent, order_by: [asc: s.id], preload: [:repository])
  end

  @doc "One superagent by id."
  def get(id), do: Repo.get(Superagent, id)

  @doc "The superagent for a repository, or nil."
  def get_by_repository(nil), do: nil

  def get_by_repository(repository_id) when is_integer(repository_id) do
    Repo.get_by(Superagent, repository_id: repository_id)
  end

  def get_by_repository(%{id: id}), do: get_by_repository(id)

  @doc "The explicit SQLite state files, in registration order."
  def state_paths do
    Repo.all(from s in Superagent, order_by: [asc: s.id], select: s.state_dir)
  end

  @doc "Create a superagent row. Provisioning adds the external profile later."
  def create(attrs) do
    %Superagent{}
    |> Superagent.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, _superagent} -> broadcast()
      _ -> :ok
    end)
  end

  @doc "Change the desired state (running, paused, stopped)."
  def set_desired(%Superagent{} = superagent, state, actor \\ "owner") do
    superagent
    |> Superagent.changeset(%{desired_state: state})
    |> Repo.update()
    |> tap(fn
      {:ok, updated} ->
        event(updated, "desired", superagent.desired_state, state, actor)
        broadcast()

      _ ->
        :ok
    end)
  end

  @doc "Change the worker ceiling; the manager applies it in phase 3."
  def set_max_workers(%Superagent{} = superagent, workers, actor \\ "owner") do
    superagent
    |> Superagent.changeset(%{max_workers: workers})
    |> Repo.update()
    |> tap(fn
      {:ok, updated} ->
        event(updated, "scale", to_string(superagent.max_workers), to_string(workers), actor)
        broadcast()

      _ ->
        :ok
    end)
  end

  @doc """
  Record one observed status. An unchanged state updates the timestamp and
  error only; a changed state writes one event and broadcasts.
  """
  def observe(%Superagent{} = superagent, %{} = observation) do
    state = observation[:state] || "unknown"
    detail = observation[:detail]
    at = observation[:observed_at] || DateTime.utc_now()

    attrs = %{
      observed_state: state,
      observed_at: at,
      last_error: observation[:last_error] || if(state == "error", do: detail)
    }

    case superagent |> Superagent.changeset(attrs) |> Repo.update() do
      {:ok, updated} ->
        maybe_observed_event(updated, superagent, state, detail)
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp maybe_observed_event(updated, before, state, detail) do
    changed? =
      updated.observed_state != before.observed_state or
        (updated.last_error && updated.last_error != before.last_error)

    if changed? do
      event(updated, "observe", before.observed_state, state, "system", detail)
      broadcast()
    end
  end

  @doc "Start the external process and mark the desired state running."
  def start(%Superagent{} = superagent, manager \\ Manager.impl()) do
    case manager.start(superagent) do
      :ok ->
        set_desired(superagent, "running")
        observe(superagent, %{state: "starting", detail: nil})
        {:ok, superagent}

      {:error, reason} ->
        failed(superagent, "start", reason)
    end
  end

  @doc "Stop the external process."
  def stop(%Superagent{} = superagent, manager \\ Manager.impl()) do
    case manager.stop(superagent) do
      :ok ->
        set_desired(superagent, "stopped")
        observe(superagent, %{state: "stopped", detail: nil})
        {:ok, superagent}

      {:error, reason} ->
        failed(superagent, "stop", reason)
    end
  end

  @doc "Pause or resume new work without killing the process."
  def pause(%Superagent{} = superagent, paused, manager \\ Manager.impl()) do
    case manager.pause(superagent, paused) do
      :ok ->
        set_desired(superagent, if(paused, do: "paused", else: "running"))

        observe(superagent, %{
          state: if(paused, do: "paused", else: "starting"),
          detail: nil
        })

        {:ok, superagent}

      {:error, reason} ->
        failed(superagent, if(paused, do: "pause", else: "resume"), reason)
    end
  end

  @doc "Change the worker ceiling through the manager."
  def scale(%Superagent{} = superagent, workers, manager \\ Manager.impl()) do
    with true <- is_integer(workers) and workers > 0 and workers <= 32,
         :ok <- manager.scale(superagent, workers) do
      set_max_workers(superagent, workers)
      {:ok, superagent}
    else
      false -> {:error, :invalid_workers}
      {:error, reason} -> failed(superagent, "scale", reason)
    end
  end

  defp failed(superagent, action, reason) do
    detail = inspect(reason)
    event(superagent, action, superagent.observed_state, "error", "owner", detail)
    observe(superagent, %{state: "error", detail: detail})
    {:error, reason}
  end

  @doc """
  Read every registered superagent through the manager and record the
  observed state. Runs in the ticker, never in a LiveView callback.
  """
  def tick(manager \\ Manager.impl()) do
    list()
    |> Task.async_stream(
      fn superagent -> {superagent, manager.status(superagent)} end,
      timeout: 6_000,
      max_concurrency: 4,
      on_timeout: :kill_task
    )
    |> Enum.each(fn
      {:ok, {superagent, {:ok, observation}}} ->
        observe(superagent, observation)

      {:ok, {superagent, {:error, reason}}} ->
        observe(superagent, %{state: "error", detail: inspect(reason)})

      {:exit, _reason} ->
        :ok
    end)
  end

  @doc """
  Reconcile the desired state after a board restart: start a stopped agent
  whose owner wants it running, stop a running agent whose owner stopped it,
  and pause a ready one whose owner paused it. An error is left for a person,
  not restarted in a loop.
  """
  def reconcile(manager \\ Manager.impl()) do
    Enum.each(list(), fn superagent ->
      case {superagent.desired_state, superagent.observed_state} do
        {"running", state} when state in ["stopped", "unknown"] ->
          start(superagent, manager)

        {"stopped", state} when state in ["ready", "paused", "starting"] ->
          stop(superagent, manager)

        {"paused", "ready"} ->
          pause(superagent, true, manager)

        _ ->
          :ok
      end
    end)
  end

  @doc "Record one lifecycle event."
  def event(%Superagent{} = superagent, action, from, to, actor, detail \\ nil) do
    %SuperagentEvent{}
    |> SuperagentEvent.changeset(%{
      superagent_id: superagent.id,
      action: action,
      from_state: from,
      to_state: to,
      actor: actor,
      detail: detail && String.slice(to_string(detail), 0, 500)
    })
    |> Repo.insert()
  end

  @doc "The latest events for one superagent."
  def events(%Superagent{id: id}, limit \\ 10) do
    Repo.all(
      from e in SuperagentEvent,
        where: e.superagent_id == ^id,
        order_by: [desc: e.inserted_at, desc: e.id],
        limit: ^limit
    )
  end

  defp broadcast,
    do: Phoenix.PubSub.broadcast(AgentBoard.PubSub, @topic, :superagents_changed)
end
