defmodule AgentBoard.Board do
  @moduledoc """
  The board's read and write surface: the repositories, the tasks, the pull
  requests and the activity.
  """
  import Ecto.Query, warn: false

  alias AgentBoard.Board.{Comment, Event, PullRequest, Repository, Review, Task}
  alias AgentBoard.Repo
  alias AgentBoard.Sync.Freshness

  @merged_page_size 50
  @task_page_size 50
  @task_states [:running, :question, :ready, :blocked, :queued]

  def merged_page_size, do: @merged_page_size
  def task_page_size, do: @task_page_size
  def task_states, do: @task_states

  @doc "Every tracked repository."
  def list_repositories, do: Repo.all(from r in Repository, order_by: r.id)

  @doc "Subscribe to a repository's live updates."
  def unsubscribe(repository_id) do
    Phoenix.PubSub.unsubscribe(AgentBoard.PubSub, "board:#{repository_id}")
  end

  def subscribe(repository_id) do
    Phoenix.PubSub.subscribe(AgentBoard.PubSub, "board:#{repository_id}")
  end

  @doc "Tell the subscribers of a repository that the board changed."
  def broadcast(repository_id) do
    Phoenix.PubSub.broadcast(AgentBoard.PubSub, "board:#{repository_id}", :board_updated)
  end

  @doc "Track a repository. It is a no-op if it already exists."
  def add_repository(owner, name) do
    %Repository{}
    |> Repository.changeset(%{owner: owner, name: name})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:owner, :name])
  end

  @doc "Delete a repository and everything scoped to it."
  def delete_repository(id), do: Repo.delete_all(from r in Repository, where: r.id == ^id)

  @doc "The board for a repository (the slug) or the first one."
  def board(slug, merged_limit \\ @merged_page_size, task_limits \\ %{})

  def board(nil, merged_limit, task_limits),
    do: {:ok, board_for(first_repository(), merged_limit, task_limits)}

  def board(slug, merged_limit, task_limits) do
    case repository_by_slug(slug) do
      nil -> :error
      repository -> {:ok, board_for(repository, merged_limit, task_limits)}
    end
  end

  @doc """
  Task ids whose linked pull request is already merged or closed.

  A ready task can be stale after a human merges its PR: the issue/ticket
  report still says "ready for review". Merged work is done, so it does not
  belong in "Precisa de você" or in the "you" rail count. A task without a
  linked PR is not resolved by guessing.
  """
  @spec resolved_task_ids([Task.t()]) :: MapSet.t()
  def resolved_task_ids([]), do: MapSet.new()

  def resolved_task_ids(tasks) do
    ids = Enum.map(tasks, & &1.id)

    comments_by_task =
      Repo.all(from c in Comment, where: c.task_id in ^ids)
      |> Enum.group_by(& &1.task_id)

    tasks
    |> Enum.filter(fn task ->
      case task_pull_request(task, Map.get(comments_by_task, task.id, [])) do
        %PullRequest{state: state} when state in ["merged", "closed"] -> true
        _ -> false
      end
    end)
    |> MapSet.new(& &1.id)
  end

  @doc """
  Marks tasks whose linked PR is already merged or closed as done.

  The read-time filter keeps them out of the lanes immediately, but the stored
  state should also stop lying: a task whose PR was merged is done, not
  waiting. Stopped and archived tasks keep their explicit state.
  """
  @spec reconcile_resolved_tasks(Repository.t()) :: non_neg_integer()
  def reconcile_resolved_tasks(repository) do
    tasks =
      Repo.all(
        from t in Task,
          where:
            t.repository_id == ^repository.id and
              t.state not in ["done", "stopped", "archived"]
      )

    ids = resolved_task_ids(tasks) |> MapSet.to_list()

    if ids == [] do
      0
    else
      now = DateTime.utc_now()

      {count, _} =
        Repo.update_all(
          from(t in Task, where: t.id in ^ids),
          set: [state: "done", state_changed_at: now, updated_at: now]
        )

      broadcast(repository.id)
      count
    end
  end

  @doc "A stable page of tasks in one active lane, newest updates first."
  def task_page(repository_id, state, cursor, limit \\ @task_page_size)
      when state in @task_states do
    state_name = Atom.to_string(state)

    base =
      from t in Task,
        where: t.repository_id == ^repository_id and t.state == ^state_name,
        order_by: [desc: t.updated_at, desc: t.id],
        limit: ^limit

    query =
      case cursor do
        nil ->
          base

        {%DateTime{} = updated_at, id} ->
          from t in base,
            where: t.updated_at < ^updated_at or (t.updated_at == ^updated_at and t.id < ^id)
      end

    Repo.all(query)
  end

  @doc "A stable page of merged pull requests, ordered newest first."
  def merged_page(repository_id, cursor, limit \\ @merged_page_size) do
    base =
      from p in PullRequest,
        where: p.repository_id == ^repository_id and p.state == "merged",
        order_by: [desc_nulls_last: p.merged_at, desc: p.id],
        limit: ^limit

    query =
      case cursor do
        nil ->
          base

        {nil, id} ->
          from p in base, where: is_nil(p.merged_at) and p.id < ^id

        {%DateTime{} = merged_at, id} ->
          from p in base,
            where:
              is_nil(p.merged_at) or p.merged_at < ^merged_at or
                (p.merged_at == ^merged_at and p.id < ^id)
      end

    Repo.all(query)
  end

  defp first_repository,
    do: Repo.one(from r in Repository, where: r.active, order_by: r.id, limit: 1)

  def repository_by_slug(slug) do
    case String.split(slug, "/", parts: 2) do
      [owner, name] ->
        Repo.one(from r in Repository, where: r.owner == ^owner and r.name == ^name)

      _ ->
        nil
    end
  end

  @doc "A saved issue in one repository, regardless of its board page or state."
  def find_task(%Repository{id: repository_id}, number) when is_integer(number) do
    Repo.get_by(Task, repository_id: repository_id, kind: "issue", number: number)
  end

  @doc "A saved pull request in one repository, regardless of its archive page."
  def find_pull_request(%Repository{id: repository_id}, number) when is_integer(number) do
    Repo.get_by(PullRequest, repository_id: repository_id, number: number)
  end

  defp board_for(nil, _merged_limit, _task_limits) do
    %{
      repos: [],
      repo: nil,
      running: [],
      ready: [],
      blocked: [],
      merged: [],
      merged_has_more: false,
      queued: [],
      task_counts: Map.new(@task_states, &{&1, 0}),
      task_has_more: Map.new(@task_states, &{&1, false})
    }
  end

  defp board_for(repository, merged_limit, task_limits) do
    merged_rows = merged_page(repository.id, nil, merged_limit + 1)
    task_pages = load_task_pages(repository.id, task_limits)
    resolved = resolved_task_ids(task_pages.ready.items)
    ready_items = Enum.reject(task_pages.ready.items, &MapSet.member?(resolved, &1.id))
    resolved_ready = length(task_pages.ready.items) - length(ready_items)
    task_pages = put_in(task_pages, [:ready, :items], ready_items)
    state_names = Enum.map(@task_states, &Atom.to_string/1)

    counts_by_name =
      Repo.all(
        from t in Task,
          where: t.repository_id == ^repository.id and t.state in ^state_names,
          group_by: t.state,
          select: {t.state, count(t.id)}
      )
      |> Map.new()

    %{
      repos: list_repositories(),
      repo: "#{repository.owner}/#{repository.name}",
      merged: Enum.take(merged_rows, merged_limit),
      merged_has_more: length(merged_rows) > merged_limit,
      task_counts:
        Map.new(@task_states, fn state ->
          count = Map.get(counts_by_name, Atom.to_string(state), 0)
          {state, if(state == :ready, do: max(count - resolved_ready, 0), else: count)}
        end),
      task_has_more: Map.new(@task_states, &{&1, task_pages[&1].has_more})
    }
    |> Map.merge(Map.new(@task_states, &{&1, task_pages[&1].items}))
  end

  defp load_task_pages(repository_id, limits) do
    Map.new(@task_states, fn state ->
      limit = Map.get(limits, state, @task_page_size)
      rows = task_page(repository_id, state, nil, limit + 1)
      {state, %{items: Enum.take(rows, limit), has_more: length(rows) > limit}}
    end)
  end

  @doc "Create a task by opening an issue that mentions the agent."
  def create_task(repository, title, body, client) do
    with issue <-
           AgentBoard.GitHub.create_issue(client, repository.owner, repository.name, title, body) do
      %Task{}
      |> Task.changeset(%{
        repository_id: repository.id,
        kind: "issue",
        number: issue["number"],
        title: title,
        body: body,
        state: "queued",
        state_changed_at: DateTime.utc_now(),
        url: issue["html_url"],
        author: "board"
      })
      |> Repo.insert(on_conflict: :nothing)
      |> tap(fn _ -> broadcast(repository.id) end)
    end
  rescue
    exception ->
      log_event(repository.id, "create_error", title, %{
        "reason" => Exception.message(exception)
      })

      {:error, exception}
  end

  @doc "Stop a task: flag it and close the issue so the agent stops picking it up."
  def stop_task(task, client) do
    # Same normalisation as ask/3: a bare Repo.get must work.
    task = Repo.preload(task, :repository)

    case AgentBoard.GitHub.close_issue(
           client,
           task.repository.owner,
           task.repository.name,
           task.number
         ) do
      _ ->
        update_state(task, %{stopped: true, state: "stopped"})
    end
  rescue
    exception ->
      log_event(task.repository_id, "stop_error", "##{task.number}", %{
        "reason" => Exception.message(exception)
      })

      {:error, exception}
  end

  @doc "Archive a task: remove it from the flow, keep the history."
  def archive_task(task), do: update_state(task, %{archived: true, state: "archived"})

  @doc "Resume a stopped or archived task."
  def resume_task(task),
    do: update_state(task, %{stopped: false, archived: false, state: "queued"})

  defp update_state(task, attrs) do
    attrs = Map.put_new(attrs, :state_changed_at, DateTime.utc_now())
    result = task |> Task.changeset(attrs) |> Repo.update()
    broadcast(task.repository_id)
    result
  end

  @doc "The conversation of a task: its comments, oldest first."
  def comments(task) do
    Repo.all(from c in Comment, where: c.task_id == ^task.id, order_by: [asc: c.inserted_at])
  end

  @doc "Ask the agent: post a comment on the task's issue that mentions the agent."
  def ask(task, body, client) do
    # The caller may hand us a bare task (a Repo.get); preload is idempotent.
    task = Repo.preload(task, :repository)
    text = String.trim(body) <> "\n\n@sallaumen-agent"

    placeholder =
      %Comment{}
      |> Comment.changeset(%{
        task_id: task.id,
        github_id: -System.unique_integer([:positive]),
        author: "you",
        body: text,
        kind: "user"
      })
      |> Repo.insert!()
      |> tap(fn _ -> broadcast(task.repository_id) end)

    case AgentBoard.GitHub.create_comment(
           client,
           task.repository.owner,
           task.repository.name,
           task.number,
           text
         ) do
      %{"id" => github_id} = comment when is_integer(github_id) ->
        placeholder
        |> Comment.changeset(%{
          github_id: github_id,
          author: get_in(comment, ["user", "login"]) || "you"
        })
        |> Repo.update()
        |> tap(fn _ -> broadcast(task.repository_id) end)

      _ ->
        Repo.delete(placeholder)
        broadcast(task.repository_id)
        {:error, :github}
    end
  rescue
    exception ->
      # The placeholder must never outlive a failed request.
      Repo.delete_all(from c in Comment, where: c.task_id == ^task.id and c.github_id < 0)
      broadcast(task.repository_id)
      {:error, exception}
  end

  @doc "Upsert a comment pulled from GitHub."
  def upsert_comment(task, comment, agent_login) do
    author = get_in(comment, ["user", "login"]) || "unknown"
    kind = if author == agent_login, do: "agent", else: "user"

    # A comment without an id (some API paths omit it) must still dedupe:
    # derive a stable negative id from the task and the body.
    github_id = comment["id"] || -:erlang.phash2({task.id, comment["body"]})

    %Comment{}
    |> Comment.changeset(%{
      task_id: task.id,
      github_id: github_id,
      author: author,
      body: comment["body"] || "",
      kind: kind
    })
    |> Repo.insert(
      on_conflict: {:replace, [:body, :author, :updated_at]},
      conflict_target: [:task_id, :github_id]
    )
  end

  @doc """
  The pull request a task names, from its body or the newest comment with a
  GitHub PR URL. The board never guesses by title.
  """
  def task_pull_request(%Task{} = task, comments) do
    repository = Repo.get(Repository, task.repository_id)

    number =
      Enum.find_value(Enum.reverse(comments), &pull_number(&1.body)) || pull_number(task.body)

    if repository && number, do: find_pull_request(repository, number)
  end

  defp pull_number(nil), do: nil

  defp pull_number(text) do
    case Regex.run(~r{https://github\.com/[^/\s]+/[^/\s]+/pull/(\d+)}, text) do
      [_, number] -> String.to_integer(number)
      _ -> nil
    end
  end

  @doc """
  The observable timeline of a task: arrival, start, current state, linked PR,
  CI and the repository events that name this task. Internal executor steps
  are not stored here, so they are not invented.
  """
  def task_activity(%Task{} = task, pull_request \\ nil) do
    repository = Repo.get(Repository, task.repository_id)

    events =
      [
        task.inserted_at && %{at: task.inserted_at, text: "Entrou na fila", tone: :queue},
        task.started_at && %{at: task.started_at, text: "O agente começou", tone: :agent},
        task.state_changed_at &&
          %{
            at: task.state_changed_at,
            text: "Estado atual: #{state_label(task.state)}",
            tone: state_tone(task.state)
          },
        pull_request && pull_request.opened_at &&
          %{
            at: pull_request.opened_at,
            text: "PR ##{pull_request.number} aberto",
            tone: :agent,
            url: pull_request.url
          },
        pull_request && pull_request.merged_at &&
          %{
            at: pull_request.merged_at,
            text: "PR ##{pull_request.number} mesclado",
            tone: :done,
            url: pull_request.url
          },
        pull_request && checks_activity(pull_request)
      ]
      |> Enum.reject(&is_nil/1)
      |> Kernel.++(task_repo_events(repository, task.number))
      |> Enum.sort_by(& &1.at, DateTime)

    events
  end

  defp task_repo_events(nil, _number), do: []

  defp task_repo_events(repository, number) do
    repository
    |> events(50)
    |> Enum.filter(
      &(&1.subject == "##{number}" or String.contains?(&1.subject || "", "##{number}"))
    )
    |> Enum.map(fn event ->
      %{
        at: event.inserted_at,
        text: event_text(event),
        tone: if(event_error?(event), do: :halt, else: :plain)
      }
    end)
    |> Enum.take(10)
  end

  defp event_text(event) do
    case event.payload do
      %{"reason" => reason} -> "#{event.kind}: #{truncate_reason(reason)}"
      _ -> event.kind
    end
  end

  defp event_error?(event) do
    payload = event.payload || %{}

    String.ends_with?(event.kind || "", "_error") or
      (is_integer(payload["errors"]) and payload["errors"] > 0)
  end

  defp truncate_reason(reason) when is_binary(reason), do: String.slice(reason, 0, 120)
  defp truncate_reason(reason), do: inspect(reason)

  defp checks_activity(%PullRequest{checks_changed_at: nil}), do: nil

  defp checks_activity(%PullRequest{checks_state: "failure"} = pull) do
    %{
      at: pull.checks_changed_at,
      text:
        "CI falhou" <>
          if(pull.checks_failed in [nil, ""], do: "", else: " · #{pull.checks_failed}"),
      tone: :halt
    }
  end

  defp checks_activity(%PullRequest{checks_state: "success"} = pull) do
    %{at: pull.checks_changed_at, text: "CI passou", tone: :agent}
  end

  defp checks_activity(_pull), do: nil

  defp state_label("running"), do: "rodando"
  defp state_label("question"), do: "pergunta"
  defp state_label("ready"), do: "para revisar"
  defp state_label("blocked"), do: "bloqueado"
  defp state_label("queued"), do: "na fila"
  defp state_label("done"), do: "mesclado"
  defp state_label("stopped"), do: "parado"
  defp state_label("archived"), do: "arquivado"
  defp state_label(state), do: state || "desconhecido"

  defp state_tone("blocked"), do: :halt
  defp state_tone("question"), do: :you
  defp state_tone("ready"), do: :you
  defp state_tone("running"), do: :agent
  defp state_tone("done"), do: :done
  defp state_tone(_state), do: :plain

  @doc "The recent activity for a repository."
  def events(repository, limit \\ 20)

  def events(nil, _limit), do: []

  def events(repository, limit) do
    Repo.all(
      from e in Event,
        where: e.repository_id == ^repository.id,
        order_by: [desc: e.inserted_at, desc: e.id],
        limit: ^limit
    )
  end

  @doc "The latest sync outcome, independent of the activity window."
  def latest_sync(repository) do
    Repo.one(
      from e in Event,
        where: e.repository_id == ^repository.id and e.kind in ["sync", "sync_error"],
        order_by: [desc: e.inserted_at, desc: e.id],
        limit: 1
    )
  end

  @doc "The newest attempt and the newest success, for the freshness snapshot."
  def sync_snapshot(repository) do
    events =
      Repo.all(
        from e in Event,
          where: e.repository_id == ^repository.id and e.kind in ["sync", "sync_error"],
          order_by: [desc: e.inserted_at, desc: e.id],
          limit: 50
      )

    %{
      last_attempt: List.first(events),
      last_success: Enum.find(events, &(&1.kind == "sync"))
    }
  end

  @doc """
  One row per repository for the rail: the counts that need a decision and
  whether the saved data is old enough to be untrusted.
  """
  def repo_overview do
    states = Enum.map(@task_states, &Atom.to_string/1)

    counts =
      Repo.all(
        from t in Task,
          where: t.state in ^states,
          group_by: [t.repository_id, t.state],
          select: {t.repository_id, t.state, count(t.id)}
      )
      |> Enum.reduce(%{}, fn {repository_id, state, count}, acc ->
        Map.update(acc, repository_id, %{state => count}, &Map.put(&1, state, count))
      end)

    syncs =
      Repo.all(
        from e in Event,
          where: e.kind in ["sync", "sync_error"],
          order_by: [desc: e.inserted_at, desc: e.id],
          limit: 200
      )
      |> Enum.uniq_by(& &1.repository_id)
      |> Map.new(&{&1.repository_id, &1})

    ready_by_repository =
      Repo.all(from t in Task, where: t.state == "ready")
      |> then(fn ready ->
        resolved = resolved_task_ids(ready)

        ready
        |> Enum.reject(&MapSet.member?(resolved, &1.id))
        |> Enum.frequencies_by(& &1.repository_id)
      end)

    now = DateTime.utc_now()

    list_repositories()
    |> Map.new(fn repository ->
      by_state = Map.get(counts, repository.id, %{})
      sync = syncs[repository.id]

      unknown =
        is_nil(sync) or sync.kind == "sync_error" or
          DateTime.diff(now, sync.inserted_at, :second) > Freshness.stale_ttl()

      {repository.id,
       %{
         id: repository.id,
         name: "#{repository.owner}/#{repository.name}",
         owner: repository.owner,
         running: Map.get(by_state, "running", 0),
         you: Map.get(ready_by_repository, repository.id, 0) + Map.get(by_state, "question", 0),
         halt: Map.get(by_state, "blocked", 0),
         unknown: unknown,
         last_sync: sync
       }}
    end)
  end

  @doc """
  How many observed changes happened after a point in time. Used by the
  reconnect notice even when the LiveView process did not survive the drop.
  """
  def changes_since(repository, %DateTime{} = since) do
    task_changes =
      Repo.aggregate(
        from(t in Task,
          where:
            t.repository_id == ^repository.id and
              (t.inserted_at > ^since or t.state_changed_at > ^since)
        ),
        :count
      )

    merged =
      Repo.aggregate(
        from(p in PullRequest,
          where: p.repository_id == ^repository.id and p.merged_at > ^since
        ),
        :count
      )

    comments =
      Repo.aggregate(
        from(c in Comment,
          join: t in Task,
          on: c.task_id == t.id,
          where: t.repository_id == ^repository.id and c.inserted_at > ^since
        ),
        :count
      )

    task_changes + merged + comments
  end

  @doc "How many visible things changed between two loaded boards."
  def change_count(nil, _new), do: 0

  def change_count(old, new) do
    old_tasks = board_tasks(old)
    new_tasks = board_tasks(new)

    changed_tasks = Enum.count(new_tasks, fn {id, state} -> Map.get(old_tasks, id) != state end)

    old_merged = MapSet.new(Map.get(old, :merged, []), & &1.id)

    changed_merged =
      Enum.count(Map.get(new, :merged, []), &(not MapSet.member?(old_merged, &1.id)))

    changed_tasks + changed_merged
  end

  defp board_tasks(board) do
    for state <- @task_states,
        task <- Map.get(board, state, []),
        into: %{},
        do: {task.id, Atom.to_string(state)}
  end

  @doc "Record an activity row."
  def log_event(repository_id, kind, subject, payload \\ %{}) do
    %Event{}
    |> Event.changeset(%{
      repository_id: repository_id,
      kind: kind,
      subject: subject,
      payload: payload
    })
    |> Repo.insert()
  end

  # The schemas are exposed so the sync and the tests can build changesets.
  def review_changeset(review, attrs), do: Review.changeset(review, attrs)
  def pull_request_changeset(pr, attrs), do: PullRequest.changeset(pr, attrs)
end
