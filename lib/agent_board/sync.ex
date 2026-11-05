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

  alias AgentBoard.{Board, GitHub, Repo}
  alias AgentBoard.Board.{PullRequest, Repository, Review, Task}

  @state_db "/state/superagent/orchestrator.sqlite"

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

  defp active_tasks(repository_id) do
    Repo.all(
      from(t in Task,
        where: t.repository_id == ^repository_id and t.state in ["running", "ready", "queued"],
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
      checks_failed: checks_failed
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
    case ticket_state(ticket) do
      nil ->
        :ok

      overlay ->
        Enum.each(ticket["numbers"], &apply_overlay(repository, by_number[&1], &1, overlay))
    end
  end

  defp apply_overlay(repository, issue, number, overlay) do
    if issue && not (issue["state"] == "closed" and overlay != "done") do
      Repo.update_all(
        from(t in Task,
          where:
            t.repository_id == ^repository.id and t.number == ^number and
              not t.stopped and not t.archived
        ),
        set: [state: overlay, updated_at: DateTime.utc_now()]
      )
    end
  end

  @doc "The state a ticket imposes on the task, or nil to keep the issue baseline."
  def ticket_state(ticket) do
    cond do
      ticket["stopped"] || ticket["archived"] -> nil
      ticket["assignment"] == "running" -> "running"
      ticket["report"] == "ready" -> "ready"
      ticket["report"] == "blocked" or ticket["assignment"] == "blocked" -> "blocked"
      ticket["ended_outcome"] == "merged" -> "done"
      true -> nil
    end
  end

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
  def normalized_tickets do
    state_db()
    |> Enum.flat_map(fn value ->
      case Jason.decode(value) do
        {:ok, ticket} -> [normalize(ticket)]
        _ -> []
      end
    end)
  end

  defp normalize(ticket) do
    numbers = ticket_numbers(ticket)
    last = List.last(ticket["assignments"] || []) || %{}
    report = last["report"] || %{}
    ended = ticket["ended"] || %{}

    %{
      "numbers" => Enum.uniq(numbers),
      "assignment" => last["state"],
      "report" => report["state"],
      "ended_outcome" => ended["outcome"],
      "stopped" => ticket["stopped"] || false,
      "archived" => ticket["archived"] || false
    }
  end

  def ticket_numbers_for(ticket), do: ticket_numbers(ticket)

  defp ticket_numbers(ticket) do
    scope = get_in(ticket, ["mandate", "basis", "scope"]) || %{}
    base = if is_integer(scope["number"]), do: [scope["number"]], else: []

    # The parens matter: |> binds tighter than ||, so without them the
    # pipeline would apply only to the [] fallback and leave the real channel
    # entries unmapped (numbers as maps instead of integers).
    base ++
      ((ticket["channels"] || [])
       |> Enum.map(&to_int(get_in(&1, ["address", "number"])))
       |> Enum.reject(&is_nil/1))
  end

  defp state_db do
    path = Application.get_env(:agent_board, :state_db, @state_db)

    case Exqlite.Sqlite3.open(path) do
      {:ok, conn} ->
        result =
          case Exqlite.Sqlite3.prepare(conn, "SELECT value FROM ticket") do
            {:ok, stmt} ->
              rows = read_rows(conn, stmt, [])
              Exqlite.Sqlite3.release(conn, stmt)
              rows

            {:error, _} ->
              []
          end

        Exqlite.Sqlite3.close(conn)
        result

      {:error, _} ->
        []
    end
  end

  defp read_rows(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [value]} -> read_rows(conn, stmt, [value | acc])
      _ -> Enum.reverse(acc)
    end
  end

  defp to_int(nil), do: nil
  defp to_int(n) when is_integer(n), do: n
  defp to_int(s) when is_binary(s), do: String.to_integer(s)
  defp to_int(_), do: nil

  defp to_dt(nil), do: nil

  defp to_dt(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
