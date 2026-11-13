defmodule AgentBoardWeb.BoardComponents.PrivatePanel do
  @moduledoc """
  The inspector's Private tab: the task's private context
  (`AgentBoard.Board.PrivateContext`), edited where the task is read.

  The note saves as the owner types (a debounced change, written to disk at
  once) and is read from disk only when another task opens, so a board reload
  never takes words out of the field. Files dropped here and local folders
  are copied into the folder the moment they arrive. A task born without a
  folder gets `issue-<n>` on the first save; the path reaches its issue only
  through the confirmed `:share_private_context` (`AgentAction`, mode
  `:share_private`). Nothing here goes to the model or to an event.
  """
  use AgentBoardWeb, :live_component

  alias AgentBoardWeb.BoardNotice

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1]

  alias AgentBoard.Board
  alias AgentBoard.Board.{Attachments, PrivateContext}
  alias AgentBoardWeb.BoardComponents.AgentAction
  alias AgentBoardWeb.Numbers

  @accepted Attachments.accepted() ++ ~w(.md .txt .json .csv)

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(task_id: nil, saved: nil, error: nil, folder: "", role: "reference")
     |> allow_upload(:private_files,
       accept: @accepted,
       max_entries: Attachments.max_files(),
       max_file_size: Attachments.max_bytes(),
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, Map.take(assigns, [:id, :task, :comments, :tz_offset]))
    task = socket.assigns.task

    # The note is read from disk only when another task opens.
    if socket.assigns.task_id == task.id do
      {:ok, socket}
    else
      repository = Board.repository(task.repository_id)
      dir = PrivateContext.for_task(repository, task)

      {:ok,
       socket
       |> assign(task_id: task.id, repository: repository, dir: dir, saved: nil, error: nil)
       |> assign(note: if(dir, do: PrivateContext.read_note(repository, dir), else: ""))
       |> refresh()}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        path: assigns.dir && PrivateContext.path(assigns.repository, assigns.dir),
        shared: shared?(assigns.task, assigns.dir, assigns.comments)
      )

    ~H"""
    <section id={@id} class="ab-private-panel" aria-labelledby={"#{@id}-title"}>
      <h3 id={"#{@id}-title"} class="ab-label">
        <.ico name="lock" />{gettext("Private context")}
      </h3>
      <p class="ab-meta">
        {gettext(
          "Only on this machine, outside every repository. GitHub never sees the content; the agent reads the folder here."
        )}
      </p>

      <p :if={is_nil(@dir) and not is_integer(@task.number)} class="ab-meta">
        {gettext("This task has no GitHub issue yet; its private context opens when it does.")}
      </p>

      <div :if={@dir || is_integer(@task.number)} class="ab-private-panel__body">
        <div :if={@path} class="ab-private-panel__path">
          <code id={"#{@id}-path"}>{@path}</code>
          <button
            type="button"
            class="ab-btn ab-btn--sm ab-btn--quiet"
            phx-click={JS.dispatch("board:copy", detail: %{text: @path})}
          >
            {gettext("Copy path")}
          </button>
        </div>

        <form
          id={"#{@id}-note-form"}
          phx-change="save_note"
          phx-submit="save_note"
          phx-target={@myself}
          phx-auto-recover="ignore"
        >
          <label for={"#{@id}-note"} class="ab-label">{gettext("Private notes (notes.md)")}</label>
          <textarea
            id={"#{@id}-note"}
            name="note"
            rows="8"
            spellcheck="false"
            autocomplete="off"
            phx-debounce="600"
            placeholder={gettext("Passwords, keys, test accounts, internal links…")}
          >{@note}</textarea>
          <p class="ab-meta" role="status" aria-live="polite">
            {save_status(@saved, @error, @tz_offset)}
          </p>
        </form>

        <form
          id={"#{@id}-files-form"}
          phx-change="pick"
          phx-submit="add_folder"
          phx-target={@myself}
          class="ab-private-panel__add"
        >
          <label class="ab-btn ab-btn--sm">
            <.ico name="plus" />{gettext("Add files")}
            <.live_file_input upload={@uploads.private_files} class="ab-sr" />
          </label>
          <label class="ab-attach__opt">
            {gettext("as")}
            <select name="role">
              <option value="reference" selected={@role == "reference"}>
                {gettext("Reference")}
              </option>
              <option value="before" selected={@role == "before"}>{gettext("Before")}</option>
              <option value="after" selected={@role == "after"}>{gettext("After")}</option>
            </select>
          </label>
          <div class="ab-private__folder">
            <label for={"#{@id}-folder"} class="ab-sr">{gettext("Local folder")}</label>
            <input
              id={"#{@id}-folder"}
              name="folder"
              type="text"
              value={@folder}
              placeholder="~/Downloads/claude-design-export"
              autocomplete="off"
              spellcheck="false"
            />
            <button type="submit" class="ab-btn ab-btn--sm">{gettext("Copy folder")}</button>
          </div>
          <p
            :for={entry <- @uploads.private_files.entries}
            :if={upload_errors(@uploads.private_files, entry) != []}
            class="ab-compose__error"
            role="alert"
          >
            {entry.client_name}: {gettext("not accepted (type or size)")}
          </p>
        </form>

        <ul :if={@files != []} id={"#{@id}-files"} class="ab-private__list">
          <li :for={file <- @files}>
            <a
              :if={file.image?}
              href={image_href(@repository, @dir, file.path)}
              target="_blank"
              rel="noopener noreferrer"
              class="ab-private__thumb"
            >
              <img src={image_href(@repository, @dir, file.path)} alt={file.path} loading="lazy" />
            </a>
            <span class="ab-attach__name">{file.path}</span>
            <span class="ab-meta">{Numbers.bytes(file.bytes)}</span>
            <button
              :if={String.starts_with?(file.path, "files/")}
              type="button"
              class="ab-btn ab-btn--icon ab-btn--sm ab-btn--quiet"
              phx-click="remove"
              phx-value-path={file.path}
              phx-target={@myself}
              data-confirm={
                gettext("Delete %{name} from this machine? There is no undo.", name: file.path)
              }
              aria-label={gettext("Delete %{name}", name: file.path)}
            >
              <.ico name="close" />
            </button>
          </li>
        </ul>

        <div :if={@dir && not @shared} class="ab-private-panel__share">
          <p class="ab-meta">
            {gettext("The issue does not name this folder yet: the agent will not know it exists.")}
          </p>
          <.live_component
            module={AgentAction}
            id={"share-private-#{@task.id}"}
            mode={:share_private}
            tone={:primary}
            task={@task}
            dir={@dir}
            label={gettext("Tell the agent on the issue")}
            confirm_label={gettext("Comment the path")}
            busy_label={gettext("Commenting…")}
          />
        </div>
        <p :if={@dir && @shared} class="ab-meta">
          {gettext("The issue names this folder. The agent lists it when it works; new files count.")}
        </p>
      </div>
    </section>
    """
  end

  @impl true
  def handle_event("save_note", %{"note" => note}, socket) do
    %{repository: repository, task: task} = socket.assigns
    dir = socket.assigns.dir || PrivateContext.issue_dir(task.number)

    case PrivateContext.write_note(repository, dir, note) do
      :ok ->
        {:noreply,
         socket
         |> assign(dir: dir, note: note, saved: DateTime.utc_now(), error: nil)
         |> refresh()}

      {:error, :too_large} ->
        {:noreply, assign(socket, error: gettext("Too long: at most 256 KB. Nothing was saved."))}

      {:error, _posix} ->
        {:noreply,
         assign(socket, error: gettext("Could not write on this machine. Nothing was saved."))}
    end
  end

  def handle_event("pick", params, socket),
    do: {:noreply, assign(socket, role: role(params["role"]), folder: params["folder"] || "")}

  def handle_event("add_folder", %{"folder" => folder}, socket) do
    %{repository: repository, task: task} = socket.assigns
    dir = socket.assigns.dir || PrivateContext.issue_dir(task.number)

    case PrivateContext.import_folder(repository, dir, folder) do
      {:ok, %{name: name, files: files}} ->
        text = gettext("%{name}: %{count} files copied.", name: name, count: files)

        {:noreply,
         socket |> assign(dir: dir, folder: "") |> BoardNotice.notify(:info, text) |> refresh()}

      {:error, reason} ->
        {:noreply,
         socket |> assign(folder: folder) |> BoardNotice.notify(:error, folder_error(reason))}
    end
  end

  def handle_event("remove", %{"path" => path}, socket) do
    _ = PrivateContext.remove_file(socket.assigns.repository, socket.assigns.dir, path)
    {:noreply, refresh(socket)}
  end

  # A file is copied the moment its upload finishes: nothing waits for a send.
  defp handle_progress(:private_files, %{done?: true} = entry, socket) do
    %{repository: repository, task: task, role: role} = socket.assigns
    dir = socket.assigns.dir || PrivateContext.issue_dir(task.number)

    stored =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        # `path` is LiveView's temporary file for this upload.
        {:ok, content} = :file.read_file(path)
        {:ok, PrivateContext.put_file(repository, dir, entry.client_name, content, role)}
      end)

    {kind, text} =
      case stored do
        {:ok, relative} ->
          {:info, gettext("%{name} saved.", name: relative)}

        {:error, _reason} ->
          {:error, gettext("Could not save the file on this machine.")}
      end

    {:noreply, socket |> assign(dir: dir) |> BoardNotice.notify(kind, text) |> refresh()}
  end

  defp handle_progress(:private_files, _entry, socket), do: {:noreply, socket}

  defp refresh(%{assigns: %{dir: nil}} = socket), do: assign(socket, files: [])

  defp refresh(socket),
    do: assign(socket, files: PrivateContext.list(socket.assigns.repository, socket.assigns.dir))

  # The body names a folder the composer made; a comment names one made here.
  defp shared?(_task, nil, _comments), do: false

  defp shared?(task, dir, comments) do
    marker = PrivateContext.marker(dir)

    Enum.any?(
      [task.body | Enum.map(comments, & &1.body)],
      &(is_binary(&1) and String.contains?(&1, marker))
    )
  end

  defp image_href(repository, dir, path),
    do: ~p"/private/#{repository.id}/#{dir}/#{Path.split(path)}"

  defp role(role) when role in ~w(before after), do: role
  defp role(_reference), do: "reference"

  defp save_status(_saved, error, _offset) when is_binary(error), do: error
  defp save_status(nil, _error, _offset), do: gettext("Saved as you type.")
  defp save_status(at, _error, offset), do: save_status(at, offset)

  defp save_status(%DateTime{} = at, offset),
    do: gettext("Saved at %{time}.", time: AgentBoardWeb.Time.local_time(at, offset))

  @doc false
  def folder_error(:outside_home), do: gettext("Only a folder under your home can be copied.")
  def folder_error(:hidden), do: gettext("Hidden folders (like ~/.ssh) are never copied.")

  def folder_error(:inside_private),
    do: gettext("This folder is already inside the board's private place.")

  def folder_error(:too_large), do: gettext("Too big: at most 2,000 files and 200 MB.")
  def folder_error(:empty), do: gettext("The folder has no file to copy.")
  def folder_error(_not_a_folder), do: gettext("No folder at this path.")
end
