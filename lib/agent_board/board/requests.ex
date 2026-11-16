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

  require Logger
  import Ecto.Query, warn: false

  alias AgentBoard.{Board, Executors, Repo, Routing}
  alias AgentBoard.Board.{Repository, RequestDependencies, RequestOrder, Task}

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
    with {:ok, prepared} <- RequestDependencies.prepare(request, numbers) do
      create_request(repository, prepared, client)
    end
  end

  defp remember(numbers, key, {:ok, %Task{number: number}, _outcome}),
    do: Map.put(numbers, key, number)

  defp remember(numbers, key, _failure), do: Map.put(numbers, key, :failed)

  defp do_create_request(repository, %{title: title, body: body} = request, client) do
    title = clip_title(title)
    # The body the issue will carry, so a repeat matches the stored task.
    body =
      case Map.get(request, :executor) do
        nil -> body
        executor -> Executors.issue_body(body, executor)
      end

    body = if Map.get(request, :held), do: Executors.held_body(body), else: body
    request = %{request | title: title, body: body}

    case request[:receipt_number] do
      nil -> submit(repository, request, client)
      number when is_integer(number) and number > 0 -> recover_number(repository, request, number)
    end
  end

  # Explicit recovery never opens an issue, even if the original task has
  # since ended. An older board may have lost its reservation entirely: only
  # a verified, unclaimed mirror with this exact number AND payload may stand in.
  defp recover_number(repo, request, n) do
    case Repo.get_by(Task, repository_id: repo.id, request_key: request.key) do
      %Task{number: ^n} = task ->
        {:ok, task, :existing}

      %Task{number: nil, issue_receipt: %{"number" => ^n}} = claim ->
        finalize_receipt(repo, request, claim, n)

      %Task{number: nil, issue_receipt: %{"sending" => true}} = claim ->
        # The provider answered but even saving its receipt failed. The
        # mirror must confirm the number and exact content before we use it.
        case Repo.get_by(Task,
               repository_id: repo.id,
               kind: "issue",
               number: n,
               title: request.title,
               body: request.body,
               request_key: nil
             ) do
          %Task{url: url} ->
            acknowledge_issue(repo, request, claim, n, %{"number" => n, "html_url" => url})

          nil ->
            {:error, {:receipt_pending, n}}
        end

      nil ->
        recover_mirror(repo, request, n)

      _ ->
        {:error, {:receipt_pending, n}}
    end
  end

  defp recover_mirror(repo, request, n) do
    result =
      Repo.transact(fn ->
        mirror =
          Repo.one(
            from t in Task,
              where: [
                repository_id: ^repo.id,
                kind: "issue",
                number: ^n,
                title: ^request.title,
                body: ^request.body
              ],
              where: is_nil(t.request_key),
              where: is_nil(t.origin_task_id) and is_nil(t.blocker_for_task_id),
              lock: "FOR UPDATE"
          )

        case mirror do
          %Task{} ->
            attrs =
              request
              |> Map.take([:origin_task_id, :blocker_for_task_id, :executor])
              |> Map.put(:request_key, request.key)

            mirror |> Task.changeset(attrs) |> Repo.update()

          nil ->
            {:error, :not_found}
        end
      end)

    case result do
      {:ok, task} ->
        Board.broadcast(repo.id)
        {:ok, task, :existing}

      _ ->
        {:error, {:receipt_pending, n}}
    end
  end

  defp submit(repository, %{key: key, title: title, body: body} = request, client) do
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
  defp retake_or_wait(
         %Task{issue_receipt: %{"number" => n}} = claim,
         repository,
         request,
         _client
       ) do
    finalize_receipt(repository, request, claim, n)
  end

  # A new sender that died before storing the response may already have opened
  # an issue. Its age alone cannot make a second POST safe.
  defp retake_or_wait(%Task{issue_receipt: %{}} = claim, _repository, _request, _client) do
    if DateTime.before?(claim.inserted_at, live_claim_cutoff()),
      do: {:error, :issue_send_uncertain},
      else: {:error, :in_progress}
  end

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

    case %Task{issue_receipt: %{"sending" => true}} |> Task.changeset(attrs) |> Repo.insert() do
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
    labels = if claim.executor, do: [Executors.label(claim.executor)], else: []

    case post_issue(repository, request, client, labels) do
      {:ok, %{"number" => n} = issue} when is_integer(n) and n > 0 ->
        # Commit the acknowledgement independently. A failure in the local
        # merge must never roll this number back or delete this reservation.
        acknowledge_issue(repository, request, claim, n, issue)

      {:ok, _unknown_response} ->
        {:error, :in_progress}

      {:error, %Req.TransportError{reason: cause}}
      when cause not in [:nxdomain, :econnrefused, :enetunreach, :ehostunreach] ->
        {:error, :issue_send_uncertain}

      {:error, reason} ->
        delete_claim(claim)
        {:error, reason}
    end
  end

  defp acknowledge_issue(repository, request, claim, number, issue) do
    receipt = Map.take(issue, ["number", "html_url"])
    claim = claim |> Ecto.Changeset.change(issue_receipt: receipt) |> Repo.update!()
    finalize_receipt(repository, request, claim, number)
  rescue
    e in [DBConnection.ConnectionError, Postgrex.Error, Ecto.StaleEntryError] ->
      Logger.warning(
        "Issue ##{number} was created; saving its receipt failed: #{inspect(e.__struct__)}"
      )

      {:error, {:receipt_pending, number}}
  end

  defp post_issue(repository, request, client, labels) do
    {:ok,
     AgentBoard.GitHub.create_issue(
       client,
       repository.owner,
       repository.name,
       request.title,
       request.body,
       labels
     )}
  rescue
    exception ->
      Board.log_event(repository.id, "create_error", request.title, %{
        "reason" => Exception.message(exception)
      })

      {:error, exception}
  end

  defp finalize_receipt(repository, request, claim, number) do
    # Concurrent confirms serialize on the reservation. If a sync beat us to
    # the issue, finish_claim transfers the key and links to that exact row.
    result =
      Repo.transact(fn ->
        finish_locked(repository, request, claim, number)
      end)

    case result do
      {:ok, {task, outcome}} ->
        if outcome == :created, do: Board.broadcast(repository.id)
        {:ok, task, outcome}

      {:error, _reason} ->
        {:error, {:receipt_pending, number}}
    end
  end

  defp finish_locked(repository, request, claim, number) do
    case Repo.one(from t in Task, where: t.id == ^claim.id, lock: "FOR UPDATE") do
      %Task{number: nil, issue_receipt: %{"number" => ^number} = issue} = locked ->
        with {:ok, task} <- finish_claim(locked, issue) do
          record_routing({:ok, task}, repository, claim.executor, Map.get(request, :routing))
          {:ok, {task, :created}}
        end

      _already_finished ->
        case Repo.get_by(Task,
               repository_id: repository.id,
               request_key: claim.request_key,
               number: number
             ) do
          nil -> {:error, :conflict}
          task -> {:ok, {task, :existing}}
        end
    end
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
        where:
          t.inserted_at >= ^live_claim_cutoff() or
            fragment("?->>'number' = ?::text", t.issue_receipt, parent_as(:mirror).number),
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
