defmodule AgentBoardWeb.BoardLive do
  @moduledoc "The board: the columns, the repositories and the tasks, live."
  use AgentBoardWeb, :live_view

  import Ecto.Query, warn: false

  alias AgentBoard.{
    AgentState,
    AgentWorktree,
    AI,
    Announcer,
    Board,
    ElevenLabs,
    GitHub,
    Intake,
    LocalCI,
    Repo,
    Settings,
    Time,
    Titles,
    Voice,
    Work
  }

  alias AgentBoard.Board.Task
  alias AgentBoard.Sync.{Freshness, Worker}
  alias AgentBoard.System.{Updater, Version}

  import AgentBoardWeb.BoardComponents.Composer, only: [composer: 1]
  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1, kbd: 1]
  import AgentBoardWeb.BoardComponents.FreshnessBeacon, only: [beacon: 1]
  import AgentBoardWeb.BoardComponents.FrozenBanner, only: [frozen_banner: 1]
  import AgentBoardWeb.BoardComponents.Inspector, only: [inspector: 1]
  import AgentBoardWeb.BoardComponents.MergeLog, only: [merge_log: 1]
  import AgentBoardWeb.BoardComponents.NeedsYou, only: [needs_you: 1]
  import AgentBoardWeb.BoardComponents.NowLane, only: [now_lane: 1]
  import AgentBoardWeb.BoardComponents.QueueList, only: [queue_list: 1]
  import AgentBoardWeb.BoardComponents.Shortcuts, only: [shortcuts: 1]
  import AgentBoardWeb.BoardComponents.Summary, only: [summary: 1]

  alias AgentBoardWeb.{
    BoardComponents,
    BoardNavigation,
    VoiceAnswer,
    VoiceCommands,
    VoiceMutations
  }

  alias AgentBoardWeb.BoardComponents.VoicePresence

  @voice_key "elevenlabs_voice_id"
  @tts_model_key "elevenlabs_tts_model"
  @speak_events_key "elevenlabs_speak_events"
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
        digest: nil,
        needs_expanded: false,
        queue_limit: 8,
        queue_filter: :all,
        repo: nil,
        board: empty(),
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
        conversation: nil,
        comments: [],
        inspector_tab: "conversa",
        inspector_activity: [],
        inspector_calls: [],
        inspector_pr: nil,
        inspector_ci: nil,
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
        ai_calls: [],
        ai_status: AI.status(),
        version: Version.status(),
        busy: false,
        voice: current_voice(),
        voice_draft: "",
        voice_result: nil,
        voice_action: nil,
        voice_generation: 0,
        spoken_text: nil,
        spoken_at: 0
      )

    repo =
      case params["repo"] do
        nil -> default_repo(repos)
        slug -> Board.repository_by_slug(slug) || default_repo(repos)
      end

    {:ok, load(socket, repo)}
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

  defp work_for(repo, board, agent, freshness, socket, local_ci) do
    now = DateTime.utc_now()
    tz_offset = socket.assigns.tz_offset
    last_visit = socket.assigns.last_visit
    frozen_at = if freshness.frozen?, do: freshness.at, else: nil
    tickets = tickets_by_number(agent.tickets)

    %{
      running: Enum.map(board.running, &running_card(&1, tickets, now, frozen_at)),
      needs:
        Work.needs(repo, board,
          now: now,
          last_visit: last_visit,
          tz_offset: tz_offset,
          tickets_by_number: tickets,
          local_ci: local_ci
        ),
      queue:
        Work.queue(repo, board,
          now: now,
          last_visit: last_visit,
          filter: socket.assigns.queue_filter,
          limit: socket.assigns.queue_limit
        ),
      log: Work.merge_log(repo, now: now, tz_offset: tz_offset, local_ci: local_ci),
      digest:
        if freshness.state == :unknown do
          nil
        else
          Work.digest(repo, board,
            now: now,
            last_visit: last_visit,
            tz_offset: tz_offset,
            frozen_at: frozen_at,
            frozen: freshness.frozen?
          )
        end
    }
  end

  defp running_card(task, tickets, now, frozen_at) do
    ticket = Map.get(tickets, task.number)
    started_at = task.started_at

    %{
      id: task.id,
      number: task.number,
      title: task.title,
      step: AgentWorktree.step(ticket),
      elapsed: started_at && Time.age_seconds(started_at, frozen_at || now),
      agent: nil,
      phases: []
    }
  end

  defp tickets_by_number(tickets) do
    for ticket <- tickets,
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
          inspector_pr: nil,
          inspector_ci: nil
        )

      task ->
        pr = Board.task_pull_request(task, socket.assigns.comments)

        ci = pr && Map.get(socket.assigns.local_ci, pr.number)

        assign(socket,
          inspector_activity: Board.task_activity(task, pr),
          inspector_calls: AI.recent_for_task(task.id),
          inspector_pr: pr,
          inspector_ci: ci,
          inspector_tab: socket.assigns.inspector_tab || "conversa"
        )
    end
  end

  defp refresh_inspector_after_act(socket, task_id) do
    case socket.assigns.conversation do
      %Task{id: ^task_id} ->
        task = Repo.get(Task, task_id) |> Repo.preload(:repository)

        socket
        |> assign(conversation: task, comments: Board.comments(task))
        |> load_inspector()

      _ ->
        socket
    end
  end

  defp load(socket, nil) do
    socket =
      if socket.assigns.repo do
        socket
        |> invalidate_voice_answer()
        |> assign(voice_draft: "", voice_result: nil, voice_action: nil)
      else
        socket
      end

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
      repo_overview: Board.repo_overview(),
      agent_snapshot: %{ok: false, at: nil, tickets: [], error: :unknown},
      work: empty_work(),
      digest: nil,
      live: connected?(socket),
      ai_calls: [],
      ai_status: AI.status()
    )
  end

  defp load(socket, repo) do
    # load/2 runs on mount and again on handle_params: subscribing twice would
    # deliver every broadcast twice (and keep listening to the old repo).
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
            voice_draft: "",
            voice_result: nil,
            voice_action: nil,
            voice_generation: socket.assigns.voice_generation + 1,
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

        local_ci = LocalCI.by_pr(repo, agent.tickets)
        work = work_for(repo, board, agent, freshness, socket, local_ci)

        assign(socket,
          repo: repo,
          local_ci: local_ci,
          board: board,
          resume: nil,
          events: Board.events(repo),
          sync_event: snapshot.last_attempt,
          sync_snapshot: snapshot,
          freshness: freshness,
          repo_overview: Board.repo_overview(),
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
          repo_overview: Board.repo_overview(),
          agent_snapshot: %{ok: false, at: nil, tickets: [], error: :unknown},
          work: empty_work(),
          digest: nil,
          live: connected?(socket),
          ai_calls: [],
          ai_status: AI.status()
        )
    end
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
  def handle_info({:answer, task_id, text}, socket) do
    current = socket.assigns.conversation && socket.assigns.conversation.id

    if current == task_id do
      {:noreply,
       socket
       |> put_flash(:info, text)
       |> refresh_ai()
       |> speak(Announcer.speakable_answer(text))}
    else
      {:noreply, socket}
    end
  end

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
    updater().restart()
    System.stop()
    {:noreply, socket}
  end

  def handle_info(:board_updated, socket) do
    old_board = socket.assigns.board
    old_sync = socket.assigns.sync_event

    socket =
      socket
      |> load(socket.assigns.repo)
      |> refresh_conversation()
      |> load_inspector()
      |> announce(old_board, old_sync)

    socket =
      if old_board != socket.assigns.board or old_sync != socket.assigns.sync_event do
        invalidate_pending_voice_answer(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  defp refresh_conversation(%{assigns: %{conversation: nil}} = socket), do: socket

  defp refresh_conversation(socket) do
    case Repo.get(Task, socket.assigns.conversation.id) do
      nil -> assign(socket, conversation: nil, comments: [])
      task -> assign(socket, conversation: task, comments: Board.comments(task))
    end
  end

  defp refresh_ai(socket), do: assign(socket, ai_calls: AI.recent(5), ai_status: AI.status())

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      if socket.assigns.panel == "voice" and params["panel"] != "voice" do
        socket |> invalidate_voice_answer() |> assign(voice_result: nil)
      else
        socket
      end

    repo =
      case params["repo"] do
        nil -> socket.assigns.repo
        slug -> Board.repository_by_slug(slug) || socket.assigns.repo
      end

    socket = socket |> load(repo) |> BoardNavigation.apply_params(params) |> load_inspector()

    socket =
      if socket.assigns.panel == "voice", do: socket, else: assign(socket, :voice_action, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("sync_now", _params, socket) do
    case Oban.insert(Worker.new(%{})) do
      {:ok, _job} ->
        {:noreply, put_flash(socket, :info, "Sincronização pedida.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível pedir a sincronização.")}
    end
  end

  @impl true
  def handle_event("board_reconnected", params, socket) do
    old_board = socket.assigns.board
    old_snapshot = socket.assigns.sync_snapshot
    socket = load(socket, socket.assigns.repo)

    {changes, at} =
      case parse_last_visit(params["since"]) do
        %DateTime{} = since ->
          {Board.changes_since(socket.assigns.repo, since), since}

        nil ->
          {Board.change_count(old_board, socket.assigns.board),
           old_snapshot.last_success && old_snapshot.last_success.inserted_at}
      end

    since = if at, do: Time.local_time(at, socket.assigns.tz_offset), else: "antes da queda"

    text =
      case changes do
        0 -> "Reconectado. Nada mudou desde #{since}."
        1 -> "Reconectado. 1 mudança desde #{since}."
        n -> "Reconectado. #{n} mudanças desde #{since}."
      end

    {:noreply, assign(socket, toast: %{text: text, action: nil, changes: changes})}
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
  def handle_event("show_changes", _params, socket) do
    {:noreply, assign(socket, toast: nil, highlight_changes: true)}
  end

  @impl true
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
    case Board.add_repository(owner, name) do
      {:ok, _} ->
        repos = Board.list_repositories()
        repo = Enum.find(repos, &(&1.owner == owner and &1.name == name))
        {:noreply, socket |> assign(:repos, repos) |> load(repo)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not track #{owner}/#{name}")}
    end
  end

  @impl true
  def handle_event("act", %{"id" => id, "action" => action}, socket) do
    {task_id, _} = Integer.parse(id)
    task = Repo.get(Task, task_id) |> Repo.preload(:repository)

    result =
      case {action, task} do
        {"stop", %Task{}} -> Board.stop_task(task, GitHub.client())
        {"archive", %Task{}} -> Board.archive_task(task)
        {"resume", %Task{}} -> Board.resume_task(task)
        _ -> {:error, :not_found}
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> load(socket.assigns.repo)
         |> refresh_inspector_after_act(task_id)
         |> put_flash(:info, "Task updated")
         |> speak(Voice.task_summary(task.title, action))}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not update the task")}
    end
  end

  @impl true
  def handle_event("open", %{"id" => id} = params, socket) do
    {:noreply, BoardNavigation.open_task(socket, id, params["tab"])}
  end

  @impl true
  def handle_event("inspector_tab", %{"tab" => tab}, socket) do
    tab = if tab in ~w(conversa atividade chamadas pr), do: tab, else: "conversa"
    {:noreply, assign(socket, :inspector_tab, tab)}
  end

  @impl true
  def handle_event("show_panel", %{"panel" => panel}, socket) do
    {:noreply, BoardNavigation.open_panel(socket, panel)}
  end

  @impl true
  def handle_event("voice_command", %{"mode" => "intake", "text" => text}, socket)
      when is_binary(text) do
    {:noreply, prepare_intake(socket, text)}
  end

  @impl true
  def handle_event("voice_command", %{"text" => text}, socket) when is_binary(text) do
    draft = String.trim(text)

    socket =
      socket
      |> invalidate_voice_answer()
      |> assign(voice_draft: draft, voice_action: nil)

    case VoiceMutations.prepare(draft, socket.assigns.repo) do
      {:ok, intent} ->
        {:noreply, assign(socket, voice_action: intent, voice_result: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :voice_result, voice_action_result(:error, reason))}

      :not_mutation ->
        resolve_voice_read(socket, draft)
    end
  end

  @impl true
  def handle_event("voice_ask", _params, socket) do
    case current_voice_ask(socket) do
      {:ok, task, question} ->
        socket = assign(socket, :voice_result, voice_action_result(:loading, "Sending question…"))
        voice_ask(socket, task, question)

      {:error, reason} ->
        {:noreply, assign(socket, :voice_result, voice_action_result(:error, reason))}
    end
  end

  @impl true
  def handle_event("voice_command", _params, socket) do
    result = %{
      kind: :error,
      text: "Command text is missing. Review the draft and try again.",
      as_of: nil
    }

    {:noreply,
     socket
     |> invalidate_voice_answer()
     |> assign(voice_result: result, voice_action: nil)}
  end

  @impl true
  def handle_event("voice_cancel_action", _params, socket) do
    {:noreply, assign(socket, voice_action: nil, voice_result: nil)}
  end

  @impl true
  def handle_event("voice_confirm_action", _params, socket) do
    case {socket.assigns.panel, socket.assigns.voice_action} do
      {"voice", %{action: action} = intent} ->
        socket = assign(socket, :voice_action, nil)

        case VoiceMutations.current_task(intent, socket.assigns.repo) do
          {:ok, task} ->
            confirm_voice_action(socket, task, action)

          {:error, :changed} ->
            {:noreply,
             assign(
               socket,
               :voice_result,
               voice_action_result(
                 :error,
                 "Task or repository changed. Review the board and try again."
               )
             )}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("dismiss_panel", _params, socket) do
    {:noreply,
     socket
     |> assign(:voice_action, nil)
     |> push_patch(to: BoardNavigation.path(socket.assigns.repo), replace: true)}
  end

  @impl true
  def handle_event("ask", %{"body" => body}, socket) do
    case socket.assigns.conversation do
      nil ->
        {:noreply, put_flash(socket, :error, "Open a task first")}

      task ->
        case Board.ask(task, body, GitHub.client()) do
          {:ok, _} ->
            ask_in_background(task, body)

            {:noreply,
             assign(socket,
               conversation: Repo.get(Task, task.id) |> Repo.preload(:repository),
               comments: Board.comments(task)
             )
             |> load_inspector()
             |> put_flash(:info, "Question sent")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "The question did not reach GitHub")}
        end
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
    case updater().pull() do
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
  def handle_event("voice_prepare_intake", %{"text" => text}, socket) when is_binary(text) do
    {:noreply, prepare_intake(socket, text)}
  end

  def handle_event("voice_prepare_intake", _params, socket) do
    {:noreply, put_flash(socket, :error, "Add a request before opening Split.")}
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
     assign(socket,
       composer_text: text,
       composer_title: title_from_params(params, text, socket.assigns.composer_title),
       composer_answers: params["answers"] || socket.assigns.composer_answers
     )}
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
        submit_split(socket, text, params)

      true ->
        start_single(socket, text, title_from_params(params, text, socket.assigns.composer_title))
    end
  end

  @impl true
  def handle_event("composer_retry", _params, socket) do
    socket = assign(socket, composer_error: nil, composer_receipt: nil)

    case {socket.assigns.composer_job, socket.assigns.composer_retry} do
      {nil, {:split, text}} -> start_split(socket, text)
      {nil, {:enqueue, requests}} -> start_enqueue(socket, requests)
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("composer_cancel", _params, socket) do
    {:noreply, cancel_composer_job(socket)}
  end

  @impl true
  def handle_event("composer_single", _params, socket) do
    text = String.trim(socket.assigns.composer_text)
    socket = assign(socket, composer_split: false, intake: nil, composer_selected: MapSet.new())

    if text == "",
      do: {:noreply, socket},
      else: start_single(socket, text, socket.assigns.composer_title)
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
        {:noreply, put_flash(socket, :error, "Repository changed. Review the request again.")}

      socket.assigns.ai_status == :not_configured ->
        {:noreply, put_flash(socket, :error, "AI is not configured. Split is unavailable.")}

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
  def handle_event("create_from_intake", %{"index" => index}, socket) do
    with {:ok, position} <- intake_index(index),
         %{repo: repo} when not is_nil(repo) <- socket.assigns,
         %{repo_id: repo_id, status: :ready} = intake <- socket.assigns.intake,
         true <- repo_id == repo.id,
         %{text: request_text, repo_id: ^repo_id} <- socket.assigns.intake_draft,
         true <- request_text == intake.text,
         task when not is_nil(task) <- Enum.at(intake.tasks, position),
         {:ok, _created} <-
           Board.create_task(repo, task.title, intake_body(task), GitHub.client()) do
      {:noreply, put_flash(socket, :info, "Task created: #{task.title}")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not create the task")}
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    socket =
      if socket.assigns.panel == "voice" do
        socket |> invalidate_voice_answer() |> assign(voice_result: nil, voice_action: nil)
      else
        socket
      end

    {:noreply,
     socket
     |> settle_composer()
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
    text = Voice.spoken(socket.assigns.board)

    if socket.assigns.voice.configured do
      # The agent's ElevenLabs voice speaks the status; the browser speech
      # engine is the fallback when no key is configured.
      url = speech_url(text, socket.assigns.voice.id)
      {:noreply, push_event(socket, "voice_play", %{url: url})}
    else
      {:noreply, push_event(socket, "speak", %{text: text})}
    end
  end

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

      true ->
        {:noreply,
         socket
         |> invalidate_voice_answer()
         |> assign(voice_draft: text, voice_result: nil, voice_action: nil)
         |> BoardNavigation.open_panel("voice")}
    end
  end

  @impl true
  def handle_event("voice_draft_changed", %{"text" => text}, socket) when is_binary(text) do
    draft = String.slice(text, 0, 2000)

    if draft == socket.assigns.voice_draft do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> invalidate_voice_answer()
       |> assign(voice_draft: draft, voice_result: nil, voice_action: nil)}
    end
  end

  @impl true
  def handle_event("voice_browse", _params, socket) do
    socket = assign(socket, voice: %{socket.assigns.voice | loading: true})

    case ElevenLabs.voices() do
      {:ok, voices} ->
        pick =
          if Enum.any?(voices, &(&1.id == socket.assigns.voice.id)), do: socket.assigns.voice.id

        {:noreply,
         assign(socket,
           voice: %{socket.assigns.voice | voices: voices, loading: false, pick: pick}
         )}

      {:error, reason} ->
        # A failed refresh keeps the list it already has: the board never
        # erases its last good state.
        {:noreply,
         socket
         |> assign(voice: %{socket.assigns.voice | loading: false})
         |> put_flash(:error, "Could not list voices: #{voice_reason(reason)}")}
    end
  end

  @impl true
  def handle_event("voice_pick", %{"voice" => id}, socket) do
    # A phx-change value is client input: only a voice-shaped id sticks.
    pick = if ElevenLabs.valid_voice_id?(id), do: String.trim(id)
    {:noreply, assign(socket, voice: %{socket.assigns.voice | pick: pick})}
  end

  @impl true
  def handle_event("voice_preview", _params, socket) do
    id = socket.assigns.voice.pick || socket.assigns.voice.id

    {:noreply,
     push_event(socket, "voice_play", %{
       url: speech_url("Hello! This is how your agent will sound.", id)
     })}
  end

  @impl true
  def handle_event("voice_save", _params, socket) do
    id = socket.assigns.voice.pick || socket.assigns.voice.id
    name = voice_name(socket.assigns.voice.voices, id)

    cond do
      not ElevenLabs.valid_voice_id?(id) ->
        {:noreply, put_flash(socket, :error, "Pick a voice from the list first")}

      Settings.put(@voice_key, id) == :ok ->
        {:noreply,
         socket
         |> assign(voice: %{current_voice() | pick: id, voices: socket.assigns.voice.voices})
         |> put_flash(:info, "Voice saved: #{name || id}")
         |> push_event("voice_play", %{url: speech_url("Voice selected.", id)})}

      true ->
        {:noreply, put_flash(socket, :error, "Could not save the voice")}
    end
  end

  @impl true
  def handle_event("voice_reset", _params, socket) do
    :ok = Settings.put(@voice_key, "")

    {:noreply,
     socket
     |> assign(voice: %{current_voice() | pick: ElevenLabs.voice_id()})
     |> put_flash(:info, "Voice back to the default")}
  end

  @impl true
  def handle_event("voice_model", %{"model" => model}, socket) do
    if ElevenLabs.valid_tts_model?(String.trim(model)) do
      :ok = Settings.put(@tts_model_key, model)

      {:noreply,
       socket
       |> assign(
         voice: %{
           socket.assigns.voice
           | model: ElevenLabs.tts_model(),
             model_source: ElevenLabs.tts_source()
         }
       )
       |> put_flash(:info, "Model saved: #{String.trim(model)}")}
    else
      {:noreply, put_flash(socket, :error, "Unknown TTS model")}
    end
  end

  @impl true
  def handle_event("voice_try", %{"phrase" => phrase}, socket) do
    cond do
      String.trim(phrase) == "" ->
        {:noreply, put_flash(socket, :error, "Type a phrase to hear it")}

      not ElevenLabs.valid_text?(phrase) ->
        {:noreply, put_flash(socket, :error, "The phrase is too long for one request")}

      true ->
        url = speech_url(phrase, socket.assigns.voice.id)
        {:noreply, push_event(socket, "voice_play", %{url: url})}
    end
  end

  @impl true
  def handle_event("voice_announce", %{"speak_events" => value}, socket) do
    :ok = Settings.put(@speak_events_key, if(value == "true", do: "", else: "0"))

    {:noreply,
     assign(socket, voice: %{socket.assigns.voice | speak_events: ElevenLabs.speak_events?()})}
  end

  defp current_voice_ask(socket) do
    case {socket.assigns.panel, socket.assigns.voice_result, socket.assigns.repo,
          socket.assigns.conversation} do
      {"voice",
       %{
         kind: :ask,
         question: question,
         task_id: task_id,
         task_updated_at: updated_at,
         repository_id: repository_id
       }, %{id: repository_id}, %Task{id: task_id}}
      when is_binary(question) and question != "" ->
        task = Repo.get(Task, task_id)

        if valid_voice_ask_task?(task, repository_id, updated_at) &&
             VoiceCommands.parse(socket.assigns.voice_draft) == {:ask, question},
           do: {:ok, task, question},
           else: {:error, "Task or question changed. Review the draft again before sending."}

      _ ->
        {:error, "Review the question and task before sending."}
    end
  end

  defp valid_voice_ask_task?(%Task{} = task, repository_id, updated_at) do
    task.repository_id == repository_id && task.updated_at == updated_at &&
      task.kind == "issue" && task.state in ~w(queued running ready blocked) &&
      !task.stopped && !task.archived
  end

  defp valid_voice_ask_task?(_task, _repository_id, _updated_at), do: false

  # The ask is a write: the first submit only classifies the draft, the
  # confirmed "Ask the agent" posts the question to the open task and the
  # answer comes back spoken.
  defp voice_ask(socket, task, question) do
    case Board.ask(task, question, GitHub.client()) do
      {:ok, _} ->
        ask_in_background(task, question)

        {:noreply,
         socket
         |> assign(
           voice_result: voice_action_result(:success, "Question sent: #{question}"),
           conversation: Repo.get(Task, task.id) |> Repo.preload(:repository),
           comments: Board.comments(task)
         )
         |> put_flash(:info, "Question sent")}

      {:error, _} ->
        {:noreply,
         assign(
           socket,
           :voice_result,
           voice_action_result(:error, "The question did not reach GitHub.")
         )}
    end
  end

  defp resolve_voice_read(socket, draft) do
    intent = VoiceCommands.parse(draft)
    unanswered_question? = match?({:ask, _}, intent) and is_nil(socket.assigns.conversation)

    if VoiceAnswer.archive_history_query?(draft) or
         (VoiceAnswer.read_query?(draft) and (intent == :unknown or unanswered_question?)) do
      start_voice_answer(socket, draft)
    else
      resolve_deterministic_voice_command(socket, draft)
    end
  end

  defp resolve_deterministic_voice_command(socket, draft) do
    %{result: result, path: path} = VoiceCommands.resolve(draft, socket.assigns)
    socket = assign(socket, :voice_result, result)

    case path do
      nil ->
        {:noreply, socket}

      path ->
        {:noreply, socket |> put_flash(:info, result.text) |> push_patch(to: path, replace: true)}
    end
  end

  @impl true
  def handle_async({:composer, ref}, outcome, socket) do
    case socket.assigns.composer_job do
      %{ref: ^ref} = job -> {:noreply, finish_composer_job(socket, job, outcome)}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_async({:voice_answer, generation, repo_id, draft}, outcome, socket) do
    if current_voice_answer?(socket, generation, repo_id, draft) do
      result =
        case outcome do
          {:ok, {:ok, answer}} ->
            %{
              kind: if(answer.engine == :board, do: :board_answer, else: :ai_answer),
              text: answer.text,
              as_of: answer.as_of,
              source: answer.source,
              sync_status: answer.sync_status
            }

          {:ok, {:error, reason}} ->
            voice_answer_error(reason)

          {:exit, _reason} ->
            voice_answer_error(:unavailable)
        end

      {:noreply, socket |> assign(voice_result: result) |> refresh_ai()}
    else
      {:noreply, socket}
    end
  end

  defp start_voice_answer(%{assigns: %{repo: nil}} = socket, _draft) do
    result = voice_answer_error(:no_repository)
    {:noreply, assign(socket, voice_result: result)}
  end

  defp start_voice_answer(socket, draft) do
    generation = socket.assigns.voice_generation
    repo_id = socket.assigns.repo.id
    snapshot = Map.take(socket.assigns, [:repo, :board, :sync_event])
    name = {:voice_answer, generation, repo_id, draft}

    socket =
      assign(socket,
        voice_result: %{
          kind: :loading,
          text: "Checking saved board data…",
          as_of: nil
        }
      )

    {:noreply, start_async(socket, name, fn -> VoiceAnswer.answer(snapshot, draft) end)}
  end

  defp current_voice_answer?(socket, generation, repo_id, draft) do
    current_repo_id = socket.assigns.repo && socket.assigns.repo.id

    socket.assigns.panel == "voice" and socket.assigns.voice_generation == generation and
      current_repo_id == repo_id and socket.assigns.voice_draft == draft
  end

  defp invalidate_voice_answer(socket),
    do: assign(socket, voice_generation: socket.assigns.voice_generation + 1)

  defp invalidate_pending_voice_answer(%{assigns: %{voice_result: %{kind: :loading}}} = socket) do
    socket
    |> invalidate_voice_answer()
    |> assign(
      voice_result:
        voice_answer_error_result(
          "Board data changed while the AI was answering. Ask again for an updated answer."
        )
    )
  end

  defp invalidate_pending_voice_answer(socket), do: socket

  defp voice_answer_error(:no_repository),
    do: voice_answer_error_result("Choose a tracked repository before asking the AI.")

  defp voice_answer_error(:budget_exhausted),
    do:
      voice_answer_error_result("The AI budget is exhausted. The saved board is still available.")

  defp voice_answer_error(:question_too_long),
    do: voice_answer_error_result("Keep the question under 1,000 characters and try again.")

  defp voice_answer_error(:no_provider),
    do:
      voice_answer_error_result(
        "No AI provider is configured. Read-only board commands still work."
      )

  defp voice_answer_error(:usage_limit),
    do: voice_answer_error_result("The AI provider is at its usage limit. Try again later.")

  defp voice_answer_error(_reason),
    do: voice_answer_error_result("The AI could not answer. Your command draft is still here.")

  defp voice_answer_error_result(text), do: %{kind: :error, text: text, as_of: nil}

  defp prepare_intake(socket, text) do
    case {socket.assigns.repo, String.trim(text)} do
      {nil, _} ->
        put_flash(socket, :error, "Select a repository before preparing a request.")

      {_, ""} ->
        put_flash(socket, :error, "Add a request before opening Split.")

      {repo, draft} ->
        socket
        |> assign(
          intake: nil,
          intake_draft: %{text: draft, repo_id: repo.id, source: :voice},
          voice_draft: draft
        )
        |> BoardNavigation.open_panel("intake")
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
      source: ElevenLabs.voice_source(),
      configured: ElevenLabs.configured?(),
      voices: nil,
      loading: false,
      pick: nil,
      model: ElevenLabs.tts_model(),
      model_source: ElevenLabs.tts_source(),
      models: ElevenLabs.tts_models(),
      speak_events: ElevenLabs.speak_events?()
    }
  end

  defp voice_name(nil, _id), do: nil
  defp voice_name(voices, id), do: Enum.find_value(voices, fn v -> if v.id == id, do: v.name end)

  # The agent speaks what changed, once per change: the poller already
  # broadcasts only on new hashes, and the same utterance is not repeated
  # within a short window.
  defp announce(socket, old_board, old_sync) do
    texts =
      Announcer.board_changes(
        old_board,
        socket.assigns.board,
        old_sync,
        socket.assigns.sync_event
      )

    Enum.reduce(texts, socket, &speak(&2, &1))
  end

  defp confirm_voice_action(socket, task, action) do
    result =
      case action do
        :stop -> Board.stop_task(task, GitHub.client())
        :archive -> Board.archive_task(task)
      end

    label = if action == :stop, do: "Stopped", else: "Archived"
    outcome = if match?({:ok, _}, result), do: "completed", else: "failed"

    Board.log_event(task.repository_id, "voice_action", "##{task.number}", %{
      "action" => Atom.to_string(action),
      "result" => outcome
    })

    Board.broadcast(task.repository_id)

    socket = load(socket, socket.assigns.repo)

    case result do
      {:ok, _} ->
        {:noreply,
         assign(
           socket,
           :voice_result,
           voice_action_result(:success, "#{label} task ##{task.number}.")
         )}

      _ ->
        {:noreply,
         assign(
           socket,
           :voice_result,
           voice_action_result(
             :error,
             "Could not #{Atom.to_string(action)} task ##{task.number}. Check Activity and try again."
           )
         )}
    end
  end

  defp voice_action_result(kind, text), do: %{kind: kind, text: text, as_of: nil}

  # Speaks through the agent's ElevenLabs voice when the key is configured
  # and the automatic speech is on; a repeated utterance within a short
  # window is skipped, so a burst never doubles the audio.
  defp speak(%{assigns: %{voice: %{configured: true, speak_events: true}}} = socket, text)
       when is_binary(text) do
    now = System.monotonic_time(:millisecond)

    if socket.assigns.spoken_text == text and now - socket.assigns.spoken_at < 30_000 do
      socket
    else
      socket
      |> assign(spoken_text: text, spoken_at: now)
      |> push_event("voice_play", %{url: speech_url(text, socket.assigns.voice.id)})
    end
  end

  defp speak(socket, _text), do: socket

  defp voice_reason(:not_configured), do: "no API key"
  defp voice_reason(:auth_expired), do: "the key was rejected"
  defp voice_reason(:usage_limit), do: "usage limit reached"
  defp voice_reason({:http, status}), do: "HTTP #{status}"
  defp voice_reason(reason), do: inspect(reason)

  defp speech_url(text, voice_id) do
    "/api/voice/speech?text=" <>
      URI.encode_www_form(text) <> "&voice=" <> URI.encode_www_form(voice_id)
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
      {:ok, %{json: %{"answer" => text}}} -> text
      {:ok, _} -> "The model answered, but not with text."
      {:error, :not_configured} -> "The AI is not configured."
      {:error, reason} -> "The AI did not answer: #{inspect(reason)}"
    end
  end

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
            overview={@repo_overview}
            live={@freshness.live?}
            version={@version}
            busy={@busy}
            voice={@voice}
          />

          <main id="board-work" class="ab-main">
            <details :if={@repo} class="ab-mobilebar">
              <summary><.ico name="menu" />Repositórios</summary>
              <div class="ab-mobilebar__list">
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
              </div>
            </details>

            <div :if={@repo == nil} class="ab-empty">
              <h2>Nenhum repositório acompanhado.</h2>
              <p>
                Abra Configurações → Repositórios para acompanhar um repositório. O board mostra o
                trabalho do agente, o que espera por você e o que mudou.
              </p>
            </div>

            <header :if={@repo} class="ab-top">
              <div class="ab-top__repo">
                <span class="ab-top__owner">{@repo.owner}/</span>
                <h1>{@repo.name}</h1>
              </div>
              <.beacon freshness={@freshness} />
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

            <.summary :if={@repo} digest={@digest} />

            <.frozen_banner :if={@repo} freshness={@freshness} />

            <div :if={@repo && empty?(@board)} class="ab-empty">
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

            <div :if={@repo && not empty?(@board)} class="ab-cols">
              <div class="ab-col">
                <.now_lane
                  running={@work.running}
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
                />
                <.queue_list queue={@work.queue} frozen={@freshness.frozen?} />
              </div>
              <div class="ab-col">
                <.merge_log
                  log={@work.log}
                  frozen={@freshness.frozen?}
                  has_history={@board.merged != []}
                />
              </div>
            </div>
          </main>

          <.inspector
            :if={@conversation}
            task={@conversation}
            comments={@comments}
            tab={@inspector_tab}
            activity={@inspector_activity}
            calls={@inspector_calls}
            pr={@inspector_pr}
            ci={@inspector_ci}
            tz_offset={@tz_offset}
            live={@freshness.live?}
          />
        </div>

        <VoicePresence.stage id="voice-presence-board" />
        <div
          id="voice-command-shortcut"
          phx-hook="VoiceCommand"
          data-configured={to_string(@voice.configured)}
          hidden
        />

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
          name="voice"
          title="Comando de voz"
          active={@panel == "voice"}
          flash={@flash}
        >
          <BoardComponents.VoiceCommand.draft
            draft={@voice_draft}
            result={@voice_result}
            action={@voice_action}
          />
        </BoardComponents.Panel.shell>
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

  defp updater, do: Application.get_env(:agent_board, :updater, Updater)

  # -- the composer lifecycle ---------------------------------------------------
  #
  # One job at a time, keyed by a ref: a late or cancelled result finds no job
  # with its ref and changes nothing. The durable records are the ai_calls
  # rows (the split) and the tasks with their request_key (the enqueue); the
  # receipt is read from those tasks, so a reload shows the same thing.

  defp composer_error(socket, text, retry \\ nil),
    do: assign(socket, composer_error: text, composer_retry: retry)

  defp title_from_params(%{"title" => title}, text, _current) do
    title = String.trim(title)
    if title == "" or title == Titles.from_request(text), do: nil, else: title
  end

  defp title_from_params(_params, _text, current), do: current

  defp submit_split(socket, text, params) do
    case socket.assigns.intake do
      %{status: :ready, text: ^text, tasks: tasks} when tasks != [] ->
        start_enqueue(socket, split_requests(socket, text, tasks, selected_from(params, socket)))

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

  defp split_requests(socket, text, tasks, selected) do
    repo = socket.assigns.repo

    tasks
    |> Enum.with_index()
    |> Enum.filter(fn {_task, index} -> MapSet.member?(selected, index) end)
    |> Enum.map(fn {task, _index} ->
      %{
        title: task.title,
        body: intake_body(task) <> "\n\n@sallaumen-agent",
        key: Board.request_key(repo, "split", [text, task.title])
      }
    end)
  end

  defp start_single(socket, text, title) do
    repo = socket.assigns.repo
    title = title || Titles.from_request(text)

    if title == "" do
      {:noreply, composer_error(socket, "A primeira linha vira o título; escreva algo.")}
    else
      body = text <> "\n\n@sallaumen-agent"

      start_enqueue(socket, [
        %{title: title, body: body, key: Board.request_key(repo, "single", [title, body])}
      ])
    end
  end

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

  defp start_enqueue(socket, []),
    do: {:noreply, composer_error(socket, "Escolha ao menos uma tarefa.")}

  defp start_enqueue(socket, requests) do
    repo = socket.assigns.repo
    client = GitHub.client()
    job = composer_job(:enqueue, requests, length(requests))

    {:noreply,
     socket
     |> assign(
       composer_job: job,
       composer_error: nil,
       composer_retry: nil,
       composer_receipt: nil
     )
     |> start_async({:composer, job.ref}, fn ->
       {:enqueue, requests, Enum.map(requests, &{&1, Board.create_request(repo, &1, client)})}
     end)}
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
      intake: nil
    )
  end
end
