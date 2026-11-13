defmodule AgentBoardWeb.BoardComponents.NowLane do
  @moduledoc """
  The current step of each running assignment, never a progress bar: the
  stages are the three the board can see (`AgentBoard.Tickets.stages/2`).

  A silent run keeps its place here (it is still running) and says so: the
  glyph stops pulsing, because motion that says "working" would misrepresent
  the state, and the line says how long the board has seen nothing.

  A failure the board retries by itself is here too, after the running
  cards: nobody has to act, the system is on it. Its row says what failed
  and when the next attempt goes out; the glyph is the queue's, still.
  """
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Markup, only: [markup: 1]
  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]
  alias AgentBoardWeb.Time

  attr :gates, :map, default: %{}
  attr :running, :list, required: true
  attr :frozen, :boolean, default: false
  attr :frozen_at, :any, default: nil
  attr :sync_at, :any, default: nil
  attr :tz_offset, :integer, default: 0
  attr :next_queued, :any, default: nil
  attr :retrying, :list, default: []

  def now_lane(assigns) do
    ~H"""
    <section id="sec-now" aria-labelledby="sec-now-title" phx-hook="ValueChange">
      <div class="ab-sec__head">
        <h2 id="sec-now-title">{gettext("Now")}</h2>
        <span
          class="ab-sec__count"
          data-key="now"
          data-value={"#{length(@running)}+#{length(@retrying)}"}
        >
          {count(@running, @frozen, @sync_at, @tz_offset)}{retry_count(@retrying)}
        </span>
      </div>

      <div :if={@running == [] and @retrying == []} class="ab-sec__empty">
        <.glyph kind={:queue} />{gettext("No agents working.")}
        <span :if={@next_queued} class="ab-meta">
          {gettext("Next in queue: %{task}.", task: @next_queued)}
        </span>
      </div>

      <div class="ab-now">
        <article
          :for={task <- @running}
          id={"task-#{task.id}"}
          class={["ab-run", @frozen && "is-frozen", task[:stalled] && "is-stalled"]}
          tabindex="0"
          data-task={task.id}
          data-silence={task[:silence] && task.silence.seconds}
        >
          <div class="ab-run__status">
            <.glyph kind={:run} live={not @frozen and not task[:stalled]} />
            <span>{gettext("Running")}</span>
            <span class="ab-need__id">#{task.number}</span>
            <span class="ab-top__spacer"></span>
            <div :if={task.elapsed} class="ab-run__clock">
              <span :if={@frozen}>≥ {Time.duration(task.elapsed)}</span>
              <span :if={not @frozen} data-tick={task.elapsed}>{Time.duration(task.elapsed)}</span>
              <small :if={@frozen and @sync_at}>{gettext("seen at %{time}",
                time: Time.local_time(@sync_at, @tz_offset)
              )}</small>
              <small :if={not @frozen and task.agent}>{task.agent}</small>
            </div>
          </div>

          <button
            type="button"
            class="ab-run__title"
            phx-click="open"
            phx-value-id={task.id}
            data-panel-trigger
            aria-label={open_label(task)}
          >{task.title}</button>

          <div :if={task[:answered_at]} class="ab-run__answered ab-meta">
            {gettext("Back to work: read your answer at %{time}",
              time: Time.local_time(task.answered_at, @tz_offset)
            )}
          </div>

          <div :if={task[:stalled]} class="ab-run__silence">
            <.glyph kind={:stalled} />
            <span>{gettext("no signal for %{duration}", duration: Time.duration(task.silence.seconds))}</span>
          </div>

          <div :if={task.step} class="ab-run__step">
            <span class="ab-meta">{if @frozen, do: gettext("last step seen"), else: gettext("now")}</span>
            <code>{task.step.code}</code>
            <span :if={task.step.note} class="ab-meta ab-run__note" title={task.step.note}>{task.step.note}</span>
          </div>

          <AgentBoardWeb.BoardComponents.MergeProgress.progress
            :for={{{:pull_request, number}, _} <- task.phases}
            snapshot={@gates[number]}
            compact
          />

          <%!-- ValueChange (on #sec-now): the count of done stages rising draws the line into the new one. --%>
          <div
            :if={task.phases != []}
            class="ab-phases"
            aria-label={gettext("Stages")}
            data-key={"phases-#{task.id}"}
            data-value={Enum.count(task.phases, fn {_name, state} -> state == "done" end)}
          >
            <span
              :for={{name, state} <- task.phases}
              class={["ab-phase", state == "done" && "is-done", state == "now" && "is-now"]}
              aria-current={state == "now" && "step"}
            >
              <.glyph :if={state == "done"} kind={:done} />
              <.glyph :if={state == "now"} kind={:run} />
              <.glyph :if={state == "todo"} kind={:queue} />
              {phase_label(name)}
            </span>
          </div>
        </article>

        <article
          :for={task <- @retrying}
          id={"task-#{task.id}"}
          class="ab-run ab-run--retry"
          tabindex="0"
          data-task={task.id}
        >
          <div class="ab-run__status">
            <.glyph kind={:retrying} />
            <span>{gettext("New attempt")}</span>
            <span class="ab-need__id">#{task.number}</span>
          </div>

          <button
            type="button"
            class="ab-run__title"
            phx-click="open"
            phx-value-id={task.id}
            data-panel-trigger
            aria-label={
              gettext("Open task #%{number}: %{title}", number: task.number, title: task.title)
            }
          >{task.title}</button>
          <div class="ab-run__retry"><.markup text={task.line} /></div>
        </article>
      </div>
    </section>
    """
  end

  # The button's name carries the current stage as well as the title.
  defp open_label(task) do
    label = gettext("Open task #%{number}: %{title}", number: task.number, title: task.title)

    case Enum.find(task.phases, &match?({_name, "now"}, &1)) do
      {name, _now} -> label <> ". " <> gettext("Stage: %{stage}", stage: phase_label(name))
      nil -> label
    end
  end

  defp phase_label(:analysis), do: gettext("Analysis")
  defp phase_label(:code), do: gettext("Code")
  defp phase_label({:pull_request, nil}), do: gettext("PR")
  defp phase_label({:pull_request, number}), do: gettext("PR #%{number}", number: number)

  defp retry_count([]), do: ""
  defp retry_count(retrying), do: gettext(" · %{count} retrying", count: length(retrying))

  defp count([], _frozen, _sync_at, _offset), do: "0"

  defp count(running, true, sync_at, offset) do
    gettext("≥%{count} seen at %{time}",
      count: length(running),
      time: Time.local_time(sync_at, offset)
    )
  end

  defp count(running, false, _sync_at, _offset),
    do: gettext("%{count} working", count: length(running))
end
