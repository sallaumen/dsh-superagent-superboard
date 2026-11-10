defmodule AgentBoard.Release do
  @moduledoc """
  Calls the agent on a task once what it depends on is finished.

  A mention is what starts the agent, and it has no queue, so a task with
  dependencies opens without one and waits here. The owner approves the whole
  tree when sending the split; this is the standing authorization of
  `release_task` (ADR 0005).

  A task is claimed once (`released_at`) before its comment. A comment that
  failed may have landed, so nothing repeats it: the task stays held and the
  owner decides. `config :agent_board, auto_release: false` switches it off.

  A comment that landed is not a start either: the runner may be down, or
  route the call to another ticket. `called_at/1` is when the board called,
  for the lanes to say how long nobody answered, and the owner may call again
  a task that is still in the queue.
  """
  use GenServer

  import Ecto.Query, warn: false
  require Logger

  alias AgentBoard.{Actions, Board, GitHub, Repo}
  alias AgentBoard.Board.{Repository, Task, TaskDependency}
  alias AgentBoard.Intake.IssueBody

  @finished ~w(done closed)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule()

    try do
      if enabled?() and GitHub.configured?(), do: tick(GitHub.client())
    rescue
      exception -> Logger.warning("release tick failed: #{Exception.message(exception)}")
    end

    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :tick, interval())
  defp interval, do: Application.get_env(:agent_board, :auto_release_interval, 60_000)
  defp enabled?, do: Application.get_env(:agent_board, :auto_release, true)

  @doc "One pass: calls the agent on every held task whose dependencies finished."
  @spec tick(term()) :: [{pos_integer(), term()}]
  def tick(client), do: Enum.flat_map(due(), &release(&1, client))

  @doc """
  The held tasks ready to go. A task with no stored edge is not one of them:
  it was just created and its edges are about to be written.
  """
  @spec due() :: [Task.t()]
  def due do
    Repo.all(
      from t in Task,
        as: :task,
        join: r in Repository,
        on: r.id == t.repository_id,
        where: t.held and is_nil(t.released_at) and t.state == "queued",
        where: not t.stopped and not t.archived and r.active,
        where: exists(edges()) and not exists(open_edges()),
        preload: [repository: r, objective: []]
    )
  end

  defp edges do
    from d in TaskDependency, where: d.task_id == parent_as(:task).id, select: 1
  end

  defp open_edges do
    from d in TaskDependency,
      join: b in Task,
      on: b.id == d.blocked_by_task_id,
      where: d.task_id == parent_as(:task).id and b.state not in @finished,
      select: 1
  end

  defp release(task, client) do
    if claim(task) do
      params = %{task: task, repository: task.repository, client: client}
      [{task.number, Actions.run(:release_task, params, Actions.system("release"))}]
    else
      []
    end
  end

  defp claim(task) do
    {claimed, _rows} =
      Repo.update_all(
        from(t in Task, where: t.id == ^task.id and t.held and is_nil(t.released_at)),
        set: [released_at: DateTime.truncate(DateTime.utc_now(), :second)]
      )

    claimed == 1
  end

  @doc """
  When the board called the DeepSeek runner on a task: the release comment,
  or the issue itself, which opens with the mention. nil for a held task and
  for another executor's, which nobody called.
  """
  @spec called_at(map()) :: DateTime.t() | nil
  def called_at(%{held: true}), do: nil
  def called_at(%{released_at: %DateTime{} = at}), do: at
  def called_at(%{executor: "dsh", inserted_at: at}), do: at
  def called_at(_task), do: nil

  @doc """
  The effect of `release_task`: the comment that calls the agent, on a held
  task or again on a called one that is still in the queue.
  """
  @spec call_agent(Task.t(), Repository.t(), term()) :: :ok | {:error, term()}
  def call_agent(%Task{} = task, repository, client) do
    if task.held or (task.state == "queued" and called_at(task)),
      do: comment(task, repository, client),
      else: {:error, :not_waiting}
  end

  defp comment(task, repository, client) do
    body = task |> Repo.preload(:objective) |> language() |> IssueBody.release_comment(task)
    GitHub.create_comment(client, repository.owner, repository.name, task.number, body)

    Repo.update_all(from(t in Task, where: t.id == ^task.id),
      set: [held: false, released_at: DateTime.truncate(DateTime.utc_now(), :second)]
    )

    Board.log_event(repository.id, "task_released", "##{task.number}")
    Board.broadcast(repository.id)
    :ok
  rescue
    exception ->
      Board.log_event(repository.id, "release_error", "##{task.number}", %{
        "reason" => Exception.message(exception)
      })

      {:error, exception}
  end

  defp language(%Task{objective: %{spec: %{"language" => language}}}), do: language
  defp language(_task), do: nil
end
