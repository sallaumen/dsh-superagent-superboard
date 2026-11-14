defmodule AgentBoard.Sync do
  @moduledoc """
  The sync: GitHub issues, pull requests, reviews and checks, plus the agent's
  tickets, into the board.

  The state model is two-layered:

    * the **issue** is the baseline: open -> queued, closed -> done;
    * the **ticket** is the live overlay: running, ready or blocked while the
      issue is open; merged -> done.

  A stopped or archived task keeps its own state; the sync never revives it.
  """
  import Ecto.Query, warn: false

  alias AgentBoard.{
    AgentAccess,
    AgentState,
    Attribution,
    Board,
    GitHub,
    Repo,
    TicketOverlay,
    Tickets
  }

  alias AgentBoard.Board.{Commit, PullRequest, Repository, SplitGraph, Task}

  alias AgentBoard.Sync.ReopenedTickets

  @doc "Sync every active repository. Returns how many it touched."
  def all(client \\ GitHub.client()), do: client |> run() |> length()

  @doc """
  Sync the active repositories and return each result. A rate limit ends the
  run: the quota is the account's, so the next repository would be refused too.
  """
  @spec run(Req.Request.t()) :: [term()]
  def run(client \\ GitHub.client()) do
    Repo.all(from r in Repository, where: r.active)
    |> Enum.reduce_while([], fn repository, results ->
      case sync_repo(client, repository) do
        {:error, %GitHub.RateLimited{}} = limited -> {:halt, [limited | results]}
        result -> {:cont, [result | results]}
      end
    end)
    |> Enum.reverse()
  end

  @doc "Whether there is any repository to sync."
  @spec repositories?() :: boolean()
  def repositories?, do: Repo.exists?(from r in Repository, where: r.active)

  @doc """
  Sync one repository.

  A GitHub failure (rate limit, 5xx, network) is logged as an event and
  returned as `{:error, reason}`; the Oban worker retries the job, and the
  board keeps the last good state instead of losing it.
  """
  def sync_repo(client, repository) do
    do_sync(client, repository)
  rescue
    exception ->
      Board.log_event(
        repository.id,
        "sync_error",
        "#{repository.owner}/#{repository.name}",
        error_payload(exception)
      )

      Board.broadcast(repository.id)
      {:error, exception}
  end

  defp error_payload(%GitHub.RateLimited{retry_after: seconds} = exception) do
    %{
      "reason" => Exception.message(exception),
      "rate_limited" => true,
      "retry_after" => seconds
    }
  end

  defp error_payload(exception), do: %{"reason" => Exception.message(exception)}

  # A repository can have Issues disabled (404 or 410). That is not a sync
  # failure: the pulls still matter. Any other failure read no issue state,
  # so it is a `sync_error`, never a fresh sync.
  defp fetch_issues(client, repository, since) do
    GitHub.issues(client, repository.owner, repository.name, since)
  rescue
    exception in GitHub.HTTPError ->
      if exception.status in [404, 410] do
        Board.log_event(
          repository.id,
          "issues_unavailable",
          "#{repository.owner}/#{repository.name}",
          error_payload(exception)
        )

        []
      else
        reraise exception, __STACKTRACE__
      end
  end

  defp do_sync(client, repository) do
    # Errors from earlier runs are history, not this run's outcome. Take the
    # last event id before the first read; the summary counts only rows above
    # it, so a transient failure is not repeated on every later sync.
    run_start_id =
      Repo.one(
        from e in AgentBoard.Board.Event,
          where: e.repository_id == ^repository.id,
          select: max(e.id)
      ) || 0

    since = updated_since(repository)
    issues = fetch_issues(client, repository, since)
    pulls = GitHub.pulls(client, repository.owner, repository.name, since)

    issues
    |> Enum.reject(&SplitGraph.objective_issue?/1)
    |> Enum.each(&upsert_issue(repository, &1))

    # One broken PR (reviews, checks) must not kill the whole sync.
    Enum.each(pulls, fn pull ->
      try do
        upsert_pull(client, repository, pull)
      rescue
        error in GitHub.RateLimited ->
          reraise error, __STACKTRACE__

        exception ->
          Board.log_event(repository.id, "pull_error", "##{pull["number"]}", %{
            "reason" => Exception.message(exception)
          })
      end
    end)

    commits = sync_commits(client, repository)

    apply_tickets(repository, issues, client)
    sync_comments(repository, client)
    Board.reconcile_resolved_tasks(repository)

    # The "commits" key is the evidence that the branch was read: the
    # throughput block shows `?` for a repository whose latest sync lacks it.
    summary = %{
      "issues" => length(issues),
      "pulls" => length(pulls),
      "errors" => error_count(repository, run_start_id)
    }

    summary =
      case commits do
        {:ok, stored} -> Map.put(summary, "commits", stored)
        :error -> summary
      end

    Board.log_event(repository.id, "sync", "#{repository.owner}/#{repository.name}", summary)

    Board.broadcast(repository.id)
  end

  # The errors written by this sync run. A single query keeps the summary
  # honest without threading counters through every branch.
  defp error_count(repository, after_id) do
    Repo.aggregate(
      from(e in AgentBoard.Board.Event,
        where:
          e.repository_id == ^repository.id and e.id > ^after_id and
            e.kind in [
              "issue_error",
              "pull_error",
              "review_error",
              "check_error",
              "comment_error",
              "commit_error"
            ]
      ),
      :count
    )
  end

  # The last completed sync, an hour early: its row is written when it ends, so
  # the margin covers what changed while it ran and GitHub's clock. nil: never.
  defp updated_since(repository) do
    at =
      Repo.one(
        from e in AgentBoard.Board.Event,
          where: e.repository_id == ^repository.id and e.kind == "sync",
          select: max(e.inserted_at)
      )

    at && DateTime.add(at, -1, :hour)
  end

  # -- the commits ------------------------------------------------------------

  # The throughput block's longest window; the first read of a repository
  # fills it, later reads continue from the newest commit stored.
  @commit_window_days 7
  @commit_pages 10

  # The default branch's commits, stored once by sha. A GitHub failure here is
  # one event and `:error`: the issues, pulls and tickets still sync.
  defp sync_commits(client, repository) do
    since = commits_since(repository)
    {:ok, store_commit_pages(client, repository, since, 1, 0)}
  rescue
    error in GitHub.RateLimited ->
      reraise error, __STACKTRACE__

    exception ->
      Board.log_event(
        repository.id,
        "commit_error",
        "#{repository.owner}/#{repository.name}",
        %{"reason" => Exception.message(exception)}
      )

      :error
  end

  defp commits_since(repository) do
    Repo.one(
      from c in Commit,
        where: c.repository_id == ^repository.id,
        select: max(c.committed_at)
    ) || DateTime.add(DateTime.utc_now(), -@commit_window_days, :day)
  end

  defp store_commit_pages(_client, _repository, _since, page, stored) when page > @commit_pages,
    do: stored

  defp store_commit_pages(client, repository, since, page, stored) do
    {commits, more?} = GitHub.commits(client, repository.owner, repository.name, since, page)
    stored = stored + store_commits(repository, commits)

    if more?,
      do: store_commit_pages(client, repository, since, page + 1, stored),
      else: stored
  end

  defp store_commits(_repository, []), do: 0

  defp store_commits(repository, commits) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      commits
      |> Enum.filter(&is_binary(&1["sha"]))
      |> Enum.map(fn commit ->
        %{
          repository_id: repository.id,
          sha: commit["sha"],
          author:
            get_in(commit, ["author", "login"]) || get_in(commit, ["commit", "author", "name"]),
          message: first_line(get_in(commit, ["commit", "message"])),
          authored_at: to_dt(get_in(commit, ["commit", "author", "date"])),
          committed_at: to_dt(get_in(commit, ["commit", "committer", "date"])),
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} =
      Repo.insert_all(Commit, rows,
        on_conflict: :nothing,
        conflict_target: [:repository_id, :sha]
      )

    count
  end

  # GitHub takes 256 characters and the columns hold 255.
  defp title(nil), do: nil
  defp title(text), do: String.slice(text, 0, 255)

  defp first_line(nil), do: nil

  defp first_line(message) do
    message |> String.split("\n", parts: 2) |> List.first() |> String.slice(0, 200)
  end

  # -- the conversation -------------------------------------------------------

  defp sync_comments(repository, client) do
    agent_login = AgentAccess.bot_login()

    repository.id
    |> active_tasks()
    |> Enum.each(fn task ->
      # One broken conversation must not kill the whole sync.
      try do
        case GitHub.issue_comments(client, repository.owner, repository.name, task.number) do
          comments when is_list(comments) -> Board.store_comments(task, comments, agent_login)
          _ -> :ok
        end
      rescue
        error in GitHub.RateLimited ->
          reraise error, __STACKTRACE__

        exception ->
          Board.log_event(repository.id, "comment_error", "##{task.number}", %{
            "reason" => Exception.message(exception)
          })
      end
    end)
  end

  # A task waiting on the person (a question, a block) is the one whose
  # conversation matters most: the agent's last comment is what the person
  # must answer, and the PR it names is what the board links.
  @conversation_states ["running", "retrying", "ready", "queued", "question", "blocked"]

  defp active_tasks(repository_id) do
    Repo.all(
      from(t in Task,
        where: t.repository_id == ^repository_id and t.state in @conversation_states,
        order_by: [desc: t.updated_at],
        limit: 10
      )
    )
  end

  # -- the issues -------------------------------------------------------------

  # The insert above sets the baseline only once: on conflict it keeps the
  # state, so an overlay (running, ready...) is not reset to `queued` on
  # every sync. A closed issue is the exception: it is `done` whatever the
  # overlay said, unless the owner stopped or archived the task. Without
  # this, an issue closed after it entered the board stayed in the queue.
  defp close_task(repository, number) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(t in Task,
        where:
          t.repository_id == ^repository.id and t.kind == "issue" and t.number == ^number and
            not t.stopped and not t.archived and t.state not in ["done", "closed"]
      ),
      set: [state: "done", state_changed_at: now, updated_at: now]
    )
  end

  # A reopened issue is work again: its `done` task goes back to the queue.
  # This runs before the tickets and `Board.reconcile_resolved_tasks/1`, so a
  # merge can still finish it unless GitHub confirms a later reopen. Only
  # an issue changed after the board last decided the state is reopened, so
  # that `done` is not undone and redone on every sync.
  defp reopen_task(_repository, _number, nil), do: 0

  defp reopen_task(repository, number, issue_updated_at) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(t in Task,
        where:
          t.repository_id == ^repository.id and t.kind == "issue" and t.number == ^number and
            not t.stopped and not t.archived and t.state == "done" and
            (is_nil(t.state_changed_at) or t.state_changed_at < ^issue_updated_at)
      ),
      set: [state: "queued", state_changed_at: now, updated_at: now]
    )
  end

  defp upsert_issue(repository, issue) do
    closed = issue["state"] == "closed"

    %Task{repository_id: repository.id, kind: "issue", number: issue["number"]}
    |> Task.changeset(%{
      title: title(issue["title"]),
      body: issue["body"] || "",
      state: if(closed, do: "done", else: "queued"),
      state_changed_at: DateTime.utc_now(),
      url: issue["html_url"],
      author: get_in(issue, ["user", "login"])
    })
    # `updated_at` stays the board's: replacing it made every fetched task
    # look changed now on every sync.
    |> Repo.insert(
      on_conflict: {:replace, [:title, :body, :url]},
      conflict_target: [:repository_id, :kind, :number]
    )
    |> case do
      {:ok, _} ->
        if closed,
          do: close_task(repository, issue["number"]),
          else: reopen_task(repository, issue["number"], to_dt(issue["updated_at"]))

        :ok

      {:error, changeset} ->
        Board.log_event(repository.id, "issue_error", "##{issue["number"]}", %{
          "reason" => inspect(changeset.errors)
        })
    end
  end

  # -- the pull requests ------------------------------------------------------

  @doc "Mirror only a GitHub-confirmed merged PR. Never change the issue or the sync cursor."
  def sync_merged_pull(client, repo, number) do
    with %{
           "number" => ^number,
           "state" => "closed",
           "merged_at" => at,
           "base" => %{"repo" => %{"full_name" => slug}}
         } = pull
         when is_binary(at) and is_binary(slug) <-
           GitHub.pull(client, repo.owner, repo.name, number),
         %DateTime{} <- to_dt(at),
         true <- String.downcase(slug) == String.downcase("#{repo.owner}/#{repo.name}") do
      with {:ok, _} <- upsert_pull(client, repo, pull), do: Board.broadcast(repo.id)
    else
      _ -> :ok
    end
  end

  defp upsert_pull(client, repository, pull) do
    merged = pull["merged_at"] != nil

    state =
      if merged, do: "merged", else: if(pull["state"] == "closed", do: "closed", else: "open")

    existing = Repo.get_by(PullRequest, repository_id: repository.id, number: pull["number"])

    {review_state, checks_state, checks_failed} =
      rollup_for(client, repository, pull, state, existing)

    now = DateTime.utc_now()
    checks_changed_at = checks_changed_at(existing, checks_state, now)

    %PullRequest{repository_id: repository.id, number: pull["number"]}
    |> PullRequest.changeset(%{
      title: title(pull["title"]),
      state: state,
      url: pull["html_url"],
      author: get_in(pull, ["user", "login"]),
      opened_at: to_dt(pull["created_at"]),
      merged_at: to_dt(pull["merged_at"]),
      review_state: review_state,
      checks_state: checks_state,
      checks_failed: checks_failed,
      checks_changed_at: checks_changed_at,
      head_sha: get_in(pull, ["head", "sha"]),
      head_ref: head_ref(pull, repository),
      closes_issues: Attribution.closing_numbers(pull["body"], repository.owner, repository.name)
    })
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :title,
           :state,
           :url,
           :opened_at,
           :review_state,
           :checks_state,
           :checks_failed,
           :checks_changed_at,
           :head_sha,
           :head_ref,
           :closes_issues,
           :merged_at,
           :updated_at
         ]},
      conflict_target: [:repository_id, :number]
    )
    |> case do
      {:ok, pull_request} ->
        {:ok, pull_request}

      {:error, changeset} ->
        Board.log_event(repository.id, "pull_error", "##{pull["number"]}", %{
          "reason" => inspect(changeset.errors)
        })

        {:error, changeset}
    end
  end

  # A fork's branch does not exist in this repository: a session on a branch
  # of the same name here did not open that PR. GitHub sends `head.repo`
  # null for a deleted fork, so null is a fork too; a pull with no `repo`
  # key at all (an older payload) keeps its ref.
  defp head_ref(pull, repository) do
    own = String.downcase("#{repository.owner}/#{repository.name}")

    case get_in(pull, ["head", "repo"]) do
      %{"full_name" => full_name} when is_binary(full_name) ->
        if String.downcase(full_name) == own, do: get_in(pull, ["head", "ref"])

      nil ->
        if Map.has_key?(pull["head"] || %{}, "repo"), do: nil, else: get_in(pull, ["head", "ref"])

      _ ->
        nil
    end
  end

  # Merged and closed pulls also carry reviews and checks: the board shows
  # them in the merged column, so they must be fetched, not left nil.
  # A pull that ended changes no more, and it is most of what the list brings:
  # reading its reviews and checks again cost two calls per pull per sync, past
  # the account's hourly quota with three repositories. Once stored as ended
  # at the same commit it keeps what it has; only running checks are worth
  # another read.
  defp rollup_for(client, repository, pull, state, existing) do
    cond do
      settled?(existing, pull, state) ->
        {existing.review_state, existing.checks_state, existing.checks_failed}

      stale?(pull) ->
        {nil, nil, nil}

      true ->
        rollups(client, repository, pull, existing)
    end
  end

  defp settled?(%PullRequest{state: state, checks_state: checks} = existing, pull, state)
       when state in ["merged", "closed"] and checks not in ["pending", nil],
       do: existing.head_sha == get_in(pull, ["head", "sha"])

  defp settled?(_existing, _pull, _state), do: false

  @stale_days 30

  defp stale?(pull) do
    case to_dt(pull["merged_at"] || pull["closed_at"]) do
      nil -> false
      ended_at -> DateTime.diff(DateTime.utc_now(), ended_at, :day) > @stale_days
    end
  end

  defp rollups(client, repository, pull, existing) do
    # A failing review/check fetch must not abort the PR insert: the PR is
    # stored with the rollups it can get, and the failure is logged.
    reviews =
      safe_fetch(repository, "review_error", pull, fn ->
        GitHub.reviews(client, repository.owner, repository.name, pull["number"])
      end)

    checks =
      safe_fetch(repository, "check_error", pull, fn ->
        GitHub.check_runs(
          client,
          repository.owner,
          repository.name,
          get_in(pull, ["head", "sha"]) || ""
        )
      end)

    {checks_state, checks_failed} = read_checks(checks, reviews, pull, existing)
    {read_reviews(reviews, pull, existing), checks_state, checks_failed}
  end

  # What a failed read leaves depends on whether the pull comes back. An open
  # pull is read on every sync, so it keeps what was known until the next one.
  # An ended pull stores nil, "not read", so it is read again; "none" means
  # GitHub answered that there are no checks, and that one is settled.
  defp read_checks(
         nil,
         _reviews,
         %{"state" => "open", "head" => %{"sha" => sha}},
         %PullRequest{head_sha: sha} = existing
       ),
       do: {existing.checks_state, existing.checks_failed}

  defp read_checks(nil, _reviews, _pull, _existing), do: {nil, nil}
  defp read_checks(_checks, nil, %{"state" => "closed"}, _existing), do: {nil, nil}
  defp read_checks(checks, _reviews, _pull, _existing), do: checks_rollup(checks)

  defp read_reviews(nil, %{"state" => "open"}, %PullRequest{} = existing),
    do: existing.review_state

  defp read_reviews(reviews, _pull, _existing), do: review_rollup(reviews || [])

  defp safe_fetch(repository, kind, pull, fun) do
    fun.()
  rescue
    error in GitHub.RateLimited ->
      reraise error, __STACKTRACE__

    exception ->
      Board.log_event(repository.id, kind, "##{pull["number"]}", %{
        "reason" => Exception.message(exception)
      })

      nil
  end

  # -- the tickets ------------------------------------------------------------

  defp apply_tickets(repository, issues, client) do
    by_number = Map.new(issues, &{&1["number"], &1})

    tickets =
      AgentState.tickets()
      |> Enum.filter(&AgentState.same_repository?(&1, repository))
      |> Tickets.by_number()

    ReopenedTickets.reconcile(client, repository, by_number, tickets)

    Enum.each(tickets, fn {number, ticket} ->
      case Tickets.state(ticket,
             workpad: fn -> Board.agent_workpad(repository.id, number) end,
             asked?: fn -> Board.agent_asked?(repository.id, number) end
           ) do
        nil ->
          :ok

        overlay ->
          apply_overlay(repository, by_number[number], number, overlay, ticket)
      end
    end)
  end

  defp apply_overlay(repository, issue, number, overlay, ticket) do
    if issue && not (issue["state"] == "closed" and overlay != "done") do
      TicketOverlay.apply(repository, number, overlay, ticket["started_at"],
        include_finished: true,
        ended_at: ticket["ended_at"]
      )
    end
  end

  defp checks_changed_at(_existing, nil, _now), do: nil

  defp checks_changed_at(nil, _checks_state, now), do: now

  defp checks_changed_at(%PullRequest{checks_state: checks_state} = existing, checks_state, _now),
    do: existing.checks_changed_at

  defp checks_changed_at(_existing, _checks_state, now), do: now

  @doc "The strongest review state."
  def review_rollup(reviews) do
    states =
      reviews
      |> Enum.map(&String.downcase(&1["state"] || ""))
      |> Enum.reject(&(&1 == ""))
      |> MapSet.new()

    cond do
      MapSet.member?(states, "changes_requested") -> "changes_requested"
      MapSet.member?(states, "approved") -> "approved"
      MapSet.size(states) > 0 -> "pending"
      true -> "none"
    end
  end

  @doc "The CI result and the failing check names."
  def checks_rollup(checks) do
    case checks_failed(checks) do
      "" ->
        if Enum.any?(checks, &(&1["status"] in ["queued", "in_progress"])),
          do: {"pending", ""},
          else: {if(checks == [], do: "none", else: "success"), ""}

      failed ->
        {"failure", failed}
    end
  end

  defp checks_failed(checks) do
    checks
    |> Enum.filter(&(&1["conclusion"] in ["failure", "timed_out", "cancelled"]))
    |> Enum.map_join(", ", &(&1["name"] || "check"))
  end

  defp to_dt(nil), do: nil

  defp to_dt(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
