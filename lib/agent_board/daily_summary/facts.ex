defmodule AgentBoard.DailySummary.Facts do
  @moduledoc """
  What the summary of the day says, collected once from records the board
  already holds, for the window `[since, until)`. Nothing is estimated here
  except the executor's cost, which `AgentBoard.Usage.Harness` already marks
  as an estimate; a source the board cannot read is `"unknown"`, never zero.

  The map has string keys (it is stored as JSON in `daily_summaries`):

    * `"merged"`: `%{"count", "items"}`, pull requests merged in the window
      (GitHub's `merged_at`), newest first, at most five items;
    * `"needs"`: `%{"blocked", "waiting", "items"}`, what needs the owner at
      generation time (blocked; questions and reviews whose PR is still
      open), stopped and archived tasks left out, at most three items;
    * `"sync_errors"`: `sync_error` events in the window;
    * `"retries"`: `%{"sent", "tasks", "not_accepted"}`, the automatic
      retries the board asked for in the window (`agent_retries`);
    * `"spend"`: one line per executor, never summed: DeepSeek from the
      harness transcripts (US$, estimated), Claude Code from the usage ledger
      (US$ at the Max subscription's list price, a reference and not a bill;
      its quota is unknown) and Codex from the ledger plus its newest weekly
      quota reading (percentage of the window, no US$).
  """

  import Ecto.Query, warn: false

  alias AgentBoard.AutoRetry.Attempt
  alias AgentBoard.Board
  alias AgentBoard.Board.{Event, PullRequest, Repository, Task}
  alias AgentBoard.Repo
  alias AgentBoard.Usage.Harness
  alias AgentBoard.Usage.Report

  @merged_items 5
  @need_items 3

  @doc """
  The facts for the window. `:spend` is the DeepSeek reader, a function of
  `(since, until)` returning an `Usage.Harness` reading (default
  `Harness.window/2`); `:usage` reads the ledger's spend for Claude Code
  and Codex (default `Report.spend_window/2`).
  """
  @spec collect(DateTime.t(), DateTime.t(), keyword()) :: map()
  def collect(since, until, opts \\ []) do
    reader = Keyword.get(opts, :spend, &Harness.window/2)
    usage_reader = Keyword.get(opts, :usage, &Report.spend_window/2)
    usage = usage_reader.(since, until)

    %{
      "merged" => merged(since, until),
      "needs" => needs(),
      "sync_errors" => sync_errors(since, until),
      "retries" => retries(since, until),
      "spend" => [
        deepseek(reader.(since, until)),
        claude(Map.get(usage, "claude_code")),
        codex(Map.get(usage, "codex"))
      ]
    }
  end

  defp merged(since, until) do
    pulls =
      Repo.all(
        from p in PullRequest,
          join: r in Repository,
          on: r.id == p.repository_id,
          where: p.state == "merged" and p.merged_at >= ^since and p.merged_at < ^until,
          order_by: [desc: p.merged_at, desc: p.id],
          select: %{number: p.number, title: p.title, url: p.url, owner: r.owner, name: r.name}
      )

    %{
      "count" => length(pulls),
      "items" =>
        pulls
        |> Enum.take(@merged_items)
        |> Enum.map(fn pull ->
          %{
            "repo" => "#{pull.owner}/#{pull.name}",
            "number" => pull.number,
            "title" => pull.title,
            "url" => pull.url
          }
        end)
    }
  end

  defp needs do
    tasks =
      Repo.all(
        from t in Task,
          join: r in assoc(t, :repository),
          where:
            t.state in ["blocked", "question", "ready"] and t.stopped == false and
              t.archived == false,
          order_by: [asc: t.state_changed_at, asc: t.id],
          preload: [repository: r]
      )

    # A review whose PR was already merged is done, as on the board.
    resolved = tasks |> Enum.filter(&(&1.state == "ready")) |> Board.resolved_task_ids()
    tasks = Enum.reject(tasks, &MapSet.member?(resolved, &1.id))
    {blocked, waiting} = Enum.split_with(tasks, &(&1.state == "blocked"))

    %{
      "blocked" => length(blocked),
      "waiting" => length(waiting),
      "items" =>
        (blocked ++ waiting)
        |> Enum.take(@need_items)
        |> Enum.map(fn task ->
          %{
            "repo" => "#{task.repository.owner}/#{task.repository.name}",
            "number" => task.number,
            "title" => task.title,
            "state" => task.state,
            "url" => task.url
          }
        end)
    }
  end

  defp sync_errors(since, until) do
    Repo.aggregate(
      from(e in Event,
        where: e.kind == "sync_error" and e.inserted_at >= ^since and e.inserted_at < ^until
      ),
      :count
    )
  end

  defp retries(since, until) do
    attempts =
      Repo.all(
        from a in Attempt,
          where: a.inserted_at >= ^since and a.inserted_at < ^until,
          select: {a.ticket_id, a.outcome}
      )

    %{
      "sent" => length(attempts),
      "tasks" => attempts |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length(),
      "not_accepted" => Enum.count(attempts, fn {_t, o} -> o not in ["retried", "sending"] end)
    }
  end

  # The harness transcripts: tokens measured, cost estimated in US$ from the
  # board's price table. A reading with no request in the window means the
  # executor did not run; an unreadable file makes the cost a minimum.
  # A window whose only transcripts were unreadable is unknown, not "did
  # not run": a missing file is not an empty day.
  defp deepseek(%{status: :measured, requests: 0, unreadable: unreadable})
       when is_integer(unreadable) and unreadable > 0,
       do: %{"executor" => "deepseek", "status" => "unknown", "reason" => "unreadable"}

  defp deepseek(%{status: :measured, requests: 0}),
    do: %{"executor" => "deepseek", "status" => "none"}

  defp deepseek(%{status: :measured, cost: %{micros: micros, complete?: complete}} = reading) do
    %{
      "executor" => "deepseek",
      "status" => "measured",
      "currency" => "USD",
      "micros" => micros,
      "complete" => complete and Map.get(reading, :unreadable, 0) == 0,
      "requests" => reading.requests,
      "models" => reading.models
    }
  end

  defp deepseek(%{status: :measured}),
    do: %{"executor" => "deepseek", "status" => "unknown", "reason" => "no_price"}

  defp deepseek(%{status: :none}), do: %{"executor" => "deepseek", "status" => "none"}

  defp deepseek(reading),
    do: %{
      "executor" => "deepseek",
      "status" => "unknown",
      "reason" => to_string(Map.get(reading, :reason) || "unreadable")
    }

  # Claude Code's US$ is the list price of the Max subscription: estimated
  # from the ledger's tokens, a reference and never the bill. The real quota
  # is not in the files, so it stays unknown.
  defp claude(%{status: :measured, requests: 0}),
    do: %{"executor" => "claude", "status" => "none"}

  defp claude(%{status: :measured, cost: %{micros: micros, complete?: complete?}} = reading) do
    %{
      "executor" => "claude",
      "status" => "measured",
      "currency" => "USD",
      "reference" => "list",
      "quota" => "unknown",
      "micros" => micros,
      "complete" => complete?,
      "requests" => reading.requests,
      "models" => reading.models
    }
  end

  defp claude(%{status: :measured}),
    do: %{"executor" => "claude", "status" => "unknown", "reason" => "no_price"}

  defp claude(%{status: :none}), do: %{"executor" => "claude", "status" => "none"}
  defp claude(nil), do: unknown("claude")

  defp claude(reading) do
    %{
      "executor" => "claude",
      "status" => "unknown",
      "reason" => to_string(Map.get(reading, :reason) || "unreadable")
    }
  end

  # Codex spends the weekly window, not a currency: the line is the share
  # used and when it resets. Without a quota reading it is unknown.
  defp codex(%{quota: %{used_percent: percent, window_minutes: window} = quota} = reading)
       when is_number(percent) do
    %{
      "executor" => "codex",
      "status" => "measured",
      "currency" => "quota",
      "percent" => percent,
      "window_minutes" => window,
      "resets_at" => quota.resets_at && DateTime.to_iso8601(quota.resets_at),
      "requests" => Map.get(reading, :requests, 0)
    }
  end

  defp codex(%{status: :unknown} = reading) do
    %{
      "executor" => "codex",
      "status" => "unknown",
      "reason" => to_string(Map.get(reading, :reason) || "no_quota")
    }
  end

  defp codex(%{quota: nil}),
    do: %{"executor" => "codex", "status" => "unknown", "reason" => "no_quota"}

  defp codex(%{status: :none}), do: %{"executor" => "codex", "status" => "none"}
  defp codex(nil), do: unknown("codex")

  defp codex(_reading),
    do: %{"executor" => "codex", "status" => "unknown", "reason" => "no_quota"}

  defp unknown(executor),
    do: %{"executor" => executor, "status" => "unknown", "reason" => "no_source"}
end
