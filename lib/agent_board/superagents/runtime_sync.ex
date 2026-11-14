defmodule AgentBoard.Superagents.RuntimeSync do
  @moduledoc """
  Postgres owns each operator request and its last result. This board drains
  only its own requests in one supervised task; a busy profile never blocks
  another. No worker or timer is tied to a browser session.
  """
  use GenServer
  import Ecto.Query

  alias AgentBoard.{Repo, Superagents}
  alias AgentBoard.Superagents.{DshManager, Superagent}

  @pending ~w(waiting pending)
  @statuses ~w(updated current paused busy changed identity unavailable in_progress failed)
  @interval :timer.seconds(15)
  @cli_lock Path.expand("../../../priv/agent/harness/package-lock.json", __DIR__)
  @notice_patch Path.expand("../../../priv/agent/duplicate-issue-notice.patch", __DIR__)
  @branch_patch Path.expand("../../../priv/agent/assignment-branch.patch", __DIR__)
  @publication_patch Path.expand("../../../priv/agent/managed-publication.patch", __DIR__)
  @container_patch Path.expand("../../../priv/agent/container-worker.patch", __DIR__)
  @cleanup_patch Path.expand("../../../priv/agent/container-report-cleanup.patch", __DIR__)
  @external_resource @cleanup_patch
  @container_helper Path.expand("../../../priv/agent/container_worker.py", __DIR__)
  @external_resource @container_patch
  @external_resource @container_helper
  @external_resource @publication_patch
  @helper Path.expand("../../../priv/agent/superboard-branch.py", __DIR__)
  @external_resource @branch_patch
  @external_resource @helper
  @external_resource @cli_lock
  @external_resource @notice_patch
  @lock_digest Base.encode16(
                 :crypto.hash(:sha256, [
                   File.read!(@cli_lock),
                   File.read!(@notice_patch),
                   File.read!(@branch_patch),
                   File.read!(@publication_patch),
                   File.read!(@container_patch),
                   File.read!(@cleanup_patch),
                   File.read!(@container_helper),
                   File.read!(@helper)
                 ]),
                 case: :lower
               )

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def start(targets, server \\ __MODULE__) do
    owner = Oban.config().node
    lock = @lock_digest

    {:ok, :ok} =
      Repo.transaction(fn ->
        Enum.each(Enum.sort(targets), fn {id, repo} -> request(id, repo, owner, lock) end)
      end)

    announce()
    GenServer.cast(server, :check)
    :ok
  end

  defp request(id, repo, owner, lock) do
    # Serialize simultaneous clicks before deciding whether a request already exists.
    case Repo.one(from s in Superagent, where: s.id == ^id, lock: "FOR UPDATE")
         |> Repo.preload(:repository) do
      nil ->
        :ok

      %{runtime_sync: %{"status" => status}} when status in @pending ->
        :ok

      agent ->
        if slug(agent) == repo do
          receipt = %{
            "status" => "waiting",
            "owner" => owner,
            "repo" => repo,
            "identity" => identity(agent),
            "lock" => lock,
            "request" => Ecto.UUID.generate()
          }

          agent |> Ecto.Changeset.change(runtime_sync: receipt) |> Repo.update!()
        end
    end
  end

  defp identity(agent), do: [agent.profile, agent.port, agent.state_dir]

  # Owner controls and the ticker share this lock with the handoff. In
  # particular, an explicit pause must never be undone by sync's final resume.
  def exclusive(id, fun) do
    case :global.trans({{__MODULE__, id}, self()}, fun, [node()], 0) do
      :aborted -> {:error, :control_in_progress}
      result -> result
    end
  end

  def targets(agents), do: Map.new(agents, &{&1.id, slug(&1)})
  defp slug(agent), do: agent.repository.owner <> "/" <> agent.repository.name

  @impl true
  def init(opts) do
    interval =
      Keyword.get(
        opts,
        :interval,
        Application.get_env(:agent_board, :runtime_sync_interval, @interval)
      )

    state = %{
      interval: interval,
      runner: Keyword.get(opts, :runner, &run/3),
      task: nil,
      again: false
    }

    {:ok, schedule(state)}
  end

  defp schedule(%{interval: :manual} = state), do: state

  defp schedule(state) do
    Process.send_after(self(), :tick, state.interval)
    state
  end

  @impl true
  def handle_cast(:check, %{task: nil} = state), do: {:noreply, launch(state)}
  def handle_cast(:check, state), do: {:noreply, %{state | again: true}}

  @impl true
  def handle_info(:tick, state) do
    state = schedule(state)
    {:noreply, if(state.task, do: state, else: launch(state))}
  end

  def handle_info({ref, _}, %{task: ref} = state) do
    Process.demonitor(ref, [:flush])
    finish(state)
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{task: ref} = state), do: finish(state)

  defp finish(state) do
    ready = %{state | task: nil, again: false}
    {:noreply, if(state.again, do: launch(ready), else: ready)}
  end

  defp launch(state) do
    runner = state.runner

    task =
      Task.Supervisor.async_nolink(AgentBoard.Superagents.TaskSupervisor, fn -> drain(runner) end)

    %{state | task: task.ref}
  end

  defp drain(runner) do
    owner = Oban.config().node

    rows =
      Repo.all(
        from s in Superagent,
          where: s.runtime_sync["owner"] == ^owner and s.runtime_sync["status"] in ^@pending,
          order_by: s.id,
          select: {s.id, s.runtime_sync}
      )

    drain_rows(rows, runner)
  end

  defp drain_rows([], _runner), do: :ok

  defp drain_rows(rows, runner) do
    lock = @lock_digest

    Enum.each(rows, fn {id, receipt} ->
      exclusive(id, fn -> attempt(id, receipt, lock, runner) end)
    end)
  end

  defp attempt(id, receipt, lock, runner) do
    case Superagents.get(id) do
      %{runtime_sync: ^receipt} = agent ->
        save_result(id, receipt, check(agent, receipt, lock, runner))

      _ ->
        :ok
    end
  end

  defp save_result(_id, %{"status" => result}, result), do: :ok

  defp save_result(id, receipt, result) do
    next = Map.put(receipt, "status", result)

    {count, _} =
      Repo.update_all(from(s in Superagent, where: s.id == ^id and s.runtime_sync == ^receipt),
        set: [runtime_sync: next]
      )

    if count > 0, do: announce()
  end

  defp check(agent, receipt, lock, runner) do
    cond do
      identity(agent) != receipt["identity"] or slug(agent) != receipt["repo"] ->
        "identity"

      receipt["lock"] != lock ->
        "changed"

      agent.desired_state == "paused" ->
        "paused"

      agent.desired_state != "running" or agent.provision_failed_at ->
        "unavailable"

      true ->
        next_status(runner.(agent, receipt["repo"], lock), receipt["status"])
    end
  rescue
    _ -> "failed"
  end

  defp next_status("busy", _), do: "pending"
  defp next_status("in_progress", previous), do: previous
  defp next_status(result, _), do: result

  defp announce,
    do: Phoenix.PubSub.broadcast(AgentBoard.PubSub, "superagents", :runtime_sync_changed)

  defp run(agent, repo, lock) do
    script = Application.app_dir(:agent_board, "priv/agent/sync_runtime.py")

    args = [
      script,
      "--expected-lock",
      lock,
      "--profile",
      agent.profile,
      "--profiles-root",
      Path.expand(Superagents.profiles_root()),
      "--manager",
      DshManager.script(),
      "--port",
      Integer.to_string(agent.port),
      "--repo",
      repo,
      "--state",
      agent.state_dir
    ]

    case System.cmd("python3", args, stderr_to_stdout: true) do
      {output, 0} ->
        result = String.trim(output)
        if result in @statuses, do: result, else: "failed"

      _ ->
        "failed"
    end
  end
end
