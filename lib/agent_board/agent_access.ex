defmodule AgentBoard.AgentAccess do
  @moduledoc """
  Who may put a superagent to work, per project.

  The list itself belongs to the agent (`policy.sources.github.allowed`); the
  board reads it, proposes changes through `AgentBoard.Actions`, and keeps
  only one record of its own: the requests the owner set aside. A person on
  the list who mentions the bot opens work that spends money and may reach
  `main`, so every change names the person and the project.

  Reads never raise and never call GitHub unless asked: the overview touches
  only the loopback API and the local database, so it can run on a timer.
  """
  import Ecto.Query, warn: false

  alias AgentBoard.AgentAccess.{Dismissal, Refusals}
  alias AgentBoard.Board.Task, as: BoardTask
  alias AgentBoard.{GitHub, Repo, Superagents}
  alias AgentBoard.Superagents.{Manager, Superagent}

  @login ~r/\A[a-z0-9](?:[a-z0-9-]{0,38})\z/i
  @finished_states ~w(done closed)
  @rerun_limit 10
  @read_timeout 6_000

  @type project :: map()

  @doc "The bot's GitHub account, the name a person writes to ask for work."
  def bot_login, do: "sallaumen-agent"

  @doc "How many issues one confirmation may re-run."
  def rerun_limit, do: @rerun_limit

  @doc "A GitHub login from free text, with or without the @."
  @spec normalize_login(term()) :: {:ok, String.t()} | {:error, :invalid_login}
  def normalize_login(value) when is_binary(value) do
    login = value |> String.trim() |> String.trim_leading("@")
    if Regex.match?(@login, login), do: {:ok, login}, else: {:error, :invalid_login}
  end

  def normalize_login(_value), do: {:error, :invalid_login}

  @doc "Every project with its cleared people and the requests still waiting."
  @spec overview([Superagent.t()], module()) :: [project()]
  def overview(superagents \\ Superagents.list(), manager \\ Manager.impl()) do
    superagents
    |> Task.async_stream(&read(&1, manager),
      timeout: @read_timeout,
      max_concurrency: 4,
      on_timeout: :kill_task
    )
    |> Enum.zip(superagents)
    |> Enum.map(fn
      {{:ok, read}, superagent} -> project(superagent, read)
      {{:exit, _reason}, superagent} -> project(superagent, {{:error, :timeout}, {:ok, []}})
    end)
  end

  defp read(superagent, manager),
    do: {manager.access(superagent), Refusals.read(superagent.state_dir)}

  defp project(superagent, {{:ok, %{allowed: allowed}}, refusals}) do
    {refused, reason} =
      case refusals do
        {:ok, refused} -> {refused, nil}
        {:error, reason} -> {[], {:refusals, reason}}
      end

    cleared = MapSet.new(allowed, &key(&1.login))

    waiting =
      refused
      |> Enum.reject(&MapSet.member?(cleared, key(&1.login)))
      |> Enum.filter(&match?({:ok, _}, normalize_login(&1.login)))

    states = task_states(superagent, waiting)

    %{
      id: superagent.id,
      superagent: superagent,
      repository: repository_name(superagent),
      state: :ok,
      reason: reason,
      allowed: allowed,
      requests: requests(superagent, waiting, states),
      refused:
        waiting
        |> Enum.reject(&(&1.handled or is_nil(&1.number)))
        |> MapSet.new(& &1.number)
    }
  end

  defp project(superagent, {{:error, reason}, _refusals}) do
    %{
      id: superagent.id,
      superagent: superagent,
      repository: repository_name(superagent),
      state: :unavailable,
      reason: reason,
      allowed: [],
      requests: [],
      refused: MapSet.new()
    }
  end

  defp task_states(%Superagent{repository_id: repository_id}, refusals) do
    numbers = refusals |> Enum.map(& &1.number) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if numbers == [] do
      %{}
    else
      Repo.all(
        from t in BoardTask,
          where: t.repository_id == ^repository_id and t.number in ^numbers,
          select: {t.number, t.state}
      )
      |> Map.new()
    end
  end

  defp requests(superagent, refusals, states) do
    dismissed = dismissed_at(superagent)

    refusals
    |> Enum.group_by(&key(&1.login))
    |> Enum.map(fn {login_key, mentions} -> request(login_key, mentions, states) end)
    |> Enum.reject(fn request ->
      case dismissed[request.key] do
        nil -> false
        at -> DateTime.compare(request.last_at, at) != :gt
      end
    end)
    |> Enum.sort_by(& &1.last_at, {:desc, DateTime})
  end

  # Mentions arrive newest first, so the first of each issue is the one to
  # run again: one issue never starts twice.
  defp request(login_key, [latest | _] = mentions, states) do
    issues =
      mentions
      |> Enum.reject(&is_nil(&1.number))
      |> Enum.uniq_by(& &1.number)
      |> Enum.map(&issue(&1, states))

    %{
      key: login_key,
      login: latest.login,
      mentions: length(mentions),
      last_at: latest.at,
      issues: issues,
      rerun:
        issues
        |> Enum.filter(& &1.runnable)
        |> Enum.take(@rerun_limit)
        |> Enum.map(&Map.take(&1, [:number, :trigger_id]))
    }
  end

  defp issue(mention, states) do
    mention
    |> Map.take([:number, :url, :title, :trigger_id, :handled])
    |> Map.put(:runnable, not mention.handled and states[mention.number] not in @finished_states)
  end

  defp dismissed_at(%Superagent{id: id}) do
    Repo.all(
      from d in Dismissal, where: d.superagent_id == ^id, select: {d.login, d.dismissed_at}
    )
    |> Map.new()
  end

  @doc """
  A failed read keeps what the last good one showed, marked unavailable, so
  a restarting agent does not make people vanish from the screen.
  """
  @spec keep_last_good([project()], [project()]) :: [project()]
  def keep_last_good(previous, fresh) do
    by_id = Map.new(previous, &{&1.id, &1})

    Enum.map(fresh, fn
      %{state: :unavailable, id: id} = project ->
        case by_id[id] do
          nil -> project
          last -> %{last | state: :unavailable, reason: project.reason}
        end

      project ->
        project
    end)
  end

  @doc "What the rest of the board shows: people waiting, and issues the agent refused."
  @spec summary([project()]) :: %{count: non_neg_integer(), refused: MapSet.t()}
  def summary(projects) do
    %{
      count: projects |> Enum.map(&length(&1.requests)) |> Enum.sum(),
      refused:
        projects
        |> Enum.flat_map(fn project ->
          Enum.map(project.refused, &{project.superagent.repository_id, &1})
        end)
        |> MapSet.new()
    }
  end

  @doc "A value that changes when what the board shows about access changes."
  @spec fingerprint([project()]) :: integer()
  def fingerprint(projects) do
    projects
    |> Enum.map(fn project ->
      {project.id, project.state, Enum.map(project.allowed, & &1.login),
       Enum.map(project.requests, &{&1.key, &1.mentions}), project.refused}
    end)
    |> :erlang.phash2()
  end

  @doc "Read access and tell open boards if it differs; answers the new fingerprint."
  @spec announce_if_changed(integer() | nil) :: integer()
  def announce_if_changed(previous) do
    fingerprint = fingerprint(overview())
    if fingerprint != previous, do: changed()
    fingerprint
  end

  @doc """
  Put a person on the project's list and, when asked, run again the mentions
  the agent refused. A re-run that fails does not undo the clearance: the
  answer says which issues still need a new mention.
  """
  def grant(%Superagent{} = superagent, login, rerun \\ [], manager \\ Manager.impl()) do
    with {:ok, login} <- normalize_login(login),
         :ok <- manager.allow(superagent, login) do
      {requeued, failed} =
        rerun |> Enum.take(@rerun_limit) |> Enum.split_with(&requeued?(superagent, &1, manager))

      changed()

      {:ok,
       %{
         login: login,
         requeued: Enum.map(requeued, & &1.number),
         failed: Enum.map(failed, & &1.number)
       }}
    end
  end

  defp requeued?(superagent, %{trigger_id: trigger_id}, manager),
    do: manager.requeue(superagent, trigger_id) == {:ok, true}

  @doc "Take a person off the list. The repository's owner cannot be removed."
  def revoke(%Superagent{} = superagent, login, manager \\ Manager.impl()) do
    with {:ok, login} <- normalize_login(login),
         :ok <- refuse_owner(superagent, login),
         :ok <- manager.disallow(superagent, login) do
      changed()
      {:ok, login}
    end
  end

  @doc "Whether this login is the repository's owner."
  def owner?(%Superagent{repository: %{owner: owner}}, login), do: key(owner) == key(login)
  def owner?(_superagent, _login), do: false

  defp refuse_owner(superagent, login) do
    if owner?(superagent, login), do: {:error, :owner_protected}, else: :ok
  end

  @doc "Set a request aside until the person mentions the bot again."
  def dismiss(%Superagent{id: id}, login) do
    with {:ok, login} <- normalize_login(login),
         {:ok, dismissal} <-
           %Dismissal{}
           |> Dismissal.changeset(%{
             superagent_id: id,
             login: key(login),
             dismissed_at: DateTime.utc_now() |> DateTime.truncate(:second)
           })
           |> Repo.insert(
             on_conflict: {:replace, [:dismissed_at, :updated_at]},
             conflict_target: [:superagent_id, :login]
           ) do
      changed()
      {:ok, dismissal}
    end
  end

  @doc "The repository's collaborators by lowercase login, with their role."
  @spec collaborators(Superagent.t(), Req.Request.t()) :: {:ok, map()} | {:error, term()}
  def collaborators(%Superagent{repository: repo}, client \\ GitHub.client()) do
    {:ok,
     client
     |> GitHub.collaborators(repo.owner, repo.name)
     |> Map.new(&{key(&1["login"]), &1["role_name"] || "unknown"})}
  rescue
    exception -> {:error, exception}
  end

  @doc """
  What the board knows about someone about to be added: whether the account
  exists and what it may do in the repository. GitHub being unavailable is
  `:unknown`, never "does not exist".
  """
  @spec candidate(Superagent.t(), String.t(), Req.Request.t()) :: map()
  def candidate(%Superagent{repository: repo}, login, client \\ GitHub.client()) do
    case GitHub.collaborator_permission(client, repo.owner, repo.name, login) do
      {:ok, role} -> %{login: login, exists: true, role: role}
      :not_found -> %{login: login, exists: false, role: nil}
    end
  rescue
    _exception -> %{login: login, exists: :unknown, role: nil}
  end

  @doc "Tell every open board that access changed."
  def changed, do: Superagents.broadcast_access_changed()

  defp key(login), do: String.downcase(login)

  defp repository_name(%Superagent{repository: %{owner: owner, name: name}}),
    do: "#{owner}/#{name}"

  defp repository_name(%Superagent{repository_id: id}), do: "#{id}"
end
