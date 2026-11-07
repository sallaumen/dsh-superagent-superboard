defmodule AgentBoard.Work do
  @moduledoc """
  The board's reading lanes, built only from rows the board observed.

  A missing field becomes an omitted sentence, never a fabricated one: the
  activity step, the PR stats and the executor's internal log are not stored
  here, so they do not appear.
  """

  import Ecto.Query, warn: false

  alias AgentBoard.{AgentSignal, Board, Repo, Sync, Time, Titles, Workpad}
  alias AgentBoard.Board.{Comment, PullRequest, Task}

  @queue_limit 8
  @day_limit 3
  @log_days 7

  @doc """
  The attention list: blocked work, silent runs, PRs for review and
  questions, in that order. Merged work is done and its CI lives in
  Mesclados, where a failed GitHub check is quiet and the local gate is the
  evidence that counts.

  A silence (`:silences`, from `AgentBoard.AgentSignal`) is derived, never a
  task state: a running task is the owner's only while its ticket has given
  no signal for `:stall_after` seconds.
  """
  def needs(_repository, board, opts \\ []) do
    context = context(board, opts)

    [
      lane(board, :blocked, :blocked, context),
      silent_lane(board, context),
      lane(board, :ready, :review, context),
      lane(board, :question, :question, context)
    ]
    |> List.flatten()
    |> Enum.sort_by(fn need ->
      {rank(need.kind), not need.is_new, -(need.age_seconds || 0)}
    end)
  end

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
      stall_after: Keyword.get(opts, :stall_after, AgentSignal.stall_after())
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
      age_seconds: Time.age_seconds(at, context.now),
      is_new: new?(at, context.last_visit),
      actions: need_actions(task, kind, pull)
    }
  end

  # A silence is news from the moment it crossed the threshold, not from the
  # last signal: that is when the item appeared, and what "novo" refers to.
  defp need_at(task, :stalled, context) do
    DateTime.add(context.silences[task.number].at, context.stall_after, :second)
  end

  defp need_at(task, _kind, _context),
    do: task.state_changed_at || task.updated_at || task.inserted_at

  defp task_why(_task, :review, _ticket, %PullRequest{number: number}, _context),
    do: "**PR ##{number} pronto para revisão**"

  defp task_why(_task, :review, ticket, nil, _context) do
    case ticket && ticket["report_summary"] do
      summary when is_binary(summary) and summary != "" ->
        "**Pronto para revisão**, PR não identificado. O agente disse: " <> excerpt(summary)

      _ ->
        "**Pronto para revisão**, PR não identificado pelo board. Abra a conversa."
    end
  end

  defp task_why(task, :question, ticket, _pull, _context) do
    question =
      case last_agent_comment(task) do
        %Comment{body: body} -> comment_question(body)
        nil -> nil
      end

    summary = ticket && ticket["report_summary"]

    cond do
      question ->
        "**O agente perguntou:** " <> excerpt(question)

      is_binary(summary) and AgentBoard.Sync.question?(summary) ->
        "**O agente perguntou:** " <> excerpt(summary)

      true ->
        "**O agente espera uma resposta sua.** Abra a conversa e responda."
    end
  end

  defp task_why(task, :blocked, ticket, _pull, _context) do
    blockage =
      case last_agent_comment(task) do
        %Comment{body: body} -> comment_blockage(body)
        nil -> nil
      end

    summary = ticket && ticket["report_summary"]

    cond do
      blockage -> "**Bloqueado:** " <> excerpt(blockage)
      is_binary(summary) and summary != "" -> "**Bloqueado:** " <> excerpt(summary)
      true -> "**Bloqueado**, sem motivo no relatório do agente. Abra o detalhe."
    end
  end

  # The item says what the board saw last and when; it never says the agent
  # died. A long model turn with no file change is a silence too.
  defp task_why(task, :stalled, _ticket, _pull, context) do
    silence = Map.fetch!(context.silences, task.number)
    since = Time.local_time(silence.at, context.tz_offset)
    "**Sem sinal #{Time.ago(silence.seconds)}.** " <> silence_source(silence.source, since)
  end

  defp silence_source(:report, since),
    do: "O último relatório do agente foi às #{since}; nenhum sinal no worktree desde então."

  defp silence_source(:worktree, since),
    do: "A última mudança no worktree foi às #{since}; nenhum relatório depois."

  defp silence_source(:start, since),
    do:
      "Começou às #{since} e não deu sinal desde então: nenhum relatório nem mudança no worktree."

  defp need_actions(task, :review, %PullRequest{url: url, number: number}) when is_binary(url) do
    [
      %{label: action_label(:review), task_id: task.id},
      %{label: "Abrir PR ##{number}", url: url}
    ]
  end

  defp need_actions(task, kind, _pull), do: [%{label: action_label(kind), task_id: task.id}]

  # The same reading as Mesclados: the local gate is the evidence, the red
  # remote check is quiet, and no local report is a `?`, not a pass.
  defp need_ci(pull, local) do
    {state, note, title} = ci_status(pull, local)
    %{state: state, note: note, title: title}
  end

  defp checks_label(%PullRequest{checks_failed: failed}) when is_binary(failed) do
    failed
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(" e ")
    |> String.slice(0, 80)
  end

  defp checks_label(_pull), do: ""

  defp last_agent_comment(task) do
    Repo.one(
      from c in Comment,
        where: c.task_id == ^task.id and c.kind == "agent",
        order_by: [desc: c.inserted_at, desc: c.id],
        limit: 1
    )
  end

  # A workpad is quoted by its section; any other comment by its text, and
  # only when it asks.
  defp comment_question(body) do
    case Workpad.parse(body) do
      %{question: question} -> question
      nil -> if Sync.question?(body), do: body
    end
  end

  defp comment_blockage(body) do
    case Workpad.parse(body) do
      %{blockage: blockage} -> blockage
      nil -> nil
    end
  end

  defp action_label(:review), do: "Revisar"
  defp action_label(:question), do: "Responder"
  defp action_label(:blocked), do: "Ver detalhe"
  defp action_label(:stalled), do: "Ver detalhe"
  defp action_label(:cifail), do: "Ver falha"

  # A silent run blocks the whole queue while there is one worker: it comes
  # right after a block, before the work that only waits for the owner.
  defp rank(:cifail), do: 0
  defp rank(:blocked), do: 1
  defp rank(:stalled), do: 2
  defp rank(:review), do: 3
  defp rank(:question), do: 4

  @doc """
  The queue, numbered in arrival order. A title that repeats a merged PR gets
  the warning; an unknown origin is omitted instead of invented.
  """
  def queue(repository, _board, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    last_visit = Keyword.get(opts, :last_visit)
    filter = Keyword.get(opts, :filter, :all)
    limit = Keyword.get(opts, :limit, @queue_limit)

    rows =
      Repo.all(
        from t in Task,
          where: t.repository_id == ^repository.id and t.state == "queued",
          order_by: [asc: t.inserted_at, asc: t.id],
          select: %{
            id: t.id,
            number: t.number,
            title: t.title,
            inserted_at: t.inserted_at,
            origin_task_id: t.origin_task_id
          }
      )

    merged =
      Repo.all(
        from p in PullRequest,
          where: p.repository_id == ^repository.id and p.state == "merged",
          select: %{id: p.id, number: p.number, title: p.title}
      )

    origins = origin_numbers(rows)
    items = Enum.map(rows, &queue_item(&1, merged, origins, now, last_visit))
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

  defp queue_item(row, merged, origins, now, last_visit) do
    duplicate = Titles.duplicate(row.title, merged)

    %{
      key: "task-#{row.id}",
      id: row.id,
      number: row.number,
      title: row.title,
      age_seconds: Time.age_seconds(row.inserted_at, now),
      is_new: new?(row.inserted_at, last_visit),
      sub:
        case Map.get(origins, row.origin_task_id) do
          nil -> nil
          number -> "dividido de ##{number}"
        end,
      note: duplicate && "Parece repetir ##{duplicate.number}, já mesclado"
    }
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
      split: Enum.count(items, &(!is_nil(&1.sub))),
      dupes: Enum.count(items, &(!is_nil(&1.note)))
    }
  end

  defp filters(%{all: all}) when all <= @queue_limit, do: []

  defp filters(counts) do
    [
      {"Todas", counts.all},
      {"Novas", counts.new},
      {"Divididas", counts.split},
      {"Possíveis repetidas", counts.dupes}
    ]
  end

  defp filter_items(items, :new), do: Enum.filter(items, & &1.is_new)
  defp filter_items(items, :split), do: Enum.filter(items, &(!is_nil(&1.sub)))
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

    days =
      Enum.map(0..(@log_days - 1), fn index ->
        date = Date.add(start, index)
        day_pulls = Enum.filter(pulls, &(Time.local_date(&1.merged_at, offset) == date))

        %{
          date: date,
          label: Time.short_day_label(date, today),
          n: length(day_pulls),
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
          label: Time.day_label(day.date, today),
          n: length(day_pulls),
          more: max(length(day_pulls) - @day_limit, 0),
          items: Enum.map(shown, &merged_pr(&1, offset, local_ci))
        }
      end)

    %{days: days, groups: groups, total: Enum.sum(Enum.map(days, & &1.n))}
  end

  defp merged_pr(pull, offset, local_ci) do
    {ci, ci_note, ci_title} = ci_status(pull, Map.get(local_ci, pull.number))

    %{
      id: pull.id,
      number: pull.number,
      title: pull.title,
      url: pull.url,
      ci: ci,
      ciNote: ci_note,
      ciTitle: ci_title,
      review: review_label(pull.review_state),
      at: Time.local_time(pull.merged_at, offset)
    }
  end

  defp ci_status(pull, %{state: :pass} = local) do
    {"pass", "CI local ok", local_title(local, pull)}
  end

  defp ci_status(_pull, %{state: :fail} = local) do
    {"fail", "CI local falhou", local_title(local, nil)}
  end

  # The workpad names a gate on another commit than the PR's head: the
  # evidence exists but does not cover what would merge.
  defp ci_status(_pull, %{state: :stale, detail: detail}), do: {"unknown", "CI local ?", detail}

  defp ci_status(%PullRequest{checks_state: "failure"} = pull, nil) do
    {"unknown", "CI local ?", remote_failure_title(pull)}
  end

  defp ci_status(%PullRequest{checks_state: "success"}, nil),
    do: {"pass", "CI ok", "GitHub Actions passou."}

  defp ci_status(%PullRequest{checks_state: "pending"}, nil),
    do: {"unknown", "CI rodando", "GitHub Actions ainda está rodando."}

  defp ci_status(_pull, nil), do: {"unknown", "sem CI", "Nenhum check remoto configurado."}

  defp local_state(pull, local_ci) when is_map(local_ci) do
    case Map.get(local_ci, pull.number, %{}) do
      %{state: state} -> state
      _ -> nil
    end
  end

  defp local_title(local, pull) do
    prefix =
      if local.remote_blocked do
        "#{remote_label(pull)} (billing/sem crédito no GitHub)."
      else
        "#{remote_label(pull)}."
      end

    "#{prefix} CI local passou#{local_scope(local)}: #{local.detail}"
  end

  defp remote_label(%{checks_state: "failure"}), do: "GitHub Actions falhou"
  defp remote_label(%{checks_state: "success"}), do: "GitHub Actions passou"
  defp remote_label(%{checks_state: "pending"}), do: "GitHub Actions ainda roda"
  defp remote_label(_pull), do: "GitHub Actions sem checks"

  defp local_scope(%{scope: :ticket, evidence_pr: number}),
    do: " no ticket (relatório cita ##{number}; este PR é do mesmo trabalho)"

  defp local_scope(_local), do: ""

  defp remote_failure_title(pull) do
    case checks_label(pull) do
      "" ->
        "GitHub Actions falhou (billing/sem crédito); sem evidência de CI local."

      checks ->
        "GitHub Actions falhou em #{checks} (billing/sem crédito); sem evidência de CI local."
    end
  end

  defp review_label("approved"), do: "revisado"
  defp review_label("changes_requested"), do: "mudanças pedidas"
  defp review_label("pending"), do: "revisão pendente"
  defp review_label(_state), do: "sem revisão"

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
          suffix: (frozen? && " Depois disso, não sabemos.") || ".",
          now: now
        }
    end
  end

  defp first_phrases(_repository, board) do
    running = length(Map.get(board, :running, []))
    waiting = length(Map.get(board, :ready, [])) + length(Map.get(board, :question, []))
    blocked = length(Map.get(board, :blocked, []))
    queued = Map.get(board, :task_counts, %{}) |> Map.get(:queued, 0)

    [
      running > 0 && [%{text: "#{running} rodando", role: :agent}],
      waiting > 0 && [%{text: "#{waiting} esperando você", role: :you}],
      blocked > 0 && [%{text: "#{blocked} #{plural(blocked, "bloqueado")}", role: :halt}],
      queued > 0 && [%{text: "#{queued} na fila", role: :agent}]
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
              if(frozen? and is_nil(frozen_at), do: "não sabemos o que mudou", else: "nada mudou"),
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
        [%{text: "fez #{counts.questions} #{plural(counts.questions, "pergunta")}", role: :you}],
      running != [] && [running_phrase(running)],
      blocked != [] && [blocked_phrase(blocked)],
      counts.queue_new > 0 && [queue_phrase(counts.queue_new)]
    ]
    |> Enum.reject(&(&1 == false))
    |> Enum.map(&List.wrap/1)
  end

  defp first_prefix(true, %DateTime{} = frozen_at, offset),
    do: "Até #{Time.local_time(frozen_at, offset)}: "

  defp first_prefix(true, nil, _offset), do: "Sem uma sincronia concluída: "
  defp first_prefix(false, _frozen_at, _offset), do: "Primeira visita: "

  defp since_prefix(_last_visit, offset, %DateTime{} = frozen_at, true, _now),
    do: "Até #{Time.local_time(frozen_at, offset)}, "

  defp since_prefix(_last_visit, _offset, nil, true, _now),
    do: "Sem uma sincronia concluída, "

  defp since_prefix(last_visit, offset, nil, false, now),
    do: "Desde #{Time.since_label(last_visit, offset, now)} "

  defp since_suffix(_phrases, true), do: ". Depois disso, não sabemos."
  defp since_suffix(_phrases, false), do: "."

  defp queue_phrase(1), do: %{text: "1 nova na fila", role: :agent}
  defp queue_phrase(n), do: %{text: "#{n} novas na fila", role: :agent}

  defp merged_phrase(merged),
    do: [%{text: "o agente mesclou #{merged} #{plural(merged, "PR")}", role: :agent}]

  defp review_phrase(1, pr) do
    %{text: "abriu 1 PR para revisão", role: :you, url: pr && pr.url}
  end

  defp review_phrase(n, pr) do
    %{text: "abriu #{n} PRs para revisão", role: :you, url: pr && pr.url}
  end

  defp running_phrase([task]) do
    %{text: "está trabalhando em ##{task.number}", role: :agent, task_id: task.id}
  end

  defp running_phrase(tasks) do
    %{text: "está trabalhando em #{length(tasks)} tarefas", role: :agent}
  end

  defp blocked_phrase([task]) do
    %{text: "##{task.number} continua bloqueado", role: :halt, task_id: task.id}
  end

  defp blocked_phrase(tasks) do
    %{text: "#{length(tasks)} continuam bloqueados", role: :halt}
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
    |> Kernel.++([%{text: " e ", role: :plain}])
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

  defp plural(1, singular), do: singular
  defp plural(_n, singular), do: singular <> "s"
end
