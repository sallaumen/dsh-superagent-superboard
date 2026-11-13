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
    Titles,
    Workpad
  }

  alias AgentBoard.Board.{PullRequest, Task, TaskDependency}
  alias AgentBoard.Usage.TaskCosts
  # The locale-aware times: these sentences are read on the screen.
  alias AgentBoardWeb.{Locale, Time}

  @queue_limit 8
  @day_limit 3
  # A wide window shows this many per day; the rows past @day_limit are `extra`.
  @day_reach 8
  @log_days 7

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

  A call nobody answered is derived too (`unanswered?/2`): the mention is
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
    |> Enum.sort_by(fn need ->
      {rank(need.kind), not need.is_new, -(need.age_seconds || 0)}
    end)
  end

  defp collapse_agent_down(needs, board, %{agent: :down} = context) do
    {waiting, rest} =
      Enum.split_with(needs, &(&1.kind in [:blocked, :stalled, :unanswered, :slow]))

    [agent_down_need(length(waiting) + length(Map.get(board, :retrying, [])), context) | rest]
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

  # Minutes of work the owner allows a running task before being told, by
  # size (2026-11-10: small 20, large 60). A task without a size, as most
  # issues opened on GitHub are, waits as long as a large one.
  @slow_after %{"S" => 20, "M" => 40, "L" => 60}
  @slow_after_unsized 60

  @doc "Seconds of work after which a running task of this size is a heads-up."
  @spec slow_after(String.t() | nil) :: pos_integer()
  def slow_after(size), do: Map.get(@slow_after, size, @slow_after_unsized) * 60

  # The work counts from when the task last became `running`: a retry or the
  # owner's answer starts it again, and the time it waited is not work.
  @doc "Since when a running task works: time spent waiting is not work."
  @spec working_since(map()) :: DateTime.t() | nil
  def working_since(task), do: task.state_changed_at || task.started_at

  @doc "The moment a running task passes the time its size allows, or nil."
  @spec slow_at(map()) :: DateTime.t() | nil
  def slow_at(task) do
    case working_since(task) do
      %DateTime{} = since -> DateTime.add(since, slow_after(task.size), :second)
      nil -> nil
    end
  end

  @doc "Whether a running task has passed the time its size allows."
  @spec slow?(map(), DateTime.t()) :: boolean()
  def slow?(task, now) do
    case slow_at(task) do
      %DateTime{} = at -> DateTime.compare(now, at) != :lt
      nil -> false
    end
  end

  @doc """
  Milliseconds until the next running task becomes a long run or goes silent, nil
  when none will. Nothing broadcasts a task that goes quiet, so the open board
  sets one timer for this moment instead of waiting for the next sync.
  """
  @spec next_attention_in([map()], map(), pos_integer(), DateTime.t()) :: pos_integer() | nil
  def next_attention_in(running, silences, stall_after, now) do
    long_runs = Enum.map(running, &slow_at/1)

    quiet =
      Enum.map(running, fn task ->
        case silences[task.number] do
          %{at: at} -> DateTime.add(at, stall_after, :second)
          nil -> nil
        end
      end)

    (long_runs ++ quiet)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&DateTime.diff(&1, now, :millisecond))
    |> Enum.filter(&(&1 > 0))
    |> Enum.min(fn -> nil end)
  end

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
    |> Enum.filter(&(unanswered?(&1, context) or call_failed?(&1, context.now)))
    |> Enum.map(&task_need(&1, :unanswered, context))
  end

  # The board claimed the call and the comment did not land: the task is
  # still held, and the release tick never calls a claimed task again
  # (`AgentBoard.Release`). A minute covers a comment still on its way.
  @call_grace 60

  defp call_failed?(%{held: true, released_at: %DateTime{} = at}, now),
    do: DateTime.diff(now, at) >= @call_grace

  defp call_failed?(_task, _now), do: false

  # Called by the board longer ago than a silence takes, and no ticket of the
  # runner names the issue: one waiting for a worker has a ticket already.
  defp unanswered?(task, %{tickets: tickets, stall_after: stall_after, now: now}) do
    case Release.called_at(task) do
      %DateTime{} = at ->
        not Map.has_key?(tickets, task.number) and DateTime.diff(now, at) >= stall_after

      nil ->
        false
    end
  end

  # Every item says what to do, where and why: the kind is the what, the
  # actions are the where, and `why` is the evidence the board has. A fact
  # the board cannot see is said to be missing, never filled in.
  defp task_need(task, kind, context) do
    at = need_at(task, kind, context)
    ticket = Map.get(context.tickets, task.number)
    pull = Map.get(context.pulls, task.id)
    ci = pull && need_ci(pull, Map.get(context.local_ci, pull.number))

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
      is_new: new?(at, context.last_visit),
      actions: need_actions(task, kind, pull, context)
    }
  end

  # A silence is news from the moment it crossed the threshold, not from the
  # last signal: that is when the item appeared, and what "novo" refers to.
  defp need_at(task, :stalled, context) do
    DateTime.add(context.silences[task.number].at, context.stall_after, :second)
  end

  # The same for a long run: it is news from the minute it passed its limit.
  defp need_at(task, :slow, _context),
    do: DateTime.add(working_since(task), slow_after(task.size), :second)

  defp need_at(%{held: true, released_at: at}, :unanswered, _context), do: at

  defp need_at(task, :unanswered, context),
    do: DateTime.add(Release.called_at(task), context.stall_after, :second)

  defp need_at(task, _kind, _context),
    do: task.state_changed_at || task.updated_at || task.inserted_at

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
    case ticket && ticket["report_summary"] do
      summary when is_binary(summary) and summary != "" ->
        gettext("**Ready for review**, PR not identified. The agent said: %{summary}",
          summary: excerpt(summary)
        )

      _ ->
        gettext("**Ready for review**, PR not identified by the board. Open the conversation.")
    end
  end

  defp task_why(task, :question, ticket, _pull, _context) do
    question = Board.agent_question(task.repository_id, task.number)
    summary = ticket && ticket["report_summary"]

    cond do
      question ->
        gettext("**The agent asked:** %{question}", question: excerpt(question))

      is_binary(summary) and Workpad.question?(summary) ->
        gettext("**The agent asked:** %{question}", question: excerpt(summary))

      true ->
        gettext("**The agent is waiting for your answer.** Open the conversation and reply.")
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

    cond do
      blockage ->
        gettext("**Blocked:** %{reason}", reason: excerpt(blockage))

      is_binary(summary) and summary != "" ->
        gettext("**Blocked:** %{reason}", reason: excerpt(summary))

      true ->
        gettext("**Blocked**, with no reason in the agent's report. Open the details.")
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

  # The same reading as Mesclados: the local gate is the evidence, the red
  # remote check is quiet, and no local report is a `?`, not a pass.
  defp need_ci(pull, local) do
    {state, note, title} = ci_status(pull, local)
    %{state: state, note: note, title: title, local: local_pass?(local)}
  end

  # The tag's tone reads this, never the note's words.
  defp local_pass?(local), do: match?(%{state: :pass}, local)

  defp checks_label(%PullRequest{checks_failed: failed}) when is_binary(failed) do
    failed
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(" #{gettext("and")} ")
    |> String.slice(0, 80)
  end

  defp checks_label(_pull), do: ""

  defp action_label(:review), do: gettext("Review")
  defp action_label(:question), do: gettext("Respond")
  defp action_label(:blocked), do: gettext("View details")
  defp action_label(:stalled), do: gettext("View details")
  defp action_label(:unanswered), do: gettext("View details")
  defp action_label(:slow), do: gettext("View details")

  # A silent run blocks the whole queue while there is one worker: it comes
  # right after a block, before the work that only waits for the owner.
  # The agent being down explains every block and silence below it.
  defp rank(:agent_down), do: -1
  defp rank(:cifail), do: 0
  defp rank(:blocked), do: 1
  defp rank(:stalled), do: 2
  defp rank(:unanswered), do: 2
  defp rank(:review), do: 3
  defp rank(:question), do: 4
  # Nothing to do yet: after everything that waits for the owner.
  defp rank(:slow), do: 5

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

    rows =
      Repo.all(
        from t in Task,
          where: t.repository_id == ^repository.id and t.state == "queued",
          order_by: [
            desc: fragment("? IS NOT NULL", t.blocker_for_task_id),
            asc: t.inserted_at,
            asc: t.id
          ],
          select: %{
            id: t.id,
            number: t.number,
            title: t.title,
            inserted_at: t.inserted_at,
            origin_task_id: t.origin_task_id,
            blocker_for_task_id: t.blocker_for_task_id,
            held: t.held,
            released_at: t.released_at,
            executor: t.executor
          }
      )

    merged =
      Repo.all(
        from p in PullRequest,
          where: p.repository_id == ^repository.id and p.state == "merged",
          select: %{id: p.id, number: p.number, title: p.title}
      )

    origins = origin_numbers(rows)
    blockers = blocker_numbers(rows)
    waits = open_dependencies(rows)

    items =
      Enum.map(rows, fn row ->
        item = queue_item(row, merged, origins, blockers, now, last_visit)

        stuck = stuck(row, calls)
        held = if is_nil(stuck), do: held_sub(row, waits)

        Map.merge(item, %{
          sub: held || join_sub([item.sub, call_sub(row, calls)]),
          stuck: stuck
        })
      end)

    counts = queue_counts(items)

    filtered = filter_items(items, filter)

    %{
      items: Enum.take(filtered, limit),
      total: length(filtered),
      hidden: max(length(filtered) - limit, 0),
      limit: limit,
      counts: counts,
      filters: filters(counts),
      filter: filter
    }
  end

  defp queue_item(row, merged, origins, blockers, now, last_visit) do
    duplicate = Titles.duplicate(row.title, merged)

    sub =
      case {Map.get(blockers, row.blocker_for_task_id), Map.get(origins, row.origin_task_id)} do
        {number, _origin} when is_integer(number) ->
          gettext("unblocks #%{number}", number: number)

        {nil, number} when is_integer(number) ->
          gettext("split from #%{number}", number: number)

        _ ->
          nil
      end

    %{
      key: "task-#{row.id}",
      id: row.id,
      number: row.number,
      title: row.title,
      age_seconds: Time.age_seconds(row.inserted_at, now),
      is_new: new?(row.inserted_at, last_visit),
      sub: sub,
      split: not is_nil(sub),
      note:
        duplicate &&
          gettext("Looks like a repeat of #%{number}, already merged", number: duplicate.number)
    }
  end

  defp join_sub(parts) do
    case Enum.reject(parts, &is_nil/1) do
      [] -> nil
      said -> Enum.join(said, " · ")
    end
  end

  # A held task names what it still waits for; one with every dependency
  # finished is about to be called (`AgentBoard.Release`, within a minute).
  defp held_sub(%{held: false}, _waits), do: nil

  defp held_sub(row, waits) do
    case Map.get(waits, row.id, []) do
      [] -> gettext("waiting for its dependencies")
      numbers -> gettext("waiting for %{tasks}", tasks: Enum.map_join(numbers, ", ", &"##{&1}"))
    end
  end

  defp open_dependencies(rows) do
    case for(%{held: true, id: id} <- rows, do: id) do
      [] ->
        %{}

      ids ->
        from(d in TaskDependency,
          join: b in Task,
          on: b.id == d.blocked_by_task_id,
          where: d.task_id in ^ids and b.state not in ["done", "closed"],
          order_by: b.number,
          select: {d.task_id, b.number}
        )
        |> Repo.all()
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    end
  end

  # A called task between the call and the start: who holds it now. One
  # nobody answered says so in `stuck/2`; a ticket that started or ended is
  # the overlay's to place (`AgentBoard.Tickets.state/2`).
  defp call_sub(row, calls) do
    called = Release.called_at(row)
    ticket = Map.get(calls.tickets, row.number)

    cond do
      is_nil(called) or unanswered?(row, calls) ->
        nil

      is_nil(ticket) ->
        gettext("called %{ago}, waiting for the agent",
          ago: Time.ago(DateTime.diff(calls.now, called))
        )

      ticket["stopped"] || ticket["archived"] ->
        nil

      is_nil(ticket["started_at"]) and is_nil(ticket["ended_at"]) ->
        agent_queue(ticket, calls.now)

      true ->
        nil
    end
  end

  # The runner took the call and has no free worker yet.
  defp agent_queue(ticket, now) do
    case List.last(ticket["assignments"] || []) do
      %{"created_at" => %DateTime{} = at} ->
        gettext("entered the agent's queue %{ago}", ago: Time.ago(DateTime.diff(now, at)))

      _no_assignment ->
        gettext("in the agent's queue")
    end
  end

  # The same derivation as the item in Precisa de você (`unanswered?/2`).
  defp stuck(row, calls) do
    cond do
      call_failed?(row, calls.now) ->
        gettext("the call to the agent did not complete")

      unanswered?(row, calls) ->
        called = Time.ago(DateTime.diff(calls.now, Release.called_at(row)))
        gettext("called %{ago}, the agent did not start", ago: called)

      true ->
        nil
    end
  end

  defp blocker_numbers(rows) do
    ids =
      rows
      |> Enum.map(& &1.blocker_for_task_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if ids == [] do
      %{}
    else
      Repo.all(from t in Task, where: t.id in ^ids, select: {t.id, t.number}) |> Map.new()
    end
  end

  defp origin_numbers(rows) do
    ids = rows |> Enum.map(& &1.origin_task_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      %{}
    else
      Repo.all(from t in Task, where: t.id in ^ids, select: {t.id, t.number}) |> Map.new()
    end
  end

  defp queue_counts(items) do
    %{
      all: length(items),
      new: Enum.count(items, & &1.is_new),
      split: Enum.count(items, & &1.split),
      dupes: Enum.count(items, &(!is_nil(&1.note)))
    }
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

  defp filter_items(items, :new), do: Enum.filter(items, & &1.is_new)
  defp filter_items(items, :split), do: Enum.filter(items, & &1.split)
  defp filter_items(items, :dupes), do: Enum.filter(items, &(!is_nil(&1.note)))
  defp filter_items(items, _all), do: items

  @doc "Seven days of merges: the dots, the day counts and the per-day record."
  def merge_log(repository, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    offset = Keyword.get(opts, :tz_offset, 0)
    local_ci = Keyword.get(opts, :local_ci, %{})
    today = Time.local_date(now, offset)
    start = Date.add(today, -(@log_days - 1))
    start_utc = DateTime.new!(start, ~T[00:00:00Z]) |> DateTime.add(offset * 60, :second)

    pulls =
      Repo.all(
        from p in PullRequest,
          where:
            p.repository_id == ^repository.id and p.state == "merged" and
              p.merged_at >= ^start_utc,
          order_by: [desc: p.merged_at, desc: p.id]
      )

    costs = TaskCosts.for_pulls(pulls)

    days =
      Enum.map(0..(@log_days - 1), fn index ->
        date = Date.add(start, index)
        day_pulls = Enum.filter(pulls, &(Time.local_date(&1.merged_at, offset) == date))

        %{
          date: date,
          label: Time.day_label(date, today),
          n: length(day_pulls),
          issues: delivered(day_pulls),
          fail: Enum.count(day_pulls, &(local_state(&1, local_ci) == :fail)),
          ok: Enum.count(day_pulls, &(local_state(&1, local_ci) == :pass)),
          today: date == today
        }
      end)

    groups =
      days
      |> Enum.reverse()
      |> Enum.reject(&(&1.n == 0))
      |> Enum.map(fn day ->
        day_pulls =
          pulls
          |> Enum.filter(&(Time.local_date(&1.merged_at, offset) == day.date))
          |> Enum.sort_by(& &1.merged_at, :desc)

        shown = Enum.take(day_pulls, @day_limit)

        %{
          date: day.date,
          label: Time.day_label(day.date, today),
          n: length(day_pulls),
          more: max(length(day_pulls) - @day_limit, 0),
          more_wide: max(length(day_pulls) - @day_reach, 0),
          items: Enum.map(shown, &merged_pr(&1, offset, local_ci, costs)),
          extra:
            day_pulls
            |> Enum.slice(@day_limit, @day_reach - @day_limit)
            |> Enum.map(&merged_pr(&1, offset, local_ci, costs))
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
  def delivered(pulls),
    do: pulls |> Enum.flat_map(&(&1.closes_issues || [])) |> Enum.uniq() |> length()

  @doc """
  How a pull's CI reads, the local gate first: `{state, note, title}`. One
  wording for every list of merged pulls (the merge log and History).
  """
  def ci(pull, local_ci), do: ci_status(pull, Map.get(local_ci, pull.number))

  defp merged_pr(pull, offset, local_ci, costs) do
    local = Map.get(local_ci, pull.number)
    {ci, ci_note, ci_title} = ci_status(pull, local)

    %{
      id: pull.id,
      number: pull.number,
      title: pull.title,
      url: pull.url,
      closes: pull.closes_issues || [],
      ci: ci,
      ciNote: ci_note,
      ciTitle: ci_title,
      ciLocal: local_pass?(local),
      review: review_label(pull.review_state),
      at: Time.local_time(pull.merged_at, offset),
      cost: Map.get(costs, pull.number)
    }
  end

  defp ci_status(pull, %{state: :pass} = local) do
    {"pass", gettext("Local CI passed"), local_title(local, pull)}
  end

  defp ci_status(_pull, %{state: :fail} = local) do
    {"fail", gettext("Local CI failed"), local_title(local, nil)}
  end

  # The workpad names a gate on another commit than the PR's head: the
  # evidence exists but does not cover what would merge.
  defp ci_status(_pull, %{state: :stale, detail: detail}),
    do: {"unknown", gettext("Local CI unknown"), detail}

  defp ci_status(%PullRequest{checks_state: "failure"} = pull, nil) do
    {"unknown", gettext("Local CI unknown"), remote_failure_title(pull)}
  end

  defp ci_status(%PullRequest{checks_state: "success"}, nil),
    do: {"pass", gettext("CI passed"), gettext("GitHub Actions passed.")}

  defp ci_status(%PullRequest{checks_state: "pending"}, nil),
    do: {"unknown", gettext("CI running"), gettext("GitHub Actions is still running.")}

  defp ci_status(_pull, nil),
    do: {"unknown", gettext("no CI"), gettext("No remote check configured.")}

  defp local_state(pull, local_ci) when is_map(local_ci) do
    case Map.get(local_ci, pull.number, %{}) do
      %{state: state} -> state
      _ -> nil
    end
  end

  defp local_title(local, pull) do
    prefix =
      if local.remote_blocked do
        gettext("%{remote} (billing/no credit on GitHub).", remote: remote_label(pull))
      else
        "#{remote_label(pull)}."
      end

    gettext("%{prefix} Local CI passed%{scope}: %{detail}",
      prefix: prefix,
      scope: local_scope(local),
      detail: local.detail
    )
  end

  defp remote_label(%{checks_state: "failure"}), do: gettext("GitHub Actions failed")
  defp remote_label(%{checks_state: "success"}), do: gettext("GitHub Actions passed")
  defp remote_label(%{checks_state: "pending"}), do: gettext("GitHub Actions is still running")
  defp remote_label(_pull), do: gettext("GitHub Actions has no checks")

  defp local_scope(%{scope: :ticket, evidence_pr: number}),
    do:
      " " <>
        gettext("on the ticket (report cites #%{number}; this PR is from the same work)",
          number: number
        )

  defp local_scope(_local), do: ""

  defp remote_failure_title(pull) do
    case checks_label(pull) do
      "" ->
        gettext("GitHub Actions failed (billing/no credit); no evidence of local CI.")

      checks ->
        gettext(
          "GitHub Actions failed on %{checks} (billing/no credit); no evidence of local CI.",
          checks: checks
        )
    end
  end

  defp review_label("approved"), do: gettext("reviewed")
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
      first_digest(repository, board, now, offset, frozen_at, frozen?)
    else
      since_digest(repository, board, last_visit, now, offset, frozen_at, frozen?)
    end
  end

  defp first_digest(repository, board, now, offset, frozen_at, frozen?) do
    case first_phrases(repository, board) do
      [] ->
        nil

      phrases ->
        %{
          prefix: first_prefix(frozen?, frozen_at, offset),
          segments: join_phrases(phrases),
          suffix: (frozen? && " " <> gettext("After that, we do not know.")) || ".",
          now: now
        }
    end
  end

  defp first_phrases(_repository, board) do
    running = length(Map.get(board, :running, []))
    waiting = length(Map.get(board, :ready, [])) + length(Map.get(board, :question, []))
    blocked = length(Map.get(board, :blocked, []))
    retrying = length(Map.get(board, :retrying, []))
    queued = Map.get(board, :task_counts, %{}) |> Map.get(:queued, 0)

    [
      running > 0 && [%{text: gettext("%{count} running", count: running), role: :agent}],
      retrying > 0 &&
        [%{text: gettext("%{count} in automatic retry", count: retrying), role: :agent}],
      waiting > 0 &&
        [
          %{
            text: ngettext("%{count} waiting for you", "%{count} waiting for you", waiting),
            role: :you
          }
        ],
      blocked > 0 &&
        [
          %{
            text: pngettext("digest", "%{count} blocked", "%{count} blocked", blocked),
            role: :halt
          }
        ],
      queued > 0 && [%{text: gettext("%{count} in the queue", count: queued), role: :agent}]
    ]
    |> Enum.reject(&(&1 == false))
  end

  defp since_digest(repository, board, last_visit, now, offset, frozen_at, frozen?) do
    counts = since_counts(repository, last_visit)
    phrases = since_phrases(repository, board, last_visit, counts, offset)

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
        join_phrases(phrases)
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

  defp since_counts(repository, last_visit) do
    %{
      merged: merged_count(repository, last_visit),
      reviews: review_count(repository, last_visit),
      questions: question_count(repository, last_visit),
      queue_new: queue_new_count(repository, last_visit)
    }
  end

  defp merged_count(repository, last_visit) do
    Repo.aggregate(
      from(p in PullRequest,
        where:
          p.repository_id == ^repository.id and p.state == "merged" and
            p.merged_at >= ^last_visit
      ),
      :count
    )
  end

  defp review_count(repository, last_visit) do
    Repo.aggregate(
      from(p in PullRequest,
        where:
          p.repository_id == ^repository.id and p.state == "open" and
            p.opened_at >= ^last_visit
      ),
      :count
    )
  end

  defp question_count(repository, last_visit) do
    Repo.aggregate(
      from(t in Task,
        where:
          t.repository_id == ^repository.id and t.state == "question" and
            t.state_changed_at >= ^last_visit
      ),
      :count
    )
  end

  defp queue_new_count(repository, last_visit) do
    Repo.aggregate(
      from(t in Task,
        where:
          t.repository_id == ^repository.id and t.state == "queued" and
            t.inserted_at >= ^last_visit
      ),
      :count
    )
  end

  defp since_phrases(repository, board, last_visit, counts, _offset) do
    running = Map.get(board, :running, [])
    blocked = Map.get(board, :blocked, [])
    first_review = first_review(repository, last_visit)

    [
      counts.merged > 0 && merged_phrase(counts.merged),
      counts.reviews > 0 && [review_phrase(counts.reviews, first_review)],
      counts.questions > 0 &&
        [
          %{
            text:
              ngettext(
                "it asked %{count} question",
                "it asked %{count} questions",
                counts.questions
              ),
            role: :you
          }
        ],
      running != [] && [running_phrase(running)],
      blocked != [] && [blocked_phrase(blocked)],
      counts.queue_new > 0 && [queue_phrase(counts.queue_new)]
    ]
    |> Enum.reject(&(&1 == false))
    |> Enum.map(&List.wrap/1)
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

  defp queue_phrase(n) do
    %{text: ngettext("%{count} new in the queue", "%{count} new in the queue", n), role: :agent}
  end

  defp merged_phrase(merged) do
    text = ngettext("the agent merged %{count} PR", "the agent merged %{count} PRs", merged)
    [%{text: text, role: :agent}]
  end

  defp review_phrase(n, pr) do
    %{
      text: ngettext("it opened %{count} PR for review", "it opened %{count} PRs for review", n),
      role: :you,
      url: pr && pr.url
    }
  end

  defp running_phrase([task]) do
    %{
      text: gettext("it is working on #%{number}", number: task.number),
      role: :agent,
      task_id: task.id
    }
  end

  defp running_phrase(tasks) do
    %{text: gettext("it is working on %{count} tasks", count: length(tasks)), role: :agent}
  end

  defp blocked_phrase([task]) do
    %{
      text: gettext("#%{number} is still blocked", number: task.number),
      role: :halt,
      task_id: task.id
    }
  end

  defp blocked_phrase(tasks) do
    %{text: gettext("%{count} are still blocked", count: length(tasks)), role: :halt}
  end

  defp first_review(repository, last_visit) do
    Repo.one(
      from p in PullRequest,
        where:
          p.repository_id == ^repository.id and p.state == "open" and
            p.opened_at >= ^last_visit,
        order_by: [desc: p.opened_at],
        limit: 1
    )
  end

  defp join_phrases([]), do: []

  defp join_phrases([only]), do: only

  defp join_phrases(phrases) do
    {init, [last]} = Enum.split(phrases, -1)

    init
    |> Enum.intersperse([%{text: ", ", role: :plain}])
    |> List.flatten()
    |> Kernel.++([%{text: " #{gettext("and")} ", role: :plain}])
    |> Kernel.++(last)
  end

  defp new?(nil, _last_visit), do: false
  defp new?(_at, nil), do: false
  defp new?(at, %DateTime{} = last_visit), do: DateTime.compare(at, last_visit) == :gt

  defp excerpt(nil), do: ""

  defp excerpt(text) do
    text
    |> String.split("\n", parts: 2)
    |> hd()
    |> String.trim()
    |> String.slice(0, 160)
  end
end
