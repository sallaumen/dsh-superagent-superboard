defmodule AgentBoardWeb.BoardComponents.Throughput do
  @moduledoc """
  Vazão: the agent's throughput per hour, from what the board recorded.

  Eight tiles in one strip: five rates (done, opened, merged, commits, tickets),
  the queue depth, the cycle and the runner's parallelism. Every number is a
  count the reader can check against GitHub or the runner; a source the board
  never read shows `?` with the reason, never a zero. The sparkline is 24 clock
  hours in the reader's offset, the current one in the agent's colour.
  """
  use AgentBoardWeb, :html

  alias AgentBoard.{Metrics, Orchestrator, Time}

  attr :flow, :map, required: true
  attr :tz_offset, :integer, default: 0

  def throughput(assigns) do
    ~H"""
    <section
      id="sec-flow"
      class="ab-flow"
      aria-labelledby="sec-flow-title"
      phx-hook="Throughput"
      data-computed-at={DateTime.to_iso8601(@flow.computed_at)}
    >
      <div class="ab-sec__head">
        <h2 id="sec-flow-title">Vazão</h2>
        <span class="ab-sec__count">
          por hora · calculado às {Time.local_time(@flow.computed_at, @tz_offset)}
        </span>
      </div>
      <ul class="ab-flow__grid" aria-label="Vazão por hora, 24 h e 7 dias">
        <li :for={tile <- @flow.tiles} id={"flow-#{tile.key}"} class="ab-flow__tile">
          <.tile tile={tile} buckets={@flow.buckets} offset={@tz_offset} />
        </li>
      </ul>
    </section>
    """
  end

  attr :tile, :map, required: true
  attr :buckets, :list, required: true
  attr :offset, :integer, required: true

  defp tile(%{tile: %{kind: kind}} = assigns) when kind in [:rate, :depth] do
    ~H"""
    <span class="ab-flow__label">{@tile.label}</span>
    <span class="ab-flow__now">
      <span
        class={["ab-flow__value", @tile.status == :unknown && "is-unknown"]}
        data-key={@tile.key}
        data-value={Metrics.count(@tile.hour)}
        title={title(@tile)}
      >
        {Metrics.count(@tile.hour)}
      </span>
      <span class="ab-flow__unit">{if @tile.kind == :rate, do: "/h", else: "na fila"}</span>
      <span
        class={["ab-tag", delta_tone(@tile)]}
        title={delta_title(@tile)}
      >
        {Metrics.delta(@tile.delta)}<span class="ab-sr"> em relação à hora anterior</span>
      </span>
    </span>
    <.spark tile={@tile} buckets={@buckets} offset={@offset} />
    <dl class="ab-flow__win">
      <div>
        <dt>24 h</dt>
        <dd><.window tile={@tile} field={:day} hours={24} /></dd>
      </div>
      <div>
        <dt>7 d</dt>
        <dd><.window tile={@tile} field={:week} hours={168} /></dd>
      </div>
    </dl>
    """
  end

  defp tile(%{tile: %{kind: :cycle}} = assigns) do
    ~H"""
    <span class="ab-flow__label">{@tile.label}</span>
    <table class="ab-flow__cycle">
      <caption class="ab-sr">
        Tempo médio de issue a PR e de PR a merge, sobre os tickets cujo PR foi mesclado na janela
      </caption>
      <thead>
        <tr>
          <th scope="col"><span class="ab-sr">etapa</span></th>
          <th scope="col">24 h</th>
          <th scope="col">7 d</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <th scope="row">issue→PR</th>
          <td
            class="ab-flow__value ab-flow__value--small"
            data-key="cycle.issue_pr"
            data-value={Metrics.duration(@tile.day.issue_to_pr)}
          >
            {Metrics.duration(@tile.day.issue_to_pr)}
          </td>
          <td>{Metrics.duration(@tile.week.issue_to_pr)}</td>
        </tr>
        <tr>
          <th scope="row">PR→merge</th>
          <td
            class="ab-flow__value ab-flow__value--small"
            data-key="cycle.pr_merge"
            data-value={Metrics.duration(@tile.day.pr_to_merge)}
          >
            {Metrics.duration(@tile.day.pr_to_merge)}
          </td>
          <td>{Metrics.duration(@tile.week.pr_to_merge)}</td>
        </tr>
        <tr class="ab-flow__cycle-n">
          <th scope="row">tickets</th>
          <td>{@tile.day.n}</td>
          <td>{@tile.week.n}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp tile(%{tile: %{kind: :load}} = assigns) do
    ~H"""
    <span class="ab-flow__label">{@tile.label}</span>
    <span class="ab-flow__now">
      <span
        class={["ab-flow__value", @tile.status == :unknown && "is-unknown"]}
        data-key="load"
        data-value={load_value(@tile)}
        title={title(@tile)}
      >
        {Metrics.count(@tile.running)}
      </span>
      <span class="ab-flow__unit">de</span>
      <.limit tile={@tile} />
      <span class="ab-tag" title="tickets esperando no orquestrador">
        {Metrics.count(@tile.queued)}<span class="ab-sr"> tickets</span> esperando
      </span>
    </span>
    <.capacity tile={@tile} />
    <dl class="ab-flow__win">
      <div>
        <dt>fonte</dt>
        <dd>
          {if @tile.status == :measured, do: "orquestrador, agora", else: Metrics.reason(@tile.reason)}
        </dd>
      </div>
    </dl>
    """
  end

  attr :tile, :map, required: true

  # The ceiling is changed where it is read: minus and plus save
  # `executor.maxWorkers` in the runner (`Orchestrator.set_max_workers/2`).
  defp limit(%{tile: %{status: :measured}} = assigns) do
    range = Orchestrator.worker_range()
    assigns = assign(assigns, min: range.first, max: range.last)

    ~H"""
    <span class="ab-flow__limit">
      <button
        type="button"
        class="ab-btn ab-btn--icon ab-flow__step"
        phx-click="set_max_workers"
        phx-value-to={@tile.max - 1}
        disabled={@tile.max <= @min}
        aria-label="Menos um agente"
        title="Menos um agente em paralelo"
      >
        −
      </button>
      <span class="ab-flow__unit" data-key="load-max">{@tile.max}</span>
      <button
        type="button"
        class="ab-btn ab-btn--icon ab-flow__step"
        phx-click="set_max_workers"
        phx-value-to={@tile.max + 1}
        disabled={@tile.max >= @max}
        aria-label="Mais um agente"
        title="Mais um agente em paralelo"
      >
        +
      </button>
    </span>
    """
  end

  defp limit(assigns) do
    ~H"""
    <span class="ab-flow__unit" data-key="load-max">{Metrics.count(@tile.max)}</span>
    """
  end

  attr :tile, :map, required: true
  attr :field, :atom, required: true
  attr :hours, :integer, required: true

  defp window(%{tile: %{status: :unknown}} = assigns) do
    ~H"""
    ?
    """
  end

  defp window(%{tile: %{kind: :depth}} = assigns) do
    ~H"""
    <b>{Metrics.count(Map.get(@tile, @field))}</b> pico
    """
  end

  defp window(assigns) do
    count = Map.get(assigns.tile, assigns.field)
    assigns = assign(assigns, count: count, rate: Metrics.rate(count / assigns.hours))

    ~H"""
    <b>{@count}</b> · {@rate}/h
    """
  end

  attr :tile, :map, required: true
  attr :buckets, :list, required: true
  attr :offset, :integer, required: true

  defp spark(%{tile: %{series: nil}} = assigns) do
    ~H"""
    <svg
      class="ab-flow__spark is-unknown"
      viewBox="0 0 96 24"
      preserveAspectRatio="none"
      role="img"
      aria-label={"#{@tile.label}: #{Metrics.reason(@tile.reason)}"}
    >
      <line x1="0" y1="23.5" x2="96" y2="23.5" class="ab-flow__base" />
    </svg>
    """
  end

  # The queue is a level, not a count per hour: a step line, so a flat queue
  # of one reads as a line and not as a wall of full bars.
  defp spark(%{tile: %{kind: :depth}} = assigns) do
    series = assigns.tile.series
    peak = max(Enum.max(series, fn -> 0 end), 1)

    steps =
      series
      |> Enum.with_index()
      |> Enum.map(fn {n, index} -> {index * 4, 24 - n / peak * 22} end)

    line =
      Enum.map_join(steps, " ", fn {x, y} ->
        "#{if x == 0, do: "M", else: "V"}#{if x == 0, do: "0,", else: ""}#{y} H#{x + 4}"
      end)

    hovers =
      series
      |> Enum.zip(assigns.buckets)
      |> Enum.with_index()
      |> Enum.map(fn {{n, bucket}, index} ->
        %{x: index * 4, title: "#{bucket_label(bucket, assigns.offset)}: #{n}"}
      end)

    assigns =
      assign(assigns,
        line: line,
        area: "M0,24 #{String.replace(line, "M0,", "L0,")} L96,24 Z",
        hovers: hovers,
        aria: aria(assigns.tile, series)
      )

    ~H"""
    <svg
      class="ab-flow__spark ab-flow__spark--level"
      viewBox="0 0 96 24"
      preserveAspectRatio="none"
      role="img"
      aria-label={@aria}
    >
      <line x1="0" y1="23.5" x2="96" y2="23.5" class="ab-flow__base" />
      <path d={@area} class="ab-flow__area" />
      <path d={@line} class="ab-flow__line" vector-effect="non-scaling-stroke" />
      <rect :for={hover <- @hovers} x={hover.x} y="0" width="4" height="24" class="ab-flow__hover">
        <title>{hover.title}</title>
      </rect>
    </svg>
    """
  end

  defp spark(assigns) do
    series = assigns.tile.series
    peak = max(Enum.max(series, fn -> 0 end), 1)
    last = length(series) - 1

    bars =
      series
      |> Enum.zip(assigns.buckets)
      |> Enum.with_index()
      |> Enum.map(fn {{n, bucket}, index} ->
        %{
          x: index * 4,
          h: if(n == 0, do: 0, else: max(round(n / peak * 22), 1)),
          n: n,
          now?: index == last,
          title: "#{bucket_label(bucket, assigns.offset)}: #{n}"
        }
      end)

    assigns = assign(assigns, bars: bars, aria: aria(assigns.tile, series))

    ~H"""
    <svg
      class="ab-flow__spark"
      viewBox="0 0 96 24"
      preserveAspectRatio="none"
      role="img"
      aria-label={@aria}
    >
      <line x1="0" y1="23.5" x2="96" y2="23.5" class="ab-flow__base" />
      <rect
        :for={bar <- @bars}
        :if={bar.h > 0}
        x={bar.x}
        y={24 - bar.h}
        width="3"
        height={bar.h}
        class={bar.now? && "is-now"}
      >
        <title>{bar.title}</title>
      </rect>
    </svg>
    """
  end

  attr :tile, :map, required: true

  defp capacity(%{tile: %{status: :unknown}} = assigns) do
    ~H"""
    <svg
      class="ab-flow__spark is-unknown"
      viewBox="0 0 96 24"
      preserveAspectRatio="none"
      role="img"
      aria-label={"Paralelismo: #{Metrics.reason(@tile.reason)}"}
    >
      <line x1="0" y1="23.5" x2="96" y2="23.5" class="ab-flow__base" />
    </svg>
    """
  end

  defp capacity(assigns) do
    max = max(assigns.tile.max, 1)
    width = 96 / max

    slots =
      for index <- 0..(max - 1) do
        %{x: index * width + 0.5, w: max(width - 1, 1), on?: index < assigns.tile.running}
      end

    assigns = assign(assigns, slots: slots)

    ~H"""
    <svg
      class="ab-flow__spark ab-flow__capacity"
      viewBox="0 0 96 24"
      preserveAspectRatio="none"
      role="img"
      aria-label={"#{@tile.running} de #{@tile.max} vagas do orquestrador em uso, #{@tile.queued} esperando"}
    >
      <rect
        :for={slot <- @slots}
        x={slot.x}
        y="14"
        width={slot.w}
        height="9"
        class={slot.on? && "is-now"}
      />
    </svg>
    """
  end

  # -- words ------------------------------------------------------------------

  defp title(%{status: :unknown, reason: reason}), do: Metrics.reason(reason)
  defp title(%{kind: :rate}), do: "nos últimos 60 minutos"
  defp title(%{kind: :depth}), do: "tarefas na fila agora"
  defp title(%{kind: :load}), do: "vagas do orquestrador em uso agora"

  defp delta_tone(%{status: :unknown}), do: nil
  defp delta_tone(%{kind: :rate, delta: delta}) when delta > 0, do: "ab-tag--agent"
  defp delta_tone(_tile), do: nil

  defp delta_title(%{status: :unknown}), do: nil

  defp delta_title(%{previous: previous, kind: kind}),
    do: "hora anterior: #{previous}#{if kind == :rate, do: "/h", else: " na fila"}"

  defp load_value(%{status: :unknown}), do: "?"

  defp load_value(%{running: running, max: max, queued: queued}),
    do: "#{running}/#{max}/#{queued}"

  defp bucket_label(%{from: from, to: to}, offset),
    do: "#{Time.local_time(from, offset)}–#{Time.local_time(to, offset)}"

  defp aria(%{kind: :depth} = tile, series) do
    "#{tile.label} ao fim de cada hora nas últimas 24 h, da mais antiga à atual: " <>
      Enum.map_join(series, ", ", &Integer.to_string/1)
  end

  defp aria(tile, series) do
    "#{tile.label} por hora nas últimas 24 h, da mais antiga à atual: " <>
      Enum.map_join(series, ", ", &Integer.to_string/1)
  end
end
