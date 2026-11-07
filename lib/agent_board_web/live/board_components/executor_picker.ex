defmodule AgentBoardWeb.BoardComponents.ExecutorPicker do
  @moduledoc """
  Who the request is for, inside the composer form: the three executors as
  one radio group, the router's suggestion with its reasons and the
  expected cost, and what choosing someone other than the DeepSeek runner
  means today (the issue is recorded, nothing starts).

  The suggestion comes from `AgentBoard.Routing.suggest/2`; while the board
  reads the signals it is `nil` and the group still works.
  """
  use Phoenix.Component

  alias AgentBoard.Executors
  alias Phoenix.LiveView.JS

  attr :suggestion, :map, default: nil
  attr :chosen, :string, required: true
  attr :disabled, :boolean, default: false

  def executor_picker(assigns) do
    assigns =
      assigns
      |> assign(:executors, Executors.all())
      |> assign(:reasons, (assigns.suggestion && assigns.suggestion.reasons) || [])
      |> assign(:ruled_out, ruled_out(assigns.suggestion, assigns.chosen))

    ~H"""
    <fieldset id="composer-executor" class="ab-exec" disabled={@disabled}>
      <legend class="ab-label">Executor</legend>
      <div class="ab-exec__options">
        <label
          :for={executor <- @executors}
          for={"composer-executor-" <> executor}
          class={["ab-exec__opt", executor == @chosen && "is-on"]}
        >
          <input
            type="radio"
            id={"composer-executor-" <> executor}
            name="executor"
            value={executor}
            checked={executor == @chosen}
            class="ab-sr"
          />
          <span>{Executors.name(executor)}</span>
          <span :if={suggested?(@suggestion, executor)} class="ab-exec__hint">sugerido</span>
        </label>
      </div>

      <div id="composer-routing" class="ab-exec__why" aria-live="polite">
        <p :if={is_nil(@suggestion)} class="ab-meta">Lendo os executores…</p>
        <p :if={@suggestion} class="ab-meta">
          <b>{suggestion_head(@suggestion)}</b>
          <span :if={@reasons != []}>{hd(@reasons)}</span>
        </p>
        <details
          :if={length(@reasons) > 1}
          id="composer-routing-reasons"
          class="ab-exec__reasons"
          phx-mounted={JS.ignore_attributes("open")}
        >
          <summary class="ab-meta">{more_label(length(@reasons) - 1)}</summary>
          <ul>
            <li :for={reason <- tl(@reasons)} class="ab-meta">{reason}</li>
          </ul>
        </details>
        <p :if={@suggestion} class="ab-meta">
          Custo esperado: {cost_label(@suggestion.cost)}
        </p>
        <p :if={@ruled_out} id="composer-executor-warning" class="ab-meta ab-exec__warn" role="alert">
          Atenção: {@ruled_out} A issue abre, mas não anda.
        </p>
        <p
          :if={not Executors.dispatched_by_board?(@chosen)}
          id="composer-executor-note"
          class="ab-meta"
        >
          Sem a menção ao agente, o DeepSeek não pega o pedido.
        </p>
      </div>
    </fieldset>
    """
  end

  # The reason the router left the chosen executor out, as a sentence.
  defp ruled_out(%{ruled_out: out}, chosen) do
    Enum.find_value(out, fn %{executor: executor, reason: reason} ->
      if executor == chosen,
        do: String.capitalize(String.first(reason)) <> String.slice(reason, 1..-1//1)
    end)
  end

  defp ruled_out(_suggestion, _chosen), do: nil

  defp more_label(1), do: "Mais 1 motivo"
  defp more_label(n), do: "Mais #{n} motivos"

  defp suggested?(%{executor: executor}, executor), do: true
  defp suggested?(_suggestion, _executor), do: false

  defp suggestion_head(%{executor: nil}), do: "Sem sugestão."
  defp suggestion_head(%{executor: executor}), do: "Sugestão: #{Executors.name(executor)}."

  @doc "The expected cost in the executor's own currency; unknown until the usage ledger exists."
  def cost_label(:unknown), do: "desconhecido (ainda não há histórico de uso)"

  def cost_label(%{micros: micros, complete?: complete?}) when is_integer(micros) do
    dollars = :erlang.float_to_binary(micros / 1_000_000, decimals: 2)
    if complete?, do: "US$ #{dollars}", else: "≥ US$ #{dollars}"
  end

  def cost_label(_other), do: "desconhecido"
end
