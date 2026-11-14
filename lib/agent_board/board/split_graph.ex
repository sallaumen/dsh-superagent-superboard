defmodule AgentBoard.Board.SplitGraph do
  @moduledoc """
  What a split's tasks are to each other, kept here and shown on GitHub.

  The board's own edges are the record. GitHub's sub-issues and blocked-by are
  a mirror for whoever reads the issues: a mirror that fails is an event, and
  never undoes an issue that already exists.
  """

  alias AgentBoard.{Board, Executors, GitHub, Repo}
  alias AgentBoard.Board.{Objective, Task, TaskDependency}
  alias AgentBoard.Intake.IssueBody

  # The sync reads this label to keep a group's issue out of the queue.
  @objective_label "board:objective"

  @doc "The label of an issue that groups a split's tasks."
  def objective_label, do: @objective_label

  @doc "Whether an issue from GitHub is a group of tasks and not a task."
  @spec objective_issue?(map()) :: boolean()
  def objective_issue?(%{"labels" => labels}) when is_list(labels),
    do: Enum.any?(labels, &(is_map(&1) and &1["name"] == @objective_label))

  def objective_issue?(_issue), do: false

  @doc "Stores the edges among the tasks a split created."
  @spec record([{map(), term()}]) :: :ok
  def record(results) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      for {task, blocker} <- edges(results) do
        %{task_id: task.id, blocked_by_task_id: blocker.id, inserted_at: now, updated_at: now}
      end

    Repo.insert_all(TaskDependency, rows, on_conflict: :nothing)
    :ok
  end

  @doc """
  Opens the issue that groups the split and mirrors the graph, once every task
  exists: a retry that completes the split publishes it. The issue never
  mentions the agent, so it starts no ticket.
  """
  @spec publish(map(), Objective.t(), [{map(), term()}], term()) :: :ok
  def publish(_repository, %Objective{issue_number: number}, _results, _client)
      when is_integer(number),
      do: :ok

  def publish(repository, objective, results, client) do
    if Enum.all?(results, &match?({_request, {:ok, %Task{}, _outcome}}, &1)) do
      open_and_link(repository, objective, results, client)
    else
      :ok
    end
  rescue
    exception -> failed(repository, objective.title, exception)
  end

  defp open_and_link(repository, objective, results, client) do
    tasks = for {_request, {:ok, task, _outcome}} <- results, do: task
    body = objective.spec |> parent_body(objective, tasks) |> Executors.without_mention()

    issue =
      GitHub.create_issue(client, repository.owner, repository.name, objective.title, body, [
        @objective_label
      ])

    objective
    |> Objective.changeset(%{issue_number: issue["number"], issue_url: issue["html_url"]})
    |> Repo.update!()

    ids = Map.new(tasks, &{&1.number, issue_id(repository, &1, client)})

    Enum.each(tasks, fn task ->
      link(repository, objective, fn ->
        GitHub.add_sub_issue(
          client,
          repository.owner,
          repository.name,
          issue["number"],
          ids[task.number]
        )
      end)
    end)

    Enum.each(edges(results), fn {task, blocker} ->
      link(repository, objective, fn ->
        GitHub.add_blocked_by(
          client,
          repository.owner,
          repository.name,
          task.number,
          ids[blocker.number]
        )
      end)
    end)

    Board.broadcast(repository.id)
  end

  defp parent_body(spec, objective, tasks),
    do: IssueBody.parent(objective.request_text || objective.title, spec || %{}, tasks)

  defp issue_id(repository, task, client) do
    client |> GitHub.issue(repository.owner, repository.name, task.number) |> Map.fetch!("id")
  end

  defp link(repository, objective, write) do
    write.()
    :ok
  rescue
    exception -> failed(repository, objective.title, exception)
  end

  defp failed(repository, title, exception) do
    Board.log_event(repository.id, "link_error", title, %{
      "reason" => Exception.message(exception)
    })

    :ok
  end

  @doc """
  Returns `{task, blocker}` pairs from split results, resolving `depends_on` by request key.

  Newly created tasks and existing receipts both count. A missing or failed
  blocker contributes no edge, nor do two keys that resolve to the same task ID.
  """
  @spec edges([{map(), {:ok, Task.t(), :created | :existing} | {:error, term()}}]) ::
          [{Task.t(), Task.t()}]
  def edges(results) do
    tasks =
      for {request, {:ok, %Task{} = task, _outcome}} <- results,
          into: %{},
          do: {request.key, task}

    for {request, {:ok, %Task{} = task, _outcome}} <- results,
        key <- Map.get(request, :depends_on, []),
        blocker = tasks[key],
        blocker && blocker.id != task.id do
      {task, blocker}
    end
  end
end
