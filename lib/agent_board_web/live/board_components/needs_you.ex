defmodule AgentBoardWeb.BoardComponents.NeedsYou do
  @moduledoc "Work only the reader can unblock, in urgency order."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Markup, only: [markup: 1]
  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]
  alias AgentBoardWeb.BoardComponents.AgentAction
  alias AgentBoardWeb.Time

  attr :needs, :list, required: true
  attr :max, :integer, default: 5
  attr :selected, :any, default: nil
  attr :last_visit, :any, default: nil
  attr :frozen, :boolean, default: false
  attr :frozen_at, :any, default: nil
  attr :tz_offset, :integer, default: 0

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
        <h2 id="sec-needs-title">{gettext("Needs you")}</h2>
        <span class="ab-sec__count">{count(length(@needs), @frozen)}</span>
      </div>

      <div :if={@needs == []} class="ab-sec__empty">
        <.glyph kind={:done} />{gettext("Nothing waiting for you.")}
      </div>

      <div :if={@needs != []} class="ab-needs">
        <div :for={{need, index} <- Enum.with_index(@shown)} class="ab-needs__item">
          <div :if={@since_at == index} class="ab-since" role="separator">
            {gettext("since your last visit")}
          </div>

          <article
            id={dom_id(need)}
            class="ab-need"
            aria-current={to_string(not is_nil(@selected) and @selected == need[:id])}
            data-task={need[:id]}
            tabindex={if need[:id], do: "0"}
            role={if need[:id], do: "button"}
            phx-click={if need[:id], do: "open"}
            phx-value-id={need[:id]}
            phx-value-tab={if need.kind == :review, do: "pr"}
            data-panel-trigger={need[:id] && "conversation"}
          >
            <div class="ab-need__top">
              <.glyph kind={need.kind} />
              <span class="ab-need__kind">{kind_label(need.kind)}</span>
              <span :if={need.number} class="ab-need__id">#{need.number}</span>
              <span class="ab-top__spacer"></span>
              <span class="ab-need__side ab-meta">
                <span :if={need.is_new} class="ab-new">{gettext("new")}</span>
                <span :if={need.age_seconds}>{age(need.age_seconds, @frozen, @frozen_at, @tz_offset)}</span>
              </span>
            </div>

            <div class="ab-need__title">{need.title}</div>

            <div class={["ab-need__why", tone(need.kind)]}>
              <.markup text={need.why} />
              <span
                :if={need[:ci]}
                class={[
                  "ab-tag",
                  need.ci.state == "fail" && "ab-tag--halt",
                  need.ci.state == "pass" && need.ci.note == gettext("Local CI passed") &&
                    "ab-tag--agent"
                ]}
                title={need.ci.title}
              >
                <.glyph :if={need.ci.state == "fail"} kind={:cifail} />
                {need.ci.note}
              </span>
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
                  confirm_label={gettext("Restart")}
                  busy_label={gettext("Restarting the agent…")}
                />
                <.live_component
                  :if={action[:retry]}
                  module={AgentAction}
                  id={"need-retry-#{need.id}"}
                  mode={:retry}
                  tone={:halt}
                  ticket_id={action.retry.ticket_id}
                  task_id={need.id}
                  repository_id={action.retry.repository_id}
                  number={action.retry.number}
                  label={action.label}
                  confirm_label={gettext("Request another attempt")}
                  busy_label={gettext("Asking the agent…")}
                />
                <a
                  :if={action[:url]}
                  class={["ab-btn ab-btn--sm", action_class(need.kind)]}
                  href={action.url}
                  target="_blank"
                  rel="noopener noreferrer"
                >{action.label}<span class="ab-sr">{gettext("(opens GitHub in a new tab)")}</span></a>
                <button
                  :if={action[:release]}
                  type="button"
                  class={["ab-btn ab-btn--sm", action_class(need.kind)]}
                  phx-click="release_task"
                  phx-value-id={need.id}
                  phx-value-confirm={action.release}
                  data-confirm={action.release}
                >{action.label}</button>
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
  defp dom_id(%{kind: :slow, id: id}) when not is_nil(id), do: "slow-#{id}"
  # A call nobody answered is also the row in Fila.
  defp dom_id(%{kind: :unanswered, id: id}) when not is_nil(id), do: "unanswered-#{id}"
  defp dom_id(%{id: id}) when not is_nil(id), do: "task-#{id}"
  defp dom_id(_need), do: nil

  defp kind_label(:review), do: gettext("Review")
  defp kind_label(:question), do: pgettext("status", "Question")
  defp kind_label(:blocked), do: pgettext("status", "Blocked")
  defp kind_label(:cifail), do: pgettext("status", "CI failed")
  defp kind_label(:stalled), do: pgettext("status", "No signal")
  defp kind_label(:unanswered), do: pgettext("status", "No answer")
  defp kind_label(:slow), do: pgettext("status", "Taking long")
  defp kind_label(:agent_down), do: pgettext("status", "Agent offline")
  defp kind_label(_kind), do: gettext("Attention")

  defp tone(:agent_down), do: "is-halt"
  defp tone(:cifail), do: "is-halt"
  defp tone(:blocked), do: "is-halt"
  defp tone(:stalled), do: "is-halt"
  defp tone(:unanswered), do: "is-halt"
  defp tone(:slow), do: "is-stale"
  defp tone(_kind), do: "is-you"

  defp action_class(:agent_down), do: "ab-btn--halt"
  defp action_class(:cifail), do: "ab-btn--halt"
  defp action_class(:blocked), do: "ab-btn--halt"
  defp action_class(:stalled), do: "ab-btn--halt"
  defp action_class(:unanswered), do: "ab-btn--halt"
  defp action_class(_kind), do: "ab-btn--quiet"

  defp age(_seconds, true, %DateTime{} = at, offset), do: Time.local_time(at, offset)
  defp age(seconds, _frozen, _at, _offset), do: Time.ago(seconds)

  defp count(0, _frozen), do: "0"
  defp count(n, true), do: "≥#{n}"
  defp count(n, false), do: "#{n}"
end
