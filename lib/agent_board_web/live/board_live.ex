defmodule AgentBoardWeb.BoardLive do
  @moduledoc "The board: the columns, the repositories and the tasks, live."
  use AgentBoardWeb, :live_view

  import Ecto.Query, warn: false

  alias AgentBoard.{
    Actions,
    AgentAccess,
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
    Tickets,
    Time,
    Titles,
    Unblock,
    Voice
  }

  alias AgentBoard.Board.{Attachments, PrivateContext, Task}
  alias AgentBoard.Freshness
  alias AgentBoard.Intake.{IssueBody, RepoDigest}
  alias AgentBoard.Metrics.Observations
  alias AgentBoard.Routing
  alias AgentBoard.Routing.Signals
  alias AgentBoard.Runners.Execution
  alias AgentBoard.System.{UpdateRun, Version}
  alias AgentBoard.Usage.{Costs, Harness, Ledger, Report}
  alias AgentBoard.Voice.{Activity, Phrases}

  import AgentBoardWeb.BoardComponents.Composer, only: [composer: 1]
  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1, kbd: 1]
  import AgentBoardWeb.BoardComponents.DailySummary, only: [daily_summary: 1]
  import AgentBoardWeb.BoardComponents.FreshnessBeacon, only: [beacon: 1]
  import AgentBoardWeb.BoardComponents.FrozenBanner, only: [frozen_banner: 1]
  import AgentBoardWeb.BoardComponents.Inspector, only: [inspector: 1]
  import AgentBoardWeb.BoardComponents.LogsSheet, only: [logs_sheet: 1]
  import AgentBoardWeb.BoardComponents.MergeLog, only: [merge_log: 1]
  import AgentBoardWeb.BoardComponents.NeedsYou, only: [needs_you: 1]
  import AgentBoardWeb.BoardComponents.ObjectiveTree, only: [objective_tree: 1]
  import AgentBoardWeb.BoardComponents.NowLane, only: [now_lane: 1]
  import AgentBoardWeb.BoardComponents.QueueList, only: [queue_list: 1]
  import AgentBoardWeb.BoardComponents.Shortcuts, only: [shortcuts: 1]
  import AgentBoardWeb.BoardComponents.Summary, only: [summary: 1]
  import AgentBoardWeb.BoardComponents.Today, only: [today_view: 1]
  import AgentBoardWeb.BoardComponents.Throughput, only: [throughput: 1]
  import AgentBoardWeb.Components.VersionBadge, only: [version_badge: 1]

  alias AgentBoardWeb.FailureText

  alias AgentBoardWeb.{
    BoardComponents,
    BoardNavigation,
    Locale,
    VoiceConversation,
    VoiceSpeech
  }

  alias AgentBoardWeb.BoardComponents.PeakRate
  alias AgentBoardWeb.BoardComponents.VoicePresence

  # The task actions a button may send, mapped explicitly (never to_atom).
  @task_actions %{"stop" => :stop_task, "archive" => :archive_task, "resume" => :resume_task}
  @max_resume_items 1000
  # What the composer gathers for the request's private context: never sent
  # to the model, written on this machine at the send (`PrivateContext`).
  @empty_private %{note: "", folder: "", folders: [], folder_error: nil, meta: %{}, files: []}
  @version_check_interval 5 * 60 * 1000

  @impl true
  def mount(params, _session, socket) do
    repos = Board.list_repositories()
    connect = if connected?(socket), do: get_connect_params(socket), else: %{}
    resume = connect["board_resume"]
    last_visit = parse_last_visit(connect["board_last_visit"])
    message_seen = parse_message_seen(connect["board_message_seen"])
    tz_offset = parse_offset(connect["board_tz_offset"])

    socket =
      assign(socket,
        repos: repos,
        last_visit: last_visit,
        message_seen: message_seen,
        inbox_filter: "all",
        inbox_notice: nil,
        inbox: %{messages: [], alerts: [], providers: []},
        tz_offset: tz_offset,
        work: empty_work(),
        flow: nil,
        orchestrator: {:error, :unknown},
        digest: nil,
        daily_summary: nil,
        needs_expanded: false,
        queue_limit: 8,
        queue_filter: :all,
        history_list: "tasks",
        history_query: "",
        ended: %{items: [], has_more: false},
        repo: nil,
        view: nil,
        dispatch_paused: false,
        board: empty(),
        today: %{
          repos: %{},
          needs: [],
          running: [],
          queue: [],
          projects: [],
          merged_today: 0,
          delivered_today: 0,
          seen_today: 0,
          trend: []
        },
        today_spend: nil,
        objectives: [],
        superagents: [],
        agent_access_projects: [],
        agent_access: %{count: 0, refused: MapSet.new()},
        project_pending: nil,
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
        settings_section: nil,
        logs_sources: [],
        logs_entries: [],
        logs_state: Logs.empty_state(),
        logs_status: %{},
        logs_timer: nil,
        logs_paused: false,
        reload_pending: false,
        attention_timer: nil,
        peak_rate: nil,
        peak_now: nil,
        conversation: nil,
        comments: [],
        ask_sending: %{},
        ask_draft: %{},
        ask_error: %{},
        inspector_tab: "conversa",
        inspector_activity: [],
        inspector_calls: [],
        inspector_calls_total: 0,
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
        inspector_blockers: [],
        unblock: nil,
        unblock_for: nil,
        unblock_suggestions: [],
        unblock_ai: :idle,
        blocker_open: false,
        blocker_title: "",
        blocker_body: "",
        blocker_pending: nil,
        intake: nil,
        composer_text: "",
        composer_title: nil,
        composer_split: false,
        composer_selected: MapSet.new(),
        composer_error: nil,
        composer_retry: nil,
        composer_job: nil,
        composer_receipt: nil,
        composer_answers: "",
        composer_attachments: [],
        composer_private: @empty_private,
        composer_routing: nil,
        composer_routing_for: nil,
        composer_executor: nil,
        composer_executor_touched: false,
        ai_calls: [],
        ai_status: AI.status(),
        version: Version.status(),
        codex_quota: Costs.codex_weekly(Ledger.limits()),
        # A page opened during an update joins it, the fast-forward's own
        # reload included.
        busy: UpdateRun.running?(),
        update_progress: update_in_progress(),
        voice: current_voice(),
        spoken_text: nil,
        spoken_at: 0,
        # Rotates the attention phrases; a random start keeps a reload from
        # always opening with the same sentence.
        voice_turn: :rand.uniform(1_000)
      )
      |> allow_upload(:attachments,
        accept: Attachments.accepted(),
        max_entries: Attachments.max_files(),
        max_file_size: Attachments.max_bytes(),
        auto_upload: true
      )

    repo =
      case params["repo"] do
        nil -> default_repo(repos)
        slug -> Board.repository_by_slug(slug) || default_repo(repos)
      end

    # The voice settings are board-wide: a change in another tab, by the API
    # or by a spoken command reaches this socket (handle_info setting_changed).
    if connected?(socket), do: subscribe_board_wide()

    socket = maybe_check_version(socket)

    # handle_params/3 always follows mount and loads the board: loading here
    # too read everything twice on every page and every connection.
    {:ok,
     socket
     |> assign(:superagents, Superagents.list())
     |> then(&if(connected?(&1), do: refresh_agent_access(&1), else: &1))
     |> VoiceConversation.mount()
     |> assign(:opening_repo, repo)
     |> show_daily_summary()}
  end

  defp subscribe_board_wide do
    Settings.subscribe()
    DailySummary.subscribe()
    Board.subscribe_today()
    Superagents.subscribe()
    UpdateRun.subscribe()
  end

  # A page opened during an update joins it, the fast-forward's own reload
  # included.
  defp update_in_progress do
    if UpdateRun.running?(), do: [update_step(:fetch, :running)], else: []
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

  defp parse_message_seen(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, seen} when is_map(seen) ->
        seen
        |> Enum.take(300)
        |> Enum.reduce(%{}, &put_valid_message_seen/2)

      _ ->
        %{}
    end
  end

  defp parse_message_seen(_), do: %{}

  defp put_valid_message_seen({key, version}, acc) do
    if valid_message_seen?(key, version),
      do: Map.put(acc, key, version),
      else: acc
  end

  defp valid_message_seen?(key, version),
    do: is_binary(key) and is_binary(version) and version =~ ~r/\A[0-9a-f]{64}\z/

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
      next_attention_ms:
        Lanes.next_attention_in(board.running, run.silences, run.stall_after, now),
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
          limit: socket.assigns.queue_limit,
          tickets_by_number: run.tickets,
          stall_after: run.stall_after
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
  # with the API switched off, or not answered yet, does not know.
  defp agent_status({:ok, _load}), do: :up
  defp agent_status({:error, :not_configured}), do: :unknown
  defp agent_status({:error, :unknown}), do: :unknown
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

  # The same span the long-run rule measures, so the clock and the heads-up agree.
  defp elapsed(task, run) do
    case Lanes.working_since(task) do
      %DateTime{} = since -> Time.age_seconds(since, run.frozen_at || run.now)
      nil -> nil
    end
  end

  defp running_card(task, run) do
    ticket = Map.get(run.tickets, task.number)
    silence = Map.get(run.silences, task.number)

    worktree = AgentWorktree.observe(ticket)

    %{
      id: task.id,
      number: task.number,
      title: task.title,
      step: worktree && worktree.step,
      elapsed: elapsed(task, run),
      silence: silence,
      stalled: AgentSignal.stalled?(silence, run.stall_after),
      answered_at: ticket && Tickets.answered_at(ticket),
      agent: nil,
      phases: Tickets.stages(ticket, worktree)
    }
  end

  defp tickets_by_number(tickets, repo) do
    tickets
    |> Enum.filter(&AgentState.same_repository?(&1, repo))
    |> Tickets.by_number()
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

  defp load_inspector(socket) do
    case socket.assigns.conversation do
      nil ->
        assign(socket,
          inspector_activity: [],
          inspector_calls: [],
          inspector_calls_total: 0,
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
          inspector_blockers: [],
          unblock: nil,
          unblock_for: nil,
          unblock_suggestions: [],
          unblock_ai: :idle,
          blocker_open: false,
          blocker_title: "",
          blocker_body: "",
          blocker_pending: nil
        )

      task ->
        pr = Board.task_pull_request(task, socket.assigns.comments)

        ci = pr && Map.get(socket.assigns.local_ci, pr.number)

        executions = inspector_executions(socket, task)
        runner_executions = Runners.for_task(task.id)

        assign(
          socket,
          [
            inspector_activity: Board.task_activity(task, pr),
            inspector_calls: AI.recent_for_task(task.id),
            inspector_calls_total: AI.count_for_task(task.id),
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
          ] ++ unblock_assigns(socket, task)
        )
    end
  end

  # The unblock inputs belong to the open task: a board update must not erase
  # an AI suggestion or a confirmation the person is editing.
  defp unblock_assigns(socket, task) do
    same? = socket.assigns[:unblock_for] == task.id

    [
      inspector_blockers: Board.blockers_for(task),
      unblock: Unblock.context(socket.assigns.comments),
      unblock_for: task.id,
      unblock_suggestions: if(same?, do: socket.assigns[:unblock_suggestions], else: []),
      unblock_ai: if(same?, do: socket.assigns[:unblock_ai], else: :idle),
      blocker_open: if(same?, do: socket.assigns[:blocker_open], else: false),
      blocker_pending: if(same?, do: socket.assigns[:blocker_pending], else: nil)
    ]
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

  # The project card's − and + and the totals count from the row, not the runner.
  defp save_superagent_ceiling(socket, max) do
    if superagent = Superagents.get_by_repository(socket.assigns.repo) do
      Superagents.set_max_workers(superagent, max)
    end

    socket
  end

  # The runner's ceiling, saved through its API; the tile re-reads the load.
  defp set_max_workers(socket, max) do
    params = %{max: max, client: Orchestrator.client_for(socket.assigns.repo)}

    case Actions.run(:set_max_workers, params, ui()) do
      {:ok, max} ->
        socket
        |> save_superagent_ceiling(max)
        |> load(socket.assigns.repo)
        |> put_flash(:info, gettext("Executor limit: %{agents}.", agents: agents(max)))

      {:ok, max, :restarting} ->
        socket
        |> save_superagent_ceiling(max)
        |> load(socket.assigns.repo)
        |> put_flash(
          :info,
          gettext("Executor limit: %{agents}. The orchestrator will restart.",
            agents: agents(max)
          )
        )

      {:error, :conflict} ->
        socket
        |> load(socket.assigns.repo)
        |> put_flash(
          :error,
          gettext(
            "Executor settings changed in the agent dashboard. Check the limit and try again."
          )
        )

      {:error, reason} ->
        put_flash(
          socket,
          :error,
          gettext("Could not change the executor limit (%{reason}).",
            reason: limit_reason(reason)
          )
        )
    end
  end

  defp agents(n), do: ngettext("%{count} agent", "%{count} agents", n)

  defp limit_reason(:out_of_range), do: gettext("must be between 1 and 16")
  defp limit_reason(:not_configured), do: gettext("orchestrator API is off")
  defp limit_reason(:unreachable), do: gettext("orchestrator unreachable")
  defp limit_reason(:timeout), do: gettext("orchestrator did not respond")
  defp limit_reason({:refused, message}) when is_binary(message), do: message
  defp limit_reason({:http, status}), do: "HTTP #{status}"
  defp limit_reason(_reason), do: gettext("unexpected response")

  # The ledger is read when the Executions tab opens and reused while the
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
    running_ids = MapSet.new(Enum.map(merged, & &1.id))

    projects =
      Enum.map(today.projects, fn project ->
        %{
          project
          | running: Enum.count(merged, &(&1.repository_id == project.id)),
            queued:
              Enum.count(
                today.queue,
                &(&1.repository_id == project.id and not MapSet.member?(running_ids, &1.id))
              )
        }
      end)

    %{
      today
      | running: merged,
        queue: Enum.reject(today.queue, &MapSet.member?(running_ids, &1.id)),
        projects: projects
    }
  end

  defp load(socket, nil) do
    today = Overview.today(socket.assigns.tz_offset) |> with_runner_running()

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
      inspector_calls_total: 0,
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
    |> watch_next_change()
  end

  # The span is the board's load budget on the dashboard
  # (`agent_board.board.load`): every reload goes through here.
  defp load(socket, repo) do
    :telemetry.span([:agent_board, :board, :load], %{repository: repo_slug(repo)}, fn ->
      {socket |> read_board(repo) |> watch_next_change(), %{repository: repo_slug(repo)}}
    end)
  end

  # Nothing broadcasts a task that goes quiet or the hour DeepSeek's rate
  # changes, so without this the page would wait for the next sync. One
  # timer per page, for the nearer of the two, replaced on every read.
  defp watch_next_change(socket) do
    if timer = socket.assigns.attention_timer, do: Process.cancel_timer(timer)

    now = DateTime.utc_now()
    rate = PeakRate.info(now, socket.assigns.tz_offset)

    due =
      [Map.get(socket.assigns.work, :next_attention_ms), PeakRate.ms_until_change(rate, now)]
      |> Enum.filter(&is_integer/1)
      |> Enum.min()

    timer = if connected?(socket), do: Process.send_after(self(), :board_updated, due)

    assign(socket, attention_timer: timer, peak_rate: rate, peak_now: now)
  end

  defp read_board(socket, repo) do
    today = Overview.today(socket.assigns.tz_offset) |> with_runner_running()
    spend = Report.today(socket.assigns.tz_offset)
    inbox = Board.inbox()

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
            orchestrator: {:error, :unknown},
            conversation: nil,
            comments: [],
            intake: nil,
            composer_text: "",
            composer_title: nil,
            composer_split: false,
            composer_selected: MapSet.new(),
            composer_error: nil,
            composer_retry: nil,
            composer_job: nil,
            composer_receipt: nil,
            composer_answers: "",
            composer_attachments: [],
            composer_private: @empty_private,
            composer_routing: nil,
            composer_routing_for: nil,
            composer_executor: nil,
            composer_executor_touched: false,
            inspector_tab: "conversa",
            inspector_activity: [],
            inspector_calls: [],
            inspector_calls_total: 0,
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

        # The last answer: a runner that accepts and never answers would hold
        # this process (and every click behind it) for its timeouts.
        orchestrator = socket.assigns.orchestrator
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
          inbox: inbox,
          today_spend: spend,
          objectives: Board.objectives(repo),
          agent_snapshot: agent,
          work: work,
          digest: work.digest,
          ai_calls: AI.recent(5),
          ai_status: AI.status(),
          live: connected?(socket)
        )
        |> start_async(:orchestrator, load_for(repo))

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
          inbox: inbox,
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

  # The answer travels with the repository it is about.
  defp load_for(repo) do
    client = Orchestrator.client_for(repo)
    fn -> {repo.id, Orchestrator.load(client)} end
  end

  # The throughput strip: read once per load, from the tables, the agent's
  # tickets and the orchestrator; the arithmetic is pure and tested apart.
  defp flow_for(repo, agent, tz_offset, orchestrator) do
    now = DateTime.utc_now()

    repo
    |> Observations.read(agent, now: now, load: orchestrator)
    |> Metrics.throughput(now, tz_offset)
  end

  defp with_load_tile(nil, _answer), do: nil

  defp with_load_tile(flow, answer) do
    tiles = Enum.map(flow.tiles, &if(&1.key == "load", do: Metrics.load_tile(answer), else: &1))
    %{flow | tiles: tiles}
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
           gettext("%{job} did not finish in %{seconds} s. Nothing was confirmed; try again.",
             job: job_name(kind),
             seconds: seconds
           ),
           {kind, payload}
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(:version_check, socket) do
    if Application.get_env(:agent_board, :version_check_on_mount, true) do
      Process.send_after(self(), :version_check, @version_check_interval)
    end

    {:noreply, start_async(socket, :version_check, fn -> Version.refresh_shared() end)}
  end

  def handle_info({:update_step, id, state}, socket) do
    {:noreply,
     assign(socket,
       busy: true,
       update_progress: push_update_step(socket.assigns.update_progress, id, state)
     )}
  end

  def handle_info({:update_finished, {:ok, sha}}, socket) do
    {:noreply,
     socket
     |> assign(
       update_progress: push_update_step(socket.assigns.update_progress, :restart, :running)
     )
     |> push_event("restart", %{})
     |> put_flash(:info, gettext("Updated to %{sha}; restarting the server…", sha: sha))}
  end

  def handle_info({:update_finished, {:error, reason}}, socket) do
    progress =
      Enum.map(socket.assigns.update_progress, fn step ->
        if step.state == :running, do: %{step | state: :error}, else: step
      end)

    {:noreply,
     socket
     |> assign(busy: false, update_progress: progress)
     |> put_flash(
       :error,
       gettext(
         "The update stopped midway; the board still runs the old code and nothing was restarted. %{reason}",
         reason: FailureText.text(reason)
       )
     )}
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
      handle_info(:board_updated, socket)
    else
      if current != repository_id do
        {:noreply, assign(socket, :inbox, Board.inbox())}
      else
        {:noreply, socket}
      end
    end
  end

  def handle_info(:superagents_changed, socket) do
    socket =
      socket
      |> assign(:superagents, Superagents.list())

    # A new profile becomes a new source while the sheet is open; the old
    # entries stay in the buffer and the new file is read from its tail.
    socket =
      if socket.assigns.panel == "logs" do
        socket = assign(socket, :logs_sources, Logs.sources(socket.assigns.superagents))
        if socket.assigns.logs_paused, do: socket, else: read_logs_once(socket)
      else
        socket
      end

    {:noreply, refresh_agent_access(socket)}
  end

  def handle_info(:agent_access_changed, socket),
    do: {:noreply, refresh_agent_access(socket)}

  # The row that held the button leaves on the next read, so the result is
  # said here (AgentAction).
  def handle_info({:agent_access_done, text}, socket),
    do: {:noreply, put_flash(socket, :info, text)}

  def handle_info({:logs_tick, token}, socket) do
    current = socket.assigns.logs_timer

    if socket.assigns.panel == "logs" and not socket.assigns.logs_paused and
         match?(%{token: ^token}, current) do
      {:noreply, socket |> read_logs_once() |> schedule_logs_tick()}
    else
      {:noreply, socket}
    end
  end

  # Broadcasts come in bursts (poller, sync, actions) and a reload costs dozens
  # of queries, the runner's files and the orchestrator: one reload per burst.
  # The assigns still hold the pre-burst board, so announce/4 sees the whole
  # burst as one change.
  def handle_info(:board_updated, socket) do
    case Application.get_env(:agent_board, :board_reload_ms, 300) do
      0 ->
        handle_info(:reload_board, socket)

      _ms when socket.assigns.reload_pending ->
        {:noreply, socket}

      ms ->
        Process.send_after(self(), :reload_board, ms)
        {:noreply, assign(socket, :reload_pending, true)}
    end
  end

  def handle_info(:reload_board, socket) do
    socket = assign(socket, :reload_pending, false)
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
      |> mark_open_conversation_seen()

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

  # The header badge should know about a moved main on a fresh page, not
  # only after someone opens Settings. This is a fetch, never an update;
  # the same check repeats once every five minutes while the page is open.
  defp maybe_check_version(socket) do
    if connected?(socket) and Application.get_env(:agent_board, :version_check_on_mount, true) do
      Process.send_after(self(), :version_check, @version_check_interval)
      start_async(socket, :version_check, fn -> Version.refresh_shared() end)
    else
      socket
    end
  end

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
      |> refresh_settings_quota(previous_panel)
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

    {:noreply, socket |> assign_page_title() |> mark_open_conversation_seen()}
  end

  # The browser tab says what this tab shows, so several open boards differ.
  defp assign_page_title(%{assigns: %{view: "hoje"}} = socket),
    do: assign(socket, :page_title, gettext("Today") <> " · Agent Board")

  defp assign_page_title(%{assigns: %{repo: %{name: name}}} = socket),
    do: assign(socket, :page_title, name <> " · Agent Board")

  defp assign_page_title(socket), do: assign(socket, :page_title, nil)

  # The Codex quota moves while the board runs. Reading it when the settings
  # panel opens keeps the navigation hint fresh without a query per render.
  defp refresh_settings_quota(%{assigns: %{panel: "settings"}} = socket, previous)
       when previous != "settings" do
    assign(socket, :codex_quota, Costs.codex_weekly(Ledger.limits()))
  end

  defp refresh_settings_quota(socket, _previous), do: socket

  defp mark_open_conversation_seen(%{assigns: %{conversation: nil}} = socket), do: socket

  defp mark_open_conversation_seen(socket) do
    task_id = socket.assigns.conversation.id
    item = Enum.find(socket.assigns.inbox.messages, &(&1.task_id == task_id))
    key = Integer.to_string(task_id)

    if item && item.version != Map.get(socket.assigns.message_seen, key) do
      socket =
        assign(socket, :message_seen, Map.put(socket.assigns.message_seen, key, item.version))

      if connected?(socket),
        do: push_event(socket, "message_seen", %{task_id: task_id, version: item.version}),
        else: socket
    else
      socket
    end
  end

  # The list on screen can be older than a removal in another tab.
  # Only the agent's loopback API and its local database: no GitHub quota.
  defp refresh_agent_access(%{assigns: %{superagents: []}} = socket) do
    assign(socket, agent_access_projects: [], agent_access: AgentAccess.summary([]))
  end

  defp refresh_agent_access(socket) do
    superagents = socket.assigns.superagents

    start_async(socket, :agent_access, fn -> AgentAccess.overview(superagents) end)
  end

  defp superagent_gone(socket) do
    socket
    |> assign(:superagents, Superagents.list())
    |> put_flash(:error, gettext("That superagent is no longer on the board."))
  end

  # Dictation continues the draft: it arrives whole and has no undo.
  defp with_dictated(draft, dictated) do
    if String.trim(draft || "") == "",
      do: dictated,
      else: String.trim_trailing(draft) <> "\n" <> dictated
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

  defp provision_project(socket, owner, name, params) do
    owner = String.trim(owner)
    name = String.trim(name)
    path = String.trim(params["path"] || "")
    path = if path == "", do: default_checkout_path(name), else: Path.expand(path)
    workers = worker_count(params["workers"])

    with {:ok, _} <- Actions.run(:add_repository, %{owner: owner, name: name}, ui()),
         repository when not is_nil(repository) <- Board.repository_by_slug("#{owner}/#{name}"),
         {:ok, source} <- Superagents.default_source(),
         {:ok, preview} <-
           Superagents.preview(repository, source, %{path: path, workers: workers}) do
      phrase =
        Actions.phrase(
          :provision_superagent,
          %{
            repository: repository,
            source: source,
            path: path
          },
          Locale.language()
        )

      {:noreply,
       socket
       |> assign(:repos, Board.list_repositories())
       |> assign(:project_pending, %{
         params: %{repository: repository, source: source, path: path, workers: preview.workers},
         phrase: phrase
       })}
    else
      {:error, :no_working_profile} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext(
             "No DSH working profile on this machine. Run dsh once to create the superagent profile."
           )
         )}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Could not prepare the project: %{reason}", reason: inspect(reason))
         )}
    end
  end

  defp track_project(socket, owner, name) do
    owner = String.trim(owner)
    name = String.trim(name)

    case Actions.run(:add_repository, %{owner: owner, name: name}, ui()) do
      {:ok, _} ->
        repos = Board.list_repositories()
        repo = Enum.find(repos, &(&1.owner == owner and &1.name == name))
        {:noreply, socket |> assign(:repos, repos) |> load(repo)}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, gettext("Could not track %{repo}", repo: "#{owner}/#{name}"))}
    end
  end

  defp worker_count(value) do
    case Integer.parse(to_string(value || "")) do
      {count, ""} when count >= 1 -> min(count, Orchestrator.worker_range().last)
      _ -> 1
    end
  end

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
        {:noreply, put_flash(socket, :info, gettext("Sync requested."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Unable to request synchronization."))}
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
    with task_id when is_integer(task_id) <- Board.parse_id(id),
         %Task{} = task <- Board.task(task_id) do
      {:noreply,
       push_patch(socket, to: BoardNavigation.path(task.repository, "conversation", task.id))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("open_inbox_task", %{"id" => id}, socket) do
    with {task_id, ""} <- Integer.parse(to_string(id)),
         %Task{} = task <- Board.task(task_id),
         true <- task.repository.active do
      {:noreply,
       push_patch(socket,
         to: BoardNavigation.path(task.repository, "conversation", task.id, "conversa")
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("filter_inbox", %{"filter" => filter}, socket)
      when filter in ["all", "unread"] do
    {:noreply, assign(socket, inbox_filter: filter, inbox_notice: nil)}
  end

  def handle_event("filter_inbox", _params, socket), do: {:noreply, socket}

  def handle_event("mark_inbox_message_seen", %{"id" => id, "version" => version}, socket)
      when is_binary(id) and is_binary(version) do
    inbox = Board.inbox()
    socket = assign(socket, :inbox, inbox)

    with {task_id, ""} <- Integer.parse(id),
         true <- task_id > 0,
         %{version: ^version} <- Enum.find(inbox.messages, &(&1.task_id == task_id)) do
      key = Integer.to_string(task_id)

      if Map.get(socket.assigns.message_seen, key) == version do
        {:noreply, assign(socket, :inbox_notice, nil)}
      else
        {:noreply,
         socket
         |> assign(
           message_seen: Map.put(socket.assigns.message_seen, key, version),
           inbox_notice: nil
         )
         |> push_event("message_seen", %{task_id: task_id, version: version, quick: true})}
      end
    else
      _ ->
        {:noreply,
         assign(
           socket,
           :inbox_notice,
           gettext("The reply changed. Read the new message before marking it.")
         )}
    end
  end

  def handle_event("mark_inbox_message_seen", _params, socket),
    do:
      {:noreply,
       assign(socket, :inbox_notice, gettext("That reply was not found. Reload the window."))}

  def handle_event("mark_messages_seen", _params, socket) do
    versions =
      Map.new(socket.assigns.inbox.messages, fn item ->
        {Integer.to_string(item.task_id), item.version}
      end)

    seen = Map.merge(socket.assigns.message_seen, versions)

    if seen == socket.assigns.message_seen do
      {:noreply, assign(socket, :inbox_notice, nil)}
    else
      {:noreply,
       socket
       |> assign(message_seen: seen, inbox_notice: nil)
       |> push_event("messages_seen", %{versions: versions})}
    end
  end

  def handle_event("select", %{"repo" => slug}, socket) do
    current = socket.assigns.repo

    # Hoje keeps the last project loaded underneath: clicking it there leaves Hoje.
    if current && socket.assigns.view != "hoje" && slug == "#{current.owner}/#{current.name}" do
      # LiveView recovers phx-change forms after reconnect. Same selection must not close a panel.
      {:noreply, socket}
    else
      {:noreply, push_patch(socket, to: "/?repo=#{URI.encode_www_form(slug)}")}
    end
  end

  # A merged PR's way into its task: the first issue the PR closes that the
  # board tracks (the rule of `Attribution.task_for_pull/2`), read on the click.
  @impl true
  def handle_event("open_pr_task", %{"number" => number}, socket) do
    repo = socket.assigns.repo
    pull = repo && Board.find_pull_request(repo, Board.parse_id(number) || 0)
    task = pull && Enum.find_value(pull.closes_issues || [], &Board.find_task(repo, &1))

    if task do
      {:noreply, BoardNavigation.open_task(socket, task.id)}
    else
      {:noreply,
       put_flash(socket, :info, gettext("The board does not track the issue this PR closes."))}
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
        {:noreply,
         put_flash(socket, :error, gettext("Could not track %{repo}", repo: "#{owner}/#{name}"))}
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
        {:noreply, put_flash(socket, :error, refused_text())}

      {:ok, _} ->
        {:noreply,
         socket
         |> refresh_inspector_after_act(task_id)
         |> put_flash(:info, gettext("Task updated"))
         |> speak(Voice.task_summary(task.title, action, socket.assigns.voice.language))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Unable to update the task"))}
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
           |> put_flash(
             :info,
             gettext("Execution stopped; the task is blocked until you decide what to do.")
           )}

        {:error, {refusal, _phrase}} when refusal in [:unconfirmed, :phrase_changed] ->
          {:noreply, put_flash(socket, :error, refused_text())}

        {:error, text} ->
          {:noreply, put_flash(socket, :error, text)}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Execution not found."))}
    end
  end

  @impl true
  def handle_event("open", %{"id" => id} = params, socket) do
    {:noreply, BoardNavigation.open_task(socket, id, params["tab"])}
  end

  @impl true
  def handle_event("inspector_tab", %{"tab" => tab}, socket) do
    tab =
      if tab in ~w(conversa atividade chamadas execucoes pr privado), do: tab, else: "conversa"

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

  @impl true
  def handle_event("show_panel", %{"panel" => "settings", "section" => section}, socket) do
    {:noreply, BoardNavigation.open_panel(socket, "settings", section)}
  end

  def handle_event("show_panel", %{"panel" => "history", "list" => list}, socket)
      when not is_nil(socket.assigns.repo) do
    {:noreply, push_patch(socket, to: BoardNavigation.history_path(socket.assigns.repo, list))}
  end

  def handle_event("show_panel", %{"panel" => panel}, socket) do
    {:noreply, BoardNavigation.open_panel(socket, panel)}
  end

  # Typing in the search replaces the entry: back leaves History, it does not
  # walk through every keystroke.
  def handle_event("history_search", %{"q" => query}, socket) do
    path = BoardNavigation.history_path(socket.assigns.repo, "tasks", String.trim(query))
    {:noreply, push_patch(socket, to: path, replace: true)}
  end

  def handle_event("load_more_ended", _params, socket) do
    case {socket.assigns.repo, socket.assigns.ended} do
      {%{id: id}, %{has_more: true, items: [_ | _] = items}} ->
        last = List.last(items)
        size = Board.ended_page_size()

        rows =
          Board.ended_page(id, socket.assigns.history_query, {last.ended_at, last.id}, size + 1)

        ended = %{
          items: Enum.uniq_by(items ++ Enum.take(rows, size), & &1.id),
          has_more: length(rows) > size
        }

        {:noreply, assign(socket, :ended, ended)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("add_project", %{"owner" => owner, "name" => name} = params, socket) do
    if params["create_agent"] == "true" do
      provision_project(socket, owner, name, params)
    else
      track_project(socket, owner, name)
    end
  end

  def handle_event("add_track", %{"owner" => owner, "name" => name}, socket),
    do: track_project(socket, owner, name)

  def handle_event("add_project_confirm", _params, socket) do
    case socket.assigns.project_pending do
      %{params: params, phrase: phrase} ->
        {:noreply,
         socket
         |> assign(project_pending: nil, provisioning: true)
         |> start_async(:provision, fn ->
           Superagents.detached(fn ->
             Actions.run(:provision_superagent, params, ui(), confirm: phrase)
           end)
         end)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("add_project_cancel", _params, socket),
    do: {:noreply, assign(socket, :project_pending, nil)}

  def handle_event("superagent_command", %{"id" => id, "action" => action}, socket) do
    name = if action == "pause", do: :pause_superagent, else: :resume_superagent

    case Superagents.get(id) do
      nil ->
        {:noreply, superagent_gone(socket)}

      superagent ->
        # Read here: the task that runs the action has no locale of its own.
        language = Locale.language()

        {:noreply,
         start_async(socket, {:superagent_command, superagent.id}, fn ->
           Actions.run(name, %{superagent: superagent}, ui(), language: language)
         end)}
    end
  end

  def handle_event("superagent_scale", %{"id" => id, "delta" => delta}, socket) do
    superagent = Superagents.get(id)

    with %AgentBoard.Superagents.Superagent{} <- superagent,
         {delta, ""} <- Integer.parse(delta),
         workers = max(1, min(Orchestrator.worker_range().last, superagent.max_workers + delta)),
         true <- workers != superagent.max_workers do
      language = Locale.language()

      {:noreply,
       start_async(socket, {:superagent_scale, superagent.id}, fn ->
         Actions.run(:scale_superagent, %{superagent: superagent, workers: workers}, ui(),
           language: language
         )
       end)}
    else
      false -> {:noreply, socket}
      nil -> {:noreply, superagent_gone(socket)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Unable to change the session limit."))}
    end
  end

  @impl true
  def handle_event("dismiss_panel", _params, socket) do
    {:noreply, push_patch(socket, to: BoardNavigation.path(socket.assigns.repo), replace: true)}
  end

  # -- unblocking a stopped task ---------------------------------------------
  #
  # The buttons live next to the draft, so the owner can ask the model for a
  # suggestion, edit it and send the same `:ask_task` action as before. A
  # prerequisite is a normal `:create_tasks` request linked to the blocked
  # task; the queue puts it first and the agent picks it like any other issue.

  def handle_event("suggest_unblock", _params, socket) do
    case {socket.assigns.conversation, socket.assigns.repo, socket.assigns.unblock} do
      {%Task{} = task, %{} = repo, %{} = unblock} ->
        if socket.assigns.ai_status == :not_configured do
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("AI is not configured; write the response or create the task.")
           )}
        else
          socket = assign(socket, unblock_ai: :busy, unblock_suggestions: [])

          {:noreply,
           start_async(socket, {:unblock_ai, task.id}, fn ->
             AI.call(:suggest_unblock, Unblock.ai_inputs(task, repo, unblock), task_id: task.id)
           end)}
        end

      _ ->
        {:noreply,
         put_flash(socket, :error, gettext("The agent has not yet logged a question or block."))}
    end
  end

  # The form leaves the page with the tab, and a form without phx-change is
  # not recovered after a reconnect: what was typed lives here.
  def handle_event("ask_change", %{"body" => body}, socket) when is_binary(body) do
    case socket.assigns.conversation do
      %Task{id: task_id} ->
        if Map.has_key?(socket.assigns.ask_sending, task_id),
          do: {:noreply, socket},
          else:
            {:noreply,
             assign(socket, ask_draft: Map.put(socket.assigns.ask_draft, task_id, body))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("use_unblock_suggestion", %{"text" => text}, socket) do
    case socket.assigns.conversation do
      %Task{id: task_id} ->
        {:noreply, assign(socket, ask_draft: Map.put(socket.assigns.ask_draft, task_id, text))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("open_blocker", _params, socket) do
    case {socket.assigns.conversation, socket.assigns.unblock} do
      {%Task{} = task, %{} = unblock} ->
        {:noreply,
         assign(socket,
           blocker_open: true,
           blocker_pending: nil,
           blocker_title: Unblock.blocker_title(task, unblock),
           blocker_body: Unblock.blocker_body(task, unblock)
         )}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("The agent has not yet logged a block."))}
    end
  end

  def handle_event("close_blocker", _params, socket),
    do: {:noreply, assign(socket, blocker_open: false, blocker_pending: nil)}

  def handle_event("blocker_prepare", %{"title" => title, "body" => body}, socket) do
    with %Task{} = task <- socket.assigns.conversation,
         %{} = repo <- socket.assigns.repo,
         title when title != "" <- String.trim(title),
         body when body != "" <- String.trim(body) do
      request = Unblock.request(repo, task, title, body)

      phrase =
        Actions.phrase(:create_tasks, %{repository: repo, requests: [request]}, Locale.language())

      {:noreply,
       assign(socket,
         blocker_open: false,
         blocker_title: title,
         blocker_body: body,
         blocker_pending: %{request: request, phrase: phrase}
       )}
    else
      _ ->
        {:noreply, put_flash(socket, :error, gettext("The task needs a title and body."))}
    end
  end

  # "Voltar e editar": a recorded no, and the form comes back with the edits.
  def handle_event("blocker_cancel", _params, socket) do
    case {socket.assigns.repo, socket.assigns.blocker_pending} do
      {%{} = repo, %{request: request}} ->
        :ok = Actions.decline(:create_tasks, %{repository: repo, requests: [request]}, ui())
        {:noreply, assign(socket, blocker_pending: nil, blocker_open: true)}

      _other ->
        {:noreply, assign(socket, blocker_pending: nil, blocker_open: false)}
    end
  end

  def handle_event("blocker_confirm", _params, socket) do
    case {socket.assigns.conversation, socket.assigns.repo, socket.assigns.blocker_pending} do
      {%Task{}, %{} = repo, %{request: request, phrase: phrase}} ->
        case Actions.run(:create_tasks, %{repository: repo, requests: [request]}, ui(),
               confirm: phrase
             ) do
          {:ok, [{_request, {:ok, created, _outcome}}]} when is_map(created) ->
            {:noreply,
             socket
             |> assign(blocker_pending: nil, blocker_open: false)
             |> put_flash(
               :info,
               gettext("Unblocking task #%{number} created and put first.",
                 number: created.number
               )
             )
             |> load_inspector()}

          {:ok, [{_request, {:error, reason}}]} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Could not create task: %{reason}", reason: FailureText.text(reason))
             )}

          {:ok, _other} ->
            {:noreply,
             socket
             |> assign(blocker_pending: nil, blocker_open: false)
             |> put_flash(:info, gettext("Unblocking task created."))
             |> load_inspector()}

          {:error, {refusal, _phrase}} when refusal in [:unconfirmed, :phrase_changed] ->
            {:noreply,
             socket
             |> assign(blocker_pending: nil, blocker_open: false)
             |> put_flash(:error, refused_text())}

          {:error, reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Could not create task: %{reason}", reason: FailureText.text(reason))
             )}
        end

      _ ->
        {:noreply,
         put_flash(socket, :error, gettext("Nothing created: the blocked task is not open."))}
    end
  end

  def handle_event("ask", %{"body" => body}, socket) do
    case {socket.assigns.conversation, String.trim(body)} do
      {nil, _body} ->
        {:noreply, put_flash(socket, :error, gettext("Open a task first"))}

      {_task, ""} ->
        {:noreply, socket}

      {%Task{} = task, body} ->
        if Map.has_key?(socket.assigns.ask_sending, task.id) do
          {:noreply, socket}
        else
          params = %{task: task, question: body, client: GitHub.client()}
          phrase = Actions.phrase(:ask_task, params, Locale.language())
          ref = make_ref()

          socket =
            assign(socket,
              ask_sending:
                Map.put(socket.assigns.ask_sending, task.id, %{
                  task_id: task.id,
                  body: body,
                  ref: ref
                }),
              ask_draft: Map.delete(socket.assigns.ask_draft, task.id),
              ask_error: Map.delete(socket.assigns.ask_error, task.id)
            )

          {:noreply,
           start_async(socket, {:ask_task, task.id, ref}, fn ->
             Actions.run(:ask_task, params, ui(), confirm: phrase)
           end)}
        end
    end
  end

  @impl true
  def handle_event("check_version", _params, socket) do
    case Version.refresh() do
      {:ok, _sha} ->
        {:noreply, assign(socket, version: Version.status())}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Could not reach main: %{reason}", reason: FailureText.text(reason))
         )}
    end
  end

  @impl true
  def handle_event("update", _params, socket) do
    if socket.assigns.busy do
      {:noreply, socket}
    else
      {:ok, _pid} = UpdateRun.start(ui())
      {:noreply, assign(socket, busy: true, update_progress: [update_step(:fetch, :running)])}
    end
  end

  @impl true
  def handle_event("restart", _params, socket) do
    {:noreply, restart_after_update(socket, "Reiniciando o servidor…")}
  end

  @impl true
  def handle_event("open_composer", _params, socket) do
    # Reopening keeps the draft as it is, so a proposal or a receipt is not
    # lost; the split is a button inside the composer.
    {:noreply, BoardNavigation.open_panel(socket, "composer")}
  end

  @impl true
  def handle_event("composer_change", params, socket) do
    text = params["text"] || socket.assigns.composer_text
    changed? = text != socket.assigns.composer_text

    selected = selected_from(params, socket)

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
     |> with_task_edits(params)
     |> with_private_fields(params)
     |> assign(
       composer_text: text,
       composer_title: edited_title(params, text, socket.assigns.composer_title),
       composer_answers: params["answers"] || socket.assigns.composer_answers
     )
     |> choose_executor(params["executor"])}
  end

  @impl true
  def handle_event("release_task", %{"id" => id, "confirm" => confirm}, socket) do
    repo = socket.assigns.repo

    with {number, ""} <- Integer.parse(to_string(id)),
         %Task{repository_id: repo_id} = task when repo_id == repo.id <- Board.task(number),
         params = %{task: task, repository: repo, client: GitHub.client()},
         :ok <- Actions.run(:release_task, params, ui(), confirm: confirm) do
      {:noreply,
       put_flash(socket, :info, gettext("Agent called on #%{number}.", number: task.number))}
    else
      _refused_or_failed ->
        {:noreply, put_flash(socket, :error, gettext("Could not call the agent on this task."))}
    end
  end

  @impl true
  def handle_event("composer_add_folder", params, socket) do
    private = socket.assigns.composer_private
    source = String.trim(params["private_folder"] || private.folder)

    private =
      case PrivateContext.check_folder(source) do
        {:ok, folder} ->
          %{
            private
            | folders: Enum.uniq_by(private.folders ++ [folder], & &1.path),
              folder: "",
              folder_error: nil
          }

        {:error, reason} ->
          %{private | folder: source, folder_error: reason}
      end

    {:noreply, assign(socket, composer_private: private)}
  end

  @impl true
  def handle_event("composer_remove_folder", %{"path" => path}, socket) do
    private = socket.assigns.composer_private
    folders = Enum.reject(private.folders, &(&1.path == path))
    {:noreply, assign(socket, composer_private: %{private | folders: folders})}
  end

  @impl true
  def handle_event("composer_remove_attachment", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachments, ref)}
  end

  @impl true
  # One click runs the whole split (repository digest, refine, proposal); a
  # second click splits the current words again.
  def handle_event("composer_split", _params, socket) do
    text = String.trim(socket.assigns.composer_text)

    cond do
      socket.assigns.composer_job ->
        {:noreply, socket}

      text == "" ->
        {:noreply, composer_error(socket, gettext("Write the request before splitting."))}

      true ->
        socket
        |> assign(composer_split: true, composer_selected: MapSet.new())
        |> start_split(text)
    end
  end

  @impl true
  def handle_event("composer_unsplit", _params, socket) do
    if socket.assigns.composer_job,
      do: {:noreply, socket},
      else:
        {:noreply,
         assign(socket,
           composer_split: false,
           composer_error: nil,
           composer_retry: nil,
           intake: nil,
           composer_selected: MapSet.new()
         )}
  end

  @impl true
  def handle_event("composer_submit", params, socket) do
    text = String.trim(params["text"] || socket.assigns.composer_text)

    socket =
      socket
      |> with_task_edits(params)
      |> with_private_fields(params)
      |> choose_executor(params["executor"])
      |> ensure_composer_routing()

    # The sentence the composer showed when the person pressed send.
    shown = composer_phrase(socket.assigns)

    socket =
      assign(socket, composer_answers: params["answers"] || socket.assigns.composer_answers)

    cond do
      # A second submit while the first is in flight: the job is the receipt.
      socket.assigns.composer_job ->
        {:noreply, socket}

      is_nil(socket.assigns.repo) ->
        {:noreply, composer_error(socket, gettext("Select a repository before submitting."))}

      attachments_pending?(socket) ->
        {:noreply,
         composer_error(socket, gettext("Wait for the files to finish or remove them."))}

      text == "" ->
        {:noreply, composer_error(socket, gettext("Write the request before sending."))}

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
       inspector_calls_total: 0,
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
        text = with_dictated(socket.assigns.composer_text, text)

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
         |> put_flash(
           :error,
           gettext("Could not list voices: %{reason}", reason: voice_reason(reason))
         )}
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
        {:noreply, put_flash(socket, :error, gettext("Choose a voice from the list"))}

      id == voice.id and voice.source == :saved ->
        {:noreply, socket}

      save_setting("voice", {id, name}) == :ok ->
        {:noreply,
         socket
         |> assign(voice: refreshed_voice(voice))
         |> put_flash(:info, gettext("Voice saved: %{name}", name: name || id))
         |> push_event("voice_play", %{
           url: speech_url(Phrases.voice_saved(voice.language), id, voice.language)
         })}

      true ->
        {:noreply, put_flash(socket, :error, gettext("Voice could not be saved"))}
    end
  end

  @impl true
  def handle_event("voice_preview", _params, socket) do
    id = socket.assigns.voice.id

    {:noreply,
     push_event(socket, "voice_play", %{
       url:
         speech_url(
           Phrases.preview(socket.assigns.voice.language),
           id,
           socket.assigns.voice.language
         )
     })}
  end

  @impl true
  def handle_event("voice_reset", _params, socket) do
    :ok = save_setting("voice", {"", nil})

    {:noreply,
     socket
     |> assign(voice: refreshed_voice(socket.assigns.voice))
     |> put_flash(:info, gettext("Voice reset to default"))}
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
       |> put_flash(:info, gettext("Model saved: %{model}", model: String.trim(model)))}
    else
      {:noreply, put_flash(socket, :error, gettext("Unknown speech model"))}
    end
  end

  @impl true
  def handle_event("voice_try", %{"phrase" => phrase}, socket) do
    cond do
      String.trim(phrase) == "" ->
        {:noreply, put_flash(socket, :error, gettext("Enter a phrase to hear"))}

      not ElevenLabs.valid_text?(phrase) ->
        {:noreply, put_flash(socket, :error, gettext("The phrase is too long for a request"))}

      true ->
        url = speech_url(phrase, socket.assigns.voice.id, socket.assigns.voice.language)
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

    Activity.record(:ui, :error, "event ignored: #{String.slice(to_string(event), 0, 60)}",
      reason: "fields received: [#{keys}]"
    )

    {:noreply, socket}
  end

  @impl true
  def handle_async({:ask_task, task_id, ref}, outcome, socket) do
    case Map.get(socket.assigns.ask_sending, task_id) do
      %{body: body, ref: ^ref} ->
        socket = assign(socket, ask_sending: Map.delete(socket.assigns.ask_sending, task_id))

        case outcome do
          {:ok, {:ok, _comment}} ->
            {:noreply, ask_succeeded(socket, task_id, body)}

          {:ok, {:error, {refusal, _phrase}}}
          when refusal in [:unconfirmed, :phrase_changed] ->
            {:noreply, ask_failed(socket, task_id, body, refused_text())}

          _ ->
            {:noreply,
             ask_failed(socket, task_id, body, gettext("The question did not reach GitHub"))}
        end

      _ ->
        {:noreply, socket}
    end
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
     |> put_flash(:error, gettext("Provisioning has not completed."))}
  end

  @impl true
  def handle_async(:agent_access, {:ok, fresh}, socket) do
    projects = AgentAccess.keep_last_good(socket.assigns.agent_access_projects, fresh)

    {:noreply,
     assign(socket, agent_access_projects: projects, agent_access: AgentAccess.summary(projects))}
  end

  # The badge keeps its last reading; the ticker tries again.
  def handle_async(:agent_access, {:exit, _reason}, socket), do: {:noreply, socket}

  def handle_async({:superagent_command, _id}, {:ok, {:ok, text}}, socket) do
    {:noreply, socket |> assign(:superagents, Superagents.list()) |> put_flash(:info, text)}
  end

  def handle_async({:superagent_command, _id}, {:ok, {:error, text}}, socket),
    do: {:noreply, put_flash(socket, :error, text)}

  def handle_async({:superagent_command, _id}, {:exit, _reason}, socket),
    do: {:noreply, put_flash(socket, :error, gettext("Superagent action did not complete."))}

  def handle_async({:superagent_scale, _id}, {:ok, {:ok, text}}, socket) do
    {:noreply, socket |> assign(:superagents, Superagents.list()) |> put_flash(:info, text)}
  end

  def handle_async({:superagent_scale, _id}, {:ok, {:error, text}}, socket),
    do: {:noreply, put_flash(socket, :error, text)}

  def handle_async({:superagent_scale, _id}, {:exit, _reason}, socket),
    do: {:noreply, put_flash(socket, :error, gettext("Unable to change the session limit."))}

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

  def handle_async(
        {:unblock_ai, id},
        {:ok, {:ok, %{json: %{"suggestions" => suggestions}}}},
        %{assigns: %{conversation: %Task{id: task_id}}} = socket
      )
      when is_list(suggestions) and id == task_id do
    suggestions = suggestions |> Enum.filter(&is_binary/1) |> Enum.take(3)
    {:noreply, assign(socket, unblock_ai: :idle, unblock_suggestions: suggestions)}
  end

  def handle_async(
        {:unblock_ai, id},
        _outcome,
        %{assigns: %{conversation: %Task{id: task_id}}} = socket
      )
      when id == task_id do
    {:noreply, assign(socket, unblock_ai: :error, unblock_suggestions: [])}
  end

  def handle_async({:unblock_ai, _id}, _outcome, socket), do: {:noreply, socket}

  # The answer of the shown repository's agent: the throughput tile takes it,
  # and the lanes only when the agent went up or down. Another repository's
  # answer is dropped by the last clause.
  def handle_async(
        :orchestrator,
        {:ok, {id, answer}},
        %{assigns: %{repo: %{id: id}, orchestrator: answer}} = socket
      ),
      do: {:noreply, socket}

  def handle_async(:orchestrator, {:ok, {id, answer}}, %{assigns: %{repo: %{id: id}}} = socket) do
    %{repo: repo, board: board, agent_snapshot: agent, freshness: freshness} = socket.assigns
    changed? = agent_status(answer) != agent_status(socket.assigns.orchestrator)
    socket = assign(socket, :orchestrator, answer)

    socket =
      if changed? do
        work = work_for(repo, board, agent, freshness, socket, socket.assigns.local_ci, answer)
        assign(socket, work: work, digest: work.digest)
      else
        socket
      end

    {:noreply, assign(socket, :flow, with_load_tile(socket.assigns.flow, answer))}
  end

  def handle_async(:orchestrator, _dropped, socket), do: {:noreply, socket}

  def handle_async(:version_check, {:ok, {:ok, _sha}}, socket) do
    {:noreply, assign(socket, version: Version.status())}
  end

  def handle_async(:version_check, _outcome, socket), do: {:noreply, socket}

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

  defp show_intake_result(socket, repo, text, %{spec: spec, tasks: tasks, status: status}) do
    socket
    |> assign(intake: %{spec: spec, tasks: tasks, status: status, text: text, repo_id: repo.id})
    |> refresh_ai()
  end

  # The model answers on another process: the question is already on GitHub,
  # and blocking the LiveView for it freezes the whole board.
  # The answer is shown and spoken to this viewer: the Task carries the
  # tab's language, which a new process does not inherit.
  defp ask_in_background(task, body) do
    parent = self()
    id = task.id
    language = Locale.language()

    Elixir.Task.start(fn ->
      Gettext.put_locale(AgentBoardWeb.Gettext, Locale.gettext_locale(language))
      send(parent, {:answer, id, answer(task, body, language)})
    end)
  end

  defp ask_failed(socket, task_id, body, message) do
    socket
    |> assign(
      ask_draft: Map.put(socket.assigns.ask_draft, task_id, body),
      ask_error: Map.put(socket.assigns.ask_error, task_id, message)
    )
    |> put_flash(:error, message)
    |> push_event("inspector:message-failed", %{task_id: task_id})
  end

  defp ask_succeeded(socket, task_id, body) do
    task = Board.task(task_id)
    ask_in_background(task, body)

    socket =
      if socket.assigns.conversation && socket.assigns.conversation.id == task_id do
        socket
        |> assign(conversation: task, comments: Board.comments(task))
        |> load_inspector()
      else
        socket
      end

    socket
    |> put_flash(:info, gettext("Question sent"))
    |> push_event("inspector:message-sent", %{task_id: task_id})
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
      # the voice speaks the interface language of this tab
      language: Locale.language(),
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

  defp default_checkout_path(name) do
    candidate = Path.expand("~/projects/#{name}")

    if File.dir?(candidate) and File.exists?(Path.join(candidate, ".git")),
      do: candidate,
      else: candidate
  end

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

  defp voice_reason(:not_configured), do: gettext("API key missing")
  defp voice_reason(:auth_expired), do: gettext("the key was rejected")
  defp voice_reason(:usage_limit), do: gettext("usage limit reached")
  defp voice_reason(:quota_exceeded), do: gettext("credits spent")
  defp voice_reason({:http, status}), do: "HTTP #{status}"
  defp voice_reason(reason), do: FailureText.text(reason)

  defp speech_url(text, voice_id, language), do: VoiceSpeech.url(text, voice_id, language)

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

  defp answer(task, question, language) do
    case AI.call(
           :answer_question,
           %{
             language: language,
             question: question,
             title: task.title,
             state: task.state,
             kind: task.kind
           },
           task_id: task.id
         ) do
      {:ok, %{json: %{"answer" => text}}} ->
        {:ok, text}

      {:ok, _} ->
        {:ok, gettext("The model answered, but not with text.")}

      {:error, :not_configured} ->
        {:error, gettext("AI is not configured.")}

      {:error, reason} ->
        {:error, gettext("The AI did not answer: %{reason}", reason: FailureText.text(reason))}
    end
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
            superagents={@superagents}
            access_waiting={@agent_access.count}
          />

          <main id="board-work" class="ab-main">
            <div class="ab-inbox-top">
              <BoardComponents.MessageHub.hub
                messages={@inbox.messages}
                alerts={@inbox.alerts}
                providers={@inbox.providers}
                seen={@message_seen}
                filter={@inbox_filter}
                notice={@inbox_notice}
              >
                <BoardComponents.PeakRate.mark
                  :if={@peak_rate}
                  rate={@peak_rate}
                  now={@peak_now}
                  offset={@tz_offset}
                />
              </BoardComponents.MessageHub.hub>
            </div>
            <div :if={@repo == nil} class="ab-empty">
              <h2>{gettext("No repositories being tracked.")}</h2>
              <p>
                {gettext(
                  "Open Settings → Repositories to track a repository. The board shows the agent's work, what awaits you, and what changed."
                )}
              </p>
              <button
                type="button"
                class="ab-btn ab-btn--primary"
                phx-click="show_panel"
                phx-value-panel="settings"
                data-panel-trigger
                aria-haspopup="dialog"
                aria-controls="panel-settings"
              >{gettext("Open Settings")}</button>
            </div>

            <.today_view
              :if={@view == "hoje"}
              today={@today}
              spend={@today_spend}
              daily_summary={@daily_summary}
              offset={@tz_offset}
              version={@version}
            />

            <.frozen_banner
              :if={@repo && @view != "hoje"}
              freshness={@freshness}
              tz_offset={@tz_offset}
            />

            <div :if={@repo && @view != "hoje"} class="ab-stage">
              <div class="ab-pane ab-pane--work">
                <header class="ab-top">
                  <details :if={@repo} id="mobile-nav" data-board-menu class="ab-mobilebar">
                    <summary>
                      <span class="ab-mobilebar__repo">{@repo.name}</span>
                      <.ico name="menu" />
                      <span class="ab-sr">{gettext("Repositories")}</span>
                    </summary>
                    <div class="ab-mobilebar__list">
                      <button
                        type="button"
                        class="ab-repo"
                        aria-current={to_string(@view == "hoje")}
                        phx-click="select"
                        phx-value-view="hoje"
                      >
                        <span class="ab-repo__name">{gettext("Today")}</span>
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
                        :if={@agent_access.count > 0}
                        id="mobile-panel-agent-access"
                        type="button"
                        class="ab-btn ab-btn--quiet ab-btn--sm"
                        phx-click="show_panel"
                        phx-value-panel="settings"
                        phx-value-section="projects"
                        data-panel-trigger
                        aria-haspopup="dialog"
                        aria-controls="panel-settings"
                      >
                        {ngettext(
                          "%{count} waiting for access",
                          "%{count} waiting for access",
                          @agent_access.count
                        )}
                      </button>
                      <button
                        id="mobile-panel-superagents"
                        type="button"
                        class="ab-btn ab-btn--quiet ab-btn--sm"
                        phx-click="show_panel"
                        phx-value-panel="settings"
                        phx-value-section="projects"
                        data-panel-trigger
                        aria-haspopup="dialog"
                        aria-controls="panel-settings"
                      >
                        <.ico name="grip" />{gettext("Superagents")}
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
                        <.ico name="keys" />{gettext("Shortcuts")}
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
                        <.ico name="log" />{gettext("Logs")}
                      </button>
                      <button
                        id="mobile-panel-voice"
                        type="button"
                        class="ab-btn ab-btn--quiet ab-btn--sm"
                        phx-click="show_panel"
                        phx-value-panel="voice"
                      >
                        <.ico name="mic" />{gettext("Voice conversation")}
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
                        <.ico name="cog" />{gettext("Settings")}
                      </button>
                    </div>
                  </details>
                  <div class="ab-top__repo">
                    <span class="ab-top__owner">{@repo.owner}/</span>
                    <h1>{@repo.name}</h1>
                  </div>
                  <.beacon freshness={@freshness} tz_offset={@tz_offset} />
                  <.version_badge version={@version} />
                  <span class="ab-top__spacer"></span>
                  <div id="board-tools" class="ab-top__actions" aria-label={gettext("Board actions")}>
                    <button
                      id="open-create"
                      type="button"
                      class="ab-btn ab-btn--primary"
                      phx-click="open_composer"
                      data-panel-trigger
                      aria-haspopup="dialog"
                      aria-controls="panel-composer"
                    >
                      <.ico name="plus" />{gettext("New request")}<.kbd key="N" />
                    </button>
                  </div>
                </header>

                <.summary digest={@digest} />

                <div
                  :if={@objectives != [] or @daily_summary}
                  class={["ab-context", @objectives == [] && "is-daily-only"]}
                >
                  <section
                    :if={@objectives != []}
                    id="objectives"
                    class="ab-objectives"
                    aria-label={gettext("Objectives")}
                  >
                    <article
                      :for={objective <- @objectives}
                      :if={not objective.done?}
                      class="ab-objective"
                    >
                      <div class="ab-objective__head">
                        <span class="ab-label">{gettext("Objective")}</span>
                        <b>{objective.title}</b>
                        <span class="ab-objective__count">
                          {gettext("%{merged} of %{total} tasks merged",
                            merged: objective.merged,
                            total: objective.total
                          )}
                        </span>
                      </div>
                      <p class="ab-meta">
                        {gettext("criterion: %{criterion}", criterion: objective.done_criterion)}
                      </p>
                      <div
                        class="ab-objective__bar"
                        role="progressbar"
                        aria-valuenow={objective.merged}
                        aria-valuemin="0"
                        aria-valuemax={objective.total}
                        aria-label={gettext("Progress of objective %{title}", title: objective.title)}
                      >
                        <span style={"width: #{progress(objective)}%"}></span>
                      </div>
                      <.objective_tree :if={objective.edges != []} objective={objective} repo={@repo} />
                    </article>

                    <details
                      :if={Enum.any?(@objectives, & &1.done?)}
                      class="ab-objective-done"
                    >
                      <summary>
                        {ngettext(
                          "%{count} completed objective",
                          "%{count} completed objectives",
                          Enum.count(@objectives, & &1.done?)
                        )}
                      </summary>
                      <ul class="ab-objective-done__list">
                        <li :for={objective <- @objectives} :if={objective.done?}>
                          <span class="ab-objective-done__title">{objective.title}</span>
                          <span class="ab-objective-done__count">
                            {gettext("%{merged} of %{total} ✓",
                              merged: objective.merged,
                              total: objective.total
                            )}
                          </span>
                        </li>
                      </ul>
                    </details>
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
                      <span>{gettext("Daily summary")}</span>
                      <span class="ab-meta">{gettext("from the board")}</span>
                    </summary>
                    <div class="ab-fold__body">
                      <.daily_summary entry={@daily_summary} tz_offset={@tz_offset} />
                    </div>
                  </details>
                </div>

                <div :if={empty?(@board)} class="ab-empty">
                  <h2>
                    {if @sync_snapshot.last_success,
                      do: gettext("Nothing has happened here yet."),
                      else: gettext("No data yet.")}
                  </h2>
                  <p>
                    {if @sync_snapshot.last_success,
                      do:
                        gettext(
                          "The agent watches this repository but has not received a task yet. Write or dictate the first request; it enters the queue and appears in Now when the agent picks it up."
                        ),
                      else:
                        gettext(
                          "Waiting for the first sync. When GitHub responds, the board will show tasks, merges, and what needs your attention."
                        )}
                  </p>
                  <button
                    type="button"
                    class="ab-btn ab-btn--primary"
                    phx-click="open_composer"
                    data-panel-trigger
                    aria-haspopup="dialog"
                    aria-controls="panel-composer"
                  >
                    <.ico name="plus" />{gettext("New request")}
                  </button>
                </div>

                <div :if={not empty?(@board)} class="ab-lanes">
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
                  <.queue_list
                    queue={@work.queue}
                    frozen={@freshness.frozen?}
                    frozen_at={@freshness.at}
                    tz_offset={@tz_offset}
                    selected={@conversation && @conversation.id}
                  />
                </div>
              </div>

              <%= if not empty?(@board) do %>
                <.merge_log
                  log={@work.log}
                  frozen={@freshness.frozen?}
                  has_history={@board.merged != []}
                />

                <details
                  :if={@flow}
                  id="fold-flow"
                  class="ab-fold ab-fold--flow"
                  data-mobile-fold
                  open
                  phx-hook="BoardFold"
                >
                  <summary class="ab-fold__summary">
                    <span>{gettext("Throughput")}</span>
                    <span class="ab-meta">{if @freshness.frozen?,
                      do:
                        gettext("per hour · frozen at %{time}",
                          time: Time.local_time(@flow.computed_at, @tz_offset)
                        ),
                      else:
                        gettext("per hour · calculated at %{time}",
                          time: Time.local_time(@flow.computed_at, @tz_offset)
                        )}</span>
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
              <% end %>
            </div>
          </main>

          <div
            :if={@repo && @view != "hoje"}
            class="ab-mobile-actions"
            aria-label={gettext("Board actions")}
          >
            <button
              type="button"
              class="ab-btn ab-btn--primary"
              phx-click="open_composer"
              data-panel-trigger
              aria-haspopup="dialog"
              aria-controls="panel-composer"
            >
              {gettext("New request")}
            </button>
            <button
              type="button"
              class="ab-btn ab-btn--icon"
              phx-click="show_panel"
              phx-value-panel="voice"
              aria-label={gettext("Voice conversation")}
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
            calls_total={@inspector_calls_total}
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
            ask_sending={@conversation && Map.get(@ask_sending, @conversation.id)}
            ask_draft={if @conversation, do: Map.get(@ask_draft, @conversation.id, ""), else: ""}
            ask_error={@conversation && Map.get(@ask_error, @conversation.id)}
            ai_status={@ai_status}
            unblock={@unblock}
            unblock_suggestions={@unblock_suggestions}
            unblock_ai={@unblock_ai}
            inspector_blockers={@inspector_blockers}
            blocker_open={@blocker_open}
            blocker_title={@blocker_title}
            blocker_body={@blocker_body}
            blocker_pending={@blocker_pending}
            agent_refused={
              MapSet.member?(
                @agent_access.refused,
                {@conversation.repository_id, @conversation.number}
              )
            }
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
          aria-label={gettext("Talk to Wispr")}
          hidden
        >
          <label for="voice-wispr-text" class="voice-wispr-label">{gettext("Talk to Wispr")}</label>
          <input
            id="voice-wispr-text"
            type="text"
            autocomplete="off"
            placeholder={gettext("Hold the Wispr key and speak...")}
          />
          <span class="voice-wispr-hint">
            {gettext("Auto-send when text arrives · Enter to send · Esc to cancel")}
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
            aria-label={gettext("Close alert")}
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
            uploads={@uploads}
            attachments_ready={length(@composer_attachments)}
            private={@composer_private}
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
          title={gettext("Shortcuts")}
          active={@panel == "shortcuts"}
          flash={@flash}
        >
          <.shortcuts />
        </BoardComponents.Panel.shell>

        <BoardComponents.Panel.shell
          name="history"
          title={gettext("History")}
          active={@panel == "history"}
          flash={@flash}
        >
          <BoardComponents.Concluded.history
            :if={@repo}
            list={@history_list}
            query={@history_query}
            ended={@ended}
            offset={@tz_offset}
          >
            <.live_component
              module={BoardComponents.Archive}
              id="merged-column-history"
              items={@board.merged}
              has_more={@board.merged_has_more}
              local_ci={@local_ci}
            />
          </BoardComponents.Concluded.history>
        </BoardComponents.Panel.shell>

        <BoardComponents.Panel.shell
          name="settings"
          title={gettext("Settings")}
          active={@panel == "settings"}
          flash={@flash}
        >
          <.live_component
            module={BoardComponents.SettingsMenu}
            id="board-settings-panel"
            repo={@repo}
            repos={@repos}
            version={@version}
            codex_quota={@codex_quota}
            busy={@busy}
            progress={@update_progress}
            voice={@voice}
            dispatch_paused={@dispatch_paused}
            active={@panel == "settings"}
            section={@settings_section}
            superagents={@superagents}
            access_waiting={@agent_access.count}
            access_projects={@agent_access_projects}
            tickets={@agent_snapshot.tickets}
            ai_calls={@ai_calls}
            ai_status={@ai_status}
            events={@events}
            provisioning={@provisioning}
            tz_offset={@tz_offset}
            project_pending={@project_pending}
            board_locale={@board_locale}
          />
        </BoardComponents.Panel.shell>

        <BoardComponents.Panel.shell
          name="voice"
          title={gettext("Voice conversation")}
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
              <%= if @voice.input == "text" do %>
                <.ico name="keys" />{gettext("Write")}<.kbd key={gettext("Space ×2")} />
              <% else %>
                <.ico name="mic" />{gettext("Speak")}<.kbd key={gettext("Space ×2")} />
              <% end %>
            </button>
            <span class="ab-meta">
              {if @voice.input == "text",
                do:
                  gettext(
                    "Write in the field above; the agent replies and waits for your confirmation before acting."
                  ),
                else:
                  gettext(
                    "Speak and stop: the agent replies and waits for your confirmation before acting."
                  )}
            </span>
          </div>
          <BoardComponents.VoiceCommandList.list
            open={@voice_commands_open}
            language={@voice.language}
          />
          <BoardComponents.VoiceActivityFeed.feed events={@voice_activity} tz_offset={@tz_offset} />
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
    |> assign(busy: true, update_progress: [update_step(:restart, :running)])
    |> push_event("restart", %{})
    |> put_flash(:info, message)
  end

  # One entry per stage the version panel renders while the update runs.
  defp update_step(id, state) do
    %{id: id, state: state, label: update_label(id)}
  end

  # A new running stage closes the previous one; an update to the same stage
  # replaces it, so the list is exactly the pipeline the person watches.
  defp push_update_step(progress, id, state) do
    progress =
      Enum.map(progress, fn step ->
        if step.state == :running, do: %{step | state: :done}, else: step
      end)

    case Enum.split_with(progress, &(&1.id == id)) do
      {[], rest} -> rest ++ [update_step(id, state)]
      {[step], rest} -> rest ++ [%{step | state: state}]
    end
  end

  defp update_label(:fetch), do: gettext("Fetching main")
  defp update_label(:deps), do: gettext("Preparing dependencies")
  defp update_label(:compile), do: gettext("Compiling the new build")
  defp update_label(:assets), do: gettext("Building assets")
  defp update_label(:migrate), do: gettext("Applying migrations")
  defp update_label(:ready), do: gettext("Build ready")
  defp update_label(:restart), do: gettext("Restarting the board")

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
      %{status: :ready, text: ^text, tasks: tasks, spec: spec} when tasks != [] ->
        selected = selected_from(params, socket)

        if chosen_complete?(tasks, selected) do
          requests =
            socket.assigns.repo
            |> split_requests(text, spec, tasks, selected)
            |> for_executor(socket.assigns)

          start_enqueue(socket, requests, shown)
        else
          {:noreply,
           composer_error(
             socket,
             gettext("Every chosen task needs a title, a description and a criterion.")
           )}
        end

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
           gettext("Answer the questions or edit the request before splitting again.")
         )}

      answers ->
        answered = text <> "\n\n" <> gettext("Answers:") <> "\n" <> answers

        socket
        |> assign(composer_text: answered, composer_answers: "", intake: nil)
        |> start_split(answered)
    end
  end

  # The owner's edits live with the proposal until the send. A proposal that
  # new words invalidated has no tasks to edit.
  defp with_task_edits(%{assigns: %{intake: %{tasks: tasks} = intake}} = socket, %{
         "task_edits" => edits
       })
       when is_map(edits),
       do: assign(socket, :intake, %{intake | tasks: Intake.edit_tasks(tasks, edits)})

  defp with_task_edits(socket, _params), do: socket

  defp chosen_complete?(tasks, selected) do
    tasks
    |> Enum.with_index()
    |> Enum.all?(fn {task, index} ->
      not MapSet.member?(selected, index) or Intake.complete?(task)
    end)
  end

  defp selected_from(params, socket) do
    case params do
      %{"tasks" => values} when is_list(values) -> selected_indices(values)
      _ -> socket.assigns.composer_selected
    end
  end

  # The form always sends a blank `tasks[]`, so no box checked is an empty
  # choice and not the absence of one.
  defp selected_indices(values) do
    MapSet.new(for value <- values, {index, ""} <- [Integer.parse(value)], do: index)
  end

  # A dependency names its request by key: the positions change when the
  # owner leaves a task out. The key reads the title the model proposed, so
  # an edited task is still the same request on a retry.
  defp split_requests(repo, text, spec, tasks, selected) do
    keys = split_keys(repo, text, tasks)

    tasks
    |> Enum.with_index()
    |> Enum.filter(fn {_task, index} -> MapSet.member?(selected, index) end)
    |> Enum.map(fn {task, index} ->
      chosen = Intake.dependencies_within(tasks, index, selected)

      %{
        title: task.title,
        body: IssueBody.render(task, spec) <> "\n\n@sallaumen-agent",
        key: Enum.at(keys, index),
        work_type: task.kind,
        size: task.size,
        language: spec["language"],
        depends_on: Enum.map(chosen, &Enum.at(keys, &1))
      }
    end)
  end

  # The same title twice is two tasks: a repeat counts its occurrence, so it
  # is neither the first task's receipt nor the target of its dependents.
  defp split_keys(repo, text, tasks) do
    {keys, _seen} =
      Enum.map_reduce(tasks, %{}, fn task, seen ->
        base = Board.request_key(repo, "split", [text, task.source_title])
        repeat = Map.get(seen, base, 0)

        key =
          if repeat == 0,
            do: base,
            else: Board.request_key(repo, "split", [text, task.source_title, "#{repeat}"])

        {key, Map.put(seen, base, repeat + 1)}
      end)

    keys
  end

  defp start_single(socket, text, title, shown) do
    case single_requests(socket.assigns.repo, text, title) do
      [] ->
        {:noreply,
         composer_error(socket, gettext("The first line becomes the title; write something."))}

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
  # The ended tasks are read when History shows them, for the search in the
  # URL: one page, never on a board render.
  defp load_panel(
         %{assigns: %{panel: "history", history_list: "tasks", repo: %{id: id}}} = socket
       ) do
    size = Board.ended_page_size()
    rows = Board.ended_page(id, socket.assigns.history_query, nil, size + 1)
    assign(socket, :ended, %{items: Enum.take(rows, size), has_more: length(rows) > size})
  end

  defp load_panel(socket), do: socket

  defp load_composer_routing(%{assigns: %{panel: "composer", repo: %{id: id} = repo}} = socket) do
    if connected?(socket) and socket.assigns.composer_routing_for != id do
      # The signals carry the reason an executor is unavailable, as a sentence:
      # the task that reads them has no locale of its own.
      locale = Gettext.get_locale(AgentBoardWeb.Gettext)

      socket
      |> assign(composer_routing_for: id)
      |> start_async({:composer_routing, id}, fn ->
        Gettext.put_locale(AgentBoardWeb.Gettext, locale)
        Signals.read_for(repo)
      end)
    else
      socket
    end
  end

  defp load_composer_routing(socket), do: socket

  # A submit before the background read answered reads the signals now.
  defp ensure_composer_routing(%{assigns: %{composer_routing: nil, repo: %{} = repo}} = socket) do
    socket
    |> assign(composer_routing_for: repo.id)
    |> put_composer_routing(Signals.read_for(repo))
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
            %{status: :ready, text: ^text, tasks: [_ | _] = tasks, spec: spec} ->
              split_requests(repo, text, spec, tasks, selected)

            %{status: :no_tasks} ->
              single_requests(repo, text, title)

            _ ->
              []
          end
      end

    requests = for_executor(requests, %{composer_executor: executor, composer_routing: nil})

    if requests == [],
      do: nil,
      else:
        Actions.phrase(:create_tasks, %{repository: repo, requests: requests}, Locale.language())
  end

  @doc false
  def retry_phrase(%{} = repo, {:enqueue, [_ | _] = requests}),
    do: Actions.phrase(:create_tasks, %{repository: repo, requests: requests}, Locale.language())

  def retry_phrase(_repo, _retry), do: nil

  defp start_split(socket, text) do
    cond do
      is_nil(socket.assigns.repo) ->
        {:noreply, composer_error(socket, gettext("Select a repository before splitting."))}

      socket.assigns.ai_status == :not_configured ->
        {:noreply,
         composer_error(
           socket,
           gettext("AI is not configured. Splitting is unavailable; send as a single request.")
         )}

      true ->
        job = composer_job(:split, text, 1)
        repo = socket.assigns.repo

        {:noreply,
         socket
         |> assign(composer_job: job, composer_error: nil, composer_retry: nil, intake: nil)
         |> start_async({:composer, job.ref}, fn ->
           {:split, text, Intake.run(text, repository_digest(repo))}
         end)}
    end
  end

  defp repository_digest(repo) do
    if GitHub.configured?(), do: RepoDigest.read(repo, GitHub.client())
  end

  defp start_enqueue(socket, [], _shown),
    do: {:noreply, composer_error(socket, gettext("Choose at least one task."))}

  defp start_enqueue(socket, requests, shown) do
    socket = take_attachments(socket)
    repo = socket.assigns.repo
    client = GitHub.client()
    job = composer_job(:enqueue, requests, length(requests))
    attachments = socket.assigns.composer_attachments

    action =
      %{repository: repo, requests: requests, client: client, attachments: attachments}
      |> then(fn action ->
        case private_payload(socket) do
          nil -> action
          private -> Map.put(action, :private, private)
        end
      end)
      |> then(fn action ->
        if socket.assigns.composer_split and length(requests) > 1 do
          Map.put(action, :objective, split_objective(socket, repo))
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

  # Read once, at the send, and kept until the receipt: a retry sends the same
  # files, and an unfinished one never gets this far.
  defp take_attachments(socket) do
    private = socket.assigns.composer_private

    new =
      consume_uploaded_entries(socket, :attachments, fn %{path: path}, entry ->
        # `path` is the temporary file LiveView made for this upload; the
        # client's name for it only ever reaches `Attachments.safe_name/1`.
        {:ok, content} = :file.read_file(path)
        meta = Map.get(private.meta, entry.ref, %{private: false, role: "reference"})
        {:ok, Map.merge(meta, %{name: entry.client_name, content: content})}
      end)

    {kept, shared} = Enum.split_with(new, & &1.private)
    shared = Enum.map(shared, &%{name: role_prefix(&1.role) <> &1.name, content: &1.content})

    assign(socket,
      composer_attachments: socket.assigns.composer_attachments ++ shared,
      composer_private: %{private | files: private.files ++ kept, meta: %{}}
    )
  end

  defp role_prefix("before"), do: "before--"
  defp role_prefix("after"), do: "after--"
  defp role_prefix(_reference), do: ""

  # The owner's private note, the folder being typed and each file's place
  # (this machine or GitHub) and role, as the form last had them.
  defp with_private_fields(socket, params) do
    private = socket.assigns.composer_private

    meta =
      for {ref, fields} <- Map.get(params, "attachment_meta", %{}), is_map(fields), into: %{} do
        {ref,
         %{
           private: fields["private"] == "true",
           role: if(fields["role"] in ~w(before after), do: fields["role"], else: "reference")
         }}
      end

    assign(socket,
      composer_private: %{
        private
        | note: Map.get(params, "private_note", private.note),
          folder: Map.get(params, "private_folder", private.folder),
          meta: Map.merge(private.meta, meta)
      }
    )
  end

  # Only what holds something: an empty context makes no folder and no line.
  defp private_payload(socket) do
    private = socket.assigns.composer_private

    if String.trim(private.note) == "" and private.files == [] and private.folders == [] do
      nil
    else
      %{
        dir: PrivateContext.request_dir(socket.assigns.repo, socket.assigns.composer_text),
        note: private.note,
        files: private.files,
        folders: Enum.map(private.folders, & &1.path)
      }
    end
  end

  defp attachments_pending?(socket),
    do: Enum.any?(socket.assigns.uploads.attachments.entries, &(not &1.done?))

  defp cancel_attachments(socket) do
    Enum.reduce(socket.assigns.uploads.attachments.entries, socket, fn entry, socket ->
      cancel_upload(socket, :attachments, entry.ref)
    end)
  end

  # The request behind the group is kept with it; the key makes a retry find
  # the objective of its first attempt.
  defp split_objective(socket, repo) do
    text = socket.assigns.composer_text
    intake = socket.assigns.intake

    %{
      title: objective_title(text),
      done_criterion: gettext("All tasks merged."),
      request_key: Board.request_key(repo, "objective", [text]),
      request_text: text,
      spec: intake && intake.spec
    }
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
      "" -> gettext("Request objective")
      title -> title
    end
  end

  defp composer_job(kind, payload, total) do
    ref = System.unique_integer([:positive])
    Process.send_after(self(), {:composer_timeout, ref}, composer_timeout())
    %{ref: ref, kind: kind, payload: payload, total: total}
  end

  defp composer_timeout, do: Application.get_env(:agent_board, :composer_timeout_ms, 120_000)

  defp finish_composer_job(socket, _job, {:ok, {:split, text, {:ok, result}}}) do
    socket
    |> assign(composer_job: nil)
    |> show_intake_result(socket.assigns.repo, text, result)
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
      gettext(
        "Nothing was created: the request changed before sending. Check the phrase and send again."
      )
    )
  end

  defp finish_composer_job(socket, _job, {:ok, {:enqueue, requests, results}}) do
    items = Enum.map(results, fn {request, result} -> receipt_item(request, result) end)
    failed = Enum.count(items, &match?({:error, _}, &1.outcome))

    socket
    |> assign(
      composer_job: nil,
      composer_receipt: %{items: items},
      composer_retry: if(failed > 0, do: {:enqueue, requests}),
      composer_attachments: if(failed > 0, do: socket.assigns.composer_attachments, else: []),
      composer_private: if(failed > 0, do: socket.assigns.composer_private, else: @empty_private)
    )
    |> load(socket.assigns.repo)
    |> flash_receipt(items, failed)
  end

  defp finish_composer_job(socket, %{kind: kind, payload: payload}, {:exit, reason}) do
    socket
    |> assign(composer_job: nil)
    |> composer_error(
      gettext("%{job} stopped unexpectedly: %{reason} Nothing else was done.",
        job: job_name(kind),
        reason: FailureText.text(reason)
      ),
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
        put_flash(socket, :info, gettext("Request #%{number} queued", number: number))

      [%{outcome: :existing, task: %{number: number}}] when is_integer(number) ->
        put_flash(
          socket,
          :info,
          gettext("This request was already queued: #%{number}", number: number)
        )

      _ ->
        created = Enum.count(items, &(&1.outcome == :created))

        put_flash(
          socket,
          :info,
          ngettext("%{count} task queued", "%{count} tasks queued", created)
        )
    end
  end

  defp flash_receipt(socket, items, failed) when failed == length(items),
    do: put_flash(socket, :error, gettext("Nothing was queued. Check the receipt and try again."))

  defp flash_receipt(socket, items, failed) do
    done = length(items) - failed

    put_flash(
      socket,
      :error,
      gettext("Created %{done} of %{total}. Check the receipt and retry the remaining tasks.",
        done: done,
        total: length(items)
      )
    )
  end

  defp job_name(:split), do: gettext("The split")
  defp job_name(:enqueue), do: gettext("Issue creation")

  defp split_failure(:malformed_output),
    do: gettext("AI returned an unexpected format. Nothing was created.")

  defp split_failure(:not_configured),
    do: gettext("AI is not configured. Send as a single request.")

  defp split_failure(:auth_expired), do: gettext("The AI key expired or was rejected.")
  defp split_failure(:usage_limit), do: gettext("AI is out of quota now.")
  defp split_failure(:budget_exhausted), do: gettext("The board's AI budget is exhausted.")
  defp split_failure(:no_provider), do: gettext("No AI provider configured.")

  defp split_failure(:audit_unavailable),
    do: gettext("The AI call could not be recorded; nothing was created.")

  defp split_failure({:http, status}), do: gettext("AI returned HTTP %{status}.", status: status)

  defp split_failure(reason),
    do: gettext("AI did not respond: ") <> FailureText.text(reason)

  defp refused_text,
    do:
      gettext("Nothing happened: the action changed after confirmation. Check and confirm again.")

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
    |> cancel_attachments()
    |> assign(
      composer_text: "",
      composer_title: nil,
      composer_split: false,
      composer_selected: MapSet.new(),
      composer_error: nil,
      composer_retry: nil,
      composer_receipt: nil,
      composer_answers: "",
      composer_attachments: [],
      composer_private: @empty_private,
      intake: nil,
      composer_executor_touched: false,
      composer_executor:
        socket.assigns.composer_routing &&
          (socket.assigns.composer_routing.suggestion.executor || Executors.default())
    )
  end
end
