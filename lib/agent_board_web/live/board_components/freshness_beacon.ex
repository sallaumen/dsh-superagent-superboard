defmodule AgentBoardWeb.BoardComponents.FreshnessBeacon do
  @moduledoc "The one place that says whether what is on screen is current."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1, status_mark: 1]

  attr :freshness, :map, required: true
  attr :tz_offset, :integer, default: 0

  def beacon(assigns) do
    assigns =
      assigns
      |> assign(:age_text, age_text(assigns.freshness, assigns.tz_offset))

    ~H"""
    <details id="sync-status" class="ab-sync">
      <summary
        class="ab-beacon"
        data-state={@freshness.state}
        aria-label={gettext("Sync status: %{status}", status: label(@freshness.state))}
      >
        <span class="ab-beacon__normal">
          <.glyph :if={@freshness.state == :live} kind={:run} live />
          <.glyph :if={@freshness.state in [:delayed, :offline]} kind={:stale} />
          <.glyph :if={@freshness.state == :unknown} kind={:unknown} />
          <i :if={@freshness.state == :reconnecting} class="ab-spin" aria-hidden="true"></i>
          <b>{label(@freshness.state)}</b>
          <span class="ab-beacon__age" data-age={@freshness.age_sec}>{@age_text}</span>
        </span>
        <span class="ab-beacon__reconnect">
          <i class="ab-spin" aria-hidden="true"></i>
          <b>{gettext("Reconnecting")}</b>
          <span class="ab-beacon__age">{gettext("data from %{time}",
            time: time(@freshness.at, @tz_offset)
          )}</span>
        </span>
      </summary>

      <div class="ab-sync-pop" role="region" aria-label={gettext("Sync details")}>
        <h4>{title(@freshness)}</h4>
        <div class="ab-meta">{note(@freshness, @tz_offset)}</div>
        <dl>
          <div :for={source <- @freshness.sources} class="ab-sync-pop__source">
            <dt>{source_label(source)}</dt>
            <dd>
              <.status_mark kind={source.kind} word={source_word(source)} />
              <span class="ab-meta">{source_detail(source, @tz_offset)}</span>
            </dd>
          </div>
        </dl>
        <p class="ab-meta ab-sync-pop__cadence">
          {gettext("GitHub is checked every 5 minutes; the agent process, every 10 seconds.")}
        </p>
      </div>
    </details>
    """
  end

  defp label(:live), do: gettext("Live")
  defp label(:delayed), do: gettext("Delayed")
  defp label(:reconnecting), do: gettext("Reconnecting")
  defp label(:offline), do: gettext("No connection")
  defp label(:unknown), do: gettext("No data yet")

  defp title(%{state: :live}), do: gettext("Everything is current")
  defp title(%{state: :delayed}), do: gettext("Data is delayed")
  defp title(%{state: :reconnecting}), do: gettext("Reconnecting")
  defp title(%{state: :offline}), do: gettext("No connection to GitHub")
  defp title(_), do: gettext("No data yet")

  defp note(%{state: :live}, _offset),
    do: gettext("GitHub, the agent process, and the local queue responded on schedule.")

  defp note(%{state: :delayed}, _offset),
    do: gettext("One source is late; the times below are paused.")

  defp note(%{state: :reconnecting}, _offset),
    do: gettext("The board connection dropped. The screen shows the last known state.")

  defp note(%{state: :offline, at: nil}, _offset),
    do:
      gettext(
        "No sync has succeeded. Saved data is the last received; it may have changed elsewhere."
      )

  defp note(%{state: :offline, at: at}, offset),
    do:
      gettext("The last complete data is from %{time}. It may have changed elsewhere.",
        time: time(at, offset)
      )

  defp note(_, _offset), do: gettext("No sync has completed for this repository yet.")

  defp source_label(%{code: :queue_current}), do: gettext("Local queue")

  defp source_label(%{code: code})
       when code in [
              :github_waiting,
              :github_failed,
              :github_errors,
              :github_delayed,
              :github_current
            ],
       do: gettext("GitHub (PRs, CI)")

  defp source_label(_), do: gettext("Agent process")

  defp source_word(%{kind: :unknown}), do: gettext("No data")
  defp source_word(%{kind: :blocked, code: :github_failed}), do: gettext("Failed")
  defp source_word(%{kind: :blocked}), do: gettext("Unavailable")
  defp source_word(%{kind: :stale, code: :github_errors}), do: gettext("With errors")
  defp source_word(%{kind: :stale, code: :github_delayed}), do: gettext("Delayed")
  defp source_word(%{kind: :stale}), do: gettext("No signal")
  defp source_word(_), do: "OK"

  defp source_detail(%{code: :queue_current}, _offset), do: gettext("checked now")
  defp source_detail(%{code: :github_waiting}, _offset), do: gettext("waiting for first sync")

  defp source_detail(%{code: :github_failed, attempted_at: at}, offset),
    do: gettext("last attempt at %{time}", time: time(at, offset))

  defp source_detail(%{code: :github_errors, error_count: n}, _offset),
    do: ngettext("%{count} error in the last sync", "%{count} errors in the last sync", n)

  defp source_detail(%{code: :github_delayed, age_sec: age}, _offset),
    do: gettext("last data %{age}", age: ago(age))

  defp source_detail(%{code: :github_current, age_sec: age}, _offset),
    do: gettext("%{age} ago", age: short(age))

  defp source_detail(%{code: :agent_stale, age_sec: age}, _offset),
    do: gettext("%{age} ago; a task is running without a heartbeat", age: short(age))

  defp source_detail(%{code: :agent_empty}, _offset), do: gettext("checked now; no tickets yet")

  defp source_detail(%{code: :agent_current, age_sec: age}, _offset),
    do: gettext("checked now; last ticket %{age}", age: ago(age))

  defp source_detail(_, _offset), do: gettext("the executor database did not respond")

  defp age_text(%{state: :live, age_sec: sec}, _offset) when is_integer(sec),
    do: gettext("%{age} ago", age: short(sec))

  defp age_text(%{state: :live}, _offset), do: gettext("now")

  defp age_text(%{state: state, at: nil}, _offset) when state in [:delayed, :offline],
    do: gettext("data from unknown time")

  defp age_text(%{state: state} = freshness, offset) when state in [:delayed, :offline] do
    gettext("data from %{time} · %{age}",
      time: time(freshness.at, offset),
      age: ago(freshness.age_sec)
    )
  end

  defp age_text(%{state: :reconnecting, at: nil}, _offset),
    do: gettext("data from unknown time")

  defp age_text(%{state: :reconnecting} = freshness, offset),
    do: gettext("data from %{time}", time: time(freshness.at, offset))

  defp age_text(_freshness, _offset), do: gettext("waiting for first sync")

  defp time(nil, _offset), do: "—"
  defp time(%DateTime{} = at, offset), do: AgentBoardWeb.Time.local_time(at, offset)

  defp short(nil), do: gettext("now")
  defp short(sec) when sec < 60, do: "#{sec} s"
  defp short(sec) when sec < 3600, do: "#{div(sec, 60)} min"
  defp short(sec), do: "#{div(sec, 3600)} h"

  defp ago(nil), do: gettext("age unknown")
  defp ago(sec) when sec < 60, do: gettext("%{count} s ago", count: sec)
  defp ago(sec) when sec < 3600, do: gettext("%{count} min ago", count: div(sec, 60))
  defp ago(sec) when sec < 86_400, do: gettext("%{count} h ago", count: div(sec, 3600))
  defp ago(sec), do: gettext("%{count} d ago", count: div(sec, 86_400))
end
