defmodule AgentBoardWeb.BoardComponents.DispatchSettings do
  @moduledoc """
  The dispatch numbers in Settings: monthly cap, per-task ceiling, Codex
  timeout, quota reserve and the two models. Every save is one
  `change_setting` action per key, so the registry sees the same writes as
  the voice and the API; an invalid number saves nothing.
  """
  use AgentBoardWeb, :live_component

  alias AgentBoard.{Actions, Runners}

  @keys [
    "dispatch_monthly_usd",
    "dispatch_task_usd",
    "dispatch_codex_timeout_minutes",
    "dispatch_reserve_percent",
    "dispatch_claude_model",
    "dispatch_codex_model",
    "dsh_repositories"
  ]

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       snapshot: Runners.snapshot(),
       error: nil,
       saved: false
     )}
  end

  @impl true
  def update(assigns, socket) do
    was_active = socket.assigns[:active] || false
    socket = assign(socket, assigns)

    if assigns.active and not was_active do
      {:ok, assign(socket, snapshot: Runners.snapshot(), error: nil, saved: false)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form
      id={"dispatch-settings-form-#{@id}"}
      phx-submit="save"
      phx-target={@myself}
      phx-auto-recover="ignore"
      class="dispatch-settings"
    >
      <div class="dispatch-settings__body">
        <div class="dispatch-settings__heading">
          <h4>{gettext("Limits")}</h4>
          <p>{gettext("USD limits apply to Claude Code. The Codex quota appears separately.")}</p>
        </div>
        <div class="dispatch-settings__grid">
          <label>
            <span>{gettext("Monthly · US$")}</span>
            <input
              name="monthly_usd"
              type="number"
              min="0"
              step="0.01"
              value={number(@snapshot.monthly_usd)}
              aria-describedby="dispatch-monthly-hint"
              required
            />
          </label>
          <label>
            <span>{gettext("Per task · US$")}</span>
            <input
              name="task_usd"
              type="number"
              min="0"
              step="0.01"
              value={number(@snapshot.task_usd)}
              required
            />
          </label>
          <label>
            <span>{gettext("Time per task · min")}</span>
            <input
              name="codex_timeout_minutes"
              type="number"
              min="1"
              step="1"
              value={@snapshot.codex_timeout_minutes}
              required
            />
          </label>
        </div>
        <p id="dispatch-monthly-hint" class="ab-meta">
          {gettext("Use 0 for no monthly limit. The maximum time applies to Codex.")}
        </p>

        <div :if={is_number(@snapshot.spent_usd)} class="dispatch-settings__usage">
          <div>
            <span>{gettext("Claude Code · used this month")}</span>
            <strong>{money(@snapshot.spent_usd)}{monthly_limit(@snapshot.monthly_usd)}</strong>
          </div>
          <progress
            :if={@snapshot.monthly_usd > 0}
            value={min(@snapshot.spent_usd, @snapshot.monthly_usd)}
            max={@snapshot.monthly_usd}
            aria-label={gettext("Claude Code monthly limit usage")}
          ></progress>
        </div>
        <p :if={not is_number(@snapshot.spent_usd)} class="ab-meta">
          {gettext("Claude Code monthly usage is unavailable: some runs have unknown prices.")}
        </p>

        <div class="dispatch-settings__quota">
          <div class="dispatch-settings__quota-head">
            <h4>{gettext("Codex · weekly quota")}</h4><strong :if={@snapshot.quota}>{percent(
              @snapshot.quota.used_percent
            )}% {gettext("used")}</strong>
          </div>
          <progress
            :if={@snapshot.quota}
            value={@snapshot.quota.used_percent}
            max="100"
            aria-label={gettext("Codex weekly quota used")}
          ></progress>
          <p :if={is_nil(@snapshot.quota)}>
            {gettext("No recent quota reading. The board does not treat it as zero.")}
          </p>
          <label>
            <span>{gettext("Weekly quota reserve · %")}</span>
            <input
              name="reserve_percent"
              type="number"
              min="0"
              max="100"
              step="1"
              value={@snapshot.reserve_percent}
              required
            />
          </label>
        </div>

        <details class="dispatch-settings__advanced">
          <summary>{gettext("Models and integration")}</summary>
          <div class="dispatch-settings__advanced-body">
            <label>
              <span>{gettext("Claude Code model")}</span>
              <input name="claude_model" value={Runners.claude_model()} required />
            </label>
            <label>
              <span>{gettext("Codex model")}</span>
              <input name="codex_model" value={Runners.codex_model()} required />
            </label>
            <label>
              <span>{gettext("DeepSeek repositories (comma-separated)")}</span>
              <input
                name="dsh_repositories"
                value={Enum.join(@snapshot.dsh_repositories, ", ")}
                placeholder="sallaumen/arena-rogue, sallaumen/o_colmex"
              />
            </label>
            <p class="ab-meta">
              Claude Code:
              <code>{Runners.claude_bin()}</code> {if Runners.ready?("claude"),
                do: gettext("ready"),
                else: gettext("not found or no permission")}
            </p>
            <p class="ab-meta">
              Codex:
              <code>{Runners.codex_bin()}</code> {if Runners.ready?("codex"),
                do: gettext("ready"),
                else: gettext("not found or no permission")}
            </p>
          </div>
        </details>
      </div>

      <p :if={@error} class="settings-error" role="alert">{@error}</p>
      <p :if={@saved} class="settings-saved" role="status">{gettext("Caps saved.")}</p>

      <div class="dispatch-settings__actions">
        <button type="reset" class="ab-btn">{gettext("Discard")}</button>
        <button type="submit" class="ab-btn ab-btn--primary" phx-disable-with={gettext("Saving…")}>{gettext(
          "Save limits"
        )}</button>
      </div>
    </form>
    """
  end

  @impl true
  def handle_event("save", params, socket) do
    case validate(params) do
      {:ok, values} ->
        Enum.each(@keys, fn key ->
          :ok =
            Actions.run(:change_setting, %{setting: key, value: values[key]}, Actions.owner(:ui))
        end)

        {:noreply, assign(socket, snapshot: Runners.snapshot(), error: nil, saved: true)}

      {:error, message} ->
        {:noreply, assign(socket, error: message, saved: false)}
    end
  end

  defp validate(params) do
    with {:ok, monthly} <- float(params["monthly_usd"], gettext("monthly budget")),
         {:ok, task} <- float(params["task_usd"], gettext("per-task ceiling")),
         {:ok, timeout} <- integer(params["codex_timeout_minutes"], gettext("Codex timeout"), 1),
         {:ok, reserve} <- integer(params["reserve_percent"], gettext("quota reserve"), 0),
         true <- reserve <= 100 || {:error, gettext("Quota reserve must be between 0 and 100%.")},
         claude = String.trim(params["claude_model"] || ""),
         codex = String.trim(params["codex_model"] || ""),
         true <- claude != "" || {:error, gettext("Choose a Claude Code model.")},
         true <- codex != "" || {:error, gettext("Choose a Codex model.")} do
      {:ok,
       %{
         "dispatch_monthly_usd" => number(monthly),
         "dispatch_task_usd" => number(task),
         "dispatch_codex_timeout_minutes" => Integer.to_string(timeout),
         "dispatch_reserve_percent" => Integer.to_string(reserve),
         "dispatch_claude_model" => claude,
         "dispatch_codex_model" => codex,
         "dsh_repositories" => String.trim(params["dsh_repositories"] || "")
       }}
    else
      {:error, message} -> {:error, message}
      false -> {:error, gettext("Check the dispatch numbers.")}
    end
  end

  defp float(value, label) do
    case Float.parse(to_string(value || "")) do
      {number, _} when number >= 0 ->
        {:ok, number}

      _ ->
        {:error,
         gettext("%{label} must be a number greater than or equal to zero.", label: label)}
    end
  end

  defp integer(value, label, min) do
    case Integer.parse(to_string(value || "")) do
      {number, ""} when number >= min ->
        {:ok, number}

      _ ->
        {:error,
         gettext("%{label} must be an integer greater than or equal to %{min}.",
           label: label,
           min: min
         )}
    end
  end

  defp number(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp number(value), do: to_string(value)

  defp monthly_limit(value) when value > 0,
    do: gettext(" of %{amount}", amount: money(value))

  defp monthly_limit(_value), do: gettext(" · no limit")

  defp money(value) do
    separator = if Gettext.get_locale(AgentBoardWeb.Gettext) == "pt_BR", do: ",", else: "."
    "US$ " <> (value |> number() |> String.replace(".", separator))
  end

  defp percent(value) when is_float(value),
    do: value |> :erlang.float_to_binary(decimals: 0) |> String.replace(".", ",")

  defp percent(value), do: to_string(value)
end
