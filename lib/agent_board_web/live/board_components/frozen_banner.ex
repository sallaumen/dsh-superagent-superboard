defmodule AgentBoardWeb.BoardComponents.FrozenBanner do
  @moduledoc "The banner that tells the board is showing saved data, never current data."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1]
  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]

  attr :freshness, :map, required: true
  attr :tz_offset, :integer, default: 0

  def frozen_banner(assigns) do
    ~H"""
    <div :if={@freshness.frozen?} class="ab-frozen" role="status">
      <.glyph kind={:stale} />
      <span :if={@freshness.at}>
        <strong>{gettext("Showing what we knew at %{time}.", time: time(@freshness.at, @tz_offset))}</strong>
        {gettext("Timers and counts are frozen; the agent may have made progress.")}
      </span>
      <span :if={is_nil(@freshness.at)}>
        <strong>{gettext("Showing last saved data.")}</strong>
        {gettext("We don't know the last sync time; timers and counters are stopped.")}
      </span>
      <span class="ab-top__spacer"></span>
      <button type="button" class="ab-btn ab-btn--sm" phx-click="sync_now">
        <.ico name="retry" />{gettext("Try now")}
      </button>
    </div>

    <div :if={not @freshness.frozen?} id="reconnect-banner" class="ab-frozen" role="status">
      <.glyph kind={:stale} />
      <span :if={@freshness.at}>
        <strong>{gettext("Reconnecting.")}</strong>
        {gettext("Showing what we knew at %{time}; timers are frozen.",
          time: time(@freshness.at, @tz_offset)
        )}
      </span>
      <span :if={is_nil(@freshness.at)}>
        <strong>{gettext("Reconnecting.")}</strong> {gettext(
          "Showing last saved data; time is stopped."
        )}
      </span>
      <span class="ab-top__spacer"></span>
      <button type="button" class="ab-btn ab-btn--sm" phx-click="sync_now">
        <.ico name="retry" />{gettext("Try now")}
      </button>
    </div>
    """
  end

  defp time(nil, _offset), do: "—"
  defp time(%DateTime{} = at, offset), do: AgentBoardWeb.Time.local_time(at, offset)
end
