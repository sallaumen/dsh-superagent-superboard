defmodule AgentBoard.Superagents do
  @moduledoc """
  The board's registry of DeepSeek superagents: one per repository, with the
  profile, port and state directory the external DSH manager uses. The board
  never starts a process from a LiveView; the manager and ticker are the
  effects (see `docs/research/superagents.md`).
  """
  import Ecto.Query, warn: false

  alias AgentBoard.Board
  alias AgentBoard.Orchestrator
  alias AgentBoard.Repo
  alias AgentBoard.Superagents.{Manager, Provisioner, Superagent, SuperagentEvent}

  @reconcile_pause_seconds 600

  @dsh_state Path.expand("~/.dsh/state")
  @dsh_profiles Path.expand("~/.dsh/profiles")
  @archive_root Path.expand("~/.agent_board/archived-superagents")

  @topic "superagents"

  @doc "Subscribe to `:superagents_changed` and `:agent_access_changed`."
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

  @doc "The directory the DSH state lives in; overridable in tests."
  def state_root,
    do: Path.expand(Application.get_env(:agent_board, :dsh_state_root, @dsh_state))

  @doc """
  Run `fun` to its end even if the caller dies, and return its result.

  Provisioning takes minutes and is started from a page; a reload must not cut
  it in half, because the half is what leaves an empty agent behind.
  """
  def detached(fun) when is_function(fun, 0) do
    AgentBoard.Superagents.TaskSupervisor
    |> Task.Supervisor.async_nolink(fun)
    |> Task.await(:infinity)
  end

  @doc "The directory the DSH profiles live in; overridable in tests."
  def profiles_root, do: Application.get_env(:agent_board, :dsh_profiles_dir, @dsh_profiles)

  @doc """
  Every DSH working profile on disk, with the port its `cordis.patch.yml`
  declares. The provisioner clones one of these; a profile without a patch
  port is listed without a port and cannot serve as a source.
  """
  def profiles_on_disk(root \\ profiles_root()) do
    case File.ls(root) do
      {:ok, names} ->
        names
        |> Enum.sort()
        |> Enum.map(&profile_entry(root, &1))
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  defp profile_entry(root, name) do
    dir = Path.join(root, name)
    if File.dir?(dir), do: %{name: name, dir: dir, port: patch_port(dir)}
  end

  @doc """
  The default source for a new project: the machine's main `superagent`
  profile when it exists, else the first profile on disk. `{:error,
  :no_working_profile}` means dsh has never created a profile here.
  """
  def default_source do
    case Enum.find(profiles_on_disk(), &(&1.name == "superagent")) ||
           List.first(profiles_on_disk()) do
      nil -> {:error, :no_working_profile}
      %{name: name, port: port} when is_integer(port) -> {:ok, source_struct(name, port)}
      %{name: name} -> {:error, {:profile_port_missing, name}}
    end
  end

  @doc "A source by working-profile name, ready for `provision/4`."
  def source_by_profile(name) when is_binary(name) do
    case Enum.find(profiles_on_disk(), &(&1.name == name)) do
      %{name: name, port: port} when is_integer(port) -> {:ok, source_struct(name, port)}
      %{name: name} -> {:error, {:profile_port_missing, name}}
      nil -> {:error, :profile_missing}
    end
  end

  @doc """
  The values a new project will use, without writing anything: the sentence
  the owner confirms shows these before the provisioner runs.
  """
  def preview(repository, source, attrs) do
    with {:ok, source} <- normalize_source(source),
         {:ok, profile} <- next_profile(repository),
         {:ok, port} <- port_for(attrs) do
      {:ok,
       %{
         profile: profile,
         port: port,
         state_dir: Path.join(state_root(), profile),
         workers: Map.get(attrs, :workers, 3),
         source_profile: source.profile
       }}
    end
  end

  defp source_struct(name, port), do: %Superagent{profile: name, port: port}

  defp normalize_source(%Superagent{} = source), do: {:ok, source}
  defp normalize_source(name) when is_binary(name), do: source_by_profile(name)
  defp normalize_source(nil), do: {:error, :source_required}

  defp port_for(attrs) do
    case Map.get(attrs, :port) do
      port when is_integer(port) -> {:ok, port}
      _ -> free_port()
    end
  end

  defp patch_port(dir) do
    case :file.read_file(Path.join(dir, "cordis.patch.yml")) do
      {:ok, text} ->
        case Regex.run(~r/^\s*port:\s*(\d+)/m, text, capture: :all_but_first) do
          [port] -> String.to_integer(port)
          _ -> nil
        end

      {:error, _} ->
        nil
    end
  end

  @doc """
  Reserve one row and ask the provisioner to create the external profile,
  port, state and setup. A failure keeps the row in `error`, marked for
  "Tentar de novo", and returns the reason; a missing checkout removes the row
  instead, since a retry would use the same path. An agent that would not stop
  keeps an ordinary row in `error`.
  """
  def provision(repository, source, attrs, provisioner \\ Provisioner.impl()) do
    with nil <- get_by_repository(repository),
         {:ok, source} <- normalize_source(source),
         {:ok, profile} <- next_profile(repository),
         {:ok, port} <- port_for(attrs),
         state_dir = Path.join(state_root(), profile),
         {:ok, superagent} <-
           create(%{
             repository_id: repository.id,
             profile: profile,
             port: port,
             state_dir: state_dir,
             desired_state: "running",
             observed_state: "starting",
             max_workers: Map.get(attrs, :workers, 3),
             created_by: Map.get(attrs, :actor, "owner"),
             checkout_path: Map.get(attrs, :path),
             source_profile: source.profile
           }) do
      superagent
      |> provisioner.provision(source, attrs)
      |> settle_provision(superagent, nil)
    else
      %Superagent{} -> {:error, :already_registered}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Run again a provisioning that failed, with what it was first asked for.
  Only a project that never came up can be retried.
  """
  def retry_provision(superagent, provisioner \\ Provisioner.impl())

  def retry_provision(
        %Superagent{provision_failed_at: %DateTime{}, source_profile: name, checkout_path: path} =
          superagent,
        provisioner
      )
      when is_binary(name) and is_binary(path) do
    attrs = %{path: path, workers: superagent.max_workers}

    with {:ok, source} <- source_by_profile(name),
         {:ok, superagent} <- claim_retry(superagent) do
      superagent
      |> provisioner.provision(source, attrs)
      |> settle_provision(superagent, "error")
    end
  end

  def retry_provision(_superagent, _provisioner), do: {:error, :nothing_to_retry}

  # One retry at a time, decided by the database and not by the row the screen
  # had: a second tab finds it taken. The failure mark stays until it works, so
  # the ticker keeps away from a project that is still being built.
  defp claim_retry(%Superagent{id: id}) do
    {claimed, _rows} =
      Repo.update_all(
        from(s in Superagent,
          where: s.id == ^id and not is_nil(s.provision_failed_at) and s.observed_state == "error"
        ),
        set: [observed_state: "starting", last_error: nil]
      )

    if claimed == 1 do
      broadcast()
      {:ok, get(id)}
    else
      {:error, :nothing_to_retry}
    end
  end

  defp settle_provision({:ok, _result}, superagent, from) do
    event(superagent, "provision", from, "starting", "owner", superagent.profile)

    superagent
    |> Superagent.changeset(%{provision_failed_at: nil})
    |> Repo.update()
    |> tap(fn _ -> broadcast() end)
  end

  # The agent would not stop, so its files stayed and it still needs a card to
  # be stopped or removed from: an ordinary row, which the board must not
  # restart and "Tentar de novo" could not rebuild.
  defp settle_provision({:error, {:still_running, reason, stop_failure}}, superagent, _from) do
    detail = "#{reason_text(reason)}; the agent did not stop: #{reason_text(stop_failure)}"

    {:ok, stopped} =
      superagent
      |> Superagent.changeset(%{desired_state: "stopped", provision_failed_at: nil})
      |> Repo.update()

    event(stopped, "provision", "starting", "error", "owner", detail)
    observe(stopped, %{state: "error", detail: detail})
    log_provision_error(stopped, detail)
    {:error, detail}
  end

  # A retry would use the same missing path again, so the row goes and the
  # repository returns to the form where the path is typed. Nothing was created.
  defp settle_provision({:error, :checkout_missing} = error, superagent, _from) do
    {:ok, _} = Repo.delete(superagent)
    broadcast()
    log_provision_error(superagent, "no git checkout at #{superagent.checkout_path}")
    error
  end

  # The provisioner undid its work. The row stays, with what a retry needs, and
  # the ticker keeps away from it. The page that asked may be gone, so the
  # reason is also kept in the repository's activity.
  defp settle_provision({:error, reason}, superagent, _from) do
    detail = reason_text(reason)
    event(superagent, "provision", "starting", "error", "owner", detail)

    {:ok, failed} =
      superagent
      |> Superagent.changeset(%{
        provision_failed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()

    observe(failed, %{state: "error", detail: detail})
    log_provision_error(failed, detail)
    {:error, reason}
  end

  defp log_provision_error(superagent, text) do
    Board.log_event(superagent.repository_id, "provision_error", superagent.profile, %{
      "reason" => text
    })
  end

  defp reason_text(text) when is_binary(text), do: text
  defp reason_text({:setup, text}) when is_binary(text), do: text
  defp reason_text(other), do: inspect(other)

  defp next_profile(repository) do
    base =
      repository.name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    base = if base == "", do: "project-#{repository.id}", else: base
    candidate = "superagent-" <> String.slice(base, 0, 40)

    taken =
      Repo.exists?(from s in Superagent, where: s.profile == ^candidate) or
        File.exists?(Path.join(profiles_root(), candidate))

    if taken do
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

  @doc """
  Start the external process and mark the desired state running. A project
  whose provisioning failed has nothing to start: it is retried instead.
  """
  def start(superagent, manager \\ Manager.impl(), actor \\ "owner")

  def start(%Superagent{provision_failed_at: %DateTime{}}, _manager, _actor),
    do: {:error, :provision_failed}

  def start(%Superagent{} = superagent, manager, actor) do
    case manager.start(superagent) do
      :ok ->
        set_desired(superagent, "running")
        observe(superagent, %{state: "starting", detail: nil})
        {:ok, superagent}

      {:error, reason} ->
        failed(superagent, "start", reason, actor)
    end
  end

  @doc "Stop the external process."
  def stop(%Superagent{} = superagent, manager \\ Manager.impl(), actor \\ "owner") do
    case manager.stop(superagent) do
      :ok ->
        set_desired(superagent, "stopped")
        observe(superagent, %{state: "stopped", detail: nil})
        {:ok, superagent}

      {:error, reason} ->
        failed(superagent, "stop", reason, actor)
    end
  end

  @doc "Pause or resume new work without killing the process."
  def pause(%Superagent{} = superagent, paused, manager \\ Manager.impl(), actor \\ "owner") do
    case manager.pause(superagent, paused) do
      :ok ->
        set_desired(superagent, if(paused, do: "paused", else: "running"))

        observe(superagent, %{
          state: if(paused, do: "paused", else: "starting"),
          detail: nil
        })

        {:ok, superagent}

      {:error, reason} ->
        failed(superagent, if(paused, do: "pause", else: "resume"), reason, actor)
    end
  end

  @doc "Change the worker ceiling through the manager."
  def scale(%Superagent{} = superagent, workers, manager \\ Manager.impl()) do
    with true <-
           is_integer(workers) and workers > 0 and workers <= Orchestrator.worker_range().last,
         :ok <- manager.scale(superagent, workers) do
      set_max_workers(superagent, workers)
      {:ok, superagent}
    else
      false -> {:error, :invalid_workers}
      # A save in between is the agent's settings moving, not the agent failing.
      {:error, :conflict} -> {:error, :conflict}
      {:error, reason} -> failed(superagent, "scale", reason)
    end
  end

  defp failed(superagent, action, reason, actor \\ "owner") do
    detail = inspect(reason)
    event(superagent, action, superagent.observed_state, "error", actor, detail)
    observe(superagent, %{state: "error", detail: detail})
    {:error, reason}
  end

  @doc """
  Read every registered superagent through the manager and record the
  observed state. Runs in the ticker, never in a LiveView callback.
  """
  def tick(manager \\ Manager.impl()) do
    superagents = list() |> Enum.filter(&is_nil(&1.provision_failed_at))

    superagents
    |> Task.async_stream(&manager.status/1,
      timeout: Application.get_env(:agent_board, :superagent_status_timeout_ms, 6_000),
      max_concurrency: 4,
      on_timeout: :kill_task
    )
    |> Enum.zip(superagents)
    |> Enum.each(fn
      {{:ok, {:ok, observation}}, superagent} ->
        observe(superagent, observation)

      {{:ok, {:error, reason}}, superagent} ->
        observe(superagent, %{state: "error", detail: inspect(reason)})

      # A read the board had to kill is an observation too: the row would
      # otherwise keep a state nobody has seen for a while.
      {{:exit, _reason}, superagent} ->
        observe(superagent, %{state: "unknown", detail: "status read timed out"})
    end)
  end

  @doc """
  Reconcile the desired state after a board restart: start a stopped agent
  whose owner wants it running, stop a running agent whose owner stopped it,
  and pause a ready one whose owner paused it. An error is left for a person;
  an unreachable agent is started again at most once every ten minutes.
  """
  def reconcile(manager \\ Manager.impl()) do
    list()
    |> Enum.filter(&is_nil(&1.provision_failed_at))
    |> Enum.each(&reconcile_one(&1, manager))
  end

  defp reconcile_one(superagent, manager) do
    case {superagent.desired_state, superagent.observed_state} do
      {"running", state} when state in ["stopped", "unknown"] ->
        auto_start(superagent, manager)

      {"running", "error"} ->
        if unreachable?(superagent.last_error), do: auto_start(superagent, manager), else: :ok

      {"stopped", state} when state in ["ready", "paused", "starting"] ->
        board_action(superagent, "stop", "stopped", fn -> stop(superagent, manager, "board") end)

      {"paused", "ready"} ->
        board_action(superagent, "pause", "paused", fn ->
          pause(superagent, true, manager, "board")
        end)

      _ ->
        :ok
    end
  end

  defp auto_start(superagent, manager),
    do:
      board_action(superagent, "start", "starting", fn -> start(superagent, manager, "board") end)

  # A start whose health check times out still answers :ok, so an agent that
  # dies at boot would be started again on every tick; a stop or pause the
  # manager refuses would be asked again every tick once the status read sees
  # the old state. The board's own actions are recorded as `board` and wait
  # @reconcile_pause_seconds between them.
  defp board_action(superagent, action, to_state, run) do
    if board_acted_recently?(superagent, action) do
      :ok
    else
      event(superagent, action, superagent.observed_state, to_state, "board", "reconcile")
      run.()
    end
  end

  defp board_acted_recently?(superagent, action) do
    since = DateTime.add(DateTime.utc_now(), -@reconcile_pause_seconds, :second)

    Repo.exists?(
      from e in SuperagentEvent,
        where:
          e.superagent_id == ^superagent.id and e.action == ^action and e.actor == "board" and
            e.inserted_at > ^since
    )
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

  defp profile_dir(profile), do: Path.join(profiles_root(), profile)

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

  @doc "Tell every open board that who may use an agent, or who asked, changed."
  def broadcast_access_changed,
    do: Phoenix.PubSub.broadcast(AgentBoard.PubSub, @topic, :agent_access_changed)

  defp broadcast,
    do: Phoenix.PubSub.broadcast(AgentBoard.PubSub, @topic, :superagents_changed)
end
