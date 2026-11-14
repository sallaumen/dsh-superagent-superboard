defmodule AgentBoardWeb.ComposerLifecycle do
  @moduledoc """
  The LiveView side of the composer: one lifecycle on `BoardLive`'s socket.

  | Transition | Owner | Durable record |
  |---|---|---|
  | draft | the socket (`composer_text`, kept across close/reopen) | none |
  | splitting → ready / needs_clarification / no_tasks / failed | `start_async` keyed by a `ref`; a late or cancelled result changes nothing | `ai_calls` |
  | enqueuing → receipt | `start_async`, one `Board.Requests.create_request/3` per chosen task | `tasks.request_key` |
  | timeout | `{:composer_timeout, ref}` after `:composer_timeout_ms`; cancels the job and names the failure | — |

  One job at a time, keyed by a ref: a late or cancelled result finds no job
  with its ref and changes nothing. The durable records are the ai_calls
  rows (the split) and the tasks with their request_key (the enqueue); the
  receipt is read from those tasks, so a reload shows the same thing. The
  presentation is `AgentBoardWeb.BoardComponents.Composer`.
  """

  use Gettext, backend: AgentBoardWeb.Gettext

  import Phoenix.Component, only: [assign: 2, assign: 3]

  import Phoenix.LiveView,
    only: [
      allow_upload: 3,
      cancel_async: 2,
      cancel_upload: 3,
      connected?: 1,
      consume_uploaded_entries: 3,
      put_flash: 3,
      start_async: 3
    ]

  alias AgentBoard.{Actions, AI, Board, Executors, GitHub, Intake, Titles}
  alias AgentBoard.Board.{Attachments, PrivateContext}
  alias AgentBoard.Intake.{IssueBody, RepoDigest}
  alias AgentBoard.Routing
  alias AgentBoard.Routing.Signals
  alias AgentBoardWeb.{BoardNavigation, FailureText, Locale}

  # What the composer gathers for the request's private context: never sent
  # to the model, written on this machine at the send (`PrivateContext`).
  @empty_private %{
    dir: nil,
    note: "",
    folder: "",
    folders: [],
    folder_error: nil,
    meta: %{},
    files: []
  }

  @doc "The assigns and the upload a socket needs before the composer opens."
  def mount(socket) do
    socket
    |> assign(
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
      composer_private: new_private(),
      composer_routing: nil,
      composer_routing_for: nil,
      composer_executor: nil,
      composer_executor_touched: false
    )
    |> allow_upload(:attachments,
      accept: Attachments.accepted(),
      max_entries: Attachments.max_files(),
      max_file_size: Attachments.max_bytes(),
      auto_upload: true
    )
  end

  @doc """
  Open the panel. Reopening keeps the draft as it is, so a proposal or a
  receipt is not lost; the split is a button inside the composer.
  """
  def open(socket), do: BoardNavigation.open_panel(socket, "composer")

  @doc "The form changed: words, title, answers, checkboxes, private fields or the executor."
  def change(socket, params) do
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

    socket
    |> with_task_edits(params)
    |> with_private_fields(params)
    |> assign(
      composer_text: text,
      composer_title: edited_title(params, text, socket.assigns.composer_title),
      composer_answers: params["answers"] || socket.assigns.composer_answers
    )
    |> choose_executor(params["executor"])
  end

  @doc "Add the folder being typed to the private context, or show why it cannot be."
  def add_folder(socket, params) do
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

    assign(socket, composer_private: private)
  end

  @doc "Remove a folder from the private context."
  def remove_folder(socket, path) do
    private = socket.assigns.composer_private
    folders = Enum.reject(private.folders, &(&1.path == path))
    assign(socket, composer_private: %{private | folders: folders})
  end

  @doc "Remove an attachment that has not been sent yet."
  def remove_attachment(socket, ref), do: cancel_upload(socket, :attachments, ref)

  @doc """
  One click runs the whole split (repository digest, refine, proposal); a
  second click splits the current words again.
  """
  def split(socket) do
    text = String.trim(socket.assigns.composer_text)

    cond do
      socket.assigns.composer_job ->
        socket

      text == "" ->
        composer_error(socket, gettext("Write the request before splitting."))

      true ->
        socket
        |> assign(composer_split: true, composer_selected: MapSet.new())
        |> start_split(text)
    end
  end

  @doc "Back to a single request; a job in flight keeps the split."
  def unsplit(socket) do
    if socket.assigns.composer_job,
      do: socket,
      else:
        assign(socket,
          composer_split: false,
          composer_error: nil,
          composer_retry: nil,
          intake: nil,
          composer_selected: MapSet.new()
        )
  end

  @doc "The send button: a split, the answers, or a single request."
  def submit(socket, params) do
    text = String.trim(params["text"] || socket.assigns.composer_text)

    socket =
      socket
      |> with_task_edits(params)
      |> with_private_fields(params)
      |> choose_executor(params["executor"])
      |> ensure_routing()

    # The sentence the composer showed when the person pressed send.
    shown = composer_phrase(socket.assigns)

    socket =
      assign(socket, composer_answers: params["answers"] || socket.assigns.composer_answers)

    cond do
      # A second submit while the first is in flight: the job is the receipt.
      socket.assigns.composer_job ->
        socket

      is_nil(socket.assigns.repo) ->
        composer_error(socket, gettext("Select a repository before submitting."))

      attachments_pending?(socket) ->
        composer_error(socket, gettext("Wait for the files to finish or remove them."))

      text == "" ->
        composer_error(socket, gettext("Write the request before sending."))

      socket.assigns.composer_split ->
        submit_split(socket, text, params, shown)

      # The title the screen confirmed (`composer_title`, kept by the
      # change events), never the field as the send carried it.
      true ->
        start_single(socket, text, socket.assigns.composer_title, shown)
    end
  end

  @doc "Run the failed job again: the split of the same words or the remaining requests."
  def retry(socket) do
    socket = assign(socket, composer_error: nil, composer_receipt: nil)

    case {socket.assigns.composer_job, socket.assigns.composer_retry} do
      {nil, {:split, text}} ->
        start_split(socket, text)

      {nil, {:enqueue, requests} = retry} ->
        start_enqueue(socket, requests, retry_phrase(socket.assigns.repo, retry))

      _ ->
        socket
    end
  end

  @doc "Cancel the job in flight; its late result changes nothing."
  def cancel(socket), do: cancel_job(socket)

  @doc "Send the current words as one request, dropping the proposal."
  def single(socket) do
    text = String.trim(socket.assigns.composer_text)
    socket = ensure_routing(socket)
    shown = composer_phrase(socket.assigns)
    socket = assign(socket, composer_split: false, intake: nil, composer_selected: MapSet.new())

    if text == "",
      do: socket,
      else: start_single(socket, text, socket.assigns.composer_title, shown)
  end

  @doc "Dictation continues the draft: it arrives whole and has no undo."
  def dictate(socket, dictated) do
    text = with_dictated(socket.assigns.composer_text, dictated)

    socket
    |> assign(composer_text: text, composer_error: nil)
    |> invalidate_intake_if_changed(text)
  end

  @doc "A `{:composer_timeout, ref}` message: only the job with that ref is failed."
  def timeout(socket, ref) do
    case socket.assigns.composer_job do
      %{ref: ^ref, kind: kind, payload: payload} ->
        seconds = div(composer_timeout(), 1000)

        socket
        |> cancel_job()
        |> composer_error(
          gettext("%{job} did not finish in %{seconds} s. Nothing was confirmed; try again.",
            job: job_name(kind),
            seconds: seconds
          ),
          {kind, payload}
        )

      _ ->
        socket
    end
  end

  @doc """
  The `{:composer, ref}` job answered: only the current job is finished. A
  receipt reloads the board through `load`, BoardLive's own `load/2`.
  """
  def finish(socket, ref, outcome, load) do
    case socket.assigns.composer_job do
      %{ref: ^ref} = job -> finish_job(socket, job, outcome, load)
      _ -> socket
    end
  end

  @doc """
  The router reads the runner once per opening of the composer in a
  repository, never per render: a runner that does not answer costs the
  orchestrator's timeouts in the background, not in the form.
  """
  def load_routing(%{assigns: %{panel: "composer", repo: %{id: id} = repo}} = socket) do
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

  def load_routing(socket), do: socket

  @doc "The `{:composer_routing, repo_id}` read answered; another repository's answer is dropped."
  def routing_read(socket, repo_id, outcome) do
    signals =
      case outcome do
        {:ok, signals} -> signals
        {:exit, _reason} -> Signals.read(fn -> {:error, :unreachable} end)
      end

    case socket.assigns.repo do
      %{id: ^repo_id} -> put_routing(socket, signals)
      _ -> socket
    end
  end

  @doc """
  Closing a receipt whose items all landed starts the next request fresh; a
  receipt with a failure stays, so the retry is still there when the panel
  reopens.
  """
  def settle(%{assigns: %{panel: "composer", composer_receipt: %{items: items}}} = socket) do
    if Enum.any?(items, &match?({:error, _}, &1.outcome)),
      do: socket,
      else: reset(socket)
  end

  def settle(socket), do: socket

  @doc "Start the next request fresh: no draft, no job, no files."
  def reset(socket) do
    socket
    |> cancel_job()
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
      composer_private: new_private(),
      intake: nil,
      composer_executor_touched: false,
      composer_executor:
        socket.assigns.composer_routing &&
          (socket.assigns.composer_routing.suggestion.executor || Executors.default())
    )
  end

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
          composer_error(
            socket,
            gettext("Every chosen task needs a title, a description and a criterion.")
          )
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
        composer_error(
          socket,
          gettext("Answer the questions or edit the request before splitting again.")
        )

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
        body: IssueBody.render(task, spec) <> Executors.mention_suffix(),
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
        composer_error(socket, gettext("The first line becomes the title; write something."))

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
    if Executors.valid?(executor) and executor != socket.assigns.composer_executor and
         executor not in unwatched(socket.assigns.composer_routing),
       do: assign(socket, composer_executor: executor, composer_executor_touched: true),
       else: socket
  end

  # A submit before the background read answered reads the signals now.
  defp ensure_routing(%{assigns: %{composer_routing: nil, repo: %{} = repo}} = socket) do
    socket
    |> assign(composer_routing_for: repo.id)
    |> put_routing(Signals.read_for(repo))
  end

  defp ensure_routing(socket), do: socket

  defp put_routing(socket, signals) do
    routed = Routing.plan(socket.assigns.repo, %{}, nil, "composer", signals)

    socket
    |> assign(composer_routing: routed.routing)
    |> then(fn socket ->
      # A choice the owner made stays, unless no agent watches it here.
      if socket.assigns.composer_executor_touched and
           socket.assigns.composer_executor not in unwatched(routed.routing),
         do: socket,
         else: assign(socket, composer_executor: routed.executor)
    end)
  end

  defp unwatched(%{suggestion: %{unwatched: executors}}), do: executors
  defp unwatched(_routing), do: []

  defp single_requests(repo, text, title) do
    title = title || Titles.from_request(text)
    body = text <> Executors.mention_suffix()

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
        composer_error(socket, gettext("Select a repository before splitting."))

      socket.assigns.ai_status == :not_configured ->
        composer_error(
          socket,
          gettext("AI is not configured. Splitting is unavailable; send as a single request.")
        )

      true ->
        job = composer_job(:split, text, 1)
        repo = socket.assigns.repo

        socket
        |> assign(composer_job: job, composer_error: nil, composer_retry: nil, intake: nil)
        |> start_async({:composer, job.ref}, fn ->
          {:split, text, Intake.run(text, repository_digest(repo))}
        end)
    end
  end

  defp repository_digest(repo) do
    if GitHub.configured?(), do: RepoDigest.read(repo, GitHub.client())
  end

  defp start_enqueue(socket, [], _shown),
    do: composer_error(socket, gettext("Choose at least one task."))

  defp start_enqueue(socket, requests, shown) do
    socket = take_attachments(socket)
    repo = socket.assigns.repo
    client = GitHub.client()

    job =
      composer_job(:enqueue, requests, Enum.count(requests, &(not Map.has_key?(&1, :receipt))))

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
    end)
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

  # A request's own folder, kept until it is sent: a retry reuses it.
  defp new_private, do: %{@empty_private | dir: PrivateContext.new_request_dir()}

  # Only what holds something: an empty context makes no folder and no line.
  defp private_payload(socket) do
    private = socket.assigns.composer_private

    if String.trim(private.note) == "" and private.files == [] and private.folders == [] do
      nil
    else
      %{
        dir: private.dir,
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

  defp with_dictated(draft, dictated) do
    if String.trim(draft || "") == "",
      do: dictated,
      else: String.trim_trailing(draft) <> "\n" <> dictated
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

  # The same read as BoardLive's refresh_ai/1: a split wrote ai_calls rows.
  defp refresh_ai(socket), do: assign(socket, ai_status: AI.status())

  defp composer_job(kind, payload, total) do
    ref = System.unique_integer([:positive])
    Process.send_after(self(), {:composer_timeout, ref}, composer_timeout())
    %{ref: ref, kind: kind, payload: payload, total: total}
  end

  defp composer_timeout, do: Application.get_env(:agent_board, :composer_timeout_ms, 120_000)

  defp finish_job(socket, _job, {:ok, {:split, text, {:ok, result}}}, _load) do
    socket
    |> assign(composer_job: nil)
    |> show_intake_result(socket.assigns.repo, text, result)
    |> assign(composer_selected: all_indices(result.tasks))
  end

  defp finish_job(socket, _job, {:ok, {:split, text, {:error, reason}}}, _load) do
    socket
    |> assign(composer_job: nil)
    |> composer_error(split_failure(reason), {:split, text})
    |> refresh_ai()
  end

  # The words changed between what the composer showed and what was sent:
  # nothing was created; the person reads the new sentence and sends again.
  defp finish_job(socket, _job, {:ok, {:enqueue_refused, _requests, _refusal}}, _load) do
    socket
    |> assign(composer_job: nil)
    |> composer_error(
      gettext(
        "Nothing was created: the request changed before sending. Check the phrase and send again."
      )
    )
  end

  defp finish_job(socket, _job, {:ok, {:enqueue, requests, results}}, load) do
    items = Enum.map(results, fn {request, result} -> receipt_item(request, result) end)
    failed = Enum.count(items, &match?({:error, _}, &1.outcome))

    socket
    |> assign(
      composer_job: nil,
      composer_receipt: %{items: items},
      composer_retry: if(failed > 0, do: {:enqueue, keep_receipts(requests, results)}),
      composer_attachments: if(failed > 0, do: socket.assigns.composer_attachments, else: []),
      composer_private: if(failed > 0, do: socket.assigns.composer_private, else: new_private())
    )
    |> load.(socket.assigns.repo)
    |> flash_receipt(items, failed)
  end

  defp finish_job(socket, %{kind: kind, payload: payload}, {:exit, reason}, _load) do
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

  defp cancel_job(%{assigns: %{composer_job: nil}} = socket), do: socket

  defp cancel_job(%{assigns: %{composer_job: %{ref: ref}}} = socket) do
    socket
    |> cancel_async({:composer, ref})
    |> assign(composer_job: nil, composer_error: nil, composer_retry: nil)
  end

  # Keep the original requests (before files and dependency links were added).
  # A successful member belongs to this batch even if its issue later closes.
  defp keep_receipts(requests, results) do
    Enum.zip_with(requests, results, fn
      request, {_sent, {:ok, task, _outcome}} -> Map.put(request, :receipt, task)
      request, {_sent, {:error, _reason}} -> request
    end)
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

  defp all_indices([]), do: MapSet.new()
  defp all_indices(tasks), do: MapSet.new(0..(length(tasks) - 1))
end
