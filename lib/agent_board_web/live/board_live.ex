defmodule AgentBoardWeb.BoardLive do
  @moduledoc "The board: the columns, the repositories and the tasks, live."
  use AgentBoardWeb, :live_view

  import Ecto.Query, warn: false

  alias AgentBoard.{AI, Board, GitHub, Intake, Repo, Voice}
  alias AgentBoard.Board.Task
  alias AgentBoard.System.{Updater, Version}
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
        live: false,
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

  defp empty, do: %{running: [], ready: [], merged: [], queued: []}

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
      live: false,
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

    case Board.board("#{repo.owner}/#{repo.name}") do
      {:ok, board} ->
        assign(socket,
          repo: repo,
          board: board,
          events: Board.events(repo),
          ai_calls: AI.recent(5),
          live: connected?(socket)
        )

      _ ->
        assign(socket,
          repo: nil,
          board: empty(),
          events: [],
          live: false,
          ai_calls: [],
          ai_status: AI.status()
        )
    end
  end

  @impl true
  def handle_info(:board_updated, socket) do
    {:noreply, load(socket, socket.assigns.repo)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    repo =
      case params["repo"] do
        nil -> socket.assigns.repo
        slug -> Board.repository_by_slug(slug) || socket.assigns.repo
      end

    {:noreply, load(socket, repo)}
  end

  @impl true
  def handle_event("select", %{"repo" => slug}, socket) do
    {:noreply, push_patch(socket, to: "/?repo=#{URI.encode_www_form(slug)}")}
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
        _ = Board.create_task(repo, title, text, GitHub.client())
        {:noreply, socket |> load(repo) |> put_flash(:info, "Task created")}
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
    {task_id, _} = Integer.parse(id)

    case Repo.get(Task, task_id) |> Repo.preload(:repository) do
      nil -> {:noreply, socket}
      task -> {:noreply, assign(socket, conversation: task, comments: Board.comments(task))}
    end
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
             |> put_flash(:info, "Question sent")
             |> put_flash(:info, answer(task, body))}

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
  def handle_event("intake", %{"text" => text}, socket) do
    case Intake.run(text) do
      {:ok, %{spec: spec, tasks: tasks}} ->
        {:noreply, assign(socket, intake: %{spec: spec, tasks: tasks, text: text})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "The AI did not answer: #{inspect(reason)}")}
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
    {:noreply, assign(socket, conversation: nil, comments: [])}
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

  defp time(nil), do: ""

  defp time(dt) do
    dt |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 5)
  end

  defp review_badge(%{review_state: state})
       when state in ["approved", "changes_requested", "pending"] do
    case state do
      "approved" -> "approved"
      "changes_requested" -> "changes requested"
      "pending" -> "review pending"
    end
  end

  # "none" is a real answer: the pull has no reviews. Saying it is more honest
  # than hiding the badge and letting the reader guess.
  defp review_badge(%{review_state: "none"}), do: "no review"
  defp review_badge(_), do: nil

  defp review_badge_class(%{review_state: "approved"}), do: "text-success"
  defp review_badge_class(%{review_state: "changes_requested"}), do: "text-error"
  defp review_badge_class(_), do: "text-base-content/75"

  defp checks_badge(%{checks_state: "failure", checks_failed: name})
       when is_binary(name) and name != "",
       do: "ci failed: #{name}"

  defp checks_badge(%{checks_state: "none"}), do: "no ci"

  defp checks_badge(%{checks_state: state}) when state in ["success", "failure", "pending"] do
    case state do
      "success" -> "ci passed"
      "failure" -> "ci failed"
      "pending" -> "ci running"
    end
  end

  defp checks_badge(_), do: nil

  defp checks_badge_class(%{checks_state: "success"}), do: "text-success"
  defp checks_badge_class(%{checks_state: "failure"}), do: "text-error"
  defp checks_badge_class(_), do: "text-base-content/75"

  defp last_sync([]), do: "no sync yet"

  defp last_sync(events) do
    case Enum.find(events, &(&1.kind == "sync")) do
      nil ->
        "no sync yet"

      sync ->
        errors = sync.payload["errors"] || 0

        suffix =
          case errors do
            0 -> " · clean"
            1 -> " · 1 error"
            n -> " · #{n} errors"
          end

        "synced #{time(sync.inserted_at)}" <> suffix
    end
  end

  # Not every non-sync event is a failure: a repository without Issues is a
  # warning, not an error (the pulls still sync).
  defp warning?(%{kind: kind}), do: kind == "issues_unavailable"

  # A sync event carries an errors count; the per-item failures (issue_error,
  # pull_error, ...) carry a reason. Both must read as problems.
  defp has_errors?(%{kind: kind, payload: payload}) do
    String.ends_with?(kind || "", "_error") or
      (is_integer(payload["errors"]) and payload["errors"] > 0)
  end

  @max_payload 120

  defp payload_summary(payload) do
    Enum.map_join(payload, " · ", fn {k, v} -> "#{k}: #{truncate(v)}" end)
  end

  # A network error can carry the whole GitHub body (hundreds of chars) and
  # would wreck the activity column. One line, bounded.
  defp truncate(value) when is_binary(value) and byte_size(value) > @max_payload,
    do: String.slice(value, 0, @max_payload) <> "…"

  defp truncate(value) when is_binary(value), do: value
  defp truncate(value), do: inspect(value)

  defp empty_copy(:running), do: "No task is running."
  defp empty_copy(:ready), do: "Nothing is waiting on a review."
  defp empty_copy(:blocked), do: "Nothing is blocked."
  defp empty_copy(:merged), do: "No pull request merged yet."
  defp empty_copy(:queued), do: "No queued task."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="agent-board min-h-screen bg-base-100 text-base-content font-mono">
        <header class="flex flex-wrap items-center gap-3 border-b border-base-content/10 px-5 py-3">
          <div class="flex flex-wrap items-baseline gap-2">
            <h1 class="text-lg tracking-[0.16em] uppercase">Agent board</h1>
            <span class="text-[10px] text-base-content/75">the agent's work, live</span>
          </div>

          <form id="repo-select" phx-change="select" class="contents">
            <select
              name="repo"
              aria-label="Repository"
              class="border border-base-content/10 bg-base-200 px-3 py-2 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
            >
              <option :if={@repo == nil} value="">select a repository</option>
              <option
                :for={r <- @repos}
                value={"#{r.owner}/#{r.name}"}
                selected={@repo && @repo.id == r.id}
              >
                {r.owner}/{r.name}
              </option>
            </select>
          </form>

          <button
            phx-click="speak"
            class="border border-base-content/10 px-3 py-2 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary hover:bg-base-300"
          >
            Speak status
          </button>
          <button
            phx-click="dictate"
            class="border border-base-content/10 px-3 py-2 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary hover:bg-base-300"
          >
            Dictate task
          </button>

          <Layouts.theme_toggle />

          <span class="flex-1"></span>

          <span class={["text-[11px]", if(@live, do: "text-success", else: "text-base-content/75")]}>
            {if @live, do: "live", else: "static"}
          </span>
          <span class="text-[11px] text-base-content/75" role="status" aria-live="polite">{last_sync(
            @events
          )}</span>

          <form id="track-repo" phx-submit="add" class="flex flex-wrap items-center gap-2">
            <input
              name="owner"
              placeholder="owner"
              aria-label="Owner"
              class="w-20 border border-base-content/10 bg-base-200 px-3 py-2 text-sm sm:w-28"
            />
            <input
              name="name"
              placeholder="repo name"
              aria-label="Repository name"
              class="w-24 border border-base-content/10 bg-base-200 px-3 py-2 text-sm sm:w-36"
            />
            <button
              class="border border-base-content/10 px-3 py-2 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary hover:bg-base-300"
              phx-disable-with="Tracking…"
            >Track repo</button>
          </form>
        </header>

        <div
          :if={Phoenix.Flash.get(@flash, :error)}
          role="alert"
          class="flex items-center justify-between border-b border-error/40 bg-error/15 px-5 py-2 text-[12px] text-error"
        >
          <span>{Phoenix.Flash.get(@flash, :error)}</span>
          <button phx-click="lv:clear-flash" phx-value-key="error" class="text-[11px] underline">
            dismiss
          </button>
        </div>

        <div
          :if={@repo == nil}
          class="flex flex-col items-center gap-3 border-b border-base-content/10 px-5 py-20 text-center"
        >
          <p class="text-sm text-base-content">No repository tracked yet.</p>
          <p class="max-w-md text-[12px] leading-relaxed text-base-content/75">
            Track one in the header. The board syncs its issues and pull requests, shows
            the agent's work in the five columns, and lets you create and ask.
          </p>
        </div>

        <SystemPanel.version_panel version={@version} busy={@busy} />

        <main
          :if={@repo}
          class="grid grid-cols-1 gap-px bg-base-content/10 sm:grid-cols-2 lg:grid-cols-5"
        >
          <%= for {title, key} <- [
              {"Running", :running},
              {"Ready", :ready},
              {"Blocked", :blocked},
              {"Merged", :merged},
              {"Queued", :queued}
            ] do %>
            <section
              aria-label={title <> " tasks"}
              tabindex="0"
              class="board-column min-w-0 overflow-y-auto bg-base-100 p-4 lg:max-h-[55vh]"
            >
              <h2 class="sticky top-0 z-10 mb-3 flex items-baseline justify-between bg-base-100 py-1 gap-2 text-[11px] uppercase tracking-[0.16em] text-base-content/75">
                <span>{title}</span>
                <span class="rounded-full bg-base-200 px-2 py-0.5 text-[10px] tabular-nums">
                  {length(Map.get(@board, key))}
                </span>
              </h2>

              <div
                :for={item <- Map.get(@board, key)}
                class={[
                  "mb-2 border border-base-content/10 border-l-2 bg-base-200 px-3 py-2 transition-colors hover:bg-base-300",
                  key == :running && "border-l-warning",
                  key == :ready && "border-l-info",
                  key == :blocked && "border-l-error",
                  key == :merged && "border-l-success",
                  key == :queued && "border-l-base-content/50"
                ]}
              >
                <a
                  :if={item.url}
                  href={item.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="block break-words text-sm font-medium hover:underline"
                >
                  {item.title}
                </a>
                <span :if={is_nil(item.url)} class="block break-words text-sm font-medium">{item.title}</span>
                <span
                  :if={review_badge(item)}
                  class={["ml-2 text-[11px] uppercase", review_badge_class(item)]}
                >
                  {review_badge(item)}
                </span>
                <span
                  :if={checks_badge(item)}
                  class={["ml-2 text-[11px] uppercase", checks_badge_class(item)]}
                >
                  {checks_badge(item)}
                </span>
                <span :if={item.number} class="ml-2 text-[11px] tabular-nums text-base-content/75">
                  #{item.number}
                </span>

                <div
                  :if={key in [:running, :ready, :blocked, :queued]}
                  class="mt-2 flex gap-1 text-[11px]"
                >
                  <button
                    phx-click={JS.push_focus() |> JS.push("open")}
                    phx-value-id={item.id}
                    aria-label={"Open task: " <> item.title}
                    class="rounded-sm border border-base-content/15 px-2 py-1 hover:bg-base-300 focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
                  >Open</button>
                  <button
                    phx-click="act"
                    phx-value-id={item.id}
                    phx-value-action="stop"
                    aria-label={"Stop task: " <> item.title}
                    class="rounded-sm border border-base-content/15 px-2 py-1 hover:bg-base-300 focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
                  >Stop</button>
                  <button
                    phx-click="act"
                    phx-value-id={item.id}
                    phx-value-action="archive"
                    aria-label={"Archive task: " <> item.title}
                    class="rounded-sm border border-base-content/15 px-2 py-1 hover:bg-base-300 focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
                  >
                    Archive
                  </button>
                </div>
              </div>

              <p :if={Map.get(@board, key) == []} class="text-xs text-base-content/75">
                {empty_copy(key)}
              </p>
            </section>
          <% end %>
        </main>

        <section
          :if={@conversation}
          id="conversation"
          class="border-t border-base-content/10 px-5 py-4"
        >
          <h2
            id="conversation-title"
            tabindex="-1"
            phx-mounted={JS.focus(to: "#conversation-title")}
            class="mb-3 flex flex-wrap items-center gap-3 text-[11px] uppercase tracking-[0.16em] text-base-content/75"
          >
            <span>Conversation · #{@conversation.number} {String.slice(@conversation.title, 0, 40)}</span>
            <button phx-click="speak" class="border border-base-content/10 px-2 py-1 text-[10px]">
              Speak
            </button>
            <button
              phx-click={JS.push("close") |> JS.pop_focus()}
              class="border border-base-content/10 px-2 py-1 text-[10px]"
            >
              Close
            </button>
          </h2>

          <div :for={c <- @comments} class="mb-2 flex gap-2">
            <span class={[
              "w-10 shrink-0 text-[10px] uppercase sm:w-14",
              c.kind == "agent" && "text-success",
              c.kind != "agent" && "text-info"
            ]}>
              {c.kind}
            </span>
            <div class="min-w-0">
              <p class="whitespace-pre-wrap break-words text-[12px] leading-relaxed text-base-content">
                {c.body}
              </p>
              <span :if={c.inserted_at} class="text-[10px] text-base-content/75">{time(c.inserted_at)}</span>
            </div>
          </div>

          <p :if={@comments == []} class="text-xs text-base-content/75">
            No messages yet. Ask the agent below.
          </p>

          <form id="ask-agent" phx-submit="ask" class="mt-3 flex gap-2">
            <input
              name="body"
              aria-label="Message to the agent"
              placeholder="Ask the agent…"
              class="flex-1 border border-base-content/10 bg-base-200 px-3 py-2 text-sm"
              required
            />
            <button
              class="bg-primary px-4 py-2 text-sm font-bold text-primary-content hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
              phx-disable-with="Sending…"
            >Send</button>
          </form>
        </section>

        <details :if={@events != []} id="activity" class="border-t border-base-content/10 px-5 py-4">
          <summary class="cursor-pointer py-2 text-xs uppercase tracking-[0.16em]">
            Activity · latest {length(@events)} events
          </summary>
          <ol
            class="mt-3 max-h-64 space-y-2 overflow-y-auto"
            tabindex="0"
            aria-label="Recent activity"
          >
            <li
              :for={e <- @events}
              class={[
                "grid min-w-0 gap-x-3 gap-y-1 text-xs sm:grid-cols-[5rem_10rem_minmax(0,1fr)]",
                has_errors?(e) && "text-error",
                warning?(e) && "text-warning"
              ]}
            >
              <span class="w-24 shrink-0 text-base-content/75">{time(e.inserted_at)}</span>
              <span class="break-words uppercase">{e.kind}</span>
              <span class="min-w-0 break-words text-base-content">{e.subject}</span>
              <span
                :if={e.payload && e.payload != %{}}
                class="min-w-0 break-words text-base-content/75 sm:col-span-2 sm:col-start-2"
              >
                {payload_summary(e.payload)}
              </span>
            </li>
          </ol>
        </details>

        <section :if={@repo} class="border-t border-base-content/10 px-5 py-4">
          <h2 class="mb-3 text-[11px] uppercase tracking-[0.16em] text-base-content/75">
            Split a request
          </h2>

          <form id="intake-form" phx-submit="intake" class="flex gap-2">
            <input
              name="text"
              placeholder="Describe what you want..."
              aria-label="Request"
              class="flex-1 border border-base-content/10 bg-base-200 px-3 py-2 text-sm"
              required
            />
            <button class="bg-primary px-4 py-2 text-sm font-bold text-primary-content hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary">
              Split
            </button>
          </form>

          <div :if={@intake} class="mt-4">
            <p class="text-[10px] uppercase text-base-content/75">Goal</p>
            <p class="text-sm text-base-content">{@intake.spec["goal"]}</p>

            <div :if={@intake.spec["open_questions"] != []} class="mt-2 text-[11px] text-warning">
              <p class="uppercase text-[10px]">Open questions</p>
              <p :for={q <- @intake.spec["open_questions"]}>{q}</p>
            </div>

            <ol class="mt-3 space-y-2">
              <li
                :for={{task, index} <- Enum.with_index(@intake.tasks)}
                class="border border-base-content/10 border-l-2 border-l-info bg-base-200 px-3 py-2"
              >
                <p class="text-[13px]">
                  {task.title}
                  <span class="ml-2 text-[10px] uppercase text-base-content/75">{task.kind}</span>
                  <span class="ml-2 text-[10px] uppercase text-base-content/75">{task.size}</span>
                </p>
                <p class="mt-1 text-[11px] text-base-content/75">{task.body}</p>
                <button
                  phx-click="create_from_intake"
                  phx-value-index={index}
                  class="mt-2 border border-base-content/10 px-2 py-1 text-[10px]"
                >
                  Create
                </button>
              </li>
            </ol>
          </div>
        </section>

        <section :if={@repo} class="border-t border-base-content/10 px-5 py-4">
          <h2 class="mb-3 flex items-center gap-3 text-[11px] uppercase tracking-[0.16em] text-base-content/75">
            <span>AI</span>
            <span class={["text-[10px] normal-case", @ai_status != :logged_in && "text-warning"]}>
              {@ai_status}
            </span>
          </h2>
          <ol class="space-y-1">
            <li :for={c <- @ai_calls} class="flex flex-wrap gap-x-3 gap-y-1 text-xs">
              <span class="min-w-0 break-words uppercase">{c.name}</span>
              <span class="w-20 shrink-0 text-base-content/75">{c.engine}</span>
              <span class={["w-16 shrink-0", c.status == "error" && "text-error"]}>
                {c.status}
              </span>
              <span class="w-20 shrink-0 text-base-content/75">{c.duration_ms}ms</span>
              <span class="text-base-content/75">{c.input_tokens + c.output_tokens} tokens</span>
            </li>
          </ol>
        </section>

        <footer class="border-t border-base-content/10 p-5">
          <form id="create-task" phx-submit="create" class="flex flex-wrap gap-2">
            <input
              name="title"
              id="task-title"
              aria-label="Task title"
              placeholder="New task: what should the agent build?"
              class="flex-1 border border-base-content/10 bg-base-200 px-3 py-2 text-sm"
              required
            />
            <button
              class="bg-primary px-4 py-2 text-sm font-bold text-primary-content hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
              phx-disable-with="Creating…"
            >Create issue</button>
            <textarea
              name="body"
              aria-label="Task details"
              placeholder="Details (optional). The agent is mentioned automatically."
              class="w-full border border-base-content/10 bg-base-200 px-3 py-2 text-sm"
            ></textarea>
          </form>
        </footer>
      </div>
    </Layouts.app>
    """
  end
end
