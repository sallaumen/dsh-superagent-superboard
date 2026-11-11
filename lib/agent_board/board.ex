defmodule AgentBoard.Board do
  @moduledoc """
  The board's read and write surface: the repositories, the tasks, the pull
  requests and the activity. Opening a request exactly once is the command in
  `AgentBoard.Board.Requests`, which calls back here to persist, record and
  broadcast.
  """
  import Ecto.Query, warn: false
  # The inspector's activity lines are interface copy.
  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Board.{
    Activity,
    Comment,
    Inbox,
    Objective,
    PullRequest,
    Repository,
    Task,
    TaskDependency
  }

  alias AgentBoard.{GitHub, Repo, Workpad}

  @merged_page_size 50
  @task_page_size 50
  @task_states [:running, :retrying, :question, :ready, :blocked, :queued]
  @today_topic "board_today"
  # The runner's hidden `<!-- dsh-superagent:... -->` line is not part of the message.
  @runner_marker ~r/<!--.*?-->/s

  def merged_page_size, do: @merged_page_size
  def task_page_size, do: @task_page_size
  def task_states, do: @task_states

  @doc "Recent agent replies and cross-project attention for the header."
  def inbox, do: Inbox.snapshot()

  @doc "The recent activity for a repository (owned by `AgentBoard.Board.Activity`)."
  def events(repository, limit \\ 20), do: Activity.events(repository, limit)

  @doc "The latest sync outcome (owned by `AgentBoard.Board.Activity`)."
  def latest_sync(repository), do: Activity.latest_sync(repository)

  @doc "The newest attempt and success (owned by `AgentBoard.Board.Activity`)."
  def sync_snapshot(repository), do: Activity.sync_snapshot(repository)

  @doc "Record an activity row (owned by `AgentBoard.Board.Activity`)."
  def log_event(repository_id, kind, subject, payload \\ %{}),
    do: Activity.log_event(repository_id, kind, subject, payload)

  @doc "Every tracked repository."
  def list_repositories, do: Repo.all(from r in Repository, order_by: r.id)

  @doc "Subscribe to a repository's live updates."
  def unsubscribe(repository_id) do
    Phoenix.PubSub.unsubscribe(AgentBoard.PubSub, "board:#{repository_id}")
  end

  def subscribe(repository_id) do
    Phoenix.PubSub.subscribe(AgentBoard.PubSub, "board:#{repository_id}")
  end

  @doc "Subscribe to the cross-repository today view."
  def subscribe_today do
    Phoenix.PubSub.subscribe(AgentBoard.PubSub, @today_topic)
  end

  @doc "Tell the subscribers of a repository that the board changed."
  def broadcast(repository_id) do
    Phoenix.PubSub.broadcast(AgentBoard.PubSub, "board:#{repository_id}", :board_updated)
    Phoenix.PubSub.broadcast(AgentBoard.PubSub, @today_topic, {:today_updated, repository_id})
  end

  @doc "Tracks a repository; every open board refreshes its list."
  def add_repository(owner, name) do
    result =
      %Repository{}
      |> Repository.changeset(%{owner: owner, name: name})
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:owner, :name])

    if match?({:ok, _}, result), do: broadcast_repos()
    result
  end

  @doc "Tells every open board that the repository list changed."
  def broadcast_repos do
    Phoenix.PubSub.broadcast(AgentBoard.PubSub, @today_topic, :repos_changed)
  end

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
    {comments_by_task, repositories} = link_sources(tasks)

    # One read for every linked PR, not one per task: the overview filters
    # all ready tasks at once and the query count stays bounded.
    pulls = linked_pulls(tasks, comments_by_task, repositories)

    tasks
    |> Enum.filter(fn task ->
      number = linked_number(task, Map.get(comments_by_task, task.id, []), repositories)

      case Map.get(pulls, {task.repository_id, number}) do
        %PullRequest{state: state} when state in ["merged", "closed"] -> true
        _ -> false
      end
    end)
    |> MapSet.new(& &1.id)
  end

  # What a task's PR link is read from, in two reads for the whole list:
  # its comments (oldest first, so the last one with a link is the newest)
  # and its repository.
  defp link_sources(tasks) do
    ids = Enum.map(tasks, & &1.id)

    comments_by_task =
      Repo.all(
        from c in Comment, where: c.task_id in ^ids, order_by: [asc: c.inserted_at, asc: c.id]
      )
      |> Enum.group_by(& &1.task_id)

    repositories =
      Repo.all(
        from r in Repository, where: r.id in ^Enum.uniq(Enum.map(tasks, & &1.repository_id))
      )
      |> Map.new(&{&1.id, &1})

    {comments_by_task, repositories}
  end

  defp linked_pulls(tasks, comments_by_task, repositories) do
    candidates =
      tasks
      |> Enum.map(fn task ->
        {task.repository_id,
         linked_number(task, Map.get(comments_by_task, task.id, []), repositories)}
      end)
      |> Enum.filter(fn {_repository_id, number} -> is_integer(number) end)
      |> Enum.uniq()

    if candidates == [] do
      %{}
    else
      repository_ids = Enum.map(candidates, &elem(&1, 0)) |> Enum.uniq()
      numbers = Enum.map(candidates, &elem(&1, 1)) |> Enum.uniq()

      Repo.all(
        from p in PullRequest,
          where: p.repository_id in ^repository_ids and p.number in ^numbers
      )
      |> Map.new(&{{&1.repository_id, &1.number}, &1})
    end
  end

  defp linked_number(task, comments, repositories) do
    repository = Map.get(repositories, task.repository_id)

    Enum.find_value(Enum.reverse(comments), &pull_number(&1.body, repository)) ||
      pull_number(task.body, repository)
  end

  @doc """
  Marks ready tasks whose linked PR is already merged or closed as done.

  The read-time filter keeps them out of the lanes immediately, but the stored
  state should also stop lying: a task whose PR was merged is done, not
  waiting. Only `ready` is reconciled, the population that filter covers: any
  link counts as the linked PR, so in another state it can be a merged PR an
  issue merely cites or the PR a rework replaces, and the ticket overlay owns
  running, blocked and question. Stopped and archived tasks keep their
  explicit state.
  """
  @spec reconcile_resolved_tasks(Repository.t()) :: non_neg_integer()
  def reconcile_resolved_tasks(repository) do
    tasks =
      Repo.all(
        from t in Task,
          where: t.repository_id == ^repository.id and t.state == "ready"
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

  @ended_states ~w(done closed stopped archived)
  @ended_page_size 50

  def ended_page_size, do: @ended_page_size

  @doc "The task states that mean the work is over."
  def ended_states, do: @ended_states

  @doc """
  A page of the tasks that ended, newest first by the instant the board saw
  the end, each with how it ended and the pull request that closes it.

  `query` narrows the page: a number (with or without `#`) is the issue's
  number, any other text is searched in the title. The page is one query and
  the pull requests of its tasks are a second one.
  """
  @spec ended_page(
          integer(),
          String.t() | nil,
          {DateTime.t() | nil, integer()} | nil,
          pos_integer()
        ) ::
          [map()]
  def ended_page(repository_id, query \\ nil, cursor \\ nil, limit \\ @ended_page_size) do
    base =
      from t in Task,
        where: t.repository_id == ^repository_id and t.kind == "issue",
        where: t.state in ^@ended_states or t.stopped or t.archived,
        order_by: [desc_nulls_last: t.state_changed_at, desc: t.id],
        limit: ^limit

    tasks = base |> ended_search(query) |> ended_after(cursor) |> Repo.all()
    pulls = closing_pulls(repository_id, tasks)

    Enum.map(tasks, fn task ->
      pull = Map.get(pulls, task.number)

      %{
        id: task.id,
        number: task.number,
        title: task.title,
        ended_at: task.state_changed_at,
        outcome: ended_outcome(task, pull),
        pull: pull && %{number: pull.number, url: pull.url}
      }
    end)
  end

  @doc "How a task ended: merged needs a merged pull request that closes its issue."
  def ended_outcome(%Task{archived: true}, _pull), do: :archived
  def ended_outcome(%Task{state: "archived"}, _pull), do: :archived
  def ended_outcome(%Task{stopped: true}, _pull), do: :stopped
  def ended_outcome(%Task{state: "stopped"}, _pull), do: :stopped
  def ended_outcome(_task, %PullRequest{state: "merged"}), do: :merged
  def ended_outcome(_task, _pull), do: :closed

  defp ended_search(base, query) do
    text = String.trim(query || "")

    case Regex.run(~r/^#?(\d+)$/, text) do
      [_, digits] ->
        from t in base, where: t.number == ^String.to_integer(digits)

      nil when text == "" ->
        base

      nil ->
        pattern = "%" <> String.replace(text, ~r/([\\%_])/, "\\\\\\1") <> "%"
        from t in base, where: ilike(t.title, ^pattern)
    end
  end

  defp ended_after(base, nil), do: base

  defp ended_after(base, {nil, id}),
    do: from(t in base, where: is_nil(t.state_changed_at) and t.id < ^id)

  defp ended_after(base, {%DateTime{} = at, id}) do
    from t in base,
      where:
        is_nil(t.state_changed_at) or t.state_changed_at < ^at or
          (t.state_changed_at == ^at and t.id < ^id)
  end

  # The pull request that closes each issue, by issue number: a merged one
  # wins, then the newest. One read for the whole page.
  defp closing_pulls(_repository_id, []), do: %{}

  defp closing_pulls(repository_id, tasks) do
    numbers = tasks |> Enum.map(& &1.number) |> Enum.reject(&is_nil/1)

    from(p in PullRequest,
      where:
        p.repository_id == ^repository_id and
          fragment("? && ?::integer[]", p.closes_issues, ^numbers),
      order_by: [asc: fragment("? = 'merged'", p.state), asc: p.id]
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn pull, acc ->
      Enum.reduce(pull.closes_issues, acc, &Map.put(&2, &1, pull))
    end)
  end

  defp first_repository,
    do: Repo.one(from r in Repository, where: r.active, order_by: r.id, limit: 1)

  def repository_by_slug(slug) when is_binary(slug) do
    with false <- String.contains?(slug, <<0>>),
         [owner, name] <- String.split(slug, "/", parts: 2) do
      find_repository(owner, name)
    else
      _no_slug -> nil
    end
  end

  # A query string can carry a map or a list where a slug was expected, and
  # Postgres refuses a NUL byte instead of finding nothing.
  def repository_by_slug(_slug), do: nil

  @max_id 9_223_372_036_854_775_807

  @doc """
  An id that came from outside (a URL, an API path) as an integer the database
  can look up, or nil. Past bigint, Postgrex raises instead of finding nothing.
  """
  @spec parse_id(term()) :: pos_integer() | nil
  def parse_id(value) when is_integer(value) and value > 0 and value <= @max_id, do: value

  def parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> parse_id(id)
      _other -> nil
    end
  end

  def parse_id(_value), do: nil

  @doc "The tracked repository with this owner and name, or nil."
  @spec find_repository(String.t(), String.t()) :: Repository.t() | nil
  def find_repository(owner, name) when is_binary(owner) and is_binary(name) do
    Repo.one(from r in Repository, where: r.owner == ^owner and r.name == ^name)
  end

  @doc "One tracked repository by the board's id, or nil."
  @spec repository(integer()) :: Repository.t() | nil
  def repository(id) when is_integer(id), do: Repo.get(Repository, id)

  @doc """
  A saved task by the board's id, with its repository loaded.

  This is the id the board generates, not the issue number (`find_task/2`).
  nil when the row is gone.
  """
  @spec task(integer()) :: Task.t() | nil
  def task(id) when is_integer(id) do
    case Repo.get(Task, id) do
      nil -> nil
      task -> Repo.preload(task, :repository)
    end
  end

  @doc "A saved task of one repository by id, with its repository loaded."
  @spec task_of(Repository.t(), integer()) :: Task.t() | nil
  def task_of(%Repository{id: repository_id}, id) when is_integer(id) do
    case Repo.get_by(Task, id: id, repository_id: repository_id) do
      nil -> nil
      task -> Repo.preload(task, :repository)
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

  @doc """
  The key of a request the board is about to create: the repository, the
  kind of submit and the exact words, hashed. The same words asked twice
  (a double click, a reload, a retry after a partial split) share the key.
  """
  @spec request_key(Repository.t(), String.t(), [String.t()]) :: String.t()
  def request_key(%Repository{id: id}, kind, parts) when is_list(parts) do
    [to_string(id), kind | Enum.map(parts, &normalize_request_text/1)]
    |> Enum.join("\n--\n")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 40)
  end

  defp normalize_request_text(text) do
    text |> to_string() |> String.trim() |> String.replace(~r/\s+/u, " ")
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

    case task |> Task.changeset(attrs) |> Repo.update() do
      {:ok, task} = result ->
        broadcast(task.repository_id)
        result

      other ->
        other
    end
  end

  @doc "The conversation of a task: its comments, oldest first."
  def comments(task) do
    # A sync stores a whole thread in one second: the id keeps GitHub's order within it.
    Repo.all(
      from c in Comment, where: c.task_id == ^task.id, order_by: [asc: c.inserted_at, asc: c.id]
    )
  end

  @doc "Open prerequisite tasks that point at this blocked task, oldest first."
  @spec blockers_for(Task.t()) :: [Task.t()]
  def blockers_for(%Task{id: id}) when is_integer(id) do
    Repo.all(
      from t in Task,
        where: t.blocker_for_task_id == ^id and t.state not in ["done", "closed"],
        order_by: [asc: t.inserted_at, asc: t.id]
    )
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

    post_mention(task, placeholder, text, client)
  end

  defp post_mention(task, placeholder, text, client) do
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
      # The placeholder must never outlive a failed request; synced comments
      # also carry negative ids, so only this row goes.
      Repo.delete(placeholder)
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
      on_conflict: {:replace, [:body, :author, :kind, :updated_at]},
      conflict_target: [:task_id, :github_id]
    )
  end

  @doc """
  Whether the newest agent comment on a task asks the person something.

  When that comment is a workpad, its Pergunta section decides, with or
  without a question mark. Otherwise a real question mark in the text does.
  The runner's hidden marker (`<!-- dsh-superagent:... -->`) is not part of
  the message. No comment, or a comment that only reports, is `false`.
  """
  @spec agent_asked?(integer(), integer()) :: boolean()
  def agent_asked?(repository_id, number),
    do: is_binary(agent_question(repository_id, number))

  @doc """
  What the newest agent comment on a task asks: the workpad's Pergunta, or
  the whole message (without the runner marker) when it is not a workpad and
  asks; nil otherwise. The rule `agent_asked?/2` states lives here.
  """
  @spec agent_question(integer(), integer()) :: String.t() | nil
  def agent_question(repository_id, number) do
    case newest_agent_comment(repository_id, number) do
      nil ->
        nil

      body ->
        case Workpad.parse(body) do
          %{question: question} ->
            question

          nil ->
            text = body |> String.replace(@runner_marker, "") |> String.trim()
            if Workpad.question?(text), do: text
        end
    end
  end

  @doc "The Bloqueio of the newest agent comment's workpad, or nil."
  @spec agent_blockage(integer(), integer()) :: String.t() | nil
  def agent_blockage(repository_id, number) do
    case agent_workpad(repository_id, number) do
      %{blockage: blockage} -> blockage
      nil -> nil
    end
  end

  @doc """
  The workpad in the newest agent comment on a task, or nil when there is no
  agent comment or it is not one (`AgentBoard.Workpad.parse/1`).
  """
  @spec agent_workpad(integer(), integer()) :: Workpad.t() | nil
  def agent_workpad(repository_id, number) do
    repository_id |> newest_agent_comment(number) |> Workpad.parse()
  end

  @doc """
  The workpad per task number, for every task of a repository whose newest
  agent comment is one. The local CI reads Validação from it.
  """
  @spec agent_workpads(integer()) :: %{optional(integer()) => Workpad.t()}
  def agent_workpads(repository_id) do
    Repo.all(
      from c in Comment,
        join: t in Task,
        on: t.id == c.task_id,
        where: t.repository_id == ^repository_id and c.kind == "agent",
        distinct: t.number,
        order_by: [asc: t.number, desc: c.inserted_at, desc: c.id],
        select: {t.number, c.body}
    )
    |> Enum.flat_map(fn {number, body} ->
      case Workpad.parse(body) do
        nil -> []
        workpad -> [{number, workpad}]
      end
    end)
    |> Map.new()
  end

  @doc """
  What `AgentBoard.Attribution.for_session/2` needs: every repository, the
  PRs with their branch and the issues they close, and the issue tasks.
  """
  @spec attribution_index() :: AgentBoard.Attribution.index()
  def attribution_index do
    AgentBoard.Attribution.index(
      Repo.all(from r in Repository, select: %{id: r.id, owner: r.owner, name: r.name}),
      Repo.all(
        from p in PullRequest,
          select: %{
            repository_id: p.repository_id,
            number: p.number,
            head_ref: p.head_ref,
            closes_issues: p.closes_issues
          }
      ),
      Repo.all(
        from t in Task,
          where: t.kind == "issue" and not is_nil(t.number),
          select: %{id: t.id, repository_id: t.repository_id, number: t.number}
      )
    )
  end

  @doc "The head sha per PR number, as the sync last saw it; a PR synced before the column is absent."
  @spec pull_heads(integer()) :: %{optional(integer()) => String.t()}
  def pull_heads(repository_id) do
    Repo.all(
      from p in PullRequest,
        where: p.repository_id == ^repository_id and not is_nil(p.head_sha),
        select: {p.number, p.head_sha}
    )
    |> Map.new()
  end

  # A task without an issue number has no agent comments to read.
  defp newest_agent_comment(_repository_id, nil), do: nil

  defp newest_agent_comment(repository_id, number) do
    Repo.one(
      from c in Comment,
        join: t in Task,
        on: t.id == c.task_id,
        where: t.repository_id == ^repository_id and t.number == ^number and c.kind == "agent",
        order_by: [desc: c.inserted_at, desc: c.id],
        limit: 1,
        select: c.body
    )
  end

  @doc """
  The pull request each task is linked to, by task id.

  The link is the PR URL the task's conversation or body names, or, failing
  that, the PR thread the task's ticket opened itself (`own_threads`). A task
  with neither is absent from the map: the board does not guess by title.
  """
  @spec linked_pull_requests([Task.t()], %{optional(integer()) => map()}) ::
          %{optional(integer()) => PullRequest.t()}
  def linked_pull_requests(tasks, tickets_by_number \\ %{})

  def linked_pull_requests([], _tickets), do: %{}

  def linked_pull_requests(tasks, tickets) do
    {comments_by_task, repositories} = link_sources(tasks)
    pulls = linked_pulls(tasks, comments_by_task, repositories)

    named =
      Enum.reduce(tasks, %{}, fn task, acc ->
        number = linked_number(task, Map.get(comments_by_task, task.id, []), repositories)

        case Map.get(pulls, {task.repository_id, number}) do
          nil -> acc
          pull -> Map.put(acc, task.id, pull)
        end
      end)

    # The rest fall back to the PR thread their ticket opened, read once for
    # all of them; the highest thread number wins, as before.
    unnamed = Enum.reject(tasks, &Map.has_key?(named, &1.id))
    threads = Map.new(unnamed, &{&1.id, own_threads(Map.get(tickets, &1.number))})
    thread_pulls = ticket_pulls(unnamed, threads)

    Enum.reduce(unnamed, named, fn task, acc ->
      pull =
        threads
        |> Map.fetch!(task.id)
        |> Enum.sort(:desc)
        |> Enum.find_value(&Map.get(thread_pulls, {task.repository_id, &1}))

      if pull, do: Map.put(acc, task.id, pull), else: acc
    end)
  end

  defp own_threads(nil), do: []
  defp own_threads(ticket), do: ticket["own_threads"] || []

  defp ticket_pulls(tasks, threads) do
    numbers = threads |> Map.values() |> List.flatten() |> Enum.uniq()

    if numbers == [] do
      %{}
    else
      repository_ids = Enum.uniq(Enum.map(tasks, & &1.repository_id))

      Repo.all(
        from p in PullRequest,
          where: p.repository_id in ^repository_ids and p.number in ^numbers
      )
      |> Map.new(&{{&1.repository_id, &1.number}, &1})
    end
  end

  @doc """
  The pull request a task names, from its body or the newest comment with a
  GitHub PR URL. The board never guesses by title.
  """
  def task_pull_request(%Task{} = task, comments) do
    repository =
      case task.repository do
        %Repository{} = repository -> repository
        _ -> Repo.get(Repository, task.repository_id)
      end

    number = linked_number(task, comments, %{task.repository_id => repository})

    if repository && number, do: find_pull_request(repository, number)
  end

  # Only a link to the task's own repository counts: the number alone would
  # match this repository's PR of the same number.
  defp pull_number(nil, _repository), do: nil
  defp pull_number(_text, nil), do: nil

  defp pull_number(text, %Repository{owner: owner, name: name}) do
    ~r{https://github\.com/([^/\s]+)/([^/\s]+)/pull/(\d+)}
    |> Regex.scan(text)
    |> Enum.find_value(fn [_, link_owner, link_name, number] ->
      if String.downcase("#{link_owner}/#{link_name}") == String.downcase("#{owner}/#{name}"),
        do: GitHub.number(number)
    end)
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
        task.inserted_at &&
          %{at: task.inserted_at, text: gettext("Entered the queue"), tone: :queue},
        task.started_at &&
          %{at: task.started_at, text: gettext("The agent started"), tone: :agent},
        task.state_changed_at &&
          %{
            at: task.state_changed_at,
            text: gettext("Current state: %{state}", state: state_label(task.state)),
            tone: state_tone(task.state)
          },
        pull_request && pull_request.opened_at &&
          %{
            at: pull_request.opened_at,
            text: gettext("PR #%{number} opened", number: pull_request.number),
            tone: :agent,
            url: pull_request.url
          },
        pull_request && pull_request.merged_at &&
          %{
            at: pull_request.merged_at,
            text: gettext("PR #%{number} merged", number: pull_request.number),
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
    |> Activity.for_number(number)
    |> Enum.map(fn event ->
      %{
        at: event.inserted_at,
        text: event_text(event),
        tone: if(event_error?(event), do: :halt, else: :plain)
      }
    end)
  end

  defp event_text(event) do
    case event.payload do
      %{"reason" => reason} -> "#{event_words(event)}: #{truncate_reason(reason)}"
      _ -> event_words(event)
    end
  end

  # What happened, in the reader's words. A kind this list does not know is
  # shown as its own words rather than hidden.
  defp event_words(%{kind: "task_released"}), do: gettext("Released to the agent")
  defp event_words(%{kind: "release_error"}), do: gettext("Release failed")
  defp event_words(%{kind: "stop_error"}), do: gettext("Stop failed")
  defp event_words(%{kind: "routing_error"}), do: gettext("Could not save the routing")
  defp event_words(%{kind: "comment_error"}), do: gettext("Could not read the comments")
  defp event_words(%{kind: "issue_error"}), do: gettext("Could not read the issue")

  defp event_words(%{kind: "agent_retry", payload: %{"attempt" => attempt, "max" => max}}),
    do: gettext("Automatic retry %{attempt} of %{max}", attempt: attempt, max: max)

  defp event_words(%{kind: "agent_retry_error", payload: %{"attempt" => attempt, "max" => max}}),
    do:
      gettext("Automatic retry %{attempt} of %{max} was not accepted", attempt: attempt, max: max)

  defp event_words(%{kind: "agent_retry_manual", payload: %{"outcome" => "retried"}}),
    do: gettext("Retry requested by you")

  defp event_words(%{kind: "agent_retry_manual"}),
    do: gettext("Retry requested by you was not accepted")

  defp event_words(%{kind: kind}), do: String.replace(kind || "", "_", " ")

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
      # Named for what it is: the remote check. The gate that counts here is
      # the local one (`AgentBoard.LocalCI`), so this is not painted as a halt.
      text:
        gettext("GitHub Actions failed") <>
          if(pull.checks_failed in [nil, ""], do: "", else: " · #{pull.checks_failed}"),
      tone: :plain
    }
  end

  defp checks_activity(%PullRequest{checks_state: "success"} = pull) do
    %{at: pull.checks_changed_at, text: gettext("GitHub Actions passed"), tone: :agent}
  end

  defp checks_activity(_pull), do: nil

  defp state_label("running"), do: pgettext("activity state", "running")
  defp state_label("question"), do: pgettext("activity state", "question")
  defp state_label("ready"), do: pgettext("activity state", "to review")
  defp state_label("blocked"), do: pgettext("activity state", "blocked")
  defp state_label("retrying"), do: pgettext("activity state", "trying again")
  defp state_label("queued"), do: pgettext("activity state", "queued")
  defp state_label("done"), do: pgettext("activity state", "merged")
  defp state_label("stopped"), do: pgettext("activity state", "stopped")
  defp state_label("archived"), do: pgettext("activity state", "archived")
  defp state_label(state), do: state || pgettext("activity state", "unknown")

  defp state_tone("blocked"), do: :halt
  defp state_tone("retrying"), do: :agent
  defp state_tone("question"), do: :you
  defp state_tone("ready"), do: :you
  defp state_tone("running"), do: :agent
  defp state_tone("done"), do: :done
  defp state_tone(_state), do: :plain

  @doc """
  Creates an objective from a split and attaches the tasks that were created
  for it. Only a group of two or more tasks becomes an objective.
  """
  @spec create_objective(Repository.t(), map(), [integer()]) ::
          {:ok, Objective.t()} | {:error, term()}
  def create_objective(repository, %{title: _title, done_criterion: _criterion} = attrs, task_ids) do
    task_ids = Enum.uniq(task_ids)

    if length(task_ids) < 2 do
      {:error, :not_a_group}
    else
      # Both writes or neither: an objective without its tasks would be listed
      # as an empty group.
      result =
        Repo.transact(fn ->
          with {:ok, objective} <- find_or_insert_objective(repository, attrs) do
            Repo.update_all(from(t in Task, where: t.id in ^task_ids),
              set: [objective_id: objective.id]
            )

            {:ok, objective}
          end
        end)

      if match?({:ok, _}, result), do: broadcast(repository.id)
      result
    end
  end

  # A retry that completes a split finds the objective of its first attempt.
  # The unique index on (repository_id, request_key) decides, so two attempts
  # at once cannot both insert; a nil key never conflicts.
  defp find_or_insert_objective(repository, attrs) do
    %Objective{}
    |> Objective.changeset(Map.put(attrs, :repository_id, repository.id))
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:repository_id, :request_key])
    |> case do
      {:ok, %Objective{id: nil}} ->
        {:ok,
         Repo.get_by!(Objective, repository_id: repository.id, request_key: attrs.request_key)}

      other ->
        other
    end
  end

  @doc "The repository's objectives with their task progress, newest first."
  @spec objectives(Repository.t()) :: [map()]
  def objectives(repository) do
    Repo.all(
      from o in Objective,
        where: o.repository_id == ^repository.id,
        order_by: [desc: o.id],
        preload: [:tasks]
    )
    |> with_edges()
    |> Enum.map(fn {objective, edges} ->
      total = length(objective.tasks)
      merged = Enum.count(objective.tasks, &(&1.state == "done"))

      %{
        id: objective.id,
        title: objective.title,
        done_criterion: objective.done_criterion,
        total: total,
        merged: merged,
        done?: total > 0 and merged == total,
        issue_url: objective.issue_url,
        tasks:
          Enum.map(
            objective.tasks,
            &Map.take(&1, [:id, :number, :title, :state, :held, :released_at])
          ),
        edges: edges
      }
    end)
  end

  defp with_edges(objectives) do
    ids = for objective <- objectives, task <- objective.tasks, do: task.id

    edges =
      Repo.all(
        from d in TaskDependency,
          where: d.task_id in ^ids,
          select: {d.task_id, d.blocked_by_task_id}
      )

    Enum.map(objectives, fn objective ->
      own = MapSet.new(objective.tasks, & &1.id)
      {objective, Enum.filter(edges, fn {task, _blocker} -> task in own end)}
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
end
