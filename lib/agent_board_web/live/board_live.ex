defmodule AgentBoardWeb.BoardLive do
  @moduledoc "The board: the columns, the repositories and the tasks, live."
  use AgentBoardWeb, :live_view

  import Ecto.Query, warn: false

  alias AgentBoard.{Board, GitHub, Repo}
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
        counter: 0
      )

    {:ok, load(socket, List.first(repos))}
  end

  defp empty, do: %{running: [], ready: [], merged: [], queued: []}

  defp load(socket, nil), do: assign(socket, repo: nil, board: empty(), events: [])

  defp load(socket, repo) do
    case Board.board("#{repo.owner}/#{repo.name}") do
      {:ok, board} -> assign(socket, repo: repo, board: board, events: Board.events(repo))
      _ -> assign(socket, repo: nil, board: empty(), events: [])
    end
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
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-[#12120f] text-[#e8e6df] font-mono">
        <header class="flex flex-wrap items-center gap-3 border-b border-[#2a2925] px-5 py-3">
          <h1 class="text-sm tracking-[0.16em] uppercase">Agent board</h1>

          <form phx-change="select" class="contents">
            <select name="repo" class="border border-[#2a2925] bg-[#191813] px-3 py-2 text-sm">
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

          <span class="flex-1"></span>

          <form phx-submit="add" class="contents">
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
            <button class="border border-[#2a2925] px-3 py-2 text-sm">Track repo</button>
          </form>
        </header>

        <main class="grid grid-cols-4 gap-px bg-[#2a2925]">
          <%= for {title, key} <- [{"Running", :running}, {"Ready", :ready}, {"Merged", :merged}, {"Queued", :queued}] do %>
            <section class="bg-[#12120f] p-4">
              <h2 class="mb-3 flex justify-between text-[11px] uppercase tracking-[0.16em] text-[#8a877d]">
                <span>{title}</span>
                <span>{length(Map.get(@board, key))}</span>
              </h2>

              <div
                :for={item <- Map.get(@board, key)}
                class={[
                  "mb-2 border border-[#2a2925] border-l-2 bg-[#191813] px-3 py-2",
                  key == :running && "border-l-[#e8a33d]",
                  key == :ready && "border-l-[#6fa8dc]",
                  key == :merged && "border-l-[#7bc47f]",
                  key == :queued && "border-l-[#8a877d]"
                ]}
              >
                <a
                  :if={item[:url]}
                  href={item[:url]}
                  target="_blank"
                  class="text-[13px] hover:underline"
                >
                  {item[:title]}
                </a>
                <span :if={item[:number]} class="text-[11px] text-[#8a877d]">#{item[:number]}</span>

                <div :if={key in [:running, :ready, :queued]} class="mt-2 flex gap-1 text-[11px]">
                  <button phx-click="act" phx-value-id={item[:id]} phx-value-action="stop">Stop</button>
                  <button phx-click="act" phx-value-id={item[:id]} phx-value-action="archive">Archive</button>
                </div>
              </div>

              <p :if={Map.get(@board, key) == []} class="text-xs text-[#8a877d]">nothing here</p>
            </section>
          <% end %>
        </main>

        <div class="border-t border-[#2a2925] px-5 py-2 text-[11px] text-[#8a877d]">
          <div :for={e <- @events}>{e.kind} · {e.subject}</div>
        </div>

        <footer class="border-t border-[#2a2925] p-5">
          <form phx-submit="create" class="flex flex-wrap gap-2">
            <input
              name="title"
              placeholder="New task: what should the agent build?"
              class="flex-1 border border-[#2a2925] bg-[#191813] px-3 py-2 text-sm"
              required
            />
            <button class="bg-[#e8a33d] px-4 py-2 text-sm font-bold text-[#12120f]">Create issue</button>
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
