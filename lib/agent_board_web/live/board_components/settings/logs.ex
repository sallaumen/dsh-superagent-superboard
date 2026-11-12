defmodule AgentBoardWeb.BoardComponents.Settings.Logs do
  @moduledoc "Filters, source health and live log entries in Settings."
  use AgentBoardWeb, :html

  alias AgentBoard.Logs

  attr :sources, :list, required: true
  attr :entries, :list, required: true
  attr :status, :map, required: true
  attr :paused, :boolean, required: true
  attr :timer, :boolean, required: true

  attr :filters, :map, required: true

  def section(assigns) do
    entries = Enum.filter(assigns.entries, &matches?(&1, assigns.filters))

    assigns =
      assigns
      |> assign(:visible_entries, entries)
      |> assign(:counts, Logs.counts(entries))
      |> assign(:unreadable, unreadable?(assigns.sources, assigns.status))
      |> assign(:has_superagents, Enum.any?(assigns.sources, &(&1.kind == :superagent)))

    ~H"""
    <section
      id="settings-logs"
      class="settings-pane settings-pane--logs"
      aria-labelledby="logs-title"
      data-logs-timer={if @timer, do: "on", else: "off"}
      data-logs-paused={to_string(@paused)}
    >
      <h3 id="logs-title">{gettext("Logs")}</h3>
      <div class="ab-logs__head">
        <p class="ab-meta" role="status">
          {ngettext("%{count} warning", "%{count} warnings", @counts.warning)} · {ngettext(
            "%{count} error",
            "%{count} errors",
            @counts.error
          )} · {if @paused, do: gettext("paused"), else: gettext("live")}
        </p>
        <div class="ab-logs__actions">
          <button type="button" class="ab-btn ab-btn--quiet ab-btn--sm" phx-click="logs_refresh">
            {gettext("Refresh")}
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
            {if @paused, do: gettext("Resume"), else: gettext("Pause")}
          </button>
        </div>
      </div>

      <form id="logs-filters" class="ab-logs__filters" phx-change="logs_filter">
        <label>
          {gettext("Source")}
          <select name="source">
            <option value="" selected={!@filters["source"]}>{gettext("All sources")}</option>
            <option
              :for={source <- @sources}
              value={source.id}
              selected={@filters["source"] == source.id}
            >
              {source.label}
            </option>
          </select>
        </label>
        <label>
          {gettext("Severity")}
          <select name="level">
            <option value="" selected={!@filters["level"]}>{gettext("All levels")}</option>
            <option
              :for={level <- [:warning, :error]}
              value={level}
              selected={@filters["level"] == to_string(level)}
            >
              {Logs.level_label(level)}
            </option>
          </select>
        </label>
      </form>

      <details class="ab-logs__details" open={@unreadable}>
        <summary>{gettext("Log sources")}</summary>
        <ul class="ab-logs__sources" aria-label={gettext("Log sources")}>
          <li
            :for={source <- @sources}
            class="ab-logs__source"
            data-status={status(@status, source.id)}
          >
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
      </details>

      <div
        phx-hook="LogFeed"
        id="logs-body"
        class="ab-logs__body"
        role="log"
        tabindex="0"
        aria-live="polite"
        aria-label={gettext("Warnings and Errors")}
      >
        <p :if={@visible_entries == []} class="ab-logs__empty" role="status">
          <strong>{if @entries != [],
            do: gettext("No entries match these filters."),
            else: gettext("No recent warnings or errors.")}</strong>
          <span :if={@unreadable}>
            {gettext("One source could not be read; the reason is in the list of sources above.")}
          </span>
        </p>

        <ol :if={@visible_entries != []} id="logs-list" class="ab-logs__list">
          <li
            :for={entry <- @visible_entries}
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
      </footer>
    </section>
    """
  end

  defp matches?(entry, filters) do
    (is_nil(filters["source"]) or entry.source == filters["source"]) and
      (is_nil(filters["level"]) or to_string(entry.level) == filters["level"])
  end

  defp status(statuses, id), do: Map.get(statuses, id, :ok)

  defp unreadable?(sources, statuses) do
    Enum.any?(sources, &(status(statuses, &1.id) != :ok))
  end
end
