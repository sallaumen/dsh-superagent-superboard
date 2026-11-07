defmodule AgentBoardWeb.BoardComponents.NowLane do
  @moduledoc """
  Agora: the real step of each running assignment, never a progress bar.

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
  alias AgentBoard.Time

  attr :running, :list, required: true
  attr :frozen, :boolean, default: false
  attr :frozen_at, :any, default: nil
  attr :sync_at, :any, default: nil
  attr :tz_offset, :integer, default: 0
  attr :next_queued, :any, default: nil
  attr :retrying, :list, default: []

  def now_lane(assigns) do
    ~H"""
    <section id="sec-now" aria-labelledby="sec-now-title">
      <div class="ab-sec__head">
        <h2 id="sec-now-title">Agora</h2>
        <span class="ab-sec__count">
          {count(@running, @frozen, @sync_at, @tz_offset)}{retry_count(@retrying)}
        </span>
      </div>

      <div :if={@running == [] and @retrying == []} class="ab-sec__empty">
        <.glyph kind={:queue} />Nenhum agente trabalhando.<span :if={@next_queued} class="ab-meta">
          A próxima da fila é #{@next_queued}.
        </span>
      </div>

      <div class="ab-now">
        <article
          :for={task <- @running}
          id={"task-#{task.id}"}
          class={["ab-run", @frozen && "is-frozen", task[:stalled] && "is-stalled"]}
          tabindex="0"
          role="button"
          data-task={task.id}
          data-silence={task[:silence] && task.silence.seconds}
          phx-click="open"
          phx-value-id={task.id}
          data-panel-trigger
          aria-label={"Abrir tarefa ##{task.number}: #{task.title}"}
        >
          <.glyph kind={:run} live={not @frozen and not task[:stalled]} />

          <div class="ab-run__title">
            <span class="ab-need__id">#{task.number}</span>
            <span>{task.title}</span>
          </div>

          <div :if={task.elapsed} class="ab-run__clock">
            <span :if={@frozen}>≥ {Time.duration(task.elapsed)}</span>
            <span :if={not @frozen} data-tick={task.elapsed}>{Time.duration(task.elapsed)}</span>
            <small :if={@frozen and @sync_at}>visto às {Time.local_time(@sync_at, @tz_offset)}</small>
            <small :if={not @frozen and task.agent}>{task.agent}</small>
          </div>

          <div :if={task[:stalled]} class="ab-run__silence">
            <.glyph kind={:stalled} />
            <span>sem sinal {Time.ago(task.silence.seconds)}</span>
          </div>

          <div :if={task.step} class="ab-run__step">
            <span class="ab-meta">{if @frozen, do: "último passo visto", else: "agora"}</span>
            <code>{task.step.code}</code>
            <span :if={task.step.note} class="ab-meta">{task.step.note}</span>
          </div>

          <div :if={task.phases != []} class="ab-phases" aria-label="Etapas">
            <span
              :for={{name, state} <- task.phases}
              class={["ab-phase", state == "done" && "is-done", state == "now" && "is-now"]}
            >
              <.glyph :if={state == "done"} kind={:done} />
              <.glyph :if={state == "now"} kind={:run} />
              <.glyph :if={state == "todo"} kind={:queue} />
              {name}
            </span>
          </div>
        </article>

        <article
          :for={task <- @retrying}
          id={"task-#{task.id}"}
          class="ab-run ab-run--retry"
          tabindex="0"
          role="button"
          data-task={task.id}
          phx-click="open"
          phx-value-id={task.id}
          data-panel-trigger
          aria-label={"Abrir tarefa ##{task.number}: #{task.title}"}
        >
          <.glyph kind={:retrying} />

          <div class="ab-run__title">
            <span class="ab-need__id">#{task.number}</span>
            <span>{task.title}</span>
          </div>

          <div class="ab-run__retry"><.markup text={task.line} /></div>
        </article>
      </div>
    </section>
    """
  end

  defp retry_count([]), do: ""
  defp retry_count(retrying), do: " · #{length(retrying)} em nova tentativa"

  defp count([], _frozen, _sync_at, _offset), do: "0"

  defp count(running, true, sync_at, offset) do
    "≥#{length(running)} visto às #{Time.local_time(sync_at, offset)}"
  end

  defp count(running, false, _sync_at, _offset), do: "#{length(running)} trabalhando"
end
