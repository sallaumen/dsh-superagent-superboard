defmodule AgentBoardWeb.BoardLive do
  @moduledoc "The board: the columns, the repositories and the tasks, live."
  use AgentBoardWeb, :live_view

  import Ecto.Query, warn: false

  alias AgentBoard.{Board, GitHub, Repo, Voice}
  alias AgentBoard.Board.{Repository, Task}

  @impl true
  def mount(_params, _session, socket) do
    repos = Board.list_repositories()

    socket =
      assign(socket,
        repos: repos,
        repo: nil,
        board: empty(),
        events: [],
        live: false,
        conversation: nil,
        comments: []
      )

    {:ok, load(socket, default_repo(repos))}
  end

  defp empty, do: %{running: [], ready: [], merged: [], queued: []}

  # The board opens on the project the agent is actually working on; the
  # first active repository is the fallback.
  defp default_repo(repos) do
    Enum.find(repos, &(&1.name == "o_colmex")) || List.first(repos)
  end

  defp load(socket, nil) do
    assign(socket, repo: nil, board: empty(), events: [], live: false)
  end

  defp load(socket, repo) do
    if connected?(socket), do: Board.subscribe(repo.id)

    case Board.board("#{repo.owner}/#{repo.name}") do
      {:ok, board} ->
        assign(socket,
          repo: repo,
          board: board,
          events: Board.events(repo),
          live: connected?(socket)
        )

      _ ->
        assign(socket, repo: nil, board: empty(), events: [], live: false)
    end
  end

  @impl true
  def handle_info(:board_updated, socket) do
    {:noreply, load(socket, socket.assigns.repo)}
  end

  @impl true
  def handle_event("select", %{"repo" => slug}, socket) do
    case Repo.one(
           from r in Repository, where: fragment("? || '/' || ?", r.owner, r.name) == ^slug
         ) do
      nil -> {:noreply, socket}
      repo -> {:noreply, load(socket, repo)}
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
        _ = Board.ask(task, body, GitHub.client())

        {:noreply,
         assign(socket,
           conversation: Repo.get(Task, task.id) |> Repo.preload(:repository),
           comments: Board.comments(task)
         )
         |> put_flash(:info, "Question sent")}
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

  defp time(nil), do: ""

  defp time(dt) do
    dt |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 5)
  end

  defp payload_summary(payload) do
    Enum.map_join(payload, " · ", fn {k, v} -> "#{k}: #{v}" end)
  end

  defp empty_copy(:running), do: "No task is running."
  defp empty_copy(:ready), do: "Nothing is waiting on a review."
  defp empty_copy(:merged), do: "No pull request merged yet."
  defp empty_copy(:queued), do: "No queued task."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-[#12120f] text-[#e8e6df] font-mono">
        <header class="flex flex-wrap items-center gap-3 border-b border-[#2a2925] px-5 py-3">
          <h1 class="text-sm tracking-[0.16em] uppercase">Agent board</h1>

          <form id="repo-select" phx-change="select" class="contents">
            <select
              name="repo"
              class="border border-[#2a2925] bg-[#191813] px-3 py-2 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#e8a33d]"
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
            class="border border-[#2a2925] px-3 py-2 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#e8a33d] hover:bg-[#23221c]"
          >
            Speak status
          </button>
          <button
            phx-click="dictate"
            class="border border-[#2a2925] px-3 py-2 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#e8a33d] hover:bg-[#23221c]"
          >
            Dictate task
          </button>

          <span class="flex-1"></span>

          <span class={["text-[11px]", if(@live, do: "text-[#7bc47f]", else: "text-[#a39f93]")]}>
            {if @live, do: "live", else: "static"}
          </span>

          <form id="track-repo" phx-submit="add" class="contents">
            <input
              name="owner"
              placeholder="owner"
              class="w-28 border border-[#2a2925] bg-[#191813] px-3 py-2 text-sm"
            />
            <input
              name="name"
              placeholder="repo name"
              class="w-36 border border-[#2a2925] bg-[#191813] px-3 py-2 text-sm"
            />
            <button
              class="border border-[#2a2925] px-3 py-2 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#e8a33d] hover:bg-[#23221c]"
              phx-disable-with="Tracking…"
            >Track repo</button>
          </form>
        </header>

        <div
          :if={Phoenix.Flash.get(@flash, :error)}
          role="alert"
          class="flex items-center justify-between border-b border-[#5c2a2a] bg-[#2a1515] px-5 py-2 text-[12px] text-[#f0b3b3]"
        >
          <span>{Phoenix.Flash.get(@flash, :error)}</span>
          <button phx-click="lv:clear-flash" phx-value-key="error" class="text-[11px] underline">
            dismiss
          </button>
        </div>

        <div
          :if={@repo == nil}
          class="flex flex-col items-center gap-3 border-b border-[#2a2925] px-5 py-20 text-center"
        >
          <p class="text-sm text-[#e8e6df]">No repository tracked yet.</p>
          <p class="max-w-md text-[12px] leading-relaxed text-[#a39f93]">
            Track one below. The board syncs its issues and pull requests, shows
            the agent's work in the four columns, and lets you create and ask.
          </p>
        </div>

        <main :if={@repo} class="grid grid-cols-4 gap-px bg-[#2a2925]">
          <%= for {title, key} <- [{"Running", :running}, {"Ready", :ready}, {"Merged", :merged}, {"Queued", :queued}] do %>
            <section class="bg-[#12120f] p-4">
              <h2 class="mb-3 flex justify-between text-[11px] uppercase tracking-[0.16em] text-[#a39f93]">
                <span>{title}</span>
                <span>{length(Map.get(@board, key))}</span>
              </h2>

              <div
                :for={item <- Map.get(@board, key)}
                class={[
                  "mb-2 border border-[#2a2925] border-l-2 bg-[#191813] px-3 py-2 transition-colors hover:bg-[#1f1e18]",
                  key == :running && "border-l-[#e8a33d]",
                  key == :ready && "border-l-[#6fa8dc]",
                  key == :merged && "border-l-[#7bc47f]",
                  key == :queued && "border-l-[#8a877d]"
                ]}
              >
                <a :if={item.url} href={item.url} target="_blank" class="text-[13px] hover:underline">
                  {item.title}
                </a>
                <span :if={item.number} class="ml-2 text-[11px] text-[#a39f93]">
                  #{item.number}
                </span>

                <div :if={key in [:running, :ready, :queued]} class="mt-2 flex gap-1 text-[11px]">
                  <button phx-click="open" phx-value-id={item.id}>Open</button>
                  <button phx-click="act" phx-value-id={item.id} phx-value-action="stop">Stop</button>
                  <button phx-click="act" phx-value-id={item.id} phx-value-action="archive">
                    Archive
                  </button>
                </div>
              </div>

              <p :if={Map.get(@board, key) == []} class="text-xs text-[#a39f93]">{empty_copy(key)}</p>
            </section>
          <% end %>
        </main>

        <section :if={@events != []} class="border-t border-[#2a2925] px-5 py-4">
          <h2 class="mb-3 text-[11px] uppercase tracking-[0.16em] text-[#a39f93]">Activity</h2>
          <ol class="space-y-1">
            <li :for={e <- @events} class="flex gap-3 text-[11px]">
              <span class="w-24 shrink-0 text-[#a39f93]">{time(e.inserted_at)}</span>
              <span class="w-14 shrink-0 uppercase">{e.kind}</span>
              <span class="text-[#e8e6df]">{e.subject}</span>
              <span :if={e.payload && e.payload != %{}} class="text-[#6b675c]">
                {payload_summary(e.payload)}
              </span>
            </li>
          </ol>
        </section>

        <section :if={@conversation} class="border-t border-[#2a2925] px-5 py-4">
          <h2 class="mb-3 flex items-center gap-3 text-[11px] uppercase tracking-[0.16em] text-[#a39f93]">
            <span>Conversation · #{@conversation.number} {String.slice(@conversation.title, 0, 40)}</span>
            <button phx-click="speak" class="border border-[#2a2925] px-2 py-1 text-[10px]">
              Speak
            </button>
            <button phx-click="close" class="border border-[#2a2925] px-2 py-1 text-[10px]">
              Close
            </button>
          </h2>

          <div :for={c <- @comments} class="mb-2 flex gap-2">
            <span class={[
              "w-14 shrink-0 text-[10px] uppercase",
              c.kind == "agent" && "text-[#7bc47f]",
              c.kind != "agent" && "text-[#6fa8dc]"
            ]}>
              {c.kind}
            </span>
            <div class="min-w-0">
              <p class="whitespace-pre-wrap text-[12px] leading-relaxed text-[#e8e6df]">{c.body}</p>
              <span :if={c.inserted_at} class="text-[10px] text-[#6b675c]">{time(c.inserted_at)}</span>
            </div>
          </div>

          <p :if={@comments == []} class="text-xs text-[#a39f93]">
            No messages yet. Ask the agent below.
          </p>

          <form id="ask-agent" phx-submit="ask" class="mt-3 flex gap-2">
            <input
              name="body"
              placeholder="Ask the agent…"
              class="flex-1 border border-[#2a2925] bg-[#191813] px-3 py-2 text-sm"
              required
            />
            <button
              class="bg-[#e8a33d] px-4 py-2 text-sm font-bold text-[#12120f] hover:bg-[#f0b356] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#e8a33d]"
              phx-disable-with="Sending…"
            >Send</button>
          </form>
        </section>

        <footer class="border-t border-[#2a2925] p-5">
          <form id="create-task" phx-submit="create" class="flex flex-wrap gap-2">
            <input
              name="title"
              id="task-title"
              placeholder="New task: what should the agent build?"
              class="flex-1 border border-[#2a2925] bg-[#191813] px-3 py-2 text-sm"
              required
            />
            <button
              class="bg-[#e8a33d] px-4 py-2 text-sm font-bold text-[#12120f] hover:bg-[#f0b356] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#e8a33d]"
              phx-disable-with="Creating…"
            >Create issue</button>
            <textarea
              name="body"
              placeholder="Details (optional). The agent is mentioned automatically."
              class="w-full border border-[#2a2925] bg-[#191813] px-3 py-2 text-sm"
            ></textarea>
          </form>
        </footer>
      </div>
    </Layouts.app>
    """
  end
end
