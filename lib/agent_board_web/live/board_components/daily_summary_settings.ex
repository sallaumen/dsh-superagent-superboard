defmodule AgentBoardWeb.BoardComponents.DailySummarySettings do
  @moduledoc """
  The "Resumo do dia" fold of Configurações: the switch and the hour of the
  summary of the day (`AgentBoard.DailySummary.settings/0`). It saves on
  change, like every field of the menu, and reads the saved settings again
  when another tab changes them (`BoardLive` sends it an update on
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
    <%!-- A save re-renders this root; the fold the owner opened stays open. --%>
    <details
      id={@id}
      class="settings-fold"
      open={@expanded}
      phx-mounted={JS.ignore_attributes("open")}
    >
      <summary>
        <span class="settings-fold-label">
          Resumo do dia <small>{fold_summary(@settings)}</small>
        </span>
        <.icon name="hero-chevron-down" class="settings-fold-chevron size-4" />
      </summary>
      <div class="settings-fold-content">
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
            /> Gerar o resumo uma vez por dia, no board e na voz
          </label>
          <label class="daily-summary-at" for="daily-summary-at">
            <span class="voice-field-label">Horário</span>
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
            Horário inválido. Use horas e minutos, como 08:00.
          </p>
          <p id="daily-summary-hint">
            Pelo relógio do Mac. Se ele estiver dormindo nesse horário, o resumo sai quando acordar, uma vez só.
          </p>
        </form>
      </div>
    </details>
    """
  end

  defp fold_summary(%{enabled: false}), do: "Desligado"
  defp fold_summary(%{at: at}), do: "Todo dia às #{DailySummary.format_at(at)}"
end
