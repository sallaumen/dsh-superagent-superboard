defmodule AgentBoardWeb.BoardComponents.NeedsYou do
  @moduledoc "Precisa de você: the work only the reader can unblock, in urgency order."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Markup, only: [markup: 1]
  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]
  alias AgentBoard.Time
  alias AgentBoardWeb.BoardComponents.AgentAction

  attr :needs, :list, required: true
  attr :max, :integer, default: 5
  attr :selected, :any, default: nil
  attr :last_visit, :any, default: nil
  attr :frozen, :boolean, default: false

  def needs_you(assigns) do
    # The line only makes sense when every new item comes before every old
    # one. A mixed list would put new items after the line and lie about them.
    new_count = Enum.count(assigns.needs, & &1.is_new)
    first_old = Enum.find_index(assigns.needs, &(not &1.is_new))

    since_at =
      if assigns.last_visit && new_count > 0 && first_old == new_count do
        first_old
      end

    assigns =
      assigns
      |> assign(:shown, Enum.take(assigns.needs, assigns.max))
      |> assign(:since_at, since_at)
      |> assign(:hidden, max(length(assigns.needs) - assigns.max, 0))

    ~H"""
    <section id="sec-needs" aria-labelledby="sec-needs-title">
      <div class="ab-sec__head">
        <h2 id="sec-needs-title">Precisa de você</h2>
        <span class="ab-sec__count">{count(length(@needs), @frozen)}</span>
      </div>

      <div :if={@needs == []} class="ab-sec__empty">
        <.glyph kind={:done} />Nada esperando por você.
      </div>

      <div :if={@needs != []} class="ab-needs">
        <div :for={{need, index} <- Enum.with_index(@shown)} class="ab-needs__item">
          <div :if={@since_at == index} class="ab-since" role="separator">
            antes da sua última visita
          </div>

          <article
            id={dom_id(need)}
            class="ab-need"
            aria-selected={to_string(not is_nil(@selected) and @selected == need[:id])}
            data-task={need[:id]}
            tabindex={if need[:id], do: "0"}
            role={if need[:id], do: "button"}
            phx-click={if need[:id], do: "open"}
            phx-value-id={need[:id]}
            phx-value-tab={if need.kind == :review, do: "pr"}
            data-panel-trigger={need[:id] && "conversation"}
          >
            <.glyph kind={need.kind} />

            <div class="ab-need__title">
              <span :if={need.number} class="ab-need__id">#{need.number}</span>
              <span>{need.title}</span>
            </div>

            <div class={["ab-need__why", tone(need.kind)]}>
              <.markup text={need.why} />
              <span
                :if={need[:ci]}
                class={[
                  "ab-tag",
                  need.ci.state == "fail" && "ab-tag--halt",
                  need.ci.state == "pass" && need.ci.note == "CI local ok" && "ab-tag--agent"
                ]}
                title={need.ci.title}
              >
                <.glyph :if={need.ci.state == "fail"} kind={:cifail} />
                {need.ci.note}
              </span>
            </div>

            <div class="ab-need__side ab-meta">
              <span :if={need.is_new} class="ab-new">novo</span>
              <span :if={need.age_seconds}>{Time.ago(need.age_seconds)}</span>
            </div>

            <div class="ab-need__actions">
              <%= for action <- need.actions do %>
                <.live_component
                  :if={action[:restart_agent]}
                  module={AgentAction}
                  id="agent-restart"
                  mode={:restart}
                  tone={:halt}
                  label={action.label}
                  confirm_label="Religar"
                  busy_label="Religando o agente…"
                />
                <a
                  :if={action[:url]}
                  class={["ab-btn ab-btn--sm", action_class(need.kind)]}
                  href={action.url}
                  target="_blank"
                  rel="noopener noreferrer"
                >{action.label}<span class="ab-sr"> (abre o GitHub em nova aba)</span></a>
                <button
                  :if={action[:task_id]}
                  type="button"
                  class={["ab-btn ab-btn--sm", action_class(need.kind)]}
                  phx-click="open"
                  phx-value-id={action.task_id}
                  phx-value-tab={if need.kind == :review, do: "pr"}
                >{action.label}</button>
              <% end %>
            </div>
          </article>
        </div>

        <button :if={@hidden > 0} type="button" class="ab-more" phx-click="needs_more">
          Mostrar mais {@hidden}
        </button>
      </div>
    </section>
    """
  end

  # A silent run is also the card in Agora: one task, two items, two ids.
  defp dom_id(%{kind: :agent_down}), do: "need-agent-down"
  defp dom_id(%{kind: :stalled, id: id}) when not is_nil(id), do: "silence-#{id}"
  defp dom_id(%{id: id}) when not is_nil(id), do: "task-#{id}"
  defp dom_id(_need), do: nil

  defp tone(:agent_down), do: "is-halt"
  defp tone(:cifail), do: "is-halt"
  defp tone(:blocked), do: "is-halt"
  defp tone(:stalled), do: "is-halt"
  defp tone(_kind), do: "is-you"

  defp action_class(:agent_down), do: "ab-btn--halt"
  defp action_class(:cifail), do: "ab-btn--halt"
  defp action_class(:blocked), do: "ab-btn--halt"
  defp action_class(:stalled), do: "ab-btn--halt"
  defp action_class(_kind), do: "ab-btn--quiet"

  defp count(0, _frozen), do: "0"
  defp count(n, true), do: "≥#{n}"
  defp count(n, false), do: "#{n}"
end
