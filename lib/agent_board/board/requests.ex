defmodule AgentBoard.Board.Requests do
  @moduledoc """
  Opens a board request exactly once.

  The claim is a `draft` task with the request key, inserted before the
  GitHub call; the same words submitted twice (a double click, a reload, a
  retry after a partial split) find that row and answer the receipt instead
  of opening a second issue. The GitHub failure removes the claim.

  This is the Board context's command side for a new task: it writes the
  task row, records the router line and broadcasts. It is a module of the
  context, not a separate context: the task table and its invariants stay
  with `AgentBoard.Board`.
  """

  import Ecto.Query, warn: false

  alias AgentBoard.{Board, Executors, Repo, Routing}
  alias AgentBoard.Board.{Repository, Task}

  @doc """
  Create a task by opening its issue.

  With `executor:` the board records who the task is for, labels the issue
  `executor:<name>` and writes the body for that executor: the DeepSeek
  runner's issue mentions the bot, anyone else's mentions nobody
  (`AgentBoard.Executors.issue_body/2`). Without it the body is opened as
  given and no executor is recorded.
  """
  def create_task(repository, title, body, client, opts \\ []) do
    executor = Keyword.get(opts, :executor)
    claim = Keyword.get(opts, :claim)
    body = if executor, do: Executors.issue_body(body, executor), else: body
    labels = if executor, do: [Executors.label(executor)], else: []

    with issue <-
           AgentBoard.GitHub.create_issue(
             client,
             repository.owner,
             repository.name,
             title,
             body,
             labels
           ) do
      attrs = %{
        repository_id: repository.id,
        kind: "issue",
        number: issue["number"],
        title: title,
        body: body,
        state: "queued",
        state_changed_at: DateTime.utc_now(),
        url: issue["html_url"],
        author: "board",
        request_key: Keyword.get(opts, :request_key),
        origin_task_id: Keyword.get(opts, :origin_task_id),
        work_type: Keyword.get(opts, :work_type),
        size: Keyword.get(opts, :size),
        executor: executor
      }

      target = claim || %Task{}

      result =
        if claim,
          do: target |> Task.changeset(attrs) |> Repo.update(),
          else: target |> Task.changeset(attrs) |> Repo.insert(on_conflict: :nothing)

      result
      |> tap(&record_routing(&1, repository, executor, Keyword.get(opts, :routing)))
      |> tap(fn
        {:ok, %Task{id: id}} when is_integer(id) -> Board.broadcast(repository.id)
        _ -> :ok
      end)
    end
  rescue
    exception ->
      Board.log_event(repository.id, "create_error", title, %{
        "reason" => Exception.message(exception)
      })

      {:error, exception}
  end

  # The router's line for the task (AgentBoard.Routing.Decision). The issue
  # already exists, so a decision that fails is an event, never a reason to
  # drop the task row: a retry without the row would open a second issue.
  defp record_routing({:ok, %Task{id: id} = task}, repository, executor, routing)
       when is_integer(id) and is_binary(executor) and is_map(routing) do
    case Routing.record(task, executor, routing) do
      {:ok, _decision} ->
        :ok

      {:error, changeset} ->
        Board.log_event(repository.id, "routing_error", "##{task.number}", %{
          "reason" => inspect(changeset.errors)
        })
    end
  end

  defp record_routing(_result, _repository, _executor, _routing), do: :ok

  @doc """
  Creates the task for a board request once.

  A task that already carries this `key`, or a queued task with the same
  title and body (one the sync stored from an issue the board opened before
  it could record the key), is the receipt of an earlier submit: it answers
  `{:ok, task, :existing}` and no second issue is opened. Otherwise the issue
  is created and the task answers `{:ok, task, :created}`.

  A request for a named executor must carry `:routing` (built by
  `AgentBoard.Routing.plan/5` at the door or by `Actions`); without one it
  answers `{:error, :not_routed}` and opens nothing. A request without an
  executor is opened as given, with no label and no router line.
  """
  @spec create_request(Repository.t(), map(), term()) ::
          {:ok, Task.t(), :created | :existing} | {:error, term()}
  def create_request(repository, %{executor: executor} = request, client)
      when is_binary(executor) do
    if is_map(Map.get(request, :routing)) do
      do_create_request(repository, request, client)
    else
      # A task for a named executor always carries its router line. The
      # write door builds it before calling here; a request without one is a
      # bug, not a reason to read the world from inside the context.
      {:error, :not_routed}
    end
  end

  def create_request(repository, request, client),
    do: do_create_request(repository, request, client)

  defp do_create_request(repository, %{title: title, body: body, key: key} = request, client) do
    # The body the issue will carry, so a repeat matches the stored task.
    body =
      case Map.get(request, :executor) do
        nil -> body
        executor -> Executors.issue_body(body, executor)
      end

    request = %{request | body: body}

    case existing_request(repository, key, title, body) do
      %Task{number: nil} -> {:error, :in_progress}
      %Task{} = task -> {:ok, task, :existing}
      nil -> claim_and_create(repository, request, client)
    end
  end

  # The claim is the unique key row, inserted before the GitHub call: two
  # doors that submit the same words both reach the database, and only one
  # gets to open an issue. A failed issue call deletes the claim.
  defp claim_and_create(repository, request, client) do
    case claim_request(repository, request) do
      {:ok, claim} -> create_new_request(repository, request, client, claim)
      {:existing, %Task{number: nil}} -> {:error, :in_progress}
      {:existing, %Task{} = task} -> {:ok, task, :existing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp claim_request(repository, %{title: title, body: body, key: key} = request) do
    attrs = %{
      repository_id: repository.id,
      kind: "issue",
      title: title,
      body: body,
      state: "draft",
      request_key: key,
      executor: Map.get(request, :executor),
      origin_task_id: Map.get(request, :origin_task_id),
      work_type: Map.get(request, :work_type),
      size: Map.get(request, :size)
    }

    case %Task{} |> Task.changeset(attrs) |> Repo.insert() do
      {:ok, claim} ->
        {:ok, claim}

      {:error, _changeset} ->
        case Repo.one(
               from t in Task,
                 where: t.repository_id == ^repository.id and t.request_key == ^key
             ) do
          %Task{} = existing -> {:existing, existing}
          nil -> {:error, :conflict}
        end
    end
  end

  defp create_new_request(
         repository,
         %{title: title, body: body, key: key} = request,
         client,
         claim
       ) do
    created =
      create_task(repository, title, body, client,
        request_key: key,
        origin_task_id: Map.get(request, :origin_task_id),
        work_type: Map.get(request, :work_type),
        size: Map.get(request, :size),
        executor: Map.get(request, :executor),
        routing: Map.get(request, :routing),
        claim: claim
      )

    case created do
      # The unique key (or the issue number) raced with another write: the
      # first one won, and it is the receipt if it carries these words.
      {:ok, %Task{id: nil}} ->
        raced_request(repository, key, title, body)

      {:ok, task} ->
        {:ok, task, :created}

      {:error, reason} ->
        delete_claim(claim)
        {:error, reason}
    end
  end

  defp delete_claim(%Task{id: id, state: "draft"}) when is_integer(id) do
    Repo.delete_all(from t in Task, where: t.id == ^id and t.state == "draft")
  end

  defp delete_claim(_claim), do: :ok

  defp raced_request(repository, key, title, body) do
    case existing_request(repository, key, title, body) do
      %Task{} = task -> {:ok, task, :existing}
      nil -> {:error, :conflict}
    end
  end

  defp existing_request(repository, key, title, body) do
    Repo.one(
      from t in Task,
        where:
          t.repository_id == ^repository.id and
            (t.request_key == ^key or
               (t.state == "queued" and t.title == ^title and t.body == ^body)),
        order_by: [asc: t.id],
        limit: 1
    )
  end
end
