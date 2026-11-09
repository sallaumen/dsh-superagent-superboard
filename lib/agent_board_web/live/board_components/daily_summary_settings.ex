defmodule AgentBoardWeb.BoardComponents.DailySummarySettings do
  @moduledoc """
  The Daily Summary block inside Settings → Voice and summary: the switch and
  the hour (`AgentBoard.DailySummary.settings/0`). It saves on change, like
  every field of the menu, and reads the saved settings again when another tab
  changes them (`BoardLive` sends it an update on
  `{:setting_changed, "daily_summary_" <> _}`).

  The form mirrors saved settings, so it opts out of form recovery
  (`phx-auto-recover="ignore"`, `docs/maintainer-contract.md`, "The voice").
  """
  use AgentBoardWeb, :live_component

  alias AgentBoard.{Actions, DailySummary}

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(Map.take(assigns, [:id, :expanded]))
     |> assign(settings: DailySummary.settings(), error: nil)}
  end

  @impl true
  def handle_event("save", params, socket) do
    form = Map.take(params, ["enabled", "at"])
    change = %{setting: "daily_summary", value: form}

    case Actions.run(:change_setting, change, Actions.owner(:ui)) do
      :ok -> {:noreply, assign(socket, settings: DailySummary.settings(), error: nil)}
      {:error, _reason} -> {:noreply, assign(socket, error: :invalid_time)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="daily-summary" aria-labelledby={"#{@id}-title"}>
      <h4 id={"#{@id}-title"}>{gettext("Daily summary")}</h4>
      <p class="daily-summary__state">{fold_summary(@settings)}</p>

      <form
        id="daily-summary-form"
        class="daily-summary-form"
        phx-change="save"
        phx-submit="save"
        phx-target={@myself}
        phx-auto-recover="ignore"
      >
        <input type="hidden" name="enabled" value="false" />
        <label class="voice-toggle">
          <input
            id="daily-summary-enabled"
            type="checkbox"
            name="enabled"
            value="true"
            checked={@settings.enabled}
          /> {gettext("Prepare a summary every day")}
        </label>
        <p class="voice-note">
          {gettext("It appears on the board and is read aloud.")}
        </p>

        <label class="daily-summary-at" for="daily-summary-at">
          <span class="voice-field-label">{gettext("Every day at")}</span>
          <input
            id="daily-summary-at"
            type="time"
            name="at"
            step="60"
            required
            value={DailySummary.format_at(@settings.at)}
            disabled={not @settings.enabled}
            aria-describedby="daily-summary-hint"
          />
        </label>
        <p :if={@error} class="daily-summary-error" role="alert">
          {gettext("Invalid schedule. Use hours and minutes, such as 08:00.")}
        </p>
        <p id="daily-summary-hint" class="voice-note">
          {gettext(
            "Based on the Mac clock. If it is asleep at that time, the summary is generated once when it wakes up."
          )}
        </p>
      </form>
    </section>
    """
  end

  defp fold_summary(%{enabled: false}), do: gettext("Off")

  defp fold_summary(%{at: at}),
    do: gettext("Every day at %{time}", time: DailySummary.format_at(at))
end
