defmodule AgentBoardWeb.BoardComponents.DispatchSettings do
  @moduledoc """
  The dispatch numbers in Configurações: monthly cap, per-task ceiling, Codex
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
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl true
  def render(assigns) do
    ~H"""
    <form
      id={"dispatch-settings-form-#{@id}"}
      phx-submit="save"
      phx-target={@myself}
      class="dispatch-settings"
    >
      <div class="dispatch-settings__grid">
        <label>
          <span>Orçamento mensal (US$; 0 = sem teto)</span>
          <input
            name="monthly_usd"
            type="number"
            min="0"
            step="0.01"
            value={number(@snapshot.monthly_usd)}
            required
          />
        </label>
        <label>
          <span>Teto por tarefa (US$)</span>
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
          <span>Codex: tempo máximo (min)</span>
          <input
            name="codex_timeout_minutes"
            type="number"
            min="1"
            step="1"
            value={@snapshot.codex_timeout_minutes}
            required
          />
        </label>
        <label>
          <span>Reserva da cota semanal (%)</span>
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
        <label>
          <span>Modelo do Claude Code</span>
          <input name="claude_model" value={Runners.claude_model()} required />
        </label>
        <label>
          <span>Modelo do Codex</span>
          <input name="codex_model" value={Runners.codex_model()} required />
        </label>
        <label>
          <span>Repositórios do DeepSeek (separados por vírgula)</span>
          <input
            name="dsh_repositories"
            value={Enum.join(@snapshot.dsh_repositories, ", ")}
            placeholder="sallaumen/arena-rogue, sallaumen/o_colmex"
          />
        </label>
      </div>

      <p :if={@snapshot.quota} class="ab-meta">
        Cota semanal do Codex agora: {percent(@snapshot.quota.used_percent)}% usada.
      </p>

      <p class="ab-meta">
        Claude Code: <code>{Runners.claude_bin()}</code>
        {if Runners.ready?("claude"), do: "pronto", else: "não encontrado ou sem permissão"} ·
        Codex: <code>{Runners.codex_bin()}</code>
        {if Runners.ready?("codex"), do: "pronto", else: "não encontrado ou sem permissão"}
      </p>

      <p :if={@error} class="settings-error" role="alert">{@error}</p>
      <p :if={@saved} class="settings-saved" role="status">Tetos salvos.</p>

      <div class="settings-actions">
        <button type="submit" phx-disable-with="Salvando…">Salvar tetos</button>
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
    with {:ok, monthly} <- float(params["monthly_usd"], "orçamento mensal"),
         {:ok, task} <- float(params["task_usd"], "teto por tarefa"),
         {:ok, timeout} <- integer(params["codex_timeout_minutes"], "tempo do Codex", 1),
         {:ok, reserve} <- integer(params["reserve_percent"], "reserva da cota", 0),
         true <- reserve <= 100 || {:error, "A reserva da cota fica entre 0 e 100%."},
         claude = String.trim(params["claude_model"] || ""),
         codex = String.trim(params["codex_model"] || ""),
         true <- claude != "" || {:error, "Escolha o modelo do Claude Code."},
         true <- codex != "" || {:error, "Escolha o modelo do Codex."} do
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
      false -> {:error, "Confira os números do despacho."}
    end
  end

  defp float(value, label) do
    case Float.parse(to_string(value || "")) do
      {number, _} when number >= 0 -> {:ok, number}
      _ -> {:error, "O #{label} precisa ser um número maior ou igual a zero."}
    end
  end

  defp integer(value, label, min) do
    case Integer.parse(to_string(value || "")) do
      {number, ""} when number >= min -> {:ok, number}
      _ -> {:error, "O #{label} precisa ser um inteiro maior ou igual a #{min}."}
    end
  end

  defp number(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp number(value), do: to_string(value)

  defp percent(value) when is_float(value),
    do: value |> :erlang.float_to_binary(decimals: 0) |> String.replace(".", ",")

  defp percent(value), do: to_string(value)
end
