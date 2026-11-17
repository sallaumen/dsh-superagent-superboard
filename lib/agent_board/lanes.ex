defmodule AgentBoard.Lanes do
  @moduledoc """
  The board's reading lanes, built only from rows the board observed.

  A missing field becomes an omitted sentence, never a fabricated one: the
  activity step, the PR stats and the executor's internal log are not stored
  here, so they do not appear.
  """

  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.{
    AgentBlock,
    AgentSignal,
    Board,
    Repo,
    Superagents
  }

  alias AgentBoard.Lanes.{
    Attention,
    CI,
    Digest,
    MergeHistory,
    Queue,
    RunTiming
  }

  alias AgentBoard.Usage.TaskCosts

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
    context = needs_context(repository, board, opts)

    %{waiting: waiting, visible: visible} = Attention.Selection.plan(board, context)
    visible = explain_blocks(visible, context)

    context =
      Map.merge(context, %{
        questions: visible_questions(visible, repository),
        blockages: visible_blockages(visible)
      })

    cards = Enum.map(visible, &Attention.Item.build(&1, context))

    cards |> add_outage(waiting, repository) |> Attention.sort()
  end

  defp explain_blocks(visible, context) do
    opts = block_opts(context)

    Enum.map(visible, fn
      %{kind: :blocked, task: task} = card ->
        block = AgentBlock.explain(context.tickets[task.number], opts)
        Map.put(card, :block, block)

      card ->
        card
    end)
  end

  defp visible_blockages(visible) do
    Map.new(Attention.Blocked.report_numbers(visible), fn {repo, numbers} ->
      {repo, Board.agent_blockages(repo, numbers)}
    end)
  end

  defp visible_questions(visible, repository) do
    numbers =
      for %{kind: :question, task: %{number: number}} <- visible, is_integer(number), do: number

    if numbers == [], do: %{}, else: Board.agent_questions(repository.id, numbers)
  end

  defp add_outage(cards, nil, _repository), do: cards

  defp add_outage(cards, waiting, repository) do
    superagent = repository |> Superagents.get_by_repository() |> Repo.preload(:repository)
    [Attention.Outage.card(waiting, superagent) | cards]
  end

  @doc """
  The failed tasks the board retries by itself, for Agora: nobody has to
  act, so they are not in Precisa de você. Each row says what failed and
  when the next attempt goes out.
  """
  def retrying(board, opts \\ []) do
    context = ticket_context(opts)

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

  defp ticket_context(opts) do
    %{
      tickets: Keyword.get(opts, :tickets_by_number, %{}),
      now: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0),
      tz_offset: Keyword.get(opts, :tz_offset, 0),
      agent: Keyword.get(opts, :agent, :unknown)
    }
  end

  defp needs_context(repository, board, opts) do
    context = ticket_context(opts)

    Map.merge(context, %{
      repository: repository,
      last_visit: Keyword.get(opts, :last_visit),
      pulls: Board.linked_pull_requests(Map.get(board, :ready, []), context.tickets),
      local_ci: Keyword.get(opts, :local_ci, %{}),
      silences: Keyword.get(opts, :silences, %{}),
      stall_after: Keyword.get(opts, :stall_after, AgentSignal.stall_after())
    })
  end

  defdelegate slow_after(size), to: RunTiming
  defdelegate working_since(task), to: RunTiming
  defdelegate slow_at(task), to: RunTiming
  defdelegate slow?(task, now), to: RunTiming

  defdelegate next_attention_in(running, silences, stall_after, now), to: RunTiming

  @doc """
  The queue, numbered in arrival order. A title that repeats a merged PR gets
  the warning; an unknown origin is omitted instead of invented.
  """
  def queue(repository, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    last_visit = Keyword.get(opts, :last_visit)
    filter = Keyword.get(opts, :filter, :all)
    limit = Keyword.get(opts, :limit, Queue.compact_limit())

    calls = %{
      now: now,
      tickets: Keyword.get(opts, :tickets_by_number, %{}),
      stall_after: Keyword.get(opts, :stall_after, AgentSignal.stall_after())
    }

    observed = Queue.Observations.load(repository)

    page = Queue.select(observed, last_visit, filter, limit)
    waits = page |> Queue.held_ids() |> Queue.Observations.open_dependencies()
    %{page | items: Enum.map(page.items, &Queue.Item.build(&1, waits, calls))}
  end

  @doc "Seven days of merges: the dots, the day counts and the per-day record."
  def merge_log(repository, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    offset = Keyword.get(opts, :tz_offset, 0)
    local_ci = Keyword.get(opts, :local_ci, %{})
    window = MergeHistory.window(now, offset)
    pulls = MergeHistory.Observations.in_window(repository, window)

    calendar = MergeHistory.Calendar.build(pulls, window, local_ci)

    costs = calendar |> MergeHistory.Calendar.visible_pulls() |> TaskCosts.for_pulls()

    MergeHistory.Report.build(calendar, local_ci, costs)
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

  @doc """
  The one-sentence digest. Since the previous visit when there is one; the
  current state on a first visit; the saved state when the board is frozen.
  """
  def digest(repository, board, opts \\ []) do
    visit = Digest.Visit.from_options(opts)

    if is_nil(visit.last_visit) do
      Digest.FirstVisit.build(Digest.first_visit(board), visit)
    else
      %{counts: counts, latest_review: review} =
        Digest.Observations.since(repository, visit.last_visit)

      Digest.ReturnVisit.build(Digest.since_visit(board, counts), review, visit)
    end
  end
end
