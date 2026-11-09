defmodule AgentBoardWeb.BoardLive do
  @moduledoc "The board: the columns, the repositories and the tasks, live."
  use AgentBoardWeb, :live_view

  import Ecto.Query, warn: false

  alias AgentBoard.{
    Actions,
    AgentBlock,
    AgentSignal,
    AgentState,
    AgentWorktree,
    AI,
    Announcer,
    AutoRetry,
    Board,
    DailySummary,
    ElevenLabs,
    Executors,
    GitHub,
    Intake,
    Lanes,
    LocalCI,
    Logs,
    Metrics,
    Orchestrator,
    Overview,
    Runners,
    Settings,
    Superagents,
    Time,
    Titles,
    Voice
  }

  alias AgentBoard.Board.Task
  alias AgentBoard.Freshness
  alias AgentBoard.Metrics.Observations
  alias AgentBoard.Routing
  alias AgentBoard.Routing.Signals
  alias AgentBoard.Runners.Execution
  alias AgentBoard.System.Version
  alias AgentBoard.Usage.{Harness, Report}
  alias AgentBoard.Voice.{Activity, Phrases}

  import AgentBoardWeb.BoardComponents.Composer, only: [composer: 1]
  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1, kbd: 1]
  import AgentBoardWeb.BoardComponents.DailySummary, only: [daily_summary: 1]
  import AgentBoardWeb.BoardComponents.Executors, only: [executors: 1]
  import AgentBoardWeb.BoardComponents.FreshnessBeacon, only: [beacon: 1]
  import AgentBoardWeb.BoardComponents.FrozenBanner, only: [frozen_banner: 1]
  import AgentBoardWeb.BoardComponents.Inspector, only: [inspector: 1]
  import AgentBoardWeb.BoardComponents.LogsSheet, only: [logs_sheet: 1]
  import AgentBoardWeb.BoardComponents.MergeLog, only: [merge_log: 1]
  import AgentBoardWeb.BoardComponents.NeedsYou, only: [needs_you: 1]
  import AgentBoardWeb.BoardComponents.NowLane, only: [now_lane: 1]
  import AgentBoardWeb.BoardComponents.QueueList, only: [queue_list: 1]
  import AgentBoardWeb.BoardComponents.Shortcuts, only: [shortcuts: 1]
  import AgentBoardWeb.BoardComponents.Summary, only: [summary: 1]
  import AgentBoardWeb.BoardComponents.Today, only: [today_view: 1]
  import AgentBoardWeb.BoardComponents.Throughput, only: [throughput: 1]

  alias AgentBoardWeb.{
    BoardComponents,
    BoardNavigation,
    VoiceConversation,
    VoiceSpeech
  }

  alias AgentBoardWeb.BoardComponents.VoicePresence

  # The task actions a button may send, mapped explicitly (never to_atom).
  @task_actions %{"stop" => :stop_task, "archive" => :archive_task, "resume" => :resume_task}
  @refused_text "Nada foi feito: a ação mudou desde a confirmação. Confira e confirme de novo."
  @max_resume_items 1000

  @impl true
  def mount(params, _session, socket) do
    repos = Board.list_repositories()
    connect = if connected?(socket), do: get_connect_params(socket), else: %{}
    resume = connect["board_resume"]
    last_visit = parse_last_visit(connect["board_last_visit"])
    tz_offset = parse_offset(connect["board_tz_offset"])

    socket =
      assign(socket,
        repos: repos,
        last_visit: last_visit,
        tz_offset: tz_offset,
        work: empty_work(),
        flow: nil,
        digest: nil,
        daily_summary: nil,
        needs_expanded: false,
        queue_limit: 8,
        queue_filter: :all,
        repo: nil,
        view: nil,
        dispatch_paused: false,
        board: empty(),
        today: %{repos: %{}, needs: [], running: []},
        today_spend: nil,
        objectives: [],
        superagents: [],
        provision_preview: nil,
        provisioning: false,
        resume: resume,
        events: [],
        sync_event: nil,
        sync_snapshot: %{last_attempt: nil, last_success: nil},
        freshness: unknown_freshness(),
        repo_overview: %{},
        agent_snapshot: %{ok: false, at: nil, tickets: [], error: :unknown},
        live: connected?(socket),
        toast: nil,
        highlight_changes: false,
        panel: nil,
        logs_sources: [],
        logs_entries: [],
        logs_state: Logs.empty_state(),
        logs_status: %{},
        logs_timer: nil,
        logs_paused: false,
        conversation: nil,
        comments: [],
        ask_pending: nil,
        ask_draft: "",
        inspector_tab: "conversa",
        inspector_activity: [],
        inspector_calls: [],
        inspector_executions: [],
        inspector_executions_for: nil,
        inspector_runner_executions: [],
        inspector_dispatch_paused: false,
        inspector_dispatch_active: false,
        inspector_dispatch_ceiling: 5.0,
        inspector_dispatch_fallback: nil,
        inspector_usage: nil,
        inspector_pr: nil,
        inspector_ci: nil,
        inspector_failure: nil,
        intake: nil,
        intake_draft: nil,
        composer_text: "",
        composer_title: nil,
        composer_split: false,
        composer_selected: MapSet.new(),
        composer_error: nil,
        composer_retry: nil,
        composer_job: nil,
        composer_receipt: nil,
        composer_answers: "",
        composer_routing: nil,
        composer_routing_for: nil,
        executor_days: 7,
        executor_report: nil,
        executor_report_for: nil,
        composer_executor: nil,
        composer_executor_touched: false,
        ai_calls: [],
        ai_status: AI.status(),
        version: Version.status(),
        busy: false,
        voice: current_voice(),
        spoken_text: nil,
        spoken_at: 0,
        # Rotates the attention phrases; a random start keeps a reload from
        # always opening with the same sentence.
        voice_turn: :rand.uniform(1_000)
      )

    repo =
      case params["repo"] do
        nil -> default_repo(repos)
        slug -> Board.repository_by_slug(slug) || default_repo(repos)
      end

    # The voice settings are board-wide: a change in another tab, by the API
    # or by a spoken command reaches this socket (handle_info setting_changed).
    if connected?(socket), do: Settings.subscribe()
    if connected?(socket), do: DailySummary.subscribe()
    if connected?(socket), do: Board.subscribe_today()
    if connected?(socket), do: Superagents.subscribe()

    # handle_params/3 always follows mount and loads the board: loading here
    # too read everything twice on every page and every connection.
    {:ok,
     socket
     |> assign(:superagents, Superagents.list())
     |> VoiceConversation.mount()
     |> assign(:opening_repo, repo)
     |> show_daily_summary()}
  end

  defp empty do
    %{
      running: [],
      question: [],
      ready: [],
      blocked: [],
      merged: [],
      merged_has_more: false,
      queued: [],
      task_counts: Map.new(Board.task_states(), &{&1, 0}),
      task_has_more: Map.new(Board.task_states(), &{&1, false})
    }
  end

  # The board opens on the project the agent is actually working on; the
  # first active repository is the fallback.
  defp default_repo(repos) do
    Enum.find(repos, &(&1.name == "o_colmex")) || List.first(repos)
  end

  defp repo_slug(nil), do: ""
  defp repo_slug(repo), do: "#{repo.owner}/#{repo.name}"

  defp parse_last_visit(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> at
      _ -> nil
    end
  end

  defp parse_last_visit(_value), do: nil

  defp parse_offset(value) when is_integer(value), do: value

  defp parse_offset(value) when is_binary(value) do
    case Integer.parse(value) do
      {offset, ""} -> offset
      _ -> 0
    end
  end

  defp parse_offset(_value), do: 0

  defp work_for(repo, board, agent, freshness, socket, local_ci, orchestrator) do
    now = DateTime.utc_now()
    tz_offset = socket.assigns.tz_offset
    last_visit = socket.assigns.last_visit
    frozen_at = if freshness.frozen?, do: freshness.at, else: nil
    run = run_context(repo, agent, board, now, frozen_at)
    agent_up = agent_status(orchestrator)

    %{
      running: Enum.map(board.running, &running_card(&1, run)),
      retrying:
        Lanes.retrying(board,
          now: now,
          tz_offset: tz_offset,
          tickets_by_number: run.tickets,
          agent: agent_up
        ),
      needs:
        Lanes.needs(repo, board,
          now: now,
          last_visit: last_visit,
          tz_offset: tz_offset,
          tickets_by_number: run.tickets,
          local_ci: local_ci,
          silences: run.silences,
          stall_after: run.stall_after,
          agent: agent_up
        ),
      queue:
        Lanes.queue(repo, board,
          now: now,
          last_visit: last_visit,
          filter: socket.assigns.queue_filter,
          limit: socket.assigns.queue_limit
        ),
      log: Lanes.merge_log(repo, now: now, tz_offset: tz_offset, local_ci: local_ci),
      digest:
        if freshness.state == :unknown do
          nil
        else
          Lanes.digest(repo, board,
            now: now,
            last_visit: last_visit,
            tz_offset: tz_offset,
            frozen_at: frozen_at,
            frozen: freshness.frozen?
          )
        end
    }
  end

  # The orchestrator's answer, asked once per load (the throughput strip
  # reads the same answer): only a refused or broken API is "down"; a board
  # with the API switched off does not know.
  defp agent_status({:ok, _load}), do: :up
  defp agent_status({:error, :not_configured}), do: :unknown
  defp agent_status({:error, _reason}), do: :down

  # The silences are read once per render, with the real clock: the ticket
  # database is local and live even when GitHub is frozen.
  defp run_context(repo, agent, board, now, frozen_at) do
    tickets = tickets_by_number(agent.tickets, repo)

    %{
      tickets: tickets,
      silences: AgentSignal.silences(board.running, tickets, now),
      stall_after: AgentSignal.stall_after(),
      now: now,
      frozen_at: frozen_at
    }
  end

  defp running_card(task, run) do
    ticket = Map.get(run.tickets, task.number)
    silence = Map.get(run.silences, task.number)

    %{
      id: task.id,
      number: task.number,
      title: task.title,
      step: AgentWorktree.step(ticket),
      elapsed: task.started_at && Time.age_seconds(task.started_at, run.frozen_at || run.now),
      silence: silence,
      stalled: AgentSignal.stalled?(silence, run.stall_after),
      agent: nil,
      phases: []
    }
  end

  defp tickets_by_number(tickets, repo) do
    for ticket <- tickets,
        AgentState.same_repository?(ticket, repo),
        number <- ticket["numbers"] || [],
        into: %{},
        do: {number, ticket}
  end

  defp empty?(board) do
    total = board.task_counts |> Map.values() |> Enum.sum()
    total == 0 and board.merged == []
  end

  defp empty_work do
    %{
      running: [],
      retrying: [],
      needs: [],
      queue: %{
        items: [],
        total: 0,
        hidden: 0,
        limit: 8,
        counts: %{all: 0, new: 0, split: 0, dupes: 0},
        filters: [],
        filter: :all
      },
      log: %{days: [], groups: [], total: 0}
    }
  end

  defp unknown_freshness do
    Freshness.snapshot(
      now: DateTime.utc_now(),
      connected: true,
      last_attempt: nil,
      last_success: nil,
      agent: %{ok: false, at: nil, tickets: [], error: :unknown}
    )
  end

  # Nothing running, nothing waiting on the owner, queue empty: the wide
  # layout collapses the lanes into one compact row and gives the merge
  # history the rest of the width.
  defp idle_board?(work) do
    work.running == [] and work.retrying == [] and work.needs == [] and
      work.queue.items == []
  end

  defp load_inspector(socket) do
    case socket.assigns.conversation do
      nil ->
        assign(socket,
          inspector_activity: [],
          inspector_calls: [],
          inspector_executions: [],
          inspector_executions_for: nil,
          inspector_runner_executions: [],
          inspector_dispatch_paused: false,
          inspector_dispatch_active: false,
          inspector_dispatch_ceiling: 5.0,
          inspector_dispatch_fallback: nil,
          inspector_usage: nil,
          inspector_pr: nil,
          inspector_ci: nil,
          inspector_failure: nil
        )

      task ->
        pr = Board.task_pull_request(task, socket.assigns.comments)

        ci = pr && Map.get(socket.assigns.local_ci, pr.number)

        executions = inspector_executions(socket, task)
        runner_executions = Runners.for_task(task.id)

        assign(socket,
          inspector_activity: Board.task_activity(task, pr),
          inspector_calls: AI.recent_for_task(task.id),
          inspector_executions: executions,
          inspector_executions_for:
            if(socket.assigns.inspector_tab == "execucoes", do: task.id, else: nil),
          inspector_runner_executions: runner_executions,
          inspector_dispatch_paused: Runners.paused?(),
          inspector_dispatch_active:
            Enum.any?(runner_executions, &(&1.status in ["starting", "running"])),
          inspector_dispatch_ceiling: Runners.task_ceiling_usd(task.executor),
          inspector_dispatch_fallback:
            case List.first(runner_executions) do
              nil -> nil
              execution -> Runners.fallback(execution)
            end,
          inspector_usage: executor_usage(socket, task),
          inspector_pr: pr,
          inspector_ci: ci,
          inspector_failure: inspector_failure(socket, task),
          inspector_tab: socket.assigns.inspector_tab || "conversa"
        )
    end
  end

  # The failure block of the open task: the same words as its card, with
  # the attempts and which of them the board asked for.
  defp inspector_failure(socket, task) do
    ticket =
      socket.assigns
      |> Map.get(:agent_snapshot, %{tickets: []})
      |> Map.get(:tickets, [])
      |> Enum.find(fn ticket ->
        task.number in (ticket["numbers"] || []) and
          AgentState.same_repository?(ticket, socket.assigns.repo)
      end)

    AgentBlock.explain(ticket,
      tz_offset: socket.assigns.tz_offset,
      retries: AutoRetry.attempts(ticket && ticket["id"])
    )
  end

  # The runner's ceiling, saved through its API; the tile re-reads the load.
  defp set_max_workers(socket, max) do
    case Actions.run(:set_max_workers, %{max: max}, ui()) do
      {:ok, max} ->
        socket
        |> load(socket.assigns.repo)
        |> put_flash(:info, "Limite do executor: #{agents(max)}.")

      {:ok, max, :restarting} ->
        socket
        |> load(socket.assigns.repo)
        |> put_flash(:info, "Limite do executor: #{agents(max)}. O orquestrador vai reiniciar.")

      {:error, :conflict} ->
        socket
        |> load(socket.assigns.repo)
        |> put_flash(
          :error,
          "As configurações do executor mudaram no painel do agente. Confira o limite e tente de novo."
        )

      {:error, reason} ->
        put_flash(
          socket,
          :error,
          "Não foi possível mudar o limite do executor (#{limit_reason(reason)})."
        )
    end
  end

  defp agents(1), do: "1 agente"
  defp agents(n), do: "#{n} agentes"

  defp limit_reason(:out_of_range), do: "fica entre 1 e 16"
  defp limit_reason(:not_configured), do: "API do orquestrador desligada"
  defp limit_reason(:unreachable), do: "orquestrador fora do ar"
  defp limit_reason(:timeout), do: "o orquestrador não respondeu"
  defp limit_reason({:refused, message}) when is_binary(message), do: message
  defp limit_reason({:http, status}), do: "HTTP #{status}"
  defp limit_reason(_reason), do: "resposta inesperada"

  # The ledger is read when the Execuções tab opens and reused while the
  # task and the tab stay the same: a board update does not query it again.
  defp inspector_executions(socket, task) do
    if socket.assigns.inspector_tab == "execucoes" do
      if socket.assigns[:inspector_executions_for] == task.id do
        socket.assigns[:inspector_executions] || []
      else
        Report.by_task(task.id, tickets: task_tickets(socket, task))
      end
    else
      []
    end
  end

  defp task_tickets(socket, task) do
    repo = socket.assigns[:repo]

    case socket.assigns[:agent_snapshot] do
      %{tickets: tickets} ->
        Enum.filter(tickets, fn ticket ->
          task.number in (ticket["numbers"] || []) and
            (repo == nil or AgentState.same_repository?(ticket, repo))
        end)

      _ ->
        []
    end
  end

  # The executor's transcripts are read only while the task is open, and an
  # unchanged reading is reused, so a board update does not decompress them.
  defp executor_usage(socket, task) do
    tickets =
      case socket.assigns[:agent_snapshot] do
        %{tickets: tickets} -> Enum.filter(tickets, &(task.number in (&1["numbers"] || [])))
        _ -> []
      end

    previous = socket.assigns[:inspector_usage]
    Harness.for_tickets(tickets, previous)
  end

  defp refresh_inspector_after_act(socket, task_id) do
    case socket.assigns.conversation do
      %Task{id: ^task_id} ->
        task = Board.task(task_id)

        socket
        |> assign(conversation: task, comments: Board.comments(task))
        |> load_inspector()

      _ ->
        socket
    end
  end

  defp with_runner_running(today) do
    running = Runners.running_items()
    merged = (running ++ today.running) |> Enum.uniq_by(& &1.id)
    Map.put(today, :running, merged)
  end

  defp load(socket, nil) do
    today = Overview.today() |> with_runner_running()

    socket
    |> assign(
      repo: nil,
      board: empty(),
      resume: nil,
      events: [],
      sync_event: nil,
      inspector_tab: "conversa",
      inspector_activity: [],
      inspector_calls: [],
      inspector_pr: nil,
      sync_snapshot: %{last_attempt: nil, last_success: nil},
      freshness: unknown_freshness(),
      repo_overview: today.repos,
      today: today,
      today_spend: Report.today(socket.assigns.tz_offset),
      objectives: [],
      agent_snapshot: %{ok: false, at: nil, tickets: [], error: :unknown},
      work: empty_work(),
      digest: nil,
      live: connected?(socket),
      ai_calls: [],
      ai_status: AI.status()
    )
  end

  # The span is the board's load budget on the dashboard
  # (`agent_board.board.load`): every reload goes through here.
  defp load(socket, repo) do
    :telemetry.span([:agent_board, :board, :load], %{repository: repo_slug(repo)}, fn ->
      {read_board(socket, repo), %{repository: repo_slug(repo)}}
    end)
  end

  defp read_board(socket, repo) do
    today = Overview.today() |> with_runner_running()
    spend = Report.today(socket.assigns.tz_offset)

    # load/2 runs again on every reload: subscribing twice would deliver every
    # broadcast twice (and keep listening to the old repo).
    if connected?(socket) and socket.assigns.repo != repo do
      if socket.assigns.repo, do: Board.unsubscribe(socket.assigns.repo.id)
      Board.subscribe(repo.id)
    end

    socket =
      if socket.assigns.repo != repo,
        do:
          assign(socket,
            conversation: nil,
            comments: [],
            intake: nil,
            intake_draft: nil,
            composer_text: "",
            composer_title: nil,
            composer_split: false,
            composer_selected: MapSet.new(),
            composer_error: nil,
            composer_retry: nil,
            composer_job: nil,
            composer_receipt: nil,
            composer_answers: "",
            composer_routing: nil,
            composer_routing_for: nil,
            composer_executor: nil,
            composer_executor_touched: false,
            inspector_tab: "conversa",
            inspector_activity: [],
            inspector_calls: [],
            inspector_pr: nil,
            toast: nil,
            highlight_changes: false,
            needs_expanded: false,
            queue_limit: 8,
            queue_filter: :all
          ),
        else: socket

    {merged_limit, task_limits} = pagination_limits(socket, repo)

    case Board.board("#{repo.owner}/#{repo.name}", merged_limit, task_limits) do
      {:ok, board} ->
        snapshot = Board.sync_snapshot(repo)
        agent = AgentState.snapshot()

        freshness =
          Freshness.snapshot(
            now: DateTime.utc_now(),
            connected: connected?(socket),
            last_attempt: snapshot.last_attempt,
            last_success: snapshot.last_success,
            agent: agent
          )

        local_ci =
          LocalCI.by_pr(repo, agent.tickets,
            workpads: Board.agent_workpads(repo.id),
            heads: Board.pull_heads(repo.id)
          )

        orchestrator = Orchestrator.load()
        work = work_for(repo, board, agent, freshness, socket, local_ci, orchestrator)
        flow = flow_for(repo, agent, socket.assigns.tz_offset, orchestrator)

        assign(socket,
          repo: repo,
          local_ci: local_ci,
          board: board,
          flow: flow,
          resume: nil,
          events: Board.events(repo),
          sync_event: snapshot.last_attempt,
          sync_snapshot: snapshot,
          freshness: freshness,
          repo_overview: today.repos,
          today: today,
          today_spend: spend,
          objectives: Board.objectives(repo),
          agent_snapshot: agent,
          work: work,
          digest: work.digest,
          ai_calls: AI.recent(5),
          ai_status: AI.status(),
          live: connected?(socket)
        )

      _ ->
        assign(socket,
          repo: nil,
          local_ci: %{},
          board: empty(),
          resume: nil,
          events: [],
          sync_event: nil,
          sync_snapshot: %{last_attempt: nil, last_success: nil},
          freshness: unknown_freshness(),
          repo_overview: today.repos,
          today: today,
          today_spend: spend,
          objectives: [],
          agent_snapshot: %{ok: false, at: nil, tickets: [], error: :unknown},
          work: empty_work(),
          flow: nil,
          digest: nil,
          live: connected?(socket),
          ai_calls: [],
          ai_status: AI.status()
        )
    end
  end

  # The throughput strip: read once per load, from the tables, the agent's
  # tickets and the orchestrator; the arithmetic is pure and tested apart.
  defp flow_for(repo, agent, tz_offset, orchestrator) do
    now = DateTime.utc_now()

    repo
    |> Observations.read(agent, now: now, load: orchestrator)
    |> Metrics.throughput(now, tz_offset)
  end

  defp pagination_limits(socket, repo) do
    if socket.assigns.repo == repo do
      merged = max(length(socket.assigns.board.merged), Board.merged_page_size())

      tasks =
        Map.new(Board.task_states(), fn state ->
          {state, max(length(Map.fetch!(socket.assigns.board, state)), Board.task_page_size())}
        end)

      {merged, tasks}
    else
      resume = resume_for(socket.assigns.resume, repo)
      resume_tasks = if is_map(resume["tasks"]), do: resume["tasks"], else: %{}

      tasks =
        Map.new(Board.task_states(), fn state ->
          {state, resume_limit(resume_tasks[Atom.to_string(state)], Board.task_page_size())}
        end)

      {resume_limit(resume["merged"], Board.merged_page_size()), tasks}
    end
  end

  defp resume_for(%{"repo" => slug} = resume, repo) do
    if slug == "#{repo.owner}/#{repo.name}", do: resume, else: %{}
  end

  defp resume_for(_, _), do: %{}

  defp resume_limit(count, minimum) when is_integer(count) and count > minimum,
    do: min(count, @max_resume_items)

  defp resume_limit(_, minimum), do: minimum

  @impl true
  def handle_info({:answer, task_id, result}, socket) do
    current = socket.assigns.conversation && socket.assigns.conversation.id

    if current == task_id do
      {:noreply, answer_arrived(socket, result)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:voice_turn_timeout, ref}, socket),
    do: {:noreply, VoiceConversation.timeout(socket, ref)}

  def handle_info({:composer_timeout, ref}, socket) do
    case socket.assigns.composer_job do
      %{ref: ^ref, kind: kind, payload: payload} ->
        seconds = div(composer_timeout(), 1000)

        {:noreply,
         socket
         |> cancel_composer_job()
         |> composer_error(
           "#{job_name(kind)} não terminou em #{seconds} s. Nada foi confirmado; tente de novo.",
           {kind, payload}
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(:restart_server, socket) do
    Actions.run(:restart_board, %{}, ui())
    {:noreply, socket}
  end

  # The summary of the day's settings live in their own fold.
  def handle_info({:setting_changed, "daily_summary_" <> _}, socket) do
    send_update(BoardComponents.DailySummarySettings, id: "settings-daily-summary-section")
    {:noreply, socket}
  end

  # A summary of the day went out or was dismissed on some board.
  def handle_info({:daily_summary, _event, _id}, socket),
    do: {:noreply, show_daily_summary(socket)}

  def handle_info(:repos_changed, socket) do
    repos = Board.list_repositories()

    if Enum.map(repos, & &1.id) == Enum.map(socket.assigns.repos, & &1.id) do
      {:noreply, socket}
    else
      {:noreply, socket |> assign(:repos, repos) |> load(socket.assigns.repo)}
    end
  end

  def handle_info({:setting_changed, "dispatch_paused"}, socket) do
    {:noreply,
     socket
     |> assign(:dispatch_paused, Runners.paused?())
     |> load_inspector()}
  end

  # A setting changed somewhere (another tab, the API, a spoken command):
  # this board's voice follows at once, keeping the list it already loaded.
  def handle_info({:setting_changed, _key}, socket),
    do: {:noreply, assign(socket, :voice, refreshed_voice(socket.assigns.voice))}

  @impl true
  def handle_info({:voice_activity, event}, socket),
    do: {:noreply, VoiceConversation.activity(socket, event)}

  # "Religar o agente" worked: the item that held the button leaves on the
  # reload, so the result is said here (AgentAction), then every board reloads.
  def handle_info({:agent_restarted, text}, socket) do
    AgentBoard.AgentControl.refresh_boards()
    {:noreply, put_flash(socket, :info, text)}
  end

  # The "Hoje" view listens to every repository. A change in the repository
  # already on screen arrives as :board_updated; this one is the other one.
  def handle_info({:today_updated, repository_id}, socket) do
    current = socket.assigns.repo && socket.assigns.repo.id

    if socket.assigns.view == "hoje" and current != repository_id do
      {:noreply, load(socket, socket.assigns.repo)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:superagents_changed, socket) do
    socket = assign(socket, :superagents, Superagents.list())

    # A new profile becomes a new source while the sheet is open; the old
    # entries stay in the buffer and the new file is read from its tail.
    socket =
      if socket.assigns.panel == "logs" do
        socket = assign(:logs_sources, Logs.sources(socket.assigns.superagents))
        if socket.assigns.logs_paused, do: socket, else: read_logs_once(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:logs_tick, token}, socket) do
    current = socket.assigns.logs_timer

    if socket.assigns.panel == "logs" and not socket.assigns.logs_paused and
         match?(%{token: ^token}, current) do
      {:noreply, socket |> read_logs_once() |> schedule_logs_tick()}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:board_updated, socket) do
    old_board = socket.assigns.board
    old_sync = socket.assigns.sync_event
    old_needs = socket.assigns.work.needs

    socket =
      socket
      |> load(socket.assigns.repo)
      |> refresh_conversation()
      |> load_inspector()
      |> announce(old_board, old_sync, old_needs)
      |> VoiceConversation.check_answers()

    {:noreply, socket}
  end

  defp refresh_conversation(%{assigns: %{conversation: nil}} = socket), do: socket

  defp refresh_conversation(socket) do
    case Board.task(socket.assigns.conversation.id) do
      nil ->
        assign(socket, conversation: nil, comments: [])

      task ->
        assign(socket, conversation: task, comments: Board.comments(task))
    end
  end

  defp refresh_ai(socket), do: assign(socket, ai_calls: AI.recent(5), ai_status: AI.status())

  @impl true
  def handle_params(params, _uri, socket) do
    current = socket.assigns.repo || socket.assigns.opening_repo

    repo =
      case params["repo"] do
        nil -> current
        slug -> Board.repository_by_slug(slug) || current
      end

    # A patch inside the same repository (opening a task, a panel, a tab)
    # changes only the panel: the board is already loaded and every change
    # to it arrives as :board_updated.
    previous_view = socket.assigns.view
    previous_panel = socket.assigns.panel
    was_showing = showing?(socket, repo)
    socket = if was_showing, do: socket, else: load(socket, repo)

    socket =
      socket
      |> BoardNavigation.apply_params(params)
      |> sync_logs_panel(previous_panel)
      |> load_inspector()
      |> load_panel()
      |> load_composer_routing()

    # Entering "Hoje" from an already loaded repository reads the other
    # repository too; the load is the same one the board already does.
    socket =
      if was_showing and previous_view != "hoje" and socket.assigns.view == "hoje",
        do: load(socket, repo),
        else: socket

    {:noreply, socket}
  end

  # -- the logs sheet ---------------------------------------------------------
  #
  # The sheet owns a timer only while its panel is the routed one. Opening
  # reads once from the tail of each source; every tick reads at most 64 KiB
  # per source and schedules the next tick only after the read returns, so a
  # slow file never queues work. Closing cancels the timer; a tick that arrives
  # after the panel changed is ignored by its token.

  defp sync_logs_panel(%{assigns: %{panel: "logs"}} = socket, "logs"), do: socket

  defp sync_logs_panel(%{assigns: %{panel: "logs"}} = socket, _previous),
    do: open_logs_panel(socket)

  defp sync_logs_panel(socket, "logs"), do: close_logs_panel(socket)
  defp sync_logs_panel(socket, _previous), do: socket

  defp open_logs_panel(socket) do
    sources = Logs.sources(socket.assigns.superagents)

    socket =
      assign(socket,
        logs_sources: sources,
        logs_entries: [],
        logs_state: Logs.empty_state(),
        logs_status: %{},
        logs_paused: false
      )

    if connected?(socket) do
      socket
      |> read_logs_once()
      |> schedule_logs_tick()
    else
      socket
    end
  end

  defp close_logs_panel(socket) do
    cancel_logs_timer(socket)
    assign(socket, logs_timer: nil, logs_paused: false)
  end

  defp read_logs_once(socket) do
    %{entries: entries, state: state, statuses: statuses} =
      Logs.read(socket.assigns.logs_sources, socket.assigns.logs_state)

    assign(socket,
      logs_entries: Logs.append(socket.assigns.logs_entries, entries),
      logs_state: state,
      logs_status: statuses
    )
  rescue
    # The observer never takes the board down and never logs into the file it
    # is reading: the unreadable state is the whole failure surface.
    _exception ->
      assign(socket, logs_status: Map.new(socket.assigns.logs_sources, &{&1.id, :unreadable}))
  end

  defp schedule_logs_tick(%{assigns: %{logs_paused: true}} = socket), do: socket

  defp schedule_logs_tick(socket) do
    token = make_ref()
    ref = Process.send_after(self(), {:logs_tick, token}, logs_tick_interval())
    assign(socket, :logs_timer, %{ref: ref, token: token})
  end

  defp cancel_logs_timer(%{assigns: %{logs_timer: %{ref: ref}}}) when is_reference(ref),
    do: Process.cancel_timer(ref)

  defp cancel_logs_timer(_socket), do: :ok

  defp logs_tick_interval, do: Application.get_env(:agent_board, :logs_tick_interval, 2_000)

  defp showing?(%{assigns: %{repo: %{id: id}}}, %{id: id}), do: true
  defp showing?(_socket, _repo), do: false

  @impl true
  def handle_event("set_max_workers", %{"to" => to}, socket) do
    case Integer.parse(to) do
      {max, ""} -> {:noreply, set_max_workers(socket, max)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("sync_now", _params, socket) do
    case Actions.run(:sync_now, %{}, ui()) do
      {:ok, _job} ->
        {:noreply, put_flash(socket, :info, "Sincronização pedida.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível pedir a sincronização.")}
    end
  end

  @impl true
  def handle_event("board_reconnected", _params, socket) do
    # A reconnect refreshes the board, but it is routine transport noise; it
    # must not put a toast in front of the owner.
    {:noreply, socket |> load(socket.assigns.repo) |> assign(:toast, nil)}
  end

  @impl true
  def handle_event("needs_more", _params, socket) do
    {:noreply, assign(socket, :needs_expanded, true)}
  end

  @impl true
  def handle_event("queue_more", _params, socket) do
    next_limit = if socket.assigns.queue_limit < 50, do: 50, else: socket.assigns.queue_limit + 50

    {:noreply, socket |> assign(:queue_limit, next_limit) |> load(socket.assigns.repo)}
  end

  @impl true
  def handle_event("filter_queue", %{"filter" => filter}, socket) do
    filter =
      case filter do
        "new" -> :new
        "split" -> :split
        "dupes" -> :dupes
        _ -> :all
      end

    {:noreply, socket |> assign(:queue_filter, filter) |> load(socket.assigns.repo)}
  end

  @impl true
  def handle_event("dismiss_toast", _params, socket), do: {:noreply, assign(socket, :toast, nil)}

  @impl true
  def handle_event("daily_summary_claim", %{"id" => id}, socket) do
    case Integer.parse(to_string(id)) do
      {id, ""} -> {:noreply, claim_daily_summary(socket, id)}
      _other -> {:noreply, socket}
    end
  end

  def handle_event("dismiss_daily_summary", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(to_string(id)),
         do: Actions.run(:dismiss_summary, %{id: id}, ui())

    {:noreply, assign(socket, :daily_summary, nil)}
  end

  @impl true
  def handle_event("show_changes", _params, socket) do
    {:noreply, assign(socket, toast: nil, highlight_changes: true)}
  end

  @impl true
  def handle_event("toggle_dispatch", _params, socket) do
    value = if Runners.paused?(), do: "false", else: "true"

    case Actions.run(:change_setting, %{setting: "dispatch_paused", value: value}, ui()) do
      :ok ->
        {:noreply,
         socket
         |> assign(:dispatch_paused, Runners.paused?())
         |> load_inspector()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select", %{"view" => "hoje"}, socket) do
    {:noreply, push_patch(socket, to: BoardNavigation.today_path())}
  end

  def handle_event("open_any", %{"id" => id}, socket) do
    with {task_id, ""} <- Integer.parse(to_string(id)),
         %Task{} = task <- Board.task(task_id) do
      {:noreply,
       push_patch(socket, to: BoardNavigation.path(task.repository, "conversation", task.id))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("select", %{"repo" => slug}, socket) do
    current = socket.assigns.repo

    if current && slug == "#{current.owner}/#{current.name}" do
      # LiveView recovers phx-change forms after reconnect. Same selection must not close a panel.
      {:noreply, socket}
    else
      {:noreply, push_patch(socket, to: "/?repo=#{URI.encode_www_form(slug)}")}
    end
  end

  @impl true
  def handle_event("load_more_merged", %{"id" => tail_id}, socket) do
    case {socket.assigns.repo, socket.assigns.board} do
      {%{id: repository_id}, %{merged_has_more: true, merged: [_ | _] = merged} = board} ->
        last = List.last(merged)

        if tail_id == "merged-tail-#{last.id}" do
          page_size = Board.merged_page_size()
          rows = Board.merged_page(repository_id, {last.merged_at, last.id}, page_size + 1)

          updated = %{
            board
            | merged: Enum.uniq_by(merged ++ Enum.take(rows, page_size), & &1.id),
              merged_has_more: length(rows) > page_size
          }

          {:noreply, assign(socket, :board, updated)}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("load_more_tasks", %{"id" => tail_id}, socket) do
    board = socket.assigns.board

    state =
      Enum.find(Board.task_states(), fn state ->
        case {board.task_has_more[state], List.last(Map.fetch!(board, state))} do
          {true, %Task{id: id}} -> tail_id == "task-tail-#{state}-#{id}"
          _ -> false
        end
      end)

    if state && socket.assigns.repo do
      items = Map.fetch!(board, state)
      last = List.last(items)
      page_size = Board.task_page_size()

      rows =
        Board.task_page(socket.assigns.repo.id, state, {last.updated_at, last.id}, page_size + 1)

      updated =
        board
        |> Map.put(state, Enum.uniq_by(items ++ Enum.take(rows, page_size), & &1.id))
        |> Map.update!(:task_has_more, &Map.put(&1, state, length(rows) > page_size))

      {:noreply, assign(socket, :board, updated)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add", %{"owner" => owner, "name" => name}, socket) do
    case Actions.run(:add_repository, %{owner: owner, name: name}, ui()) do
      {:ok, _} ->
        repos = Board.list_repositories()
        repo = Enum.find(repos, &(&1.owner == owner and &1.name == name))
        {:noreply, socket |> assign(:repos, repos) |> load(repo)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Não foi possível acompanhar #{owner}/#{name}")}
    end
  end

  @impl true
  def handle_event("act", %{"id" => id, "action" => action} = params, socket) do
    {task_id, _} = Integer.parse(id)
    repo = socket.assigns.repo

    task =
      repo &&
        Board.task_of(repo, task_id)

    # Stop is red: it runs only with the sentence its confirmation showed.
    result =
      case {Map.get(@task_actions, action), task} do
        {name, %Task{}} when not is_nil(name) ->
          Actions.run(name, %{task: task}, ui(), confirm: params["confirm"])

        _ ->
          {:error, :not_found}
      end

    case result do
      {:error, {refusal, _phrase}} when refusal in [:unconfirmed, :phrase_changed] ->
        {:noreply, put_flash(socket, :error, @refused_text)}

      {:ok, _} ->
        {:noreply,
         socket
         |> refresh_inspector_after_act(task_id)
         |> put_flash(:info, "Tarefa atualizada")
         |> speak(Voice.task_summary(task.title, action, socket.assigns.voice.language))}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível atualizar a tarefa")}
    end
  end

  def handle_event("stop_execution", %{"id" => id, "confirm" => confirm}, socket) do
    with {execution_id, _} <- Integer.parse(id),
         %Execution{} = execution <- Runners.get_execution(execution_id),
         %Task{} = task <- Board.task(execution.task_id) do
      case Actions.run(:stop_execution, %{execution: execution, task: task}, ui(),
             confirm: confirm
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> refresh_inspector_after_act(task.id)
           |> put_flash(:info, "Execução parada; a tarefa ficou bloqueada para você decidir.")}

        {:error, {refusal, _phrase}} when refusal in [:unconfirmed, :phrase_changed] ->
          {:noreply, put_flash(socket, :error, @refused_text)}

        {:error, text} ->
          {:noreply, put_flash(socket, :error, text)}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Execução não encontrada.")}
    end
  end

  @impl true
  def handle_event("open", %{"id" => id} = params, socket) do
    {:noreply, BoardNavigation.open_task(socket, id, params["tab"])}
  end

  @impl true
  def handle_event("inspector_tab", %{"tab" => tab}, socket) do
    tab = if tab in ~w(conversa atividade chamadas execucoes pr), do: tab, else: "conversa"
    socket = socket |> assign(:inspector_tab, tab) |> load_inspector()

    case socket.assigns.conversation do
      %Task{} = task ->
        {:noreply,
         push_patch(socket,
           to: BoardNavigation.path(socket.assigns.repo, "conversation", task.id, tab)
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("executor_days", %{"days" => days}, socket) do
    days = if days in ["7", "30"], do: String.to_integer(days), else: 7
    {:noreply, load_executors(socket, days)}
  end

  @impl true
  def handle_event("show_panel", %{"panel" => panel}, socket) do
    {:noreply, BoardNavigation.open_panel(socket, panel)}
  end

  def handle_event("provision_review", params, socket) do
    with {repository_id, ""} <- Integer.parse(params["repository_id"] || ""),
         {source_id, ""} <- Integer.parse(params["source_id"] || ""),
         %AgentBoard.Board.Repository{} = repository <-
           Board.repository(repository_id),
         %AgentBoard.Superagents.Superagent{} = source <- Superagents.get(source_id),
         path when is_binary(path) and path != "" <- String.trim(params["path"] || ""),
         path = Path.expand(path),
         {workers, ""} <- Integer.parse(params["workers"] || "3") do
      params = %{repository: repository, source: source, path: path, workers: workers}

      {:noreply,
       assign(socket, :provision_preview, %{
         params: params,
         phrase: Actions.phrase(:provision_superagent, params)
       })}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Confira repositório, origem, caminho e workers.")}
    end
  end

  def handle_event("provision_cancel", _params, socket),
    do: {:noreply, assign(socket, :provision_preview, nil)}

  def handle_event(
        "provision_confirm",
        _params,
        %{assigns: %{provision_preview: %{params: params, phrase: phrase}}} = socket
      ) do
    {:noreply,
     socket
     |> assign(provision_preview: nil, provisioning: true)
     |> start_async(:provision, fn ->
       Actions.run(:provision_superagent, params, ui(), confirm: phrase)
     end)}
  end

  def handle_event("provision_confirm", _params, socket), do: {:noreply, socket}

  def handle_event("superagent_command", %{"id" => id, "action" => action}, socket) do
    name = if action == "pause", do: :pause_superagent, else: :resume_superagent
    superagent = Superagents.get(id)

    {:noreply,
     start_async(socket, {:superagent_command, superagent.id}, fn ->
       Actions.run(name, %{superagent: superagent}, ui())
     end)}
  end

  def handle_event("superagent_scale", %{"id" => id, "delta" => delta}, socket) do
    superagent = Superagents.get(id)

    with {delta, ""} <- Integer.parse(delta),
         workers = max(1, min(32, superagent.max_workers + delta)),
         true <- workers != superagent.max_workers do
      {:noreply,
       start_async(socket, {:superagent_scale, superagent.id}, fn ->
         Actions.run(:scale_superagent, %{superagent: superagent, workers: workers}, ui())
       end)}
    else
      false -> {:noreply, socket}
      _ -> {:noreply, put_flash(socket, :error, "Não foi possível mudar o limite de sessões.")}
    end
  end

  @impl true
  def handle_event("dismiss_panel", _params, socket) do
    {:noreply, push_patch(socket, to: BoardNavigation.path(socket.assigns.repo), replace: true)}
  end

  # A question to the agent is red (it posts on GitHub): the first submit
  # shows the sentence, only "Mandar" posts it, Cancelar records the no.
  @impl true
  def handle_event("ask", %{"body" => body}, socket) do
    case {socket.assigns.conversation, String.trim(body)} do
      {nil, _body} ->
        {:noreply, put_flash(socket, :error, "Abra uma tarefa primeiro")}

      {_task, ""} ->
        {:noreply, socket}

      {task, body} ->
        params = %{task: task, question: body}
        pending = %{task_id: task.id, body: body, phrase: Actions.phrase(:ask_task, params)}
        {:noreply, assign(socket, ask_pending: pending)}
    end
  end

  @impl true
  def handle_event("ask_cancel", _params, socket) do
    case {socket.assigns.conversation, socket.assigns.ask_pending} do
      {%Task{} = task, %{body: body}} ->
        :ok = Actions.decline(:ask_task, %{task: task, question: body}, ui())
        {:noreply, assign(socket, ask_pending: nil, ask_draft: body)}

      _ ->
        {:noreply, assign(socket, ask_pending: nil)}
    end
  end

  @impl true
  def handle_event("ask_confirm", _params, socket) do
    case {socket.assigns.conversation, socket.assigns.ask_pending} do
      {nil, _pending} ->
        {:noreply, put_flash(socket, :error, "Abra uma tarefa primeiro")}

      {_task, pending} when not is_map(pending) ->
        {:noreply, socket}

      {%Task{id: id} = task, %{task_id: id, body: body, phrase: phrase}} ->
        socket = assign(socket, ask_pending: nil, ask_draft: "")
        params = %{task: task, question: body, client: GitHub.client()}

        case Actions.run(:ask_task, params, ui(), confirm: phrase) do
          {:error, {refusal, _phrase}} when refusal in [:unconfirmed, :phrase_changed] ->
            {:noreply, socket |> assign(ask_draft: body) |> put_flash(:error, @refused_text)}

          {:ok, _} ->
            ask_in_background(task, body)

            {:noreply,
             assign(socket,
               conversation: Board.task(task.id),
               comments: Board.comments(task)
             )
             |> load_inspector()
             |> put_flash(:info, "Pergunta enviada")}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(ask_draft: body)
             |> put_flash(:error, "A pergunta não chegou ao GitHub")}
        end

      {_task, _pending_for_another_task} ->
        {:noreply, assign(socket, ask_pending: nil)}
    end
  end

  @impl true
  def handle_event("check_version", _params, socket) do
    case Version.refresh() do
      {:ok, _sha} ->
        {:noreply, assign(socket, version: Version.status())}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Não consegui falar com a main: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("update", _params, socket) do
    # The button only appears when the panel already knows the checkout is
    # behind. A successful fast-forward is therefore always followed by a
    # restart, even when the short-sha comparison races the fetch.
    case Actions.run(:update_board, %{}, ui()) do
      {:ok, sha} ->
        {:noreply,
         restart_after_update(socket, "Atualizado para #{sha}; reiniciando o servidor…")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "A atualização falhou: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("restart", _params, socket) do
    {:noreply, restart_after_update(socket, "Reiniciando o servidor…")}
  end

  @impl true
  def handle_event("intake_draft_change", %{"text" => text} = params, socket)
      when is_binary(text) do
    socket = invalidate_intake_if_changed(socket, text)
    repo = socket.assigns.repo
    source_repo = params["source_repo"]

    if repo && (is_nil(source_repo) || source_repo == to_string(repo.id)) do
      source = if source_repo, do: :voice, else: :typed
      {:noreply, assign(socket, :intake_draft, %{text: text, repo_id: repo.id, source: source})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("intake_draft_change", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("open_composer", params, socket) do
    # "Dividir pedido" asks for the split; "Novo pedido" keeps the draft as it
    # is, so a proposal or a receipt is not lost by reopening the panel.
    split = params["split"] == "true" or socket.assigns.composer_split
    socket = assign(socket, composer_split: split)
    {:noreply, BoardNavigation.open_panel(socket, "composer")}
  end

  @impl true
  def handle_event("composer_change", params, socket) do
    text = params["text"] || socket.assigns.composer_text
    changed? = text != socket.assigns.composer_text

    selected =
      case params do
        %{"tasks" => tasks} -> MapSet.new(tasks, &String.to_integer/1)
        _ -> socket.assigns.composer_selected
      end

    # New words invalidate the proposal (it was for other words) and the
    # last failure; a checkbox or a title edit must not hide either.
    socket =
      if changed?,
        do:
          assign(socket,
            intake: nil,
            composer_selected: MapSet.new(),
            composer_error: nil,
            composer_retry: nil
          ),
        else: assign(socket, composer_selected: selected)

    {:noreply,
     socket
     |> assign(
       composer_text: text,
       composer_title: edited_title(params, text, socket.assigns.composer_title),
       composer_answers: params["answers"] || socket.assigns.composer_answers
     )
     |> choose_executor(params["executor"])}
  end

  @impl true
  def handle_event("composer_split", _params, socket) do
    if socket.assigns.composer_job do
      {:noreply, socket}
    else
      split = not socket.assigns.composer_split
      text = String.trim(socket.assigns.composer_text)

      socket =
        assign(socket,
          composer_split: split,
          composer_error: nil,
          composer_retry: nil,
          intake: if(split, do: socket.assigns.intake, else: nil),
          composer_selected: if(split, do: socket.assigns.composer_selected, else: MapSet.new())
        )

      if split and text != "" and is_nil(socket.assigns.intake),
        do: start_split(socket, text),
        else: {:noreply, socket}
    end
  end

  @impl true
  def handle_event("composer_submit", params, socket) do
    text = String.trim(params["text"] || socket.assigns.composer_text)
    socket = socket |> choose_executor(params["executor"]) |> ensure_composer_routing()
    # The sentence the composer showed when the person pressed send.
    shown = composer_phrase(socket.assigns)

    socket =
      assign(socket, composer_answers: params["answers"] || socket.assigns.composer_answers)

    cond do
      # A second submit while the first is in flight: the job is the receipt.
      socket.assigns.composer_job ->
        {:noreply, socket}

      is_nil(socket.assigns.repo) ->
        {:noreply, composer_error(socket, "Escolha um repositório antes de enviar.")}

      text == "" ->
        {:noreply, composer_error(socket, "Escreva o pedido antes de enviar.")}

      socket.assigns.composer_split ->
        submit_split(socket, text, params, shown)

      # The title the screen confirmed (`composer_title`, kept by the
      # change events), never the field as the send carried it.
      true ->
        start_single(socket, text, socket.assigns.composer_title, shown)
    end
  end

  @impl true
  def handle_event("composer_retry", _params, socket) do
    socket = assign(socket, composer_error: nil, composer_receipt: nil)

    case {socket.assigns.composer_job, socket.assigns.composer_retry} do
      {nil, {:split, text}} ->
        start_split(socket, text)

      {nil, {:enqueue, requests} = retry} ->
        start_enqueue(socket, requests, retry_phrase(socket.assigns.repo, retry))

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("composer_cancel", _params, socket) do
    {:noreply, cancel_composer_job(socket)}
  end

  @impl true
  def handle_event("composer_single", _params, socket) do
    text = String.trim(socket.assigns.composer_text)
    socket = ensure_composer_routing(socket)
    shown = composer_phrase(socket.assigns)
    socket = assign(socket, composer_split: false, intake: nil, composer_selected: MapSet.new())

    if text == "",
      do: {:noreply, socket},
      else: start_single(socket, text, socket.assigns.composer_title, shown)
  end

  @impl true
  def handle_event("composer_reset", _params, socket) do
    {:noreply, reset_composer(socket)}
  end

  @impl true
  def handle_event("intake", %{"text" => text} = params, socket) when is_binary(text) do
    socket = assign(socket, :intake, nil)
    repo = socket.assigns.repo

    cond do
      is_nil(repo) ->
        {:noreply, put_flash(socket, :error, "Select a repository before splitting.")}

      params["source_repo"] && params["source_repo"] != to_string(repo.id) ->
        {:noreply, put_flash(socket, :error, "O repositório mudou. Revise o pedido de novo.")}

      socket.assigns.ai_status == :not_configured ->
        {:noreply, put_flash(socket, :error, "IA não configurada. Dividir fica indisponível.")}

      String.trim(text) == "" ->
        {:noreply, put_flash(socket, :error, "Add a request before splitting.")}

      true ->
        case Intake.run(text) do
          {:ok, result} ->
            {:noreply, show_intake_result(socket, repo, text, params, result)}

          {:error, reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "The AI did not answer: #{inspect(reason)}")
             |> refresh_ai()}
        end
    end
  end

  def handle_event("intake", _params, socket) do
    {:noreply,
     socket
     |> assign(:intake, nil)
     |> put_flash(:error, "Add a request before splitting.")}
  end

  @impl true
  def handle_event("create_from_intake", %{"index" => index} = params, socket) do
    with {:ok, position} <- intake_index(index),
         %{repo: repo} when not is_nil(repo) <- socket.assigns,
         %{repo_id: repo_id, status: :ready} = intake <- socket.assigns.intake,
         true <- repo_id == repo.id,
         %{text: request_text, repo_id: ^repo_id} <- socket.assigns.intake_draft,
         true <- request_text == intake.text,
         task when not is_nil(task) <- Enum.at(intake.tasks, position),
         action = %{repository: repo, requests: [intake_request(repo, request_text, task)]},
         {:ok, [{_request, {:ok, _task, _outcome}}]} <-
           Actions.run(:create_tasks, action, ui(), confirm: params["confirm"]) do
      {:noreply, put_flash(socket, :info, "Task created: #{task.title}")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Não foi possível criar a tarefa")}
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    {:noreply,
     socket
     |> settle_composer()
     |> close_logs_panel()
     |> assign(
       panel: nil,
       conversation: nil,
       comments: [],
       inspector_activity: [],
       inspector_calls: [],
       inspector_pr: nil
     )
     |> push_event("panel_close", %{})}
  end

  @impl true
  def handle_event("speak", _params, socket) do
    text =
      Voice.spoken(socket.assigns.board,
        language: socket.assigns.voice.language,
        tz_offset: socket.assigns.tz_offset
      )

    {event, payload} = VoiceSpeech.push(socket.assigns.voice, text, kind: :confirm)
    {:noreply, push_event(socket, event, payload)}
  end

  # A finished utterance from the hands-free microphone (or the typed chat
  # line): the conversation answers it. In the composer, dictation still
  # fills the request instead.
  @impl true
  def handle_event("voice_turn", %{"text" => text}, socket) when is_binary(text) do
    if socket.assigns.panel == "composer",
      do: handle_event("voice_transcript", %{"text" => text}, socket),
      else: {:noreply, VoiceConversation.start(socket, text)}
  end

  @impl true
  def handle_event("voice_cancel_turn", _params, socket),
    do: {:noreply, VoiceConversation.cancel_turn(socket)}

  @impl true
  def handle_event("voice_forget", params, socket),
    do: {:noreply, VoiceConversation.forget(socket, params["confirm"])}

  @impl true
  def handle_event("voice_transcript", %{"text" => text}, socket) when is_binary(text) do
    text = text |> String.trim() |> String.slice(0, 2000)

    cond do
      text == "" ->
        {:noreply, socket}

      socket.assigns.panel == "composer" ->
        {:noreply,
         assign(socket, composer_text: text, composer_error: nil)
         |> invalidate_intake_if_changed(text)}

      # Outside the composer a transcript is a turn of the conversation.
      true ->
        {:noreply, VoiceConversation.start(socket, text)}
    end
  end

  @impl true
  def handle_event("voice_browse", _params, socket) do
    socket = assign(socket, voice: %{socket.assigns.voice | loading: true})

    case ElevenLabs.voices() do
      {:ok, voices} ->
        voice = socket.assigns.voice

        # A voice saved without its name (before names were kept, or by the
        # API) gets it from the list, once.
        with :saved <- voice.source,
             nil <- voice.name,
             name when is_binary(name) <- voice_name(voices, voice.id) do
          save_setting("voice_name", name)
        end

        {:noreply,
         assign(socket,
           voice: %{refreshed_voice(voice) | voices: voices, loading: false}
         )}

      {:error, reason} ->
        # A failed refresh keeps the list it already has: the board never
        # erases its last good state.
        {:noreply,
         socket
         |> assign(voice: %{socket.assigns.voice | loading: false})
         |> put_flash(:error, "Não foi possível listar as vozes: #{voice_reason(reason)}")}
    end
  end

  @impl true
  def handle_event("voice_pick", %{"voice" => id}, socket) do
    # Like every other field of this panel, a pick is saved on the spot: a
    # separate "Salvar" button left picks unsaved when the panel closed.
    # A phx-change value is client input: only a voice-shaped id sticks.
    id = String.trim(id)
    voice = socket.assigns.voice
    name = voice_name(voice.voices, id)

    cond do
      not ElevenLabs.valid_voice_id?(id) ->
        {:noreply, put_flash(socket, :error, "Escolha uma voz da lista")}

      id == voice.id and voice.source == :saved ->
        {:noreply, socket}

      save_setting("voice", {id, name}) == :ok ->
        {:noreply,
         socket
         |> assign(voice: refreshed_voice(voice))
         |> put_flash(:info, "Voz salva: #{name || id}")
         |> push_event("voice_play", %{
           url: speech_url(Phrases.voice_saved(voice.language), id)
         })}

      true ->
        {:noreply, put_flash(socket, :error, "Não foi possível salvar a voz")}
    end
  end

  @impl true
  def handle_event("voice_preview", _params, socket) do
    id = socket.assigns.voice.id

    {:noreply,
     push_event(socket, "voice_play", %{
       url: speech_url(Phrases.preview(socket.assigns.voice.language), id)
     })}
  end

  @impl true
  def handle_event("voice_reset", _params, socket) do
    :ok = save_setting("voice", {"", nil})

    {:noreply,
     socket
     |> assign(voice: refreshed_voice(socket.assigns.voice))
     |> put_flash(:info, "Voz de volta ao padrão")}
  end

  @impl true
  def handle_event("voice_model", %{"model" => model}, socket) do
    if ElevenLabs.valid_tts_model?(String.trim(model)) do
      :ok = save_setting("tts_model", model)

      {:noreply,
       socket
       |> assign(
         voice: %{
           socket.assigns.voice
           | model: ElevenLabs.tts_model(),
             model_source: ElevenLabs.tts_source()
         }
       )
       |> put_flash(:info, "Modelo salvo: #{String.trim(model)}")}
    else
      {:noreply, put_flash(socket, :error, "Modelo de fala desconhecido")}
    end
  end

  @impl true
  def handle_event("voice_try", %{"phrase" => phrase}, socket) do
    cond do
      String.trim(phrase) == "" ->
        {:noreply, put_flash(socket, :error, "Digite uma frase para ouvir")}

      not ElevenLabs.valid_text?(phrase) ->
        {:noreply, put_flash(socket, :error, "A frase é longa demais para um pedido")}

      true ->
        url = speech_url(phrase, socket.assigns.voice.id)
        {:noreply, push_event(socket, "voice_play", %{url: url})}
    end
  end

  @impl true
  def handle_event("voice_announce", %{"speak_events" => value}, socket) do
    :ok = save_setting("narrate", value == "true")

    {:noreply,
     assign(socket, voice: %{socket.assigns.voice | speak_events: ElevenLabs.speak_events?()})}
  end

  @impl true
  def handle_event("voice_attention", %{"attention" => value}, socket) do
    :ok = save_setting("attention", value == "true")
    {:noreply, assign(socket, voice: %{socket.assigns.voice | attention: Voice.attention?()})}
  end

  @impl true
  def handle_event("voice_language", %{"language" => lang}, socket) do
    case save_setting("language", lang) do
      :ok ->
        lang = Voice.language()
        socket = assign(socket, voice: %{socket.assigns.voice | language: lang})
        {:noreply, say(socket, Phrases.language_switched(lang), kind: :confirm)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Idioma não suportado")}
    end
  end

  @impl true
  def handle_event("voice_volume", %{"volume" => volume}, socket) do
    case save_setting("volume", volume) do
      :ok -> {:noreply, assign(socket, voice: %{socket.assigns.voice | volume: Voice.volume()})}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # Speed, intonation, pause and the start/end sounds: each control saves on
  # change and the voice assign is re-read, so the panel shows what stuck.
  @impl true
  def handle_event("voice_speed", %{"speed" => speed}, socket),
    do: {:noreply, save_voice_pref(socket, save_setting("speed", speed))}

  @impl true
  def handle_event("voice_style", %{"style" => style}, socket),
    do: {:noreply, save_voice_pref(socket, save_setting("style", style))}

  @impl true
  def handle_event("voice_pause", %{"pause" => pause}, socket),
    do: {:noreply, save_voice_pref(socket, save_setting("pause", pause))}

  @impl true
  def handle_event("voice_earcons", %{"earcons" => value}, socket),
    do: {:noreply, save_voice_pref(socket, save_setting("earcons", value == "true"))}

  @impl true
  def handle_event("voice_input", %{"input" => value}, socket),
    do: {:noreply, save_voice_pref(socket, save_setting("input", value))}

  @impl true
  def handle_event("voice_engine", %{"engine" => value}, socket),
    do: {:noreply, save_voice_pref(socket, save_setting("engine", value))}

  @impl true
  def handle_event("voice_replies", %{"replies" => value}, socket),
    do: {:noreply, save_voice_pref(socket, save_setting("replies", value))}

  # The logs sheet: clear the visible buffer without moving the read offset,
  # and pause/resume the timer. A closed sheet ignores both.
  @impl true
  def handle_event("logs_clear", _params, %{assigns: %{panel: "logs"}} = socket),
    do: {:noreply, assign(socket, :logs_entries, [])}

  def handle_event("logs_pause", _params, %{assigns: %{panel: "logs"}} = socket) do
    cancel_logs_timer(socket)
    {:noreply, assign(socket, logs_timer: nil, logs_paused: true)}
  end

  def handle_event("logs_resume", _params, %{assigns: %{panel: "logs"}} = socket) do
    socket = assign(socket, :logs_paused, false)

    if socket.assigns.logs_timer do
      {:noreply, socket}
    else
      {:noreply, socket |> read_logs_once() |> schedule_logs_tick()}
    end
  end

  def handle_event("logs_clear", _params, socket), do: {:noreply, socket}
  def handle_event("logs_pause", _params, socket), do: {:noreply, socket}
  def handle_event("logs_resume", _params, socket), do: {:noreply, socket}

  # A browser error the owner saw (microphone, playback, transcription):
  # it reaches the log and the live feed instead of staying in one tab.
  @impl true
  def handle_event("voice_client_error", %{"title" => title} = params, socket)
      when is_binary(title) do
    detail = params |> Map.get("detail", "") |> to_string() |> String.slice(0, 200)
    source = params |> Map.get("source", "browser") |> to_string() |> String.slice(0, 40)
    Activity.record(:browser, :error, "#{String.slice(title, 0, 120)}: #{detail}", reason: source)
    {:noreply, socket}
  end

  # Last clause: an event this view does not expect (a malformed payload, a
  # form recovered after a reconnect, an old tab after a deploy) is logged
  # and ignored. Before, it raised and took the whole board down.
  def handle_event(event, params, socket) do
    keys = params |> Map.keys() |> Enum.reject(&String.starts_with?(&1, "_")) |> Enum.join(", ")

    Activity.record(:ui, :error, "evento ignorado: #{String.slice(to_string(event), 0, 60)}",
      reason: "campos recebidos: [#{keys}]"
    )

    {:noreply, socket}
  end

  def handle_async(:provision, {:ok, {:ok, text}}, socket) do
    {:noreply,
     socket
     |> assign(superagents: Superagents.list(), provisioning: false)
     |> put_flash(:info, text)}
  end

  def handle_async(:provision, {:ok, {:error, text}}, socket) do
    {:noreply,
     socket
     |> assign(superagents: Superagents.list(), provisioning: false)
     |> put_flash(:error, text)}
  end

  def handle_async(:provision, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(provisioning: false)
     |> put_flash(:error, "O provisionamento não terminou.")}
  end

  @impl true
  def handle_async({:superagent_command, _id}, {:ok, {:ok, text}}, socket) do
    {:noreply, socket |> assign(:superagents, Superagents.list()) |> put_flash(:info, text)}
  end

  def handle_async({:superagent_command, _id}, {:ok, {:error, text}}, socket),
    do: {:noreply, put_flash(socket, :error, text)}

  def handle_async({:superagent_command, _id}, {:exit, _reason}, socket),
    do: {:noreply, put_flash(socket, :error, "A ação do superagent não terminou.")}

  def handle_async({:superagent_scale, _id}, {:ok, {:ok, text}}, socket) do
    {:noreply, socket |> assign(:superagents, Superagents.list()) |> put_flash(:info, text)}
  end

  def handle_async({:superagent_scale, _id}, {:ok, {:error, text}}, socket),
    do: {:noreply, put_flash(socket, :error, text)}

  def handle_async({:superagent_scale, _id}, {:exit, _reason}, socket),
    do: {:noreply, put_flash(socket, :error, "Não foi possível mudar o limite de sessões.")}

  @impl true
  def handle_async({:voice_turn, ref}, outcome, socket),
    do: {:noreply, VoiceConversation.finish(socket, ref, outcome)}

  def handle_async({:voice_compact, _ref}, _outcome, socket), do: {:noreply, socket}

  def handle_async({:composer_routing, repo_id}, outcome, socket) do
    signals =
      case outcome do
        {:ok, signals} -> signals
        {:exit, _reason} -> Signals.read(fn -> {:error, :unreachable} end)
      end

    case socket.assigns.repo do
      %{id: ^repo_id} -> {:noreply, put_composer_routing(socket, signals)}
      _ -> {:noreply, socket}
    end
  end

  def handle_async({:composer, ref}, outcome, socket) do
    case socket.assigns.composer_job do
      %{ref: ^ref} = job -> {:noreply, finish_composer_job(socket, job, outcome)}
      _ -> {:noreply, socket}
    end
  end

  defp invalidate_intake_if_changed(socket, text) do
    case socket.assigns.intake do
      %{text: ^text} -> socket
      _ -> assign(socket, :intake, nil)
    end
  end

  defp show_intake_result(socket, repo, text, params, %{spec: spec, tasks: tasks, status: status}) do
    source = if params["source_repo"], do: :voice, else: :typed

    socket
    |> assign(
      intake: %{spec: spec, tasks: tasks, status: status, text: text, repo_id: repo.id},
      intake_draft: %{text: text, repo_id: repo.id, source: source}
    )
    |> refresh_ai()
  end

  defp intake_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {position, ""} when position >= 0 -> {:ok, position}
      _ -> :error
    end
  end

  defp intake_index(_value), do: :error

  # The model answers on another process: the question is already on GitHub,
  # and blocking the LiveView for it freezes the whole board.
  defp ask_in_background(task, body) do
    parent = self()
    id = task.id
    Elixir.Task.start(fn -> send(parent, {:answer, id, answer(task, body)}) end)
  end

  # The full voice state, as one assign: id and model resolve env -> saved ->
  # default, and the picker fields ride along.
  defp current_voice do
    %{
      id: ElevenLabs.voice_id(),
      name: ElevenLabs.voice_name(),
      source: ElevenLabs.voice_source(),
      configured: ElevenLabs.configured?(),
      voices: nil,
      loading: false,
      model: ElevenLabs.tts_model(),
      model_source: ElevenLabs.tts_source(),
      models: ElevenLabs.tts_models(),
      speak_events: ElevenLabs.speak_events?(),
      attention: Voice.attention?(),
      language: Voice.language(),
      languages: Phrases.languages(),
      volume: Voice.volume(),
      speed: Voice.speed(),
      style: Voice.style(),
      pause: Voice.pause(),
      pause_ms: Voice.pause_ms(),
      earcons: Voice.earcons?(),
      input: Voice.input(),
      engine: Voice.engine(),
      replies: Voice.replies()
    }
  end

  # The saved settings, with what only this socket holds (the loaded list).
  defp refreshed_voice(voice),
    do: Map.merge(current_voice(), Map.take(voice, [:voices, :loading]))

  defp save_setting(setting, value),
    do: Actions.run(:change_setting, %{setting: setting, value: value}, ui())

  defp ui, do: Actions.owner(:ui)

  defp save_voice_pref(socket, :ok) do
    fresh = current_voice()

    assign(socket,
      voice:
        Map.merge(
          socket.assigns.voice,
          Map.take(fresh, [:speed, :style, :pause, :pause_ms, :earcons, :input, :engine, :replies])
        )
    )
  end

  defp save_voice_pref(socket, {:error, _reason}), do: socket

  defp voice_name(nil, _id), do: nil
  defp voice_name(voices, id), do: Enum.find_value(voices, fn v -> if v.id == id, do: v.name end)

  # The agent speaks what changed, once per change: the poller already
  # broadcasts only on new hashes, and the same utterance is not repeated
  # within a short window. One update is one utterance: a second push would
  # cut the first one off mid-sentence.
  defp announce(%{assigns: %{voice: voice}} = socket, old_board, old_sync, old_needs) do
    texts =
      Announcer.board_changes(
        old_board,
        socket.assigns.board,
        old_sync,
        socket.assigns.sync_event,
        language: voice.language,
        turn: socket.assigns.voice_turn,
        attention: voice.attention,
        events: voice.speak_events,
        needs: {old_needs, socket.assigns.work.needs}
      )

    case Announcer.utterance(texts) do
      nil ->
        socket

      text ->
        # A call for attention in the utterance makes it a call (the paid
        # voice in the mixed engine); otherwise it is narration.
        attention? =
          voice.attention and
            Announcer.board_changes(
              old_board,
              socket.assigns.board,
              old_sync,
              socket.assigns.sync_event,
              language: voice.language,
              events: false,
              needs: {old_needs, socket.assigns.work.needs}
            ) != []

        socket
        |> assign(voice_turn: socket.assigns.voice_turn + length(texts))
        |> say(text, kind: if(attention?, do: :call, else: :narration))
    end
  end

  # Today's summary of the day, shown until dismissed. Read only on a
  # connected socket.
  defp show_daily_summary(socket) do
    assign(socket, :daily_summary, if(connected?(socket), do: DailySummary.visible()))
  end

  # The browser asks to speak it only from a tab the owner interacted with
  # (the DailySummaryVoice hook), so a preview never spends it; the first
  # ask wins the conditional claim and the other tabs stay quiet. Its own
  # switch governs the voice, not the narration toggle; for the engine
  # choice it is narration.
  defp claim_daily_summary(%{assigns: %{daily_summary: %{id: id} = entry}} = socket, id) do
    if DailySummary.claim_spoken(id) do
      text = Phrases.daily_summary(socket.assigns.voice.language, entry.content)
      spoken_at = DateTime.utc_now() |> DateTime.truncate(:second)

      socket
      |> assign(:daily_summary, %{entry | spoken_at: spoken_at})
      |> say(text, kind: :narration)
    else
      show_daily_summary(socket)
    end
  end

  defp claim_daily_summary(socket, _id), do: socket

  # A confirmation or an answer: spoken only while the narration is on.
  defp speak(%{assigns: %{voice: %{speak_events: true}}} = socket, text),
    do: say(socket, text, kind: :narration)

  defp speak(socket, _text), do: socket

  # Speaks with the owner's engine (VoiceSpeech decides ElevenLabs or the
  # free browser voice), deduped for a short window so a burst never doubles.
  defp say(socket, text, opts)

  defp say(socket, text, opts) when is_binary(text) and text != "" do
    now = System.monotonic_time(:millisecond)

    if socket.assigns.spoken_text == text and now - socket.assigns.spoken_at < 30_000 do
      socket
    else
      {event, payload} = VoiceSpeech.push(socket.assigns.voice, text, opts)

      socket
      |> assign(spoken_text: text, spoken_at: now)
      |> push_event(event, payload)
    end
  end

  defp say(socket, _text, _opts), do: socket

  defp voice_reason(:not_configured), do: "sem chave de API"
  defp voice_reason(:auth_expired), do: "a chave foi recusada"
  defp voice_reason(:usage_limit), do: "limite de uso atingido"
  defp voice_reason({:http, status}), do: "HTTP #{status}"
  defp voice_reason(reason), do: inspect(reason)

  defp speech_url(text, voice_id), do: VoiceSpeech.url(text, voice_id)

  # A question that reached GitHub is a success even when the model cannot
  # answer it: the failure is shown as an error and never overwrites the
  # "Pergunta enviada" confirmation.
  defp answer_arrived(socket, text) when is_binary(text), do: answer_arrived(socket, {:ok, text})

  defp answer_arrived(socket, {:ok, text}) do
    socket
    |> put_flash(:info, text)
    |> refresh_ai()
    |> speak(Announcer.speakable_answer(text))
  end

  defp answer_arrived(socket, {:error, text}) do
    socket
    |> put_flash(:error, text)
    |> refresh_ai()
  end

  defp answer(task, question) do
    case AI.call(
           :answer_question,
           %{
             question: question,
             title: task.title,
             state: task.state,
             kind: task.kind
           },
           task_id: task.id
         ) do
      {:ok, %{json: %{"answer" => text}}} -> {:ok, text}
      {:ok, _} -> {:ok, "The model answered, but not with text."}
      {:error, :not_configured} -> {:error, "A IA não está configurada."}
      {:error, reason} -> {:error, "The AI did not answer: #{inspect(reason)}"}
    end
  end

  # The sentence on each Create button of the intake panel (data-confirm).
  defp intake_phrases(%{} = repo, %{status: :ready, text: text, tasks: tasks}),
    do:
      Enum.map(tasks, fn task ->
        Actions.phrase(:create_tasks, %{
          repository: repo,
          requests: [intake_request(repo, text, task)]
        })
      end)

  defp intake_phrases(_repo, _intake), do: []

  defp intake_request(repo, text, task),
    do: %{
      title: task.title,
      body: intake_body(task),
      key: Board.request_key(repo, "intake", [text, task.title]),
      work_type: task.kind,
      size: task.size
    }

  defp intake_body(task) do
    """
    #{task.body}

    ## Acceptance
    #{Enum.map_join(task.acceptance, "\n", &"- #{&1}")}
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        id="board-page"
        phx-hook="BoardPanels"
        data-panel={@panel || ""}
        data-base-url={BoardNavigation.path(@repo)}
        data-repo={repo_slug(@repo)}
        data-sync={@freshness.state}
        data-sync-at={@freshness.at && DateTime.to_iso8601(@freshness.at)}
        data-frozen={to_string(@freshness.frozen?)}
        data-connection="live"
        class="agent-board ab ab-shell"
      >
        <div id="board-connection" phx-hook="BoardConnection" hidden></div>
        <div id="board-clock" phx-hook="BoardClock" hidden></div>
        <div id="board-keyboard" phx-hook="BoardKeyboard" hidden></div>

        <div class="ab-board" data-inspector={if @conversation, do: "open", else: "closed"}>
          <.live_component
            module={BoardComponents.RepoRail}
            id="repo-rail"
            repos={@repos}
            repo={@repo}
            view={@view}
            overview={@repo_overview}
            live={@freshness.live?}
            version={@version}
            busy={@busy}
            voice={@voice}
            superagents={@superagents}
            dispatch_paused={@dispatch_paused}
            show_settings={@panel != "settings"}
            settings_panel={@panel == "settings"}
          />

          <main id="board-work" class="ab-main">
            <div :if={@repo == nil} class="ab-empty">
              <h2>Nenhum repositório acompanhado.</h2>
              <p>
                Abra Configurações → Repositórios para acompanhar um repositório. O board mostra o
                trabalho do agente, o que espera por você e o que mudou.
              </p>
            </div>

            <.today_view
              :if={@view == "hoje"}
              today={@today}
              spend={@today_spend}
              offset={@tz_offset}
            />

            <.frozen_banner
              :if={@repo && @view != "hoje"}
              freshness={@freshness}
              tz_offset={@tz_offset}
            />

            <header :if={@repo && @view != "hoje"} class="ab-top">
              <details :if={@repo} id="mobile-nav" data-board-menu class="ab-mobilebar">
                <summary>
                  <span class="ab-mobilebar__repo">{@repo.name}</span>
                  <.ico name="menu" />
                  <span class="ab-sr">Repositórios</span>
                </summary>
                <div class="ab-mobilebar__list">
                  <button
                    type="button"
                    class="ab-repo"
                    aria-current={to_string(@view == "hoje")}
                    phx-click="select"
                    phx-value-view="hoje"
                  >
                    <span class="ab-repo__name">Hoje</span>
                  </button>
                  <button
                    :for={r <- @repos}
                    type="button"
                    class="ab-repo"
                    aria-current={to_string(@repo && @repo.id == r.id)}
                    phx-click="select"
                    phx-value-repo={"#{r.owner}/#{r.name}"}
                  >
                    <span class="ab-repo__name">{r.owner}/{r.name}</span>
                  </button>

                  <button
                    id="mobile-panel-superagents"
                    type="button"
                    class="ab-btn ab-btn--quiet ab-btn--sm"
                    phx-click="show_panel"
                    phx-value-panel="superagents"
                    data-panel-trigger
                    aria-haspopup="dialog"
                    aria-controls="panel-superagents"
                  >
                    <.ico name="grip" />Superagentes
                  </button>
                  <button
                    id="mobile-panel-shortcuts"
                    type="button"
                    class="ab-btn ab-btn--quiet ab-btn--sm"
                    phx-click="show_panel"
                    phx-value-panel="shortcuts"
                    data-panel-trigger
                    aria-haspopup="dialog"
                    aria-controls="panel-shortcuts"
                  >
                    <.ico name="keys" />Atalhos
                  </button>
                  <button
                    id="mobile-panel-logs"
                    type="button"
                    class="ab-btn ab-btn--quiet ab-btn--sm"
                    phx-click="show_panel"
                    phx-value-panel="logs"
                    data-panel-trigger
                    aria-haspopup="dialog"
                    aria-controls="panel-logs"
                  >
                    <.ico name="log" />Logs
                  </button>
                  <button
                    id="mobile-panel-voice"
                    type="button"
                    class="ab-btn ab-btn--quiet ab-btn--sm"
                    phx-click="show_panel"
                    phx-value-panel="voice"
                  >
                    <.ico name="mic" />Conversa por voz
                  </button>
                  <button
                    id="mobile-panel-settings"
                    type="button"
                    class="ab-btn ab-btn--quiet ab-btn--sm"
                    phx-click="show_panel"
                    phx-value-panel="settings"
                    data-panel-trigger
                    aria-haspopup="dialog"
                    aria-controls="panel-settings"
                  >
                    <.ico name="cog" />Configurações
                  </button>
                </div>
              </details>
              <div class="ab-top__repo">
                <span class="ab-top__owner">{@repo.owner}/</span>
                <h1>{@repo.name}</h1>
              </div>
              <.beacon freshness={@freshness} tz_offset={@tz_offset} />
              <span class="ab-top__spacer"></span>
              <div id="board-tools" class="ab-top__actions" aria-label="Ações do board">
                <button
                  id="open-intake"
                  type="button"
                  class="ab-btn"
                  phx-click="open_composer"
                  phx-value-split="true"
                  data-panel-trigger
                  aria-haspopup="dialog"
                  aria-controls="panel-composer"
                >
                  <.ico name="split" />Dividir pedido
                </button>
                <button
                  id="open-create"
                  type="button"
                  class="ab-btn ab-btn--primary"
                  phx-click="open_composer"
                  phx-value-split="false"
                  data-panel-trigger
                  aria-haspopup="dialog"
                  aria-controls="panel-composer"
                >
                  <.ico name="plus" />Novo pedido<.kbd key="N" />
                </button>
              </div>
            </header>

            <.summary :if={@repo && @view != "hoje"} digest={@digest} />

            <div
              :if={@repo && @view != "hoje" && (@objectives != [] or @daily_summary)}
              class={["ab-context", @objectives == [] && "is-daily-only"]}
            >
              <section
                :if={@objectives != []}
                id="objectives"
                class="ab-objectives"
                aria-label="Objetivos"
              >
                <article
                  :for={objective <- @objectives}
                  class="ab-objective"
                  data-done={to_string(objective.done?)}
                >
                  <div class="ab-objective__head">
                    <span class="ab-label">Objetivo</span>
                    <b>{objective.title}</b>
                    <span class="ab-objective__count">
                      {objective.merged} de {objective.total}<span class="ab-sr"> tarefas mescladas</span>
                    </span>
                    <span :if={objective.done?} class="ab-tag ab-tag--agent">concluído</span>
                  </div>
                  <p class="ab-meta">critério: {objective.done_criterion}</p>
                  <div
                    class="ab-objective__bar"
                    role="progressbar"
                    aria-valuenow={objective.merged}
                    aria-valuemin="0"
                    aria-valuemax={objective.total}
                    aria-label={"Progresso do objetivo #{objective.title}"}
                  >
                    <span style={"width: #{progress(objective)}%"}></span>
                  </div>
                </article>
              </section>

              <details
                :if={@daily_summary}
                id="fold-daily"
                class="ab-fold ab-fold--daily"
                data-mobile-fold
                open
                phx-hook="BoardFold"
              >
                <summary class="ab-fold__summary">
                  <span>Resumo do dia</span>
                  <span class="ab-meta">do board</span>
                </summary>
                <div class="ab-fold__body">
                  <.daily_summary entry={@daily_summary} tz_offset={@tz_offset} />
                </div>
              </details>
            </div>

            <div :if={@repo && @view != "hoje" && empty?(@board)} class="ab-empty">
              <h2>
                {if @sync_snapshot.last_success,
                  do: "Nada aconteceu aqui ainda.",
                  else: "Sem dados ainda."}
              </h2>
              <p>
                {if @sync_snapshot.last_success,
                  do:
                    "O agente observa este repositório, mas ainda não recebeu nenhuma tarefa. Escreva ou dite o primeiro pedido; ele entra na fila e aparece em Agora quando o agente pegar.",
                  else:
                    "Aguardando a primeira sincronia. Quando o GitHub responder, o board mostra as tarefas, os merges e o que espera por você."}
              </p>
              <button
                type="button"
                class="ab-btn ab-btn--primary"
                phx-click="open_composer"
                phx-value-split="false"
                data-panel-trigger
                aria-haspopup="dialog"
                aria-controls="panel-composer"
              >
                <.ico name="plus" />Novo pedido
              </button>
            </div>

            <div
              :if={@repo && @view != "hoje" && not empty?(@board)}
              class="ab-cols"
              data-idle={to_string(idle_board?(@work))}
            >
              <div class="ab-lanes">
                <div class="ab-col ab-col--main">
                  <.now_lane
                    running={@work.running}
                    retrying={@work.retrying}
                    frozen={@freshness.frozen?}
                    frozen_at={@freshness.at}
                    sync_at={@freshness.at}
                    tz_offset={@tz_offset}
                    next_queued={@work.queue.items |> List.first() |> then(&(&1 && &1.number))}
                  />
                  <.needs_you
                    needs={@work.needs}
                    max={if @needs_expanded, do: 999, else: 5}
                    selected={@conversation && @conversation.id}
                    last_visit={@last_visit}
                    frozen={@freshness.frozen?}
                    frozen_at={@freshness.at}
                    tz_offset={@tz_offset}
                  />
                </div>
                <div class="ab-col ab-col--queue">
                  <.queue_list
                    queue={@work.queue}
                    frozen={@freshness.frozen?}
                    frozen_at={@freshness.at}
                    tz_offset={@tz_offset}
                    selected={@conversation && @conversation.id}
                  />
                </div>
              </div>
              <div class="ab-side">
                <div class="ab-col ab-col--log">
                  <.merge_log
                    log={@work.log}
                    frozen={@freshness.frozen?}
                    has_history={@board.merged != []}
                    idle={idle_board?(@work)}
                  />
                </div>
                <details
                  :if={@flow}
                  id="fold-flow"
                  class="ab-fold ab-fold--flow"
                  data-mobile-fold
                  open
                  phx-hook="BoardFold"
                >
                  <summary class="ab-fold__summary">
                    <span>Vazão</span>
                    <span class="ab-meta">por hora · {if @freshness.frozen?,
                      do: "congelada",
                      else: "calculado"} às {Time.local_time(@flow.computed_at, @tz_offset)}</span>
                  </summary>
                  <div class="ab-fold__body">
                    <.throughput
                      flow={@flow}
                      tz_offset={@tz_offset}
                      frozen={@freshness.frozen?}
                      superagents={@superagents}
                    />
                  </div>
                </details>
              </div>
            </div>
          </main>

          <div :if={@repo && @view != "hoje"} class="ab-mobile-actions" aria-label="Ações do board">
            <button
              type="button"
              class="ab-btn ab-btn--primary"
              phx-click="open_composer"
              phx-value-split="false"
              data-panel-trigger
              aria-haspopup="dialog"
              aria-controls="panel-composer"
            >
              Novo pedido
            </button>
            <button
              type="button"
              class="ab-btn ab-btn--icon"
              phx-click="show_panel"
              phx-value-panel="voice"
              aria-label="Conversa por voz"
            >
              <.ico name="mic" />
            </button>
          </div>

          <.inspector
            :if={@conversation}
            task={@conversation}
            comments={@comments}
            tab={@inspector_tab}
            activity={@inspector_activity}
            calls={@inspector_calls}
            executions={@inspector_executions}
            runner_executions={@inspector_runner_executions}
            dispatch_paused={@inspector_dispatch_paused}
            dispatch_active={@inspector_dispatch_active}
            dispatch_ceiling={@inspector_dispatch_ceiling}
            dispatch_fallback={@inspector_dispatch_fallback}
            usage={@inspector_usage}
            pr={@inspector_pr}
            ci={@inspector_ci}
            failure={@inspector_failure}
            tz_offset={@tz_offset}
            live={@freshness.live?}
            ask_pending={@ask_pending}
            ask_draft={@ask_draft}
          />
        </div>

        <VoicePresence.stage id="voice-presence-board" />
        <div
          id="voice-command-shortcut"
          phx-hook="VoiceCommand"
          data-configured={to_string(@voice.configured)}
          data-pause-ms={@voice.pause_ms}
          data-input={@voice.input}
          data-earcons={to_string(@voice.earcons)}
          hidden
        />

        <div
          id="voice-wispr"
          phx-hook="VoiceWispr"
          phx-update="ignore"
          class="voice-wispr"
          role="dialog"
          aria-label="Fale com o Wispr"
          hidden
        >
          <label for="voice-wispr-text" class="voice-wispr-label">Fale com o Wispr</label>
          <input
            id="voice-wispr-text"
            type="text"
            autocomplete="off"
            placeholder="Segure a tecla do Wispr e fale…"
          />
          <span class="voice-wispr-hint">
            Envio sozinho quando o texto chegar · Enter envia · Esc fecha
          </span>
        </div>

        <div :if={@toast} class="ab-toast" role="status">
          <span>{@toast.text}</span>
          <button
            :if={@toast.action}
            type="button"
            class="ab-btn ab-btn--quiet ab-btn--sm"
            phx-click="show_changes"
          >
            {@toast.action}
          </button>
          <button
            type="button"
            class="ab-btn ab-btn--icon ab-btn--sm"
            phx-click="dismiss_toast"
            aria-label="Fechar aviso"
          >
            <.ico name="close" />
          </button>
        </div>

        <dialog
          id="panel-composer"
          class="board-dialog ab-composer-dialog"
          aria-labelledby="composer-title"
        >
          <.composer
            :if={@repo}
            repo={"#{@repo.owner}/#{@repo.name}"}
            text={@composer_text}
            title={@composer_title}
            split={@composer_split}
            intake={@intake}
            selected={@composer_selected}
            job={@composer_job}
            receipt={@composer_receipt}
            answers={@composer_answers}
            ai_status={@ai_status}
            voice_configured={@voice.configured}
            error={@composer_error}
            retry={@composer_retry}
            confirm={
              composer_phrase(
                @repo,
                @composer_text,
                @composer_title,
                @composer_split,
                @intake,
                @composer_selected,
                @composer_executor
              )
            }
            executor={@composer_executor}
            suggestion={@composer_routing && @composer_routing.suggestion}
            retry_confirm={retry_phrase(@repo, @composer_retry)}
          />
        </dialog>

        <BoardComponents.Panel.shell
          name="shortcuts"
          title="Atalhos"
          active={@panel == "shortcuts"}
          flash={@flash}
        >
          <.shortcuts />
        </BoardComponents.Panel.shell>

        <BoardComponents.Panel.shell
          name="history"
          title="Histórico de merges"
          active={@panel == "history"}
          flash={@flash}
        >
          <.live_component
            :if={@repo}
            module={BoardComponents.Archive}
            id="merged-column-history"
            items={@board.merged}
            has_more={@board.merged_has_more}
          />
        </BoardComponents.Panel.shell>

        <BoardComponents.Panel.shell
          name="activity"
          title="Atividade"
          active={@panel == "activity"}
          flash={@flash}
        >
          <.live_component
            :if={@repo}
            module={BoardComponents.Activity}
            id="activity"
            events={@events}
          />
        </BoardComponents.Panel.shell>

        <BoardComponents.Panel.shell
          name="intake"
          title="Dividir pedido"
          active={@panel == "intake"}
          flash={@flash}
        >
          <.live_component
            :if={@repo}
            module={BoardComponents.Intake}
            id="intake"
            intake={@intake}
            draft={@intake_draft}
            phrases={intake_phrases(@repo, @intake)}
            repo={@repo}
            ai_status={@ai_status}
          />
        </BoardComponents.Panel.shell>

        <BoardComponents.Panel.shell
          name="ai"
          title="Chamadas de IA"
          active={@panel == "ai"}
          flash={@flash}
        >
          <.live_component
            :if={@repo}
            module={BoardComponents.AI}
            id="ai"
            ai_calls={@ai_calls}
            ai_status={@ai_status}
          />
        </BoardComponents.Panel.shell>

        <BoardComponents.Panel.shell
          name="superagents"
          title="Superagentes"
          active={@panel == "superagents"}
          flash={@flash}
        >
          <BoardComponents.Superagents.superagents
            superagents={@superagents}
            repos={@repos}
            provision_preview={@provision_preview}
            provisioning={@provisioning}
            tz_offset={@tz_offset}
          />
        </BoardComponents.Panel.shell>

        <BoardComponents.Panel.shell
          name="settings"
          title="Configurações"
          active={@panel == "settings"}
          flash={@flash}
        >
          <.live_component
            :if={@panel == "settings"}
            module={BoardComponents.SettingsMenu}
            id="board-settings-panel"
            repo={@repo}
            version={@version}
            busy={@busy}
            voice={@voice}
            dispatch_paused={@dispatch_paused}
            settings_panel={true}
          />
        </BoardComponents.Panel.shell>

        <BoardComponents.Panel.shell
          name="executors"
          title="Executores"
          active={@panel == "executors"}
          flash={@flash}
        >
          <.executors report={@executor_report} days={@executor_days} />
        </BoardComponents.Panel.shell>

        <BoardComponents.Panel.shell
          name="voice"
          title="Conversa por voz"
          active={@panel == "voice"}
          flash={@flash}
        >
          <BoardComponents.VoiceConversationLog.log
            turns={@voice_turns}
            thinking={@chat_turn != nil}
          />
          <div class="ab-voice-talk">
            <button
              type="button"
              class="ab-btn ab-btn--primary"
              phx-click={Phoenix.LiveView.JS.dispatch("board:voice-start")}
            >
              <.ico name="mic" />Falar<.kbd key="espaço 2×" />
            </button>
            <span class="ab-meta">Fale e pare: o agente responde e espera seu “sim” antes de agir.</span>
          </div>
          <BoardComponents.VoiceCommandList.list open={@voice_commands_open} />
          <BoardComponents.VoiceActivityFeed.feed events={@voice_activity} />
        </BoardComponents.Panel.shell>

        <.logs_sheet
          sources={@logs_sources}
          entries={@logs_entries}
          status={@logs_status}
          paused={@logs_paused}
          timer={@logs_timer != nil}
        />
      </div>
    </Layouts.app>
    """
  end

  defp restart_after_update(socket, message) do
    delay = Application.get_env(:agent_board, :update_restart_delay_ms, 1200)
    Process.send_after(self(), :restart_server, delay)

    socket
    |> assign(:busy, true)
    |> push_event("restart", %{})
    |> put_flash(:info, message)
  end

  # -- the composer lifecycle ---------------------------------------------------
  #
  # One job at a time, keyed by a ref: a late or cancelled result finds no job
  # with its ref and changes nothing. The durable records are the ai_calls
  # rows (the split) and the tasks with their request_key (the enqueue); the
  # receipt is read from those tasks, so a reload shows the same thing.

  defp composer_error(socket, text, retry \\ nil),
    do: assign(socket, composer_error: text, composer_retry: retry)

  # Only a change of the title field itself is the owner's edit. Every
  # other change carries the field as the browser last had it, the title
  # derived from the previous words; taking that for an edit froze the
  # title at a prefix when the owner typed fast.
  defp edited_title(%{"_target" => ["title"], "title" => title}, text, _current) do
    title = String.trim(title)
    if title == "" or title == Titles.from_request(text), do: nil, else: title
  end

  defp edited_title(_params, _text, current), do: current

  defp submit_split(socket, text, params, shown) do
    case socket.assigns.intake do
      %{status: :ready, text: ^text, tasks: tasks} when tasks != [] ->
        requests =
          socket.assigns.repo
          |> split_requests(text, tasks, selected_from(params, socket))
          |> for_executor(socket.assigns)

        start_enqueue(socket, requests, shown)

      %{status: :needs_clarification, text: ^text} ->
        answer_and_split(socket, text)

      _ ->
        start_split(socket, text)
    end
  end

  # The answers become part of the request (the issue carries them too) and
  # the model splits the answered text.
  defp answer_and_split(socket, text) do
    case String.trim(socket.assigns.composer_answers || "") do
      "" ->
        {:noreply,
         composer_error(
           socket,
           "Responda as perguntas ou edite o pedido antes de dividir de novo."
         )}

      answers ->
        answered = text <> "\n\nRespostas:\n" <> answers

        socket
        |> assign(composer_text: answered, composer_answers: "", intake: nil)
        |> start_split(answered)
    end
  end

  defp selected_from(params, socket) do
    case params do
      %{"tasks" => values} -> MapSet.new(values, &String.to_integer/1)
      _ -> socket.assigns.composer_selected
    end
  end

  defp split_requests(repo, text, tasks, selected) do
    tasks
    |> Enum.with_index()
    |> Enum.filter(fn {_task, index} -> MapSet.member?(selected, index) end)
    |> Enum.map(fn {task, _index} ->
      %{
        title: task.title,
        body: intake_body(task) <> "\n\n@sallaumen-agent",
        key: Board.request_key(repo, "split", [text, task.title]),
        work_type: task.kind,
        size: task.size
      }
    end)
  end

  defp start_single(socket, text, title, shown) do
    case single_requests(socket.assigns.repo, text, title) do
      [] ->
        {:noreply, composer_error(socket, "A primeira linha vira o título; escreva algo.")}

      requests ->
        start_enqueue(socket, for_executor(requests, socket.assigns), shown)
    end
  end

  # Who the composer's requests are for, and the router's line the board
  # stores with each task: the suggestion the composer showed and the
  # executor the person left chosen.
  defp for_executor(requests, %{composer_executor: executor} = assigns)
       when is_binary(executor) do
    routing = assigns.composer_routing

    Enum.map(requests, fn request ->
      request
      |> Map.put(:executor, executor)
      |> then(&if(routing, do: Map.put(&1, :routing, routing), else: &1))
    end)
  end

  defp for_executor(requests, _assigns), do: requests

  defp choose_executor(socket, executor) do
    if Executors.valid?(executor) and executor != socket.assigns.composer_executor,
      do: assign(socket, composer_executor: executor, composer_executor_touched: true),
      else: socket
  end

  # The router reads the runner once per opening of the composer in a
  # repository, never per render: a runner that does not answer costs the
  # orchestrator's timeouts in the background, not in the form.
  defp load_panel(%{assigns: %{panel: "executors"}} = socket) do
    if socket.assigns.executor_report_for == socket.assigns.executor_days,
      do: socket,
      else: load_executors(socket, socket.assigns.executor_days)
  end

  defp load_panel(socket), do: socket

  defp load_executors(socket, days) do
    since = Report.since(days)

    report = %{
      executors: Report.executors(since, tickets: all_tickets(socket)),
      daily: Report.daily(since)
    }

    assign(socket, executor_days: days, executor_report: report, executor_report_for: days)
  end

  defp all_tickets(socket) do
    case socket.assigns[:agent_snapshot] do
      %{tickets: tickets} -> tickets
      _ -> []
    end
  end

  defp load_composer_routing(%{assigns: %{panel: "composer", repo: %{id: id}}} = socket) do
    if connected?(socket) and socket.assigns.composer_routing_for != id do
      socket
      |> assign(composer_routing_for: id)
      |> start_async({:composer_routing, id}, fn -> Signals.read() end)
    else
      socket
    end
  end

  defp load_composer_routing(socket), do: socket

  # A submit before the background read answered reads the signals now.
  defp ensure_composer_routing(%{assigns: %{composer_routing: nil, repo: %{} = repo}} = socket) do
    socket
    |> assign(composer_routing_for: repo.id)
    |> put_composer_routing(Signals.read())
  end

  defp ensure_composer_routing(socket), do: socket

  defp put_composer_routing(socket, signals) do
    routed = Routing.plan(socket.assigns.repo, %{}, nil, "composer", signals)

    socket
    |> assign(composer_routing: routed.routing)
    |> then(fn socket ->
      if socket.assigns.composer_executor_touched,
        do: socket,
        else: assign(socket, composer_executor: routed.executor)
    end)
  end

  defp single_requests(repo, text, title) do
    title = title || Titles.from_request(text)
    body = text <> "\n\n@sallaumen-agent"

    if title == "",
      do: [],
      else: [%{title: title, body: body, key: Board.request_key(repo, "single", [title, body])}]
  end

  # What the composer's primary button would create now, and the sentence
  # that confirms it: shown above the button, passed to the gate on send.
  defp composer_phrase(assigns) do
    composer_phrase(
      assigns.repo,
      assigns.composer_text,
      assigns.composer_title,
      assigns.composer_split,
      assigns.intake,
      assigns.composer_selected,
      assigns.composer_executor
    )
  end

  @doc false
  def composer_phrase(nil, _text, _title, _split, _intake, _selected, _executor), do: nil

  def composer_phrase(repo, text, title, split, intake, selected, executor) do
    text = String.trim(text || "")

    requests =
      cond do
        text == "" ->
          []

        not split ->
          single_requests(repo, text, title)

        true ->
          case intake do
            %{status: :ready, text: ^text, tasks: [_ | _] = tasks} ->
              split_requests(repo, text, tasks, selected)

            %{status: :no_tasks} ->
              single_requests(repo, text, title)

            _ ->
              []
          end
      end

    requests = for_executor(requests, %{composer_executor: executor, composer_routing: nil})

    if requests == [],
      do: nil,
      else: Actions.phrase(:create_tasks, %{repository: repo, requests: requests})
  end

  @doc false
  def retry_phrase(%{} = repo, {:enqueue, [_ | _] = requests}),
    do: Actions.phrase(:create_tasks, %{repository: repo, requests: requests})

  def retry_phrase(_repo, _retry), do: nil

  defp start_split(socket, text) do
    cond do
      is_nil(socket.assigns.repo) ->
        {:noreply, composer_error(socket, "Escolha um repositório antes de dividir.")}

      socket.assigns.ai_status == :not_configured ->
        {:noreply,
         composer_error(
           socket,
           "A IA não está configurada. Dividir fica indisponível; envie como pedido único."
         )}

      true ->
        job = composer_job(:split, text, 1)

        {:noreply,
         socket
         |> assign(composer_job: job, composer_error: nil, composer_retry: nil, intake: nil)
         |> start_async({:composer, job.ref}, fn -> {:split, text, Intake.run(text)} end)}
    end
  end

  defp start_enqueue(socket, [], _shown),
    do: {:noreply, composer_error(socket, "Escolha ao menos uma tarefa.")}

  defp start_enqueue(socket, requests, shown) do
    repo = socket.assigns.repo
    client = GitHub.client()
    job = composer_job(:enqueue, requests, length(requests))

    action =
      %{repository: repo, requests: requests, client: client}
      |> then(fn action ->
        if socket.assigns.composer_split and length(requests) > 1 do
          Map.put(action, :objective, %{
            title: objective_title(socket.assigns.composer_text),
            done_criterion: "Todas as tarefas mescladas."
          })
        else
          action
        end
      end)

    {:noreply,
     socket
     |> assign(
       composer_job: job,
       composer_error: nil,
       composer_retry: nil,
       composer_receipt: nil
     )
     |> start_async({:composer, job.ref}, fn ->
       case Actions.run(:create_tasks, action, Actions.owner(:ui), confirm: shown) do
         {:ok, results} -> {:enqueue, requests, results}
         {:error, {refusal, _phrase}} -> {:enqueue_refused, requests, refusal}
       end
     end)}
  end

  defp progress(%{total: total}) when total in [0, nil], do: 0
  defp progress(%{merged: merged, total: total}), do: round(merged * 100 / total)

  defp objective_title(text) do
    text
    |> to_string()
    |> String.split("\n", parts: 2)
    |> hd()
    |> String.trim()
    |> String.slice(0, 120)
    |> case do
      "" -> "Objetivo do pedido"
      title -> title
    end
  end

  defp composer_job(kind, payload, total) do
    ref = System.unique_integer([:positive])
    Process.send_after(self(), {:composer_timeout, ref}, composer_timeout())
    %{ref: ref, kind: kind, payload: payload, total: total}
  end

  defp composer_timeout, do: Application.get_env(:agent_board, :composer_timeout_ms, 60_000)

  defp finish_composer_job(socket, _job, {:ok, {:split, text, {:ok, result}}}) do
    socket
    |> assign(composer_job: nil)
    |> show_intake_result(socket.assigns.repo, text, %{}, result)
    |> assign(composer_selected: all_indices(result.tasks))
  end

  defp finish_composer_job(socket, _job, {:ok, {:split, text, {:error, reason}}}) do
    socket
    |> assign(composer_job: nil)
    |> composer_error(split_failure(reason), {:split, text})
    |> refresh_ai()
  end

  # The words changed between what the composer showed and what was sent:
  # nothing was created; the person reads the new sentence and sends again.
  defp finish_composer_job(socket, _job, {:ok, {:enqueue_refused, _requests, _refusal}}) do
    socket
    |> assign(composer_job: nil)
    |> composer_error(
      "Nada foi criado: o pedido mudou antes do envio. Confira a frase e envie de novo."
    )
  end

  defp finish_composer_job(socket, _job, {:ok, {:enqueue, requests, results}}) do
    items = Enum.map(results, fn {request, result} -> receipt_item(request, result) end)
    failed = Enum.count(items, &match?({:error, _}, &1.outcome))

    socket
    |> assign(
      composer_job: nil,
      composer_receipt: %{items: items},
      composer_retry: if(failed > 0, do: {:enqueue, requests})
    )
    |> load(socket.assigns.repo)
    |> flash_receipt(items, failed)
  end

  defp finish_composer_job(socket, %{kind: kind, payload: payload}, {:exit, reason}) do
    socket
    |> assign(composer_job: nil)
    |> composer_error(
      "#{job_name(kind)} parou de forma inesperada (#{inspect(reason)}). Nada mais foi feito.",
      {kind, payload}
    )
  end

  defp cancel_composer_job(%{assigns: %{composer_job: nil}} = socket), do: socket

  defp cancel_composer_job(%{assigns: %{composer_job: %{ref: ref}}} = socket) do
    socket
    |> cancel_async({:composer, ref})
    |> assign(composer_job: nil, composer_error: nil, composer_retry: nil)
  end

  defp receipt_item(request, {:ok, task, outcome}),
    do: %{title: request.title, outcome: outcome, task: task}

  defp receipt_item(request, {:error, reason}),
    do: %{title: request.title, outcome: {:error, reason}, task: nil}

  defp flash_receipt(socket, items, 0) do
    case items do
      [%{outcome: :created, task: %{number: number}}] when is_integer(number) ->
        put_flash(socket, :info, "Pedido ##{number} na fila")

      [%{outcome: :existing, task: %{number: number}}] when is_integer(number) ->
        put_flash(socket, :info, "Esse pedido já estava na fila: ##{number}")

      _ ->
        created = Enum.count(items, &(&1.outcome == :created))

        put_flash(
          socket,
          :info,
          "#{created} #{if created == 1, do: "tarefa", else: "tarefas"} na fila"
        )
    end
  end

  defp flash_receipt(socket, items, failed) when failed == length(items),
    do: put_flash(socket, :error, "Nada entrou na fila. Veja o recibo e tente de novo.")

  defp flash_receipt(socket, items, failed) do
    done = length(items) - failed

    put_flash(
      socket,
      :error,
      "Criei #{done} de #{length(items)}. Veja o recibo e tente as restantes."
    )
  end

  defp job_name(:split), do: "A divisão"
  defp job_name(:enqueue), do: "A criação das issues"

  defp split_failure(:malformed_output),
    do: "A IA respondeu fora do formato esperado. Nada foi criado."

  defp split_failure(:not_configured),
    do: "A IA não está configurada. Envie como pedido único."

  defp split_failure(:auth_expired), do: "A chave da IA expirou ou foi recusada."
  defp split_failure(:usage_limit), do: "A IA está sem cota agora."
  defp split_failure(:budget_exhausted), do: "O orçamento de IA do board acabou."
  defp split_failure(:no_provider), do: "Nenhum provedor de IA configurado."

  defp split_failure(:audit_unavailable),
    do: "A chamada não pôde ser registrada; nada foi criado."

  defp split_failure({:http, status}), do: "A IA respondeu HTTP #{status}."

  defp split_failure(%{__exception__: true} = exception),
    do: "A IA não respondeu: " <> Exception.message(exception)

  defp split_failure(reason), do: "A IA não respondeu (#{inspect(reason)})."

  defp all_indices([]), do: MapSet.new()
  defp all_indices(tasks), do: MapSet.new(0..(length(tasks) - 1))

  # Closing a receipt whose items all landed starts the next request fresh; a
  # receipt with a failure stays, so the retry is still there when the panel
  # reopens.
  defp settle_composer(
         %{assigns: %{panel: "composer", composer_receipt: %{items: items}}} = socket
       ) do
    if Enum.any?(items, &match?({:error, _}, &1.outcome)),
      do: socket,
      else: reset_composer(socket)
  end

  defp settle_composer(socket), do: socket

  defp reset_composer(socket) do
    socket
    |> cancel_composer_job()
    |> assign(
      composer_text: "",
      composer_title: nil,
      composer_split: false,
      composer_selected: MapSet.new(),
      composer_error: nil,
      composer_retry: nil,
      composer_receipt: nil,
      composer_answers: "",
      intake: nil,
      composer_executor_touched: false,
      composer_executor:
        socket.assigns.composer_routing &&
          (socket.assigns.composer_routing.suggestion.executor || Executors.default())
    )
  end
end
