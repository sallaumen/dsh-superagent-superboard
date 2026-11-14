defmodule AgentBoard.Board.Requests do
  @moduledoc """
  Opens a board request exactly once.

  The claim is a `draft` task with the request key, inserted before the
  GitHub call; the same words submitted twice (a double click, a reload, a
  retry after a partial split) find that row and answer the receipt instead
  of opening a second issue. The GitHub failure removes the claim, and a task
  that ended gives its key back: the same words later open a new issue.

  This is the Board context's command side for a new task: it writes the
  task row, records the router line and broadcasts. It is a module of the
  context, not a separate context: the task table and its invariants stay
  with `AgentBoard.Board`.
  """

  import Ecto.Query, warn: false

  alias AgentBoard.{Board, Executors, Repo, Routing}
  alias AgentBoard.Board.{Repository, RequestOrder, Task}
  alias AgentBoard.Intake.IssueBody

  # The column holds 255; past that Postgres raises instead of refusing, and
  # GitHub stops at 256. A title comes from a person or a model.
  @title_limit 255
  defp clip_title(title) when is_binary(title), do: String.slice(title, 0, @title_limit)
  defp clip_title(title), do: title

  # Longer than any send can take (the composer stops one at two minutes), so
  # a claim this old lost its process before it could finish or clean up.
  @abandoned_after_seconds 300

  @doc """
  Creates the task for a board request once.

  A task that already carries this `key`, or an unclaimed queued issue with the same
  title and body (one the sync stored from an issue the board opened before
  it could record the key), is the receipt of an earlier submit: it answers
  `{:ok, task, :existing}` and no second issue is opened. Otherwise the issue
  is created and the task answers `{:ok, task, :created}`.

  A request for a named executor must carry `:routing` (built by
  `AgentBoard.Routing.plan/5` at the door or by `Actions`); without one it
  answers `{:error, :not_routed}` and opens nothing. A request the router
  refused (`:refused`, a sentence) answers `{:error, sentence}` and opens
  nothing. A request without an executor is opened as given, with no label
  and no router line.
  """
  @spec create_request(Repository.t(), map(), term()) ::
          {:ok, Task.t(), :created | :existing} | {:error, term()}
  def create_request(_repository, %{refused: reason}, _client), do: {:error, reason}

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

  @doc """
  Creates requests that may depend on each other, in the order they were given
  back to the caller.

  `depends_on` names other requests by key. A request is opened after the ones
  it depends on and its body names their numbers. If one of them failed the
  request answers `{:error, :dependency_failed}` and opens nothing: an issue
  created now could never name its blocker, and a retry opens it with the link.
  A cycle from the model is broken in list order, naming only what already has
  a number.
  """
  @spec create_requests(Repository.t(), [map()], term(), map()) ::
          [{map(), {:ok, Task.t(), :created | :existing} | {:error, term()}}]
  def create_requests(repository, requests, client, confirmed_numbers \\ %{}) do
    {created, _numbers} =
      requests
      |> RequestOrder.for_creation()
      |> Enum.map_reduce(confirmed_numbers, fn {request, position}, numbers ->
        result = create_after_blockers(repository, request, numbers, client)
        {{position, {request, result}}, remember(numbers, request.key, result)}
      end)

    created |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))
  end

  defp create_after_blockers(repository, request, numbers, client) do
    blockers = request |> depends_on() |> Enum.flat_map(&List.wrap(numbers[&1]))

    if :failed in blockers do
      {:error, :dependency_failed}
    else
      language = Map.get(request, :language)
      body = IssueBody.with_dependencies(request.body, blockers, language)

      repository
      |> create_request(%{request | body: body} |> hold(blockers), client)
    end
  end

  # The mention starts the runner at once, so what waits opens without it. Only
  # the runner: another executor's issue never calls anybody.
  defp hold(request, []), do: request

  defp hold(request, _blockers) do
    if Map.get(request, :executor) in [nil, "dsh"],
      do: Map.put(request, :held, true),
      else: request
  end

  defp remember(numbers, key, {:ok, %Task{number: number}, _outcome}),
    do: Map.put(numbers, key, number)

  defp remember(numbers, key, _failure), do: Map.put(numbers, key, :failed)

  defp depends_on(request), do: Map.get(request, :depends_on, [])

  defp do_create_request(repository, %{title: title, body: body, key: key} = request, client) do
    title = clip_title(title)
    # The body the issue will carry, so a repeat matches the stored task.
    body =
      case Map.get(request, :executor) do
        nil -> body
        executor -> Executors.issue_body(body, executor)
      end

    body = if Map.get(request, :held), do: Executors.held_body(body), else: body
    request = %{request | title: title, body: body}
    release_ended_key(repository, key)

    case existing_request(repository, key, title, body) do
      %Task{number: nil} = claim -> retake_or_wait(claim, repository, request, client)
      %Task{} = task -> {:ok, task, :existing}
      nil -> claim_and_create(repository, request, client)
    end
  end

  # The key guards a double submit, not the words forever: asking again after
  # the task ended is new work, and the old row stays without its key.
  defp release_ended_key(repository, key) do
    Repo.update_all(
      from(t in Task,
        where: t.repository_id == ^repository.id and t.request_key == ^key,
        where: t.state in ^Board.ended_states() or t.stopped or t.archived
      ),
      set: [request_key: nil]
    )
  end

  # If the process died after GitHub answered, retaking opens a second issue;
  # refusing would hold this request and everything that depends on it forever.
  defp retake_or_wait(claim, repository, request, client) do
    if DateTime.before?(claim.inserted_at, live_claim_cutoff()) do
      delete_claim(claim)
      claim_and_create(repository, request, client)
    else
      {:error, :in_progress}
    end
  end

  defp live_claim_cutoff do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.add(-@abandoned_after_seconds, :second)
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
      blocker_for_task_id: Map.get(request, :blocker_for_task_id),
      work_type: Map.get(request, :work_type),
      size: Map.get(request, :size),
      held: Map.get(request, :held, false)
    }

    case %Task{} |> Task.changeset(attrs) |> Repo.insert() do
      {:ok, claim} ->
        {:ok, claim}

      {:error, _changeset} ->
        case Repo.one(
               from(t in Task,
                 where: t.repository_id == ^repository.id and t.request_key == ^key
               )
             ) do
          %Task{} = existing -> {:existing, existing}
          nil -> {:error, :conflict}
        end
    end
  end

  defp create_new_request(repository, request, client, claim) do
    case open_claimed_issue(repository, request, client, claim) do
      {:ok, task} ->
        {:ok, task, :created}

      {:error, reason} ->
        delete_claim(claim)
        {:error, reason}
    end
  end

  defp open_claimed_issue(repository, request, client, claim) do
    executor = claim.executor
    labels = if executor, do: [Executors.label(executor)], else: []

    issue =
      AgentBoard.GitHub.create_issue(
        client,
        repository.owner,
        repository.name,
        request.title,
        request.body,
        labels
      )

    claim
    |> finish_claim(issue)
    |> tap(&record_routing(&1, repository, executor, Map.get(request, :routing)))
    |> tap(fn
      {:ok, _task} -> Board.broadcast(repository.id)
      _ -> :ok
    end)
  rescue
    exception ->
      Board.log_event(repository.id, "create_error", request.title, %{
        "reason" => Exception.message(exception)
      })

      {:error, exception}
  end

  defp finish_claim(claim, issue) do
    result =
      claim
      |> Task.changeset(%{
        number: issue["number"],
        url: issue["html_url"],
        state: "queued",
        state_changed_at: DateTime.utc_now(),
        author: "board"
      })
      |> Repo.update(mode: :savepoint)

    case result do
      {:error, changeset} ->
        if issue_number_taken?(changeset),
          do: reconcile_mirror(claim, issue["number"]),
          else: result

      success ->
        success
    end
  end

  defp issue_number_taken?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_msg, opts}} ->
      opts[:constraint_name] == "tasks_repository_id_kind_number_index"
    end)
  end

  # Sync owns the row it already observed, including its state and comments.
  # Transfer the reservation and board-only fields together; never reopen the issue.
  defp reconcile_mirror(claim, number) do
    Repo.transact(fn ->
      mirror =
        Repo.one(
          from t in Task,
            where:
              t.repository_id == ^claim.repository_id and t.kind == "issue" and
                t.number == ^number,
            where: is_nil(t.request_key),
            lock: "FOR UPDATE"
        )

      with %Task{} <- mirror, {1, _} <- delete_claim(claim) do
        attrs =
          Map.take(claim, [
            :request_key,
            :origin_task_id,
            :blocker_for_task_id,
            :work_type,
            :size,
            :executor,
            :held
          ])

        mirror |> Task.changeset(attrs) |> Repo.update()
      else
        _ -> {:error, :conflict}
      end
    end)
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

  defp delete_claim(%Task{id: id, state: "draft"}) when is_integer(id) do
    Repo.delete_all(from(t in Task, where: t.id == ^id and t.state == "draft"))
  end

  defp delete_claim(_claim), do: :ok

  defp existing_request(repository, key, title, body) do
    exact = [repository_id: repository.id, request_key: key]

    case Repo.get_by(Task, exact) do
      %Task{} = task -> task
      nil -> adopt_mirrored_issue(repository, key, title, body)
    end
  end

  # The lock makes a text match a one-time recovery. Never adopt a mirror
  # while an earlier reservation could own it: GitHub may have edited the text.
  defp adopt_mirrored_issue(repository, key, title, body) do
    Repo.transact(fn ->
      case Repo.one(unclaimed_mirror(repository, title, body)) do
        nil -> {:ok, nil}
        mirror -> mirror |> Task.changeset(%{request_key: key}) |> Repo.update()
      end
    end)
    |> case do
      {:ok, task} -> task
      {:error, _changeset} -> Repo.get_by(Task, repository_id: repository.id, request_key: key)
    end
  end

  defp unclaimed_mirror(repository, title, body) do
    matching =
      from t in Task,
        where: [repository_id: ^repository.id, kind: "issue", title: ^title],
        where: coalesce(t.body, "") == ^body

    in_flight =
      from t in Task,
        where: [repository_id: ^repository.id, kind: "issue", state: "draft"],
        where: t.inserted_at >= ^live_claim_cutoff(),
        where: t.id < parent_as(:mirror).id and not is_nil(t.request_key) and is_nil(t.number),
        select: 1

    from t in matching,
      as: :mirror,
      where: [state: "queued", archived: false, stopped: false],
      where: is_nil(t.request_key) and not is_nil(t.number),
      where: not exists(in_flight),
      order_by: [asc: t.id],
      limit: 1,
      lock: "FOR UPDATE"
  end
end
