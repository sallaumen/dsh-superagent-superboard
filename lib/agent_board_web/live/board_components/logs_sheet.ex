defmodule AgentBoardWeb.BoardComponents.LogsSheet do
  @moduledoc """
  The bottom sheet with the board's warnings and errors.

  The dialog is always mounted so `BoardPanels` can open and close it, but
  the LiveView starts reading and scheduling only while `panel=logs` is open.
  Presentation lives here; the reading, the offset state and the cap live in
  `AgentBoard.Logs` and `BoardLive`.
  """
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1]

  alias AgentBoard.Logs

  attr :sources, :list, required: true
  attr :entries, :list, required: true
  attr :status, :map, required: true
  attr :paused, :boolean, required: true
  attr :timer, :boolean, required: true

  def logs_sheet(assigns) do
    assigns =
      assigns
      |> assign(:counts, Logs.counts(assigns.entries))
      |> assign(:unreadable, unreadable?(assigns.sources, assigns.status))
      |> assign(:has_superagents, Enum.any?(assigns.sources, &(&1.kind == :superagent)))

    ~H"""
    <dialog
      id="panel-logs"
      class="board-dialog board-sheet"
      phx-hook="LogsSheet"
      aria-labelledby="logs-title"
      data-logs-timer={if @timer, do: "on", else: "off"}
      data-logs-paused={to_string(@paused)}
    >
      <div
        class="ab-logs__drag"
        data-log-drag
        role="separator"
        aria-orientation="horizontal"
        aria-label={gettext("Resize log panel")}
        aria-valuemin="180"
        tabindex="0"
      >
      </div>

      <header class="ab-logs__head">
        <div class="ab-logs__heading">
          <h2 id="logs-title">{gettext("Logs")}</h2>
          <span class="ab-meta">
            {@counts.warning} {plural(@counts.warning, "aviso", "avisos")} · {@counts.error} {plural(
              @counts.error,
              "erro",
              "erros"
            )} · {if @paused, do: "pausado", else: "ao vivo"}
          </span>
        </div>
        <div class="ab-logs__actions">
          <button
            type="button"
            class="ab-btn ab-btn--quiet ab-btn--sm"
            data-log-size="min"
            aria-label={gettext("Collapse the logs panel")}
          >
            {gettext("Collapse")}
          </button>
          <button
            type="button"
            class="ab-btn ab-btn--quiet ab-btn--sm"
            data-log-size="max"
            aria-label={gettext("Expand log panel")}
          >
            {gettext("Expand")}
          </button>
          <button
            type="button"
            class="ab-btn ab-btn--quiet ab-btn--sm"
            phx-click="logs_clear"
            disabled={@entries == []}
          >
            {gettext("Clear")}
          </button>
          <button
            type="button"
            class="ab-btn ab-btn--quiet ab-btn--sm"
            phx-click={if @paused, do: "logs_resume", else: "logs_pause"}
          >
            {if @paused, do: "Retomar", else: "Pausar"}
          </button>
          <button
            type="button"
            class="panel-close"
            phx-click="close"
            aria-label={gettext("Close logs")}
          >
            <.ico name="close" />{gettext("Close")}
          </button>
        </div>
      </header>

      <ul class="ab-logs__sources" aria-label={gettext("Log sources")}>
        <li :for={source <- @sources} class="ab-logs__source" data-status={status(@status, source.id)}>
          <span class="ab-logs__dot" aria-hidden="true"></span>
          <span class="ab-logs__source-name">{source.label}</span>
          <span class="ab-logs__source-status">{Logs.status_label(status(@status, source.id))}</span>
          <code title={source.path}>{source.path}</code>
        </li>
        <li :if={@sources == []} class="ab-logs__source" data-status="unreadable">
          <span class="ab-logs__dot" aria-hidden="true"></span>
          <span>{gettext("No source configured.")}</span>
        </li>
      </ul>

      <p :if={@has_superagents} class="ab-logs__note ab-meta">
        {gettext(
          "Superagents: only the keepalive log has a stable path; the process stdout is not read."
        )}
      </p>

      <div
        id="logs-body"
        class="ab-logs__body"
        role="log"
        aria-live="polite"
        aria-label={gettext("Warnings and Errors")}
      >
        <p :if={@entries == []} class="ab-logs__empty" role="status">
          <strong>{gettext("No recent warnings or errors.")}</strong>
          <span :if={@unreadable}>
            {gettext("One source could not be read; the reason is in the list of sources above.")}
          </span>
          <span :if={!@unreadable}>
            {gettext("The dashboard continues reading from the end of files while open.")}
          </span>
        </p>

        <ol :if={@entries != []} id="logs-list" class="ab-logs__list">
          <li
            :for={entry <- @entries}
            id={"log-entry-#{entry.seq}"}
            class="ab-logs__entry"
            data-level={entry.level}
            data-source={entry.source}
          >
            <div class="ab-logs__entry-head">
              <span class="ab-logs__time">{entry.at}</span>
              <span class="ab-logs__level">{Logs.level_label(entry.level)}</span>
              <span class="ab-logs__origin">{entry.source_label}</span>
            </div>
            <pre class="ab-logs__message">{entry.message}</pre>
            <pre :for={line <- entry.lines} class="ab-logs__continuation">{line}</pre>
          </li>
        </ol>
      </div>

      <footer class="ab-logs__foot ab-meta">
        <span>{gettext("Warnings and errors only · up to %{count} entries · incremental reading",
          count: Logs.cap()
        )}</span>
        <span :if={@paused}>{gettext("Paused: nothing is read until resumed.")}</span>
      </footer>
    </dialog>
    """
  end

  defp status(statuses, id), do: Map.get(statuses, id, :ok)

  defp unreadable?(sources, statuses) do
    Enum.any?(sources, &(status(statuses, &1.id) != :ok))
  end

  defp plural(1, one, _many), do: one
  defp plural(_count, _one, many), do: many
end
