defmodule AgentBoard.Lanes do
  @moduledoc """
  The board's reading lanes, built only from rows the board observed.

  A missing field becomes an omitted sentence, never a fabricated one: the
  activity step, the PR stats and the executor's internal log are not stored
  here, so they do not appear.
  """

  use Gettext, backend: AgentBoardWeb.Gettext

  import Ecto.Query, warn: false

  alias AgentBoard.{
    Actions,
    AgentBlock,
    AgentSignal,
    Board,
    Release,
    Repo,
    Superagents,
    Time
  }

  alias AgentBoard.Board.PullRequest

  alias AgentBoard.Lanes.{
    Attention,
    CallStatus,
    CI,
    Digest,
    MergeHistory,
    Queue,
    ReportQuote,
    RunTiming
  }

  alias AgentBoard.Usage.TaskCosts
  alias AgentBoardWeb.Locale

  @queue_limit 8

  @doc """
  The attention list: blocked work, silent runs, PRs for review and
  questions, in that order. Merged work is done and its CI lives in
  Mesclados, where a failed GitHub check is quiet and the local gate is the
  evidence that counts.

  A silence (`:silences`, from `AgentBoard.AgentSignal`) is derived, never a
  task state: a running task is the owner's only while its ticket has given
  no signal for `:stall_after` seconds.

  A long run (`slow_after/1`) is derived the same way and asks nothing: a
  running task past the time its size allows is listed last, as a heads-up,
  while it still gives signals. Once it goes silent the silence is the item.

  A failed ticket says what happened and what is left to the owner
  (`AgentBoard.AgentBlock`). With `agent: :down` (the orchestrator did not
  answer) the blocks and silences collapse into one `:agent_down` item:
  they all wait for the same thing.

  A call nobody answered is derived too (`CallStatus.unanswered?/2`): the mention is
  what starts the runner, and a comment that landed is not a start. The
  runner may have been down, or have routed the call to another ticket; the
  board only knows that no ticket names the issue, and says that.
  """
  def needs(repository, board, opts \\ []) do
    context = board |> context(opts) |> Map.put(:repository, repository)

    [
      lane(board, :blocked, :blocked, context),
      silent_lane(board, context),
      unanswered_lane(board, context),
      lane(board, :ready, :review, context),
      lane(board, :question, :question, context),
      slow_lane(board, context)
    ]
    |> List.flatten()
    |> collapse_agent_down(board, context)
    |> Attention.sort()
  end

  defp collapse_agent_down(needs, board, %{agent: :down} = context) do
    {waiting_count, rest} = Attention.outage_summary(needs, length(Map.get(board, :retrying, [])))
    [agent_down_need(waiting_count, context) | rest]
  end

  defp collapse_agent_down(needs, _board, _context), do: needs

  defp agent_down_need(waiting, context) do
    # The board read this repository's own superagent when it has one: that
    # is the agent the button starts, not the primary.
    superagent =
      context.repository |> Superagents.get_by_repository() |> Repo.preload(:repository)

    tail =
      case waiting do
        0 ->
          gettext("Nothing moves until it is back.")

        n ->
          ngettext(
            "%{count} task waits for it to come back; network failures are retried on their own.",
            "%{count} tasks wait for it to come back; network failures are retried on their own.",
            n
          )
      end

    %{
      key: "agent-down",
      id: nil,
      number: nil,
      kind: :agent_down,
      title: gettext("No new task starts until it is back"),
      why: gettext("**The orchestrator is not responding.**") <> " " <> tail,
      ci: nil,
      age_seconds: nil,
      is_new: false,
      waiting: waiting,
      actions: [
        %{label: gettext("Restart the agent"), restart_agent: true, superagent: superagent}
      ]
    }
  end

  @doc """
  The failed tasks the board retries by itself, for Agora: nobody has to
  act, so they are not in Precisa de você. Each row says what failed and
  when the next attempt goes out.
  """
  def retrying(board, opts \\ []) do
    context = context(board, opts)

    for task <- Map.get(board, :retrying, []) do
      block = AgentBlock.explain(Map.get(context.tickets, task.number), block_opts(context))

      %{
        id: task.id,
        number: task.number,
        title: task.title,
        line: (block && block.line) || gettext("**Automatic retry.** Waiting for the agent.")
      }
    end
  end

  defp block_opts(context),
    do: [now: context.now, tz_offset: context.tz_offset, agent: context.agent]

  defp context(board, opts) do
    tickets = Keyword.get(opts, :tickets_by_number, %{})

    %{
      now: Keyword.get(opts, :now, DateTime.utc_now()),
      last_visit: Keyword.get(opts, :last_visit),
      tz_offset: Keyword.get(opts, :tz_offset, 0),
      tickets: tickets,
      pulls: Board.linked_pull_requests(Map.get(board, :ready, []), tickets),
      local_ci: Keyword.get(opts, :local_ci, %{}),
      silences: Keyword.get(opts, :silences, %{}),
      stall_after: Keyword.get(opts, :stall_after, AgentSignal.stall_after()),
      agent: Keyword.get(opts, :agent, :unknown)
    }
  end

  defp lane(board, key, kind, context),
    do: board |> Map.get(key, []) |> Enum.map(&task_need(&1, kind, context))

  defp silent_lane(board, context) do
    board
    |> Map.get(:running, [])
    |> Enum.filter(&AgentSignal.stalled?(context.silences[&1.number], context.stall_after))
    |> Enum.map(&task_need(&1, :stalled, context))
  end

  defdelegate slow_after(size), to: RunTiming
  defdelegate working_since(task), to: RunTiming
  defdelegate slow_at(task), to: RunTiming
  defdelegate slow?(task, now), to: RunTiming

  defdelegate next_attention_in(running, silences, stall_after, now), to: RunTiming

  defp slow_lane(board, context) do
    board
    |> Map.get(:running, [])
    |> Enum.reject(&AgentSignal.stalled?(context.silences[&1.number], context.stall_after))
    |> Enum.filter(&slow?(&1, context.now))
    |> Enum.map(&task_need(&1, :slow, context))
  end

  defp unanswered_lane(board, context) do
    board
    |> Map.get(:queued, [])
    |> Enum.filter(&(not is_nil(CallStatus.problem(&1, context))))
    |> Enum.map(&task_need(&1, :unanswered, context))
  end

  # Every item says what to do, where and why: the kind is the what, the
  # actions are the where, and `why` is the evidence the board has. A fact
  # the board cannot see is said to be missing, never filled in.
  defp task_need(task, kind, context) do
    at = Attention.started_at(task, kind, context)
    ticket = Map.get(context.tickets, task.number)
    pull = Map.get(context.pulls, task.id)
    ci = pull && CI.Badge.describe(pull, Map.get(context.local_ci, pull.number))

    %{
      key: "task-#{task.id}",
      id: task.id,
      number: task.number,
      kind: kind,
      title: task.title,
      why: task_why(task, kind, ticket, pull, context),
      ci: ci,
      pull_number: pull && pull.number,
      age_seconds: Time.age_seconds(at, context.now),
      is_new: Time.new_since?(at, context.last_visit),
      actions: need_actions(task, kind, pull, context)
    }
  end

  defp task_why(%{held: true, released_at: at}, :unanswered, _ticket, _pull, context) do
    gettext(
      "**The call to the agent did not complete.** The board tried %{since} and does not try again on its own.",
      since: Time.since_label(at, context.tz_offset, context.now)
    )
  end

  # What the board knows: it called, and no ticket names the issue. Why the
  # runner did not start is in the runner, so the item does not guess.
  defp task_why(task, :unanswered, _ticket, _pull, context) do
    at = Release.called_at(task)

    gettext(
      "**Called %{ago} and the agent did not start.** The board posted the mention %{since} and no agent ticket names this issue.",
      ago: Time.ago(DateTime.diff(context.now, at)),
      since: Time.since_label(at, context.tz_offset, context.now)
    )
  end

  defp task_why(_task, :review, _ticket, %PullRequest{number: number}, _context),
    do: gettext("**PR #%{number} ready for review**", number: number)

  defp task_why(_task, :review, ticket, nil, _context) do
    case ReportQuote.summary(ticket && ticket["report_summary"]) do
      summary when is_binary(summary) ->
        gettext("**Ready for review**, PR not identified. The agent said: %{summary}",
          summary: summary
        )

      _ ->
        gettext("**Ready for review**, PR not identified by the board. Open the conversation.")
    end
  end

  defp task_why(task, :question, ticket, _pull, _context) do
    question = Board.agent_question(task.repository_id, task.number)
    summary = ticket && ticket["report_summary"]

    case ReportQuote.question(question, summary) do
      nil ->
        gettext("**The agent is waiting for your answer.** Open the conversation and reply.")

      quote ->
        gettext("**The agent asked:** %{question}", question: quote)
    end
  end

  defp task_why(task, :blocked, ticket, pull, context) do
    case AgentBlock.explain(ticket, block_opts(context)) do
      %{line: line} -> line
      nil -> blockage_why(task, ticket, pull, context)
    end
  end

  # The item says what the board saw last and when; it never says the agent
  # died. A long model turn with no file change is a silence too.
  defp task_why(task, :stalled, _ticket, _pull, context) do
    silence = Map.fetch!(context.silences, task.number)
    since = Time.local_time(silence.at, context.tz_offset)

    gettext("**Last signal %{ago}.**", ago: Time.ago(silence.seconds)) <>
      " " <> silence_source(silence.source, since)
  end

  # A heads-up, not a verdict: how long, the limit that made it one, and the
  # last signal when the board has one. It never says the agent is stuck.
  defp task_why(task, :slow, _ticket, _pull, context) do
    since = working_since(task)
    limit = div(slow_after(task.size), 60)

    [
      gettext("**Working since %{time} (%{ago}).**",
        time: Time.local_time(since, context.tz_offset),
        ago: Time.ago(Time.age_seconds(since, context.now))
      ),
      slow_limit(task.size, limit),
      case context.silences[task.number] do
        %{seconds: seconds} -> gettext("Last signal %{ago}.", ago: Time.ago(seconds))
        nil -> nil
      end
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  # A block the agent reported itself (a workpad Bloqueio, a `blocked`
  # report): its own words.
  defp blockage_why(task, ticket, _pull, _context) do
    blockage = Board.agent_blockage(task.repository_id, task.number)
    summary = ticket && ticket["report_summary"]

    case ReportQuote.blockage(blockage, summary) do
      nil ->
        gettext("**Blocked**, with no reason in the agent's report. Open the details.")

      quote ->
        gettext("**Blocked:** %{reason}", reason: quote)
    end
  end

  defp silence_source(:report, since),
    do:
      gettext("The agent's last report was at %{time}; no signal in the worktree since then.",
        time: since
      )

  defp silence_source(:answer, since),
    do: gettext("The agent read your answer at %{time}; no signal since then.", time: since)

  defp silence_source(:worktree, since),
    do:
      gettext("The last change in the worktree was at %{time}; no report after it.", time: since)

  defp silence_source(:start, since),
    do:
      gettext(
        "It started at %{time} and has given no signal since: no report and no change in the worktree.",
        time: since
      )

  defp need_actions(task, :review, %PullRequest{url: url, number: number}, _context)
       when is_binary(url) do
    [
      %{label: action_label(:review), task_id: task.id},
      %{label: gettext("Open PR #%{number}", number: number), url: url}
    ]
  end

  # The same red action as the tree's "Chamar o agente", with its sentence.
  defp need_actions(task, :unanswered, _pull, %{repository: repository}) do
    phrase =
      Actions.phrase(:release_task, %{task: task, repository: repository}, Locale.language())

    [
      %{label: gettext("Call again"), release: phrase},
      %{label: action_label(:unanswered), task_id: task.id}
    ]
  end

  # A failure with an attempt left to ask for gets the button on the card,
  # the same one as the detail's (`AgentBoard.AgentBlock`).
  defp need_actions(task, :blocked, _pull, context) do
    detail = %{label: action_label(:blocked), task_id: task.id}

    case AgentBlock.explain(Map.get(context.tickets, task.number), block_opts(context)) do
      %{retry: label, ticket_id: ticket_id} when is_binary(label) and is_binary(ticket_id) ->
        retry = %{ticket_id: ticket_id, repository_id: task.repository_id, number: task.number}
        [%{label: label, retry: retry}, detail]

      _no_retry ->
        [detail]
    end
  end

  defp need_actions(task, kind, _pull, _context),
    do: [%{label: action_label(kind), task_id: task.id}]

  defp action_label(:review), do: gettext("Review")
  defp action_label(:question), do: gettext("Respond")
  defp action_label(:blocked), do: gettext("View details")
  defp action_label(:stalled), do: gettext("View details")
  defp action_label(:unanswered), do: gettext("View details")
  defp action_label(:slow), do: gettext("View details")

  defp slow_limit("S", limit),
    do: gettext("A small task is flagged after %{count} min.", count: limit)

  defp slow_limit("M", limit),
    do: gettext("A medium task is flagged after %{count} min.", count: limit)

  defp slow_limit("L", limit),
    do: gettext("A large task is flagged after %{count} min.", count: limit)

  defp slow_limit(_size, limit),
    do: gettext("A task without a size is flagged after %{count} min.", count: limit)

  @doc """
  The queue, numbered in arrival order. A title that repeats a merged PR gets
  the warning; an unknown origin is omitted instead of invented.
  """
  def queue(repository, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    last_visit = Keyword.get(opts, :last_visit)
    filter = Keyword.get(opts, :filter, :all)
    limit = Keyword.get(opts, :limit, @queue_limit)

    calls = %{
      now: now,
      tickets: Keyword.get(opts, :tickets_by_number, %{}),
      stall_after: Keyword.get(opts, :stall_after, AgentSignal.stall_after())
    }

    observed = Queue.Observations.load(repository)

    items = Enum.map(observed.rows, &Queue.Item.build(&1, observed, calls, last_visit))

    page = Queue.page(items, filter, limit)
    Map.put(page, :filters, filters(page.counts))
  end

  defp filters(%{all: all}) when all <= @queue_limit, do: []

  defp filters(counts) do
    [
      {gettext("All"), counts.all},
      {pgettext("queue filter", "New"), counts.new},
      {pgettext("queue filter", "Split"), counts.split},
      {gettext("Possible repeats"), counts.dupes}
    ]
  end

  @doc "Seven days of merges: the dots, the day counts and the per-day record."
  def merge_log(repository, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    offset = Keyword.get(opts, :tz_offset, 0)
    local_ci = Keyword.get(opts, :local_ci, %{})
    %{today: today, dates: dates, since: since} = MergeHistory.window(now, offset)

    pulls =
      Repo.all(
        from p in PullRequest,
          where:
            p.repository_id == ^repository.id and p.state == "merged" and
              p.merged_at >= ^since,
          order_by: [desc: p.merged_at, desc: p.id]
      )

    by_day = Enum.group_by(pulls, &Time.local_date(&1.merged_at, offset))

    pages = Map.new(by_day, fn {date, rows} -> {date, MergeHistory.day_page(rows)} end)

    costs =
      pages
      |> Enum.flat_map(fn {_date, page} -> page.items ++ page.extra end)
      |> TaskCosts.for_pulls()

    days =
      Enum.map(dates, fn date ->
        day_pulls = Map.get(by_day, date, [])

        day_pulls
        |> MergeHistory.day_totals(local_ci)
        |> Map.merge(%{date: date, label: Time.day_label(date, today), today: date == today})
      end)

    groups =
      days
      |> Enum.reverse()
      |> Enum.reject(&(&1.n == 0))
      |> Enum.map(fn day ->
        page = Map.fetch!(pages, day.date)

        %{
          date: day.date,
          label: day.label,
          n: day.n,
          more: page.more,
          more_wide: page.more_wide,
          items: Enum.map(page.items, &merged_pr(&1, offset, local_ci, costs)),
          extra: Enum.map(page.extra, &merged_pr(&1, offset, local_ci, costs))
        }
      end)

    %{
      days: days,
      groups: groups,
      total: Enum.sum(Enum.map(days, & &1.n)),
      issues: delivered(pulls)
    }
  end

  @doc """
  The issues the PRs delivered: each issue a merged PR closes (`Closes #n`),
  once however many PRs closed it. A PR that closes nothing delivers no issue.
  """
  defdelegate delivered(pulls), to: MergeHistory

  @doc """
  How a pull's CI reads, the local gate first: `{state, note, title}`. One
  wording for every list of merged pulls (the merge log and History).
  """
  def ci(pull, local_ci) do
    badge = CI.Badge.describe(pull, Map.get(local_ci, pull.number))
    {badge.state, badge.note, badge.title}
  end

  defp merged_pr(pull, offset, local_ci, costs) do
    badge = CI.Badge.describe(pull, Map.get(local_ci, pull.number))

    %{
      id: pull.id,
      number: pull.number,
      title: pull.title,
      url: pull.url,
      closes: pull.closes_issues || [],
      ci: badge.state,
      ciNote: badge.note,
      ciTitle: badge.title,
      ciLocal: badge.local,
      review: review_label(pull.review_state),
      at: Time.local_time(pull.merged_at, offset),
      cost: Map.get(costs, pull.number)
    }
  end

  defp review_label("approved"), do: gettext("approved")
  defp review_label("changes_requested"), do: gettext("changes requested")
  defp review_label("pending"), do: gettext("review pending")
  defp review_label(_state), do: gettext("no review")

  @doc """
  The one-sentence digest. Since the previous visit when there is one; the
  current state on a first visit; the saved state when the board is frozen.
  """
  def digest(repository, board, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    last_visit = Keyword.get(opts, :last_visit)
    offset = Keyword.get(opts, :tz_offset, 0)
    frozen_at = Keyword.get(opts, :frozen_at)
    frozen? = Keyword.get(opts, :frozen, not is_nil(frozen_at))

    if is_nil(last_visit) do
      first_digest(board, now, offset, frozen_at, frozen?)
    else
      since_digest(repository, board, last_visit, now, offset, frozen_at, frozen?)
    end
  end

  defp first_digest(board, now, offset, frozen_at, frozen?) do
    case Digest.first_visit(board) do
      [] ->
        nil

      facts ->
        %{
          prefix: first_prefix(frozen?, frozen_at, offset),
          segments: facts |> Enum.map(&first_phrase/1) |> Digest.Sentence.join(gettext("and")),
          suffix: (frozen? && " " <> gettext("After that, we do not know.")) || ".",
          now: now
        }
    end
  end

  defp first_phrase({:running, n}),
    do: %{text: gettext("%{count} running", count: n), role: :agent}

  defp first_phrase({:retrying, n}),
    do: %{text: gettext("%{count} in automatic retry", count: n), role: :agent}

  defp first_phrase({:waiting, n}),
    do: %{text: ngettext("%{count} waiting for you", "%{count} waiting for you", n), role: :you}

  defp first_phrase({:blocked, n}),
    do: %{text: pngettext("digest", "%{count} blocked", "%{count} blocked", n), role: :halt}

  defp first_phrase({:queued, n}),
    do: %{text: gettext("%{count} in the queue", count: n), role: :agent}

  defp since_digest(repository, board, last_visit, now, offset, frozen_at, frozen?) do
    %{counts: counts, latest_review: review} = Digest.Observations.since(repository, last_visit)
    phrases = board |> Digest.since_visit(counts) |> Enum.map(&change_phrase(&1, review))

    segments =
      if phrases == [] do
        [
          %{
            text:
              if(frozen? and is_nil(frozen_at),
                do: gettext("we do not know what changed"),
                else: gettext("nothing changed")
              ),
            role: :plain
          }
        ]
      else
        Digest.Sentence.join(phrases, gettext("and"))
      end

    suffix =
      if frozen? and is_nil(frozen_at), do: ".", else: since_suffix(phrases, frozen?)

    %{
      prefix: since_prefix(last_visit, offset, frozen_at, frozen?, now),
      segments: segments,
      suffix: suffix,
      now: now
    }
  end

  defp first_prefix(true, %DateTime{} = frozen_at, offset),
    do: gettext("Until %{time}:", time: Time.local_time(frozen_at, offset)) <> " "

  defp first_prefix(true, nil, _offset), do: gettext("Without a completed sync:") <> " "
  defp first_prefix(false, _frozen_at, _offset), do: gettext("First visit:") <> " "

  defp since_prefix(_last_visit, offset, %DateTime{} = frozen_at, true, _now),
    do: gettext("Until %{time},", time: Time.local_time(frozen_at, offset)) <> " "

  defp since_prefix(_last_visit, _offset, nil, true, _now),
    do: gettext("Without a completed sync,") <> " "

  defp since_prefix(last_visit, offset, nil, false, now),
    do: gettext("Since %{since}", since: Time.since_label(last_visit, offset, now)) <> " "

  defp since_suffix(_phrases, true), do: ". " <> gettext("After that, we do not know.")
  defp since_suffix(_phrases, false), do: "."

  defp change_phrase({:questions, n}, _pr) do
    %{text: ngettext("it asked %{count} question", "it asked %{count} questions", n), role: :you}
  end

  defp change_phrase({:queue_new, n}, _pr) do
    %{text: ngettext("%{count} new in the queue", "%{count} new in the queue", n), role: :agent}
  end

  defp change_phrase({:merged, merged}, _pr) do
    text = ngettext("the agent merged %{count} PR", "the agent merged %{count} PRs", merged)
    %{text: text, role: :agent}
  end

  defp change_phrase({:reviews, n}, pr) do
    %{
      text: ngettext("it opened %{count} PR for review", "it opened %{count} PRs for review", n),
      role: :you,
      url: pr && pr.url
    }
  end

  defp change_phrase({:running, {:task, id, number}}, _pr) do
    %{
      text: gettext("it is working on #%{number}", number: number),
      role: :agent,
      task_id: id
    }
  end

  defp change_phrase({:running, n}, _pr) do
    %{text: gettext("it is working on %{count} tasks", count: n), role: :agent}
  end

  defp change_phrase({:blocked, {:task, id, number}}, _pr) do
    %{
      text: gettext("#%{number} is still blocked", number: number),
      role: :halt,
      task_id: id
    }
  end

  defp change_phrase({:blocked, n}, _pr) do
    %{text: gettext("%{count} are still blocked", count: n), role: :halt}
  end
end
