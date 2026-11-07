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

  alias AgentBoard.{AgentState, Board, GitHub, Repo}
  alias AgentBoard.Board.{PullRequest, Repository, Review, Task}

  @doc "Sync every active repository. Returns how many it touched."
  def all(client \\ GitHub.client()) do
    Repo.all(from r in Repository, where: r.active)
    |> Enum.map(&sync_repo(client, &1))
    |> length()
  end

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
      Board.log_event(repository.id, "sync_error", "#{repository.owner}/#{repository.name}", %{
        "reason" => Exception.message(exception)
      })

      Board.broadcast(repository.id)
      {:error, exception}
  end

  defp do_sync(client, repository) do
    # A repository can have Issues disabled (404). That is not a sync failure:
    # the pulls still matter.
    issues =
      try do
        GitHub.issues(client, repository.owner, repository.name)
      rescue
        exception ->
          Board.log_event(
            repository.id,
            "issues_unavailable",
            "#{repository.owner}/#{repository.name}",
            %{
              "reason" => Exception.message(exception)
            }
          )

          []
      end

    pulls = GitHub.pulls(client, repository.owner, repository.name)

    Enum.each(issues, &upsert_issue(repository, &1))
    # One broken PR (reviews, checks) must not kill the whole sync.
    Enum.each(pulls, fn pull ->
      try do
        upsert_pull(client, repository, pull)
      rescue
        exception ->
          Board.log_event(repository.id, "pull_error", "##{pull["number"]}", %{
            "reason" => Exception.message(exception)
          })
      end
    end)

    apply_tickets(repository, issues)
    sync_comments(repository, client)
    Board.reconcile_resolved_tasks(repository)

    Board.log_event(repository.id, "sync", "#{repository.owner}/#{repository.name}", %{
      "issues" => length(issues),
      "pulls" => length(pulls),
      "errors" => error_count(repository)
    })

    Board.broadcast(repository.id)
  end

  # The events written by one sync run. A single query keeps the summary
  # honest without threading counters through every branch.
  defp error_count(repository) do
    Repo.aggregate(
      from(e in AgentBoard.Board.Event,
        where:
          e.repository_id == ^repository.id and
            e.kind in ["issue_error", "pull_error", "comment_error"]
      ),
      :count
    )
  end

  # -- the conversation -------------------------------------------------------

  defp sync_comments(repository, client) do
    agent_login = Application.get_env(:agent_board, :agent_login, "sallaumen-agent")

    repository.id
    |> active_tasks()
    |> Enum.each(fn task ->
      # One broken conversation must not kill the whole sync.
      try do
        case AgentBoard.GitHub.issue_comments(
               client,
               repository.owner,
               repository.name,
               task.number
             ) do
          comments when is_list(comments) ->
            Enum.each(comments, &Board.upsert_comment(task, &1, agent_login))

          _ ->
            :ok
        end
      rescue
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
  @conversation_states ["running", "ready", "queued", "question", "blocked"]

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

  defp upsert_issue(repository, issue) do
    closed = issue["state"] == "closed"

    %Task{repository_id: repository.id, kind: "issue", number: issue["number"]}
    |> Task.changeset(%{
      title: issue["title"],
      body: String.slice(issue["body"] || "", 0, 4000),
      state: if(closed, do: "done", else: "queued"),
      state_changed_at: DateTime.utc_now(),
      url: issue["html_url"],
      author: get_in(issue, ["user", "login"])
    })
    |> Repo.insert(
      on_conflict: {:replace, [:title, :url, :updated_at]},
      conflict_target: [:repository_id, :kind, :number]
    )
    |> case do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Board.log_event(repository.id, "issue_error", "##{issue["number"]}", %{
          "reason" => inspect(changeset.errors)
        })
    end
  end

  # -- the pull requests ------------------------------------------------------

  defp upsert_pull(client, repository, pull) do
    merged = pull["merged_at"] != nil

    state =
      if merged, do: "merged", else: if(pull["state"] == "closed", do: "closed", else: "open")

    {review_state, checks_state, checks_failed} = rollup_for(client, repository, pull, state)
    existing = Repo.get_by(PullRequest, repository_id: repository.id, number: pull["number"])
    now = DateTime.utc_now()
    checks_changed_at = checks_changed_at(existing, checks_state, now)

    %PullRequest{repository_id: repository.id, number: pull["number"]}
    |> PullRequest.changeset(%{
      title: pull["title"],
      state: state,
      url: pull["html_url"],
      author: get_in(pull, ["user", "login"]),
      opened_at: to_dt(pull["created_at"]),
      merged_at: to_dt(pull["merged_at"]),
      review_state: review_state,
      checks_state: checks_state,
      checks_failed: checks_failed,
      checks_changed_at: checks_changed_at
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

  # Merged and closed pulls also carry reviews and checks: the board shows
  # them in the merged column, so they must be fetched, not left nil.
  defp rollup_for(client, repository, pull, _state) do
    # An old merged pull never changes: skipping its reviews and checks saves
    # ~2 API calls per pull per sync (a 100-PR repo was hitting the limit).
    if stale?(pull) do
      {nil, nil, nil}
    else
      rollups(client, repository, pull)
    end
  end

  @stale_days 30

  defp stale?(pull) do
    case to_dt(pull["merged_at"]) do
      nil -> false
      merged_at -> DateTime.diff(DateTime.utc_now(), merged_at, :day) > @stale_days
    end
  end

  defp rollups(client, repository, pull) do
    # A failing review/check fetch must not abort the PR insert: the PR is
    # stored with the rollups it can get, and the failure is logged.
    reviews =
      safe_fetch(repository, "review_error", pull, fn ->
        GitHub.reviews(client, repository.owner, repository.name, pull["number"])
      end)

    Enum.each(reviews, &upsert_review(repository, pull["number"], &1))

    checks =
      safe_fetch(repository, "check_error", pull, fn ->
        GitHub.check_runs(
          client,
          repository.owner,
          repository.name,
          get_in(pull, ["head", "sha"]) || ""
        )
      end)

    {checks_state, checks_failed} = checks_rollup(checks)

    {review_rollup(reviews), checks_state, checks_failed}
  end

  defp safe_fetch(repository, kind, pull, fun) do
    fun.()
  rescue
    exception ->
      Board.log_event(repository.id, kind, "##{pull["number"]}", %{
        "reason" => Exception.message(exception)
      })

      []
  end

  defp upsert_review(repository, number, review) do
    pr_id =
      Repo.one(
        from p in PullRequest,
          where: p.repository_id == ^repository.id and p.number == ^number,
          select: p.id
      )

    if pr_id do
      %Review{pull_request_id: pr_id}
      |> Review.changeset(%{
        reviewer: get_in(review, ["user", "login"]) || "unknown",
        state: String.downcase(review["state"] || ""),
        submitted_at: to_dt(review["submitted_at"])
      })
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [:pull_request_id, :reviewer, :submitted_at]
      )
    end
  end

  # -- the tickets ------------------------------------------------------------

  def apply_tickets(repository, issues) do
    by_number = Map.new(issues, &{&1["number"], &1})

    Enum.each(normalized_tickets(), fn ticket ->
      apply_ticket(repository, by_number, ticket)
    end)

    :ok
  end

  defp apply_ticket(repository, by_number, ticket) do
    Enum.each(ticket["numbers"], fn number ->
      case ticket_state(ticket, asked?: fn -> Board.agent_asked?(repository.id, number) end) do
        nil ->
          :ok

        overlay ->
          apply_overlay(repository, by_number[number], number, overlay, ticket["started_at"])
      end
    end)
  end

  defp apply_overlay(repository, issue, number, overlay, started_at) do
    if issue && not (issue["state"] == "closed" and overlay != "done") do
      base =
        from(t in Task,
          where:
            t.repository_id == ^repository.id and t.number == ^number and
              not t.stopped and not t.archived
        )

      now = DateTime.utc_now()

      Repo.update_all(from(t in base, where: t.state != ^overlay),
        set: [state: overlay, state_changed_at: now, updated_at: now]
      )

      if started_at do
        Repo.update_all(
          from(t in base,
            where: is_nil(t.started_at) or t.started_at < ^started_at
          ),
          set: [started_at: started_at]
        )
      end
    end
  end

  defp checks_changed_at(_existing, nil, _now), do: nil

  defp checks_changed_at(nil, _checks_state, now), do: now

  defp checks_changed_at(%PullRequest{checks_state: checks_state} = existing, checks_state, _now),
    do: existing.checks_changed_at

  defp checks_changed_at(_existing, _checks_state, now), do: now

  @doc """
  The state a ticket imposes on the task, or nil to keep the issue baseline.

  A ticket whose PR merged is done, whatever its last report said: the
  runner keeps the `ready` or `waiting` report it ended on, and the merge
  is the newer fact. Nothing else about an ended ticket imposes a state.

  A `waiting` report means the executor needs input, not that it asked a
  question. It is a question only when the report or the newest agent
  comment (`asked?`, a boolean or a function the caller can leave lazy)
  actually asks one; a waiting ticket that opened a PR is a review; anything
  else is a block whose reason is the report itself.
  """
  def ticket_state(ticket, opts \\ []) do
    cond do
      stopped?(ticket) -> nil
      ticket["ended_outcome"] == "merged" -> "done"
      ticket["report"] == "waiting" -> waiting_state(ticket, opts)
      blocked_ticket?(ticket) -> "blocked"
      ticket["report"] == "ready" -> "ready"
      running_ticket?(ticket) -> "running"
      true -> nil
    end
  end

  @pr_mention ~r/(?:\bPR\b|pull request|\/pull\/)\s*#?\s*\d+/i
  @review_word ~r/\b(review|revis(ão|ao|ar|ado|ada))\b/iu

  defp waiting_state(ticket, opts) do
    summary = ticket["report_summary"] || ""

    cond do
      question?(summary) or asked?(opts) -> "question"
      (ticket["own_threads"] || []) != [] or pr_for_review?(summary) -> "ready"
      true -> "blocked"
    end
  end

  @doc "Whether a text asks something: a real question mark, not a mood."
  def question?(text) when is_binary(text), do: String.contains?(text, "?")
  def question?(_text), do: false

  defp pr_for_review?(summary), do: summary =~ @pr_mention and summary =~ @review_word

  defp asked?(opts) do
    case Keyword.get(opts, :asked?, false) do
      fun when is_function(fun, 0) -> fun.() == true
      value -> value == true
    end
  end

  defp stopped?(ticket), do: ticket["stopped"] || ticket["archived"]

  defp blocked_ticket?(ticket),
    do: ticket["report"] in ["blocked", "failed"] or ticket["assignment"] == "blocked"

  defp running_ticket?(ticket),
    do: ticket["assignment"] == "running" and is_nil(ticket["idle_at"])

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

  # -- the agent's tickets (sqlite, read-only) --------------------------------

  @doc "The agent's tickets, normalized: the numbers, the assignment and the outcome."
  def normalized_tickets, do: AgentState.tickets()

  def ticket_numbers_for(ticket), do: AgentState.ticket_numbers(ticket)

  defp to_dt(nil), do: nil

  defp to_dt(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
