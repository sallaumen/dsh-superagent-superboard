defmodule AgentBoardWeb.BoardComponents.QueueList do
  @moduledoc "Fila: numbered in arrival order, compact for dozens of items."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]
  alias AgentBoard.Time

  attr :queue, :map, required: true
  attr :frozen, :boolean, default: false

  def queue_list(assigns) do
    ~H"""
    <section id="sec-queue" aria-labelledby="sec-queue-title">
      <div class="ab-sec__head">
        <h2 id="sec-queue-title">Fila</h2>
        <span class="ab-sec__count">
          {count(@queue.total, @frozen)}
          <span :if={@queue.filter != :all} class="ab-meta">
            de {count(@queue.counts.all, @frozen)}
          </span>
        </span>
        <span class="ab-top__spacer"></span>
        <span class="ab-meta">mais antigas primeiro</span>
      </div>

      <div :if={@queue.filters != []} class="ab-filter" role="toolbar" aria-label="Filtrar fila">
        <button
          :for={{label, filter, n} <- filter_buttons(@queue.filters)}
          type="button"
          class="ab-chip"
          aria-pressed={to_string(@queue.filter == filter)}
          phx-click="filter_queue"
          phx-value-filter={filter}
        >
          {label} <span class="ab-num">{n}</span>
        </button>
      </div>

      <div :if={@queue.items == []} class="ab-sec__empty">
        <.glyph kind={:queue} />
        <span :if={@queue.filter != :all}>Nenhuma tarefa neste filtro.</span>
        <span :if={@queue.filter == :all}>Fila vazia.</span>
        <button
          :if={@queue.filter == :all}
          type="button"
          class="ab-btn ab-btn--quiet ab-btn--sm"
          phx-click="show_panel"
          phx-value-panel="create"
        >Novo pedido</button>
      </div>

      <div :if={@queue.items != []} class="ab-list" role="list">
        <button
          :for={{task, index} <- Enum.with_index(@queue.items)}
          id={"task-#{task.id}"}
          type="button"
          class="ab-row"
          role="listitem"
          data-task={task.id}
          phx-click="open"
          phx-value-id={task.id}
        >
          <span class="ab-row__pos">{index + 1}</span>
          <.glyph kind={:queue} />
          <span class="ab-row__title">
            <span><span class="ab-need__id">#{task.number}</span> {task.title}</span>
            <span :if={task.note} class="ab-row__note"><.glyph kind={:review} />{task.note}</span>
            <span :if={is_nil(task.note) and task.sub} class="ab-meta">{task.sub}</span>
          </span>
          <span class="ab-row__side">
            <span class="ab-meta">{Time.ago(task.age_seconds)}</span>
          </span>
        </button>
      </div>

      <button :if={@queue.hidden > 0} type="button" class="ab-more" phx-click="queue_more">
        Mais {@queue.hidden} na fila
      </button>
    </section>
    """
  end

  defp filter_buttons(filters) do
    filters
    |> Enum.with_index()
    |> Enum.map(fn {{label, n}, index} ->
      {label, Enum.at(~w(all new split dupes), index), n}
    end)
  end

  defp count(0, _frozen), do: "0"
  defp count(n, true), do: "≥#{n}"
  defp count(n, false), do: "#{n}"
end
