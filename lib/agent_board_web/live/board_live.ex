defmodule AgentBoardWeb.BoardLive do
  @moduledoc "The board: the columns, the repositories and the tasks, live."
  use AgentBoardWeb, :live_view

  import Ecto.Query, warn: false

  alias AgentBoard.{AI, Announcer, Board, ElevenLabs, GitHub, Intake, Repo, Settings, Voice}
  alias AgentBoard.Board.Task
  alias AgentBoard.System.{Updater, Version}

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
    resume = if connected?(socket), do: get_connect_params(socket)["board_resume"]

    socket =
      assign(socket,
        repos: repos,
        repo: nil,
        board: empty(),
        resume: resume,
        events: [],
        sync_event: nil,
        live: connected?(socket),
        panel: nil,
        conversation: nil,
        comments: [],
        intake: nil,
        intake_draft: nil,
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
            voice_draft: "",
            voice_result: nil,
            voice_action: nil,
            voice_generation: socket.assigns.voice_generation + 1
          ),
        else: socket

    {merged_limit, task_limits} = pagination_limits(socket, repo)

    case Board.board("#{repo.owner}/#{repo.name}", merged_limit, task_limits) do
      {:ok, board} ->
        assign(socket,
          repo: repo,
          board: board,
          resume: nil,
          events: Board.events(repo),
          sync_event: Board.latest_sync(repo),
          ai_calls: AI.recent(5),
          ai_status: AI.status(),
          live: connected?(socket)
        )

      _ ->
        assign(socket,
          repo: nil,
          board: empty(),
          resume: nil,
          events: [],
          sync_event: nil,
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

  def handle_info(:board_updated, socket) do
    old_board = socket.assigns.board
    old_sync = socket.assigns.sync_event

    socket =
      socket
      |> load(socket.assigns.repo)
      |> refresh_conversation()
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

    socket = socket |> load(repo) |> BoardNavigation.apply_params(params)

    socket =
      if socket.assigns.panel == "voice", do: socket, else: assign(socket, :voice_action, nil)

    {:noreply, socket}
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
  def handle_event("create", %{"title" => title, "body" => body}, socket) do
    case socket.assigns.repo do
      nil ->
        {:noreply, put_flash(socket, :error, "Track a repository first")}

      repo ->
        text = String.trim(body) <> "\n\n@sallaumen-agent"

        case Board.create_task(repo, title, text, GitHub.client()) do
          {:ok, _} ->
            {:noreply,
             socket
             |> load(repo)
             |> put_flash(:info, "Task created")
             |> assign(:panel, nil)
             |> push_event("panel_close", %{})
             |> speak(Voice.task_summary(title, "created"))}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, "Could not create the task. Check Activity and try again.")}
        end
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
         |> put_flash(:info, "Task updated")
         |> speak(Voice.task_summary(task.title, action))}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not update the task")}
    end
  end

  @impl true
  def handle_event("open", %{"id" => id}, socket) do
    {:noreply, BoardNavigation.open_task(socket, id)}
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
        {:noreply, put_flash(socket, :error, "Could not reach main: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("update", _params, socket) do
    case Updater.pull() do
      {:ok, sha} ->
        {:noreply,
         socket
         |> assign(version: Version.status(), busy: true)
         |> put_flash(:info, "Updated to #{sha}; restarting")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Update failed: #{inspect(reason)}")}
    end
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
     |> assign(panel: nil, conversation: nil, comments: [])
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

    if text == "" do
      {:noreply, socket}
    else
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

    if VoiceAnswer.read_query?(draft) and (intent == :unknown or unanswered_question?) do
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
  def handle_async({:voice_answer, generation, repo_id, draft}, outcome, socket) do
    if current_voice_answer?(socket, generation, repo_id, draft) do
      result =
        case outcome do
          {:ok, {:ok, answer}} ->
            %{
              kind: :ai_answer,
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
          text: "Preparing an AI answer from saved board data…",
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
    case AI.call(:answer_question, %{
           question: question,
           title: task.title,
           state: task.state,
           kind: task.kind
         }) do
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
        class="agent-board min-h-screen bg-base-100 text-base-content"
      >
        <.live_component
          module={BoardComponents.Header}
          id="board-header"
          repos={@repos}
          repo={@repo}
          live={@live}
          sync_event={@sync_event}
          last_activity={List.first(@events)}
          version={@version}
          busy={@busy}
          voice={@voice}
        />
        <VoicePresence.stage id="voice-presence-board" />
        <div
          id="voice-command-shortcut"
          phx-hook="VoiceCommand"
          data-configured={to_string(@voice.configured)}
          hidden
        />

        <div
          :if={@repo == nil}
          class="flex flex-col items-center gap-3 border-b border-base-content/10 px-5 py-20 text-center"
        >
          <p class="text-sm text-base-content">No repository tracked yet.</p>
          <p class="max-w-md text-[12px] leading-relaxed text-base-content/75">
            Open Settings → Repositories to track one. The board syncs its issues and pull requests, shows
            the agent's active work and recent merges, and lets you create and ask.
          </p>
        </div>

        <main :if={@repo} id="board-work" class="board-work">
          <div class="active-lanes grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4">
            <%= for {title, key} <- [
              {"Running", :running},
              {"Ready", :ready},
              {"Blocked", :blocked},
              {"Queued", :queued}
            ] do %>
              <.live_component
                module={BoardComponents.Column}
                id={"column-#{key}"}
                title={title}
                state={key}
                items={Map.get(@board, key)}
                total={Map.fetch!(@board.task_counts, key)}
                has_more={Map.fetch!(@board.task_has_more, key)}
                history_shortcut={
                  key == :running and @board.merged != [] and
                    Enum.all?(Map.values(@board.task_counts), &(&1 == 0))
                }
              />
            <% end %>
          </div>
          <.live_component
            module={BoardComponents.Archive}
            id="merged-column"
            items={@board.merged}
            has_more={@board.merged_has_more}
          />
        </main>

        <BoardComponents.Panel.shell
          name="conversation"
          title="Task conversation"
          active={@panel == "conversation"}
          flash={@flash}
        >
          <.live_component
            :if={@conversation}
            module={BoardComponents.Conversation}
            id="conversation"
            conversation={@conversation}
            comments={@comments}
          />
        </BoardComponents.Panel.shell>

        <BoardComponents.Panel.shell
          name="activity"
          title="Activity"
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
          title="Split a request"
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

        <BoardComponents.Panel.shell name="ai" title="AI calls" active={@panel == "ai"} flash={@flash}>
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
          title="Voice command"
          active={@panel == "voice"}
          flash={@flash}
        >
          <BoardComponents.VoiceCommand.draft
            draft={@voice_draft}
            result={@voice_result}
            action={@voice_action}
          />
        </BoardComponents.Panel.shell>

        <BoardComponents.Panel.shell
          name="create"
          title="New task"
          active={@panel == "create"}
          flash={@flash}
        >
          <.live_component
            :if={@repo}
            module={BoardComponents.CreateTask}
            id="create"
          />
        </BoardComponents.Panel.shell>
      </div>
    </Layouts.app>
    """
  end
end
