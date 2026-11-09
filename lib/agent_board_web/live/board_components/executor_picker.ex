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
  use Gettext, backend: AgentBoardWeb.Gettext

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
      <legend class="ab-label">{gettext("Executor")}</legend>
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
          <span :if={suggested?(@suggestion, executor)} class="ab-exec__hint">{gettext("suggested")}</span>
        </label>
      </div>

      <div id="composer-routing" class="ab-exec__why" aria-live="polite">
        <p :if={is_nil(@suggestion)} class="ab-meta">{gettext("Reading the executors...")}</p>
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
          {gettext("Expected cost:")} {cost_label(@suggestion.cost)}
        </p>
        <p :if={@ruled_out} id="composer-executor-warning" class="ab-meta ab-exec__warn" role="alert">
          {gettext("Note:")} {@ruled_out} {gettext("The issue opens, but work does not start.")}
        </p>
        <p
          :if={not Executors.dispatched_by_board?(@chosen)}
          id="composer-executor-note"
          class="ab-meta"
        >
          {gettext("Without mentioning the agent, DeepSeek won't pick up the request.")}
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

  defp more_label(n), do: ngettext("%{count} more reason", "%{count} more reasons", n)

  defp suggested?(%{executor: executor}, executor), do: true
  defp suggested?(_suggestion, _executor), do: false

  defp suggestion_head(%{executor: nil}), do: gettext("No suggestion.")

  defp suggestion_head(%{executor: executor}),
    do: gettext("Suggested: %{executor}.", executor: Executors.name(executor))

  @doc """
  The expected cost in the executor's own currency. The Claude Code US$ is
  the list price of the Max subscription, a reference and not a bill; an
  executor with no history is unknown, never zero.
  """
  def cost_label(:unknown), do: gettext("Unknown (no usage history)")

  def cost_label(%{micros: micros, reference: :list} = cost) when is_integer(micros) do
    amount(cost) <> gettext(" at list price (reference, not a bill)")
  end

  def cost_label(%{micros: micros} = cost) when is_integer(micros), do: amount(cost)

  def cost_label(_other), do: gettext("unknown")

  defp amount(%{micros: micros, complete?: false}),
    do: "≥ US$ #{:erlang.float_to_binary(micros / 1_000_000, decimals: 2)}"

  defp amount(%{micros: micros}),
    do: "≈ US$ #{:erlang.float_to_binary(micros / 1_000_000, decimals: 2)}"
end
