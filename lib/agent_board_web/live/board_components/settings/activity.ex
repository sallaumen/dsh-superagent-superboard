defmodule AgentBoardWeb.BoardComponents.Settings.Activity do
  @moduledoc """
  Settings → System → Activity: the last twenty events, without repeating the
  same read twenty times.

  Consecutive reads of one repository with the same counts become one row
  ("n leituras sem mudança") with a disclosure. Reads whose error count never
  changes become one halt row with "Ver os erros"; the details are read only
  when the owner asks. When every timestamp is ahead of the board clock, one
  stale note explains it instead of twenty unknown stamps.
  """
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]

  alias AgentBoard.Board
  alias AgentBoardWeb.Time

  @future_margin_seconds 60

  attr :events, :list, default: []
  attr :repo, :map, default: nil
  attr :tz_offset, :integer, default: 0

  @impl true
  def mount(socket) do
    {:ok, assign(socket, errors: nil, errors_loading: false, errors_for: nil)}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    repo_id = assigns[:repo] && assigns.repo.id

    if socket.assigns[:errors_for] && socket.assigns.errors_for != repo_id do
      {:ok, assign(socket, errors: nil, errors_loading: false)}
    else
      {:ok, assign(socket, :errors_for, repo_id)}
    end
  end

  @impl true
  def handle_event("show_errors", _params, socket) do
    if socket.assigns.repo do
      repo = socket.assigns.repo

      {:noreply,
       socket
       |> assign(errors_loading: true)
       |> start_async(:errors, fn ->
         Board.events(repo, 200)
         |> Enum.filter(&String.ends_with?(&1.kind || "", "_error"))
         |> Enum.uniq_by(&{&1.kind, &1.payload["reason"]})
         |> Enum.take(30)
       end)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("hide_errors", _params, socket),
    do: {:noreply, assign(socket, errors: nil, errors_loading: false)}

  @impl true
  def handle_async(:errors, {:ok, errors}, socket),
    do: {:noreply, assign(socket, errors: errors, errors_loading: false)}

  def handle_async(:errors, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, errors_loading: false)}

  @impl true
  def render(assigns) do
    future? = future?(assigns.events)
    rows = rows(assigns.events)

    assigns =
      assigns
      |> assign(:future?, future?)
      |> assign(:rows, rows)

    ~H"""
    <section id={@id} class="settings-activity" aria-labelledby="settings-activity-title">
      <header class="settings-activity__head">
        <h4 id="settings-activity-title">{gettext("Activity")}</h4>
        <p class="ab-meta">{gettext("Last 20 events")}</p>
      </header>

      <p :if={@events == []} class="ab-meta" role="status">
        {gettext("No activity recorded for this project yet.")}
      </p>

      <p :if={@future?} class="settings-activity__future" role="status">
        {gettext(
          "All 20 events are ahead of the board clock. This is probably a timezone mistake when they were recorded. The list keeps its order, but the times are not shown."
        )}
      </p>

      <ul :if={@rows != []} class="settings-activity__list" aria-label={gettext("Recent activity")}>
        <li :for={row <- @rows} class={["settings-activity__row", activity_tone(row)]}>
          <.glyph kind={activity_glyph(row)} />

          <div class="settings-activity__body">
            <p class="settings-activity__line">{activity_line(row)}</p>
            <p :if={activity_meta(row)} class="ab-meta">{activity_meta(row)}</p>

            <details :if={row.type == :unchanged} class="settings-activity__more">
              <summary>{gettext("Show")}</summary>
              <ul>
                <li :for={event <- row.events}>
                  <time datetime={DateTime.to_iso8601(event.inserted_at)}>
                    {if @future?, do: "—", else: ago(event.inserted_at)}
                  </time>
                  <span>{counts(event)}</span>
                </li>
              </ul>
            </details>
          </div>

          <span class="settings-activity__time">
            {if @future?, do: "—", else: ago(row.latest.inserted_at)}
          </span>

          <button
            :if={row.type == :errors}
            type="button"
            class="ab-btn ab-btn--sm ab-btn--quiet settings-activity__errors"
            phx-click="show_errors"
            phx-target={@myself}
            disabled={@errors_loading}
          >
            {if @errors_loading, do: gettext("Reading…"), else: gettext("See the errors")}
          </button>
        </li>
      </ul>

      <div
        :if={@errors}
        class="settings-activity__error-list"
        role="region"
        aria-label={gettext("Errors in the recent reads")}
        aria-live="polite"
        aria-atomic="true"
      >
        <div class="settings-activity__error-head">
          <strong>{gettext("Errors in the recent reads")}</strong>
          <button
            type="button"
            class="ab-btn ab-btn--sm ab-btn--quiet"
            phx-click="hide_errors"
            phx-target={@myself}
          >
            {gettext("Close")}
          </button>
        </div>
        <p :if={@errors == []} class="ab-meta">
          {gettext("The reasons are not in the last 200 events.")}
        </p>
        <ul>
          <li :for={error <- @errors}>
            <code>{error.kind}</code>
            <span>{error.payload["reason"] || gettext("Reason not recorded")}</span>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  # -- rows -------------------------------------------------------------------

  defp rows(events) do
    events
    |> Enum.chunk_by(fn event ->
      if event.kind == "sync", do: {:read, event.subject}, else: {:other, event.id}
    end)
    |> Enum.flat_map(fn chunk ->
      case hd(chunk).kind do
        "sync" -> subject_rows(chunk)
        _kind -> Enum.map(chunk, &other_row/1)
      end
    end)
  end

  defp other_row(%{kind: "sync_error"} = event), do: %{type: :sync_error, latest: event}
  defp other_row(%{kind: "issues_unavailable"} = event), do: %{type: :warning, latest: event}

  defp other_row(%{kind: kind} = event) when is_binary(kind) do
    if String.ends_with?(kind, "_error"),
      do: %{type: :item_error, latest: event},
      else: %{type: :other, latest: event}
  end

  defp other_row(event), do: %{type: :other, latest: event}

  defp subject_rows([]), do: []

  defp subject_rows(events) do
    {errors, reads} = Enum.split_with(events, &(error_count(&1) > 0))
    error_values = Enum.map(errors, &error_count/1)

    if length(errors) > 1 and Enum.uniq(error_values) == [hd(error_values)] do
      [
        %{
          type: :errors,
          latest: hd(errors),
          reads: length(errors),
          errors: hd(error_values)
        }
        | non_error_rows(reads)
      ]
    else
      non_error_rows(reads) ++ Enum.map(errors, &%{type: :read_error, latest: &1})
    end
  end

  defp non_error_rows(reads) do
    reads
    |> Enum.chunk_by(&signature/1)
    |> Enum.flat_map(fn chunk ->
      [first | _] = chunk

      cond do
        length(chunk) > 1 and commits(first) == 0 ->
          [%{type: :unchanged, latest: first, events: chunk}]

        commits(first) > 0 ->
          [%{type: :changed, latest: first, commits: commits(first)}]

        true ->
          [%{type: :read, latest: first}]
      end
    end)
  end

  defp signature(event) do
    {
      event.payload["issues"],
      event.payload["pulls"],
      error_count(event),
      commits(event)
    }
  end

  defp error_count(%{payload: payload}) when is_map(payload), do: payload["errors"] || 0
  defp error_count(_event), do: 0

  defp commits(%{payload: payload}) when is_map(payload), do: payload["commits"] || 0
  defp commits(_event), do: 0

  # -- presentation -----------------------------------------------------------

  defp activity_glyph(%{type: :errors}), do: :blocked
  defp activity_glyph(%{type: :read_error}), do: :blocked
  defp activity_glyph(%{type: :sync_error}), do: :blocked
  defp activity_glyph(%{type: :item_error}), do: :blocked
  defp activity_glyph(%{type: :warning}), do: :stale
  defp activity_glyph(%{type: :changed}), do: :run
  defp activity_glyph(_row), do: :queue

  defp activity_tone(%{type: type})
       when type in [:errors, :read_error, :sync_error, :item_error],
       do: "is-halt"

  defp activity_tone(%{type: :warning}), do: "is-stale"
  defp activity_tone(%{type: :changed}), do: "is-agent"
  defp activity_tone(_row), do: "is-muted"

  defp activity_line(%{type: :errors} = row) do
    ngettext(
      "%{count} error on every read of %{subject}",
      "%{count} errors on every read of %{subject}",
      row.errors,
      count: row.errors,
      subject: row.latest.subject
    )
  end

  defp activity_line(%{type: :sync_error} = row) do
    text = gettext("Reading %{subject} failed", subject: row.latest.subject)
    reason = reason(row.latest)
    if reason, do: text <> ": #{reason}", else: text
  end

  defp activity_line(%{type: :item_error} = row) do
    gettext("Error while reading %{subject}", subject: row.latest.subject)
  end

  defp activity_line(%{type: :warning} = row) do
    gettext("Reading %{subject} had a warning", subject: row.latest.subject)
  end

  defp activity_line(%{type: :other} = row),
    do: gettext("%{kind} on %{subject}", kind: row.latest.kind, subject: row.latest.subject)

  defp activity_line(%{type: :unchanged} = row) do
    ngettext(
      "%{count} read without change",
      "%{count} reads without change",
      length(row.events),
      count: length(row.events)
    )
  end

  defp activity_line(%{type: :changed} = row) do
    ngettext(
      "Read brought %{count} new commit",
      "Read brought %{count} new commits",
      row.commits,
      count: row.commits
    )
  end

  defp activity_line(%{type: :read_error} = row) do
    ngettext(
      "Read had %{count} error",
      "Read had %{count} errors",
      error_count(row.latest),
      count: error_count(row.latest)
    )
  end

  defp activity_line(%{type: :read} = row),
    do: gettext("Read %{subject}", subject: row.latest.subject)

  defp activity_meta(%{type: :errors} = row) do
    gettext("The same %{count} repeat in %{reads} reads.",
      count: row.errors,
      reads: row.reads
    )
  end

  defp activity_meta(%{type: :unchanged} = row), do: counts(row.latest)

  defp activity_meta(%{type: type} = row) when type in [:read, :changed, :read_error],
    do: counts(row.latest)

  defp activity_meta(%{type: type} = row) when type in [:sync_error, :item_error, :warning],
    do: reason(row.latest)

  defp activity_meta(_row), do: nil

  defp reason(%{payload: payload}) when is_map(payload) do
    case payload["reason"] do
      nil -> nil
      text -> text |> to_string() |> truncate()
    end
  end

  defp reason(_event), do: nil

  defp truncate(text) do
    if String.length(text) > 120 do
      String.slice(text, 0, 119) <> "…"
    else
      text
    end
  end

  defp counts(%{payload: payload}) do
    issues = payload["issues"] || 0
    pulls = payload["pulls"] || 0
    gettext("%{issues} issues · %{pulls} PRs", issues: issues, pulls: pulls)
  end

  defp ago(nil), do: "—"

  defp ago(at), do: Time.ago(Time.age_seconds(at, DateTime.utc_now()))

  defp future?([]), do: false
  defp future?(events), do: Enum.all?(events, &future_time?/1)

  defp future_time?(%{inserted_at: nil}), do: false

  defp future_time?(%{inserted_at: at}) do
    DateTime.compare(at, DateTime.add(DateTime.utc_now(), @future_margin_seconds, :second)) ==
      :gt
  end
end
