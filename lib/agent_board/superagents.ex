defmodule AgentBoard.Superagents do
  @moduledoc """
  The board's registry of DeepSeek superagents: one per repository, with the
  profile, port and state directory the external DSH manager uses. The board
  never starts a process from a LiveView; the manager and ticker are the
  effects (see `docs/research/superagents.md`).
  """
  import Ecto.Query, warn: false

  alias AgentBoard.Repo
  alias AgentBoard.Superagents.{Manager, Provisioner, Superagent, SuperagentEvent}

  @dsh_state Path.expand("~/.dsh/state")
  @archive_root Path.expand("~/.agent_board/archived-superagents")

  @topic "superagents"

  @doc "Subscribe to `{:superagents_changed}`."
  def subscribe, do: Phoenix.PubSub.subscribe(AgentBoard.PubSub, @topic)

  @doc "Every registered superagent, newest first, with its repository."
  def list do
    Repo.all(from s in Superagent, order_by: [asc: s.id], preload: [:repository])
  end

  @doc "One superagent by id, with its repository."
  def get(id), do: Repo.get(Superagent, id) |> Repo.preload(:repository)

  @doc "The superagent for a repository, or nil."
  def get_by_repository(nil), do: nil

  def get_by_repository(repository_id) when is_integer(repository_id) do
    Repo.get_by(Superagent, repository_id: repository_id)
  end

  def get_by_repository(%{id: id}), do: get_by_repository(id)

  @doc "The explicit state directories, in registration order."
  def state_paths do
    Repo.all(from s in Superagent, order_by: [asc: s.id], select: s.state_dir)
  end

  @doc """
  Reserve one row and ask the provisioner to create the external profile,
  port, state and setup. A failure keeps the row in `error` with the reason so
  the owner sees what happened instead of a silent half-project.
  """
  def provision(repository, source, attrs, provisioner \\ Provisioner.impl()) do
    with nil <- get_by_repository(repository),
         {:ok, profile} <- next_profile(repository),
         {:ok, port} <- free_port(),
         state_dir = Path.join(@dsh_state, profile),
         {:ok, superagent} <-
           create(%{
             repository_id: repository.id,
             profile: profile,
             port: port,
             state_dir: state_dir,
             desired_state: "running",
             observed_state: "starting",
             max_workers: Map.get(attrs, :workers, 3),
             created_by: Map.get(attrs, :actor, "owner")
           }) do
      case provisioner.provision(superagent, source, attrs) do
        {:ok, _} ->
          event(superagent, "provision", nil, "starting", "owner", profile)
          {:ok, superagent}

        {:error, reason} ->
          event(superagent, "provision", "starting", "error", "owner", inspect(reason))
          observe(superagent, %{state: "error", detail: inspect(reason)})
          {:error, reason}
      end
    else
      %Superagent{} -> {:error, :already_registered}
      {:error, reason} -> {:error, reason}
    end
  end

  defp next_profile(repository) do
    base =
      repository.name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    base = if base == "", do: "project-#{repository.id}", else: base
    candidate = "superagent-" <> String.slice(base, 0, 40)

    if Repo.exists?(from s in Superagent, where: s.profile == ^candidate) do
      {:ok, candidate <> "-" <> Integer.to_string(System.unique_integer([:positive]))}
    else
      {:ok, candidate}
    end
  end

  defp free_port do
    used = Repo.all(from s in Superagent, select: s.port)

    Enum.find_value(3090..3199, {:error, :no_port}, fn port ->
      if port in used or port_open?(port), do: nil, else: {:ok, port}
    end)
  end

  defp port_open?(port) do
    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary], 100) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      _ ->
        false
    end
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

    changeset =
      superagent
      |> Superagent.changeset(attrs)
      |> Ecto.Changeset.force_change(:last_error, attrs.last_error)

    case Repo.update(changeset) do
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
    Enum.each(list(), &reconcile_one(&1, manager))
  end

  defp reconcile_one(superagent, manager) do
    case {superagent.desired_state, superagent.observed_state} do
      {"running", state} when state in ["stopped", "unknown"] ->
        start(superagent, manager)

      {"running", "error"} ->
        if unreachable?(superagent.last_error), do: start(superagent, manager), else: :ok

      {"stopped", state} when state in ["ready", "paused", "starting"] ->
        stop(superagent, manager)

      {"paused", "ready"} ->
        pause(superagent, true, manager)

      _ ->
        :ok
    end
  end

  @doc """
  Stop an agent, move its profile and state to the archive root and remove the
  row. Nothing is deleted: the archive keeps the profile/state for recovery.
  """
  def remove(%Superagent{} = superagent, manager \\ Manager.impl()) do
    with :ok <- stop_running(superagent, manager),
         {:ok, archive} <- archive_dirs(superagent),
         {:ok, _} <- Repo.delete(superagent) do
      broadcast()
      {:ok, archive}
    end
  end

  defp stop_running(superagent, manager) do
    case manager.status(superagent) do
      {:ok, %{state: state}} when state in ["ready", "paused", "starting"] ->
        manager.stop(superagent)

      {:ok, _} ->
        manager.stop(superagent)

      {:error, reason} ->
        if unreachable?(reason), do: :ok, else: {:error, reason}
    end
  end

  defp archive_dirs(superagent) do
    root = Application.get_env(:agent_board, :superagent_archive_root, @archive_root)
    stamp = DateTime.utc_now() |> DateTime.to_unix()
    target = Path.join(root, "#{superagent.profile}-#{stamp}")
    System.cmd("/bin/mkdir", ["-p", target])

    with :ok <- move(profile_dir(superagent.profile), Path.join(target, "profile")),
         :ok <- copy(superagent.state_dir, Path.join(target, "state")) do
      {:ok, target}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp profile_dir(profile), do: Path.expand("~/.dsh/profiles/#{profile}")

  defp copy(source, target) do
    case :file.read_file_info(source) do
      {:ok, _} ->
        case System.cmd("/bin/cp", ["-R", source, target], stderr_to_stdout: true) do
          {_output, 0} -> :ok
          {output, _code} -> {:error, {String.slice(output, 0, 200), source, target}}
        end

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, {reason, source}}
    end
  end

  defp move(source, target) do
    case :file.read_file_info(source) do
      {:ok, _} ->
        case :file.rename(source, target) do
          :ok -> :ok
          {:error, reason} -> {:error, {reason, source, target}}
        end

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, {reason, source}}
    end
  end

  defp unreachable?(nil), do: false

  defp unreachable?(error) do
    String.contains?(inspect(error), ["econnrefused", "unreachable", "TransportError"])
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
