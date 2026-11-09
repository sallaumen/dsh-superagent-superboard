defmodule AgentBoardWeb.BoardComponents.AI do
  @moduledoc "The board's ai region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation

  alias AgentBoardWeb.BoardComponents.DataAge

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="border-t border-base-content/10 px-5 py-4">
      <h2 class="mb-3 flex items-center gap-3 text-[11px] uppercase tracking-[0.16em] text-base-content/75">
        <span>{gettext("AI · all repositories")}</span>
        <span class={["text-[10px] normal-case", @ai_status != :logged_in && "text-warning"]}>
          {ai_status_label(@ai_status)}
        </span>
      </h2>
      <p :if={@ai_calls == []} class="text-xs text-base-content/75">
        {gettext("No AI calls recorded yet.")}
      </p>
      <p :if={@ai_calls != []} class="mb-2 text-xs text-base-content/75">
        {ngettext(
          "Last %{count} call on the board.",
          "Last %{count} calls on the board.",
          length(@ai_calls)
        )}
      </p>
      <p :if={@ai_calls != []} class="ai-cost-note text-[11px] text-base-content/75">
        {gettext(
          "Costs are estimates based on model pricing; unknown means no price estimate was recorded."
        )}
      </p>
      <ol>
        <li :for={c <- @ai_calls} class="ai-call">
          <div class="ai-call-identity">
            <strong>{c.name || gettext("unknown")}</strong>
            <span>{c.engine || gettext("unknown")} · {c.model || gettext("unknown")}</span>
          </div>
          <span class={["ai-call-status", c.status == "error" && "text-error"]}>{c.status ||
            gettext("unknown")}</span>
          <dl class="ai-call-metrics">
            <div>
              <dt>{gettext("Latency")}</dt><dd>{latency(c.duration_ms)}</dd>
            </div>
            <div>
              <dt>{gettext("Usage")}</dt><dd>{token_usage(c)}</dd>
            </div>
            <div>
              <dt>{gettext("Est. Cost")}</dt><dd>{estimated_cost(c.cost_micros)}</dd>
            </div>
          </dl>
          <DataAge.stamp id={"call-age-#{c.id}"} at={c.inserted_at} label={gettext("Call")} />
          <p :if={c.status == "error"} class="ai-call-reason">
            <strong>{gettext("Reason")}</strong>
            <span>{failure_reason(c.error)}</span>
          </p>
        </li>
      </ol>
    </section>
    """
  end

  defp failure_reason(reason) when is_binary(reason) do
    case String.trim(reason) do
      "" -> gettext("Reason not recorded")
      value -> value
    end
  end

  defp failure_reason(_reason), do: gettext("Reason not recorded")
end
