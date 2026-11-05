defmodule AgentBoardWeb.BoardLive do
  @moduledoc "The board: the columns, the repositories and the tasks, live."
  use AgentBoardWeb, :live_view

  import Ecto.Query, warn: false

  alias AgentBoard.{AI, Board, GitHub, Intake, Repo, Voice}
  alias AgentBoard.Board.Task
  alias AgentBoard.System.{Updater, Version}
  alias AgentBoardWeb.{BoardComponents, BoardNavigation}
  alias AgentBoardWeb.Components.SystemPanel

  @impl true
  def mount(params, _session, socket) do
    repos = Board.list_repositories()

    socket =
      assign(socket,
        repos: repos,
        repo: nil,
        board: empty(),
        events: [],
        sync_event: nil,
        live: connected?(socket),
        panel: nil,
        conversation: nil,
        comments: [],
        intake: nil,
        ai_calls: [],
        ai_status: AI.status(),
        version: Version.status(),
        busy: false
      )

    repo =
      case params["repo"] do
        nil -> default_repo(repos)
        slug -> Board.repository_by_slug(slug) || default_repo(repos)
      end

    {:ok, load(socket, repo)}
  end

  defp empty, do: %{running: [], ready: [], blocked: [], merged: [], queued: []}

  # The board opens on the project the agent is actually working on; the
  # first active repository is the fallback.
  defp default_repo(repos) do
    Enum.find(repos, &(&1.name == "o_colmex")) || List.first(repos)
  end

  defp load(socket, nil) do
    assign(socket,
      repo: nil,
      board: empty(),
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
        do: assign(socket, conversation: nil, comments: [], intake: nil),
        else: socket

    case Board.board("#{repo.owner}/#{repo.name}") do
      {:ok, board} ->
        assign(socket,
          repo: repo,
          board: board,
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
          events: [],
          sync_event: nil,
          live: connected?(socket),
          ai_calls: [],
          ai_status: AI.status()
        )
    end
  end

  @impl true
  def handle_info(:board_updated, socket) do
    {:noreply, socket |> load(socket.assigns.repo) |> refresh_conversation()}
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
    repo =
      case params["repo"] do
        nil -> socket.assigns.repo
        slug -> Board.repository_by_slug(slug) || socket.assigns.repo
      end

    {:noreply, socket |> load(repo) |> BoardNavigation.apply_params(params)}
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
            {:noreply, socket |> load(repo) |> put_flash(:info, "Task created")}

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
        {:noreply, socket |> load(socket.assigns.repo) |> put_flash(:info, "Task updated")}

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
  def handle_event("dismiss_panel", _params, socket) do
    {:noreply, push_patch(socket, to: BoardNavigation.path(socket.assigns.repo), replace: true)}
  end

  @impl true
  def handle_event("ask", %{"body" => body}, socket) do
    case socket.assigns.conversation do
      nil ->
        {:noreply, put_flash(socket, :error, "Open a task first")}

      task ->
        case Board.ask(task, body, GitHub.client()) do
          {:ok, _} ->
            {:noreply,
             assign(socket,
               conversation: Repo.get(Task, task.id) |> Repo.preload(:repository),
               comments: Board.comments(task)
             )
             |> put_flash(:info, "Question sent. " <> answer(task, body))
             |> refresh_ai()}

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
  def handle_event("intake", _params, %{assigns: %{ai_status: :not_configured}} = socket) do
    {:noreply, put_flash(socket, :error, "AI is not configured. Split is unavailable.")}
  end

  def handle_event("intake", %{"text" => text}, socket) do
    case Intake.run(text) do
      {:ok, %{spec: spec, tasks: tasks}} ->
        {:noreply,
         socket |> assign(intake: %{spec: spec, tasks: tasks, text: text}) |> refresh_ai()}

      {:error, reason} ->
        {:noreply,
         socket |> put_flash(:error, "The AI did not answer: #{inspect(reason)}") |> refresh_ai()}
    end
  end

  @impl true
  def handle_event("create_from_intake", %{"index" => index}, socket) do
    with %{repo: repo} when not is_nil(repo) <- socket.assigns,
         %{} = intake <- socket.assigns.intake,
         task when not is_nil(task) <- Enum.at(intake.tasks, String.to_integer(index)),
         {:ok, _created} <-
           Board.create_task(repo, task.title, intake_body(task), GitHub.client()) do
      {:noreply, put_flash(socket, :info, "Task created: #{task.title}")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not create the task")}
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    {:noreply,
     socket
     |> assign(panel: nil, conversation: nil, comments: [])
     |> push_event("panel_close", %{})}
  end

  @impl true
  def handle_event("speak", _params, socket) do
    {:noreply, push_event(socket, "speak", %{text: Voice.summary(socket.assigns.board)})}
  end

  @impl true
  def handle_event("dictate", _params, socket) do
    {:noreply, push_event(socket, "dictate", %{})}
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
        class="agent-board min-h-screen bg-base-100 text-base-content font-mono"
      >
        <.live_component
          module={BoardComponents.Header}
          id="board-header"
          repos={@repos}
          repo={@repo}
          live={@live}
          sync_event={@sync_event}
          last_activity={List.first(@events)}
        />

        <div
          :if={@repo == nil}
          class="flex flex-col items-center gap-3 border-b border-base-content/10 px-5 py-20 text-center"
        >
          <p class="text-sm text-base-content">No repository tracked yet.</p>
          <p class="max-w-md text-[12px] leading-relaxed text-base-content/75">
            Track one in the header. The board syncs its issues and pull requests, shows
            the agent's active work and recent merges, and lets you create and ask.
          </p>
        </div>

        <SystemPanel.version_panel version={@version} busy={@busy} />

        <nav :if={@repo} id="board-tools" aria-label="Board tools" class="board-tools">
          <button
            :for={
              {label, panel, icon} <- [
                {"Activity", "activity", "hero-clock"},
                {"Split a request", "intake", "hero-scissors"},
                {"AI calls", "ai", "hero-cpu-chip"}
              ]
            }
            id={"open-#{panel}"}
            type="button"
            phx-click="show_panel"
            phx-value-panel={panel}
            data-panel-trigger
            aria-haspopup="dialog"
            aria-controls={"panel-#{panel}"}
          ><.icon name={icon} class="size-4 shrink-0" />{label}</button>
        </nav>

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
              />
            <% end %>
          </div>
          <.live_component module={BoardComponents.Archive} id="merged-column" items={@board.merged} />
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

        <.live_component :if={@repo} module={BoardComponents.CreateTask} id="create" />
      </div>
    </Layouts.app>
    """
  end
end
