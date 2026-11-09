defmodule AgentBoardWeb.BoardComponents.Executors do
  @moduledoc """
  Executor usage over seven or thirty days, read from the usage ledger.
  Tokens are measured; USD is estimated; Codex quota uses its latest reading.
  Unknown stays unknown, never zero, and executors are not summed. The panel
  reads on open and when its window changes, not on every render.
  """
  use AgentBoardWeb, :html

  alias AgentBoardWeb.Time

  @sources ["dsh", "claude_code", "codex"]
  @labels %{"dsh" => "DeepSeek", "claude_code" => "Claude Code", "codex" => "Codex"}

  attr :report, :map, default: nil
  attr :days, :integer, default: 7

  def executors(assigns) do
    assigns =
      assigns
      |> assign(:labels, @labels)
      |> assign(:sources, @sources)
      |> assign(:days_data, days_data(assigns.report))

    ~H"""
    <section id="executors" class="ab-executors" aria-labelledby="executors-title">
      <header class="ab-executors__head">
        <div>
          <p id="executors-title" class="ab-label">{gettext("Last %{count} days", count: @days)}</p>
          <p class="ab-meta">
            {gettext("Tokens measured. Each executor in its own currency, never summed.")}
          </p>
        </div>
        <div class="ab-executors__range" role="group" aria-label={gettext("Dashboard Window")}>
          <button
            :for={days <- [7, 30]}
            type="button"
            class="ab-btn ab-btn--sm"
            aria-pressed={to_string(days == @days)}
            phx-click="executor_days"
            phx-value-days={days}
          >{days} dias</button>
        </div>
      </header>

      <div :if={is_nil(@report)} class="ab-sec__empty">{gettext("Reading the usage ledger…")}</div>

      <div :if={@report} class="ab-executors__cards">
        <article
          :for={executor <- @report.executors}
          id={"executor-" <> executor.source}
          class="ab-exec-card"
        >
          <header class="ab-exec-card__head">
            <h3>{label(executor.source)}</h3>
            <span class={["ab-tag", tag_class(executor)]}>{tag(executor)}</span>
          </header>

          <p class="ab-exec-card__value">{value(executor)}</p>
          <p class="ab-meta">{subtitle(executor)}</p>

          <dl class="ab-exec-card__facts">
            <div>
              <dt>{gettext("Sessions")}</dt><dd>{executor.executions}</dd>
            </div>
            <div>
              <dt>{gettext("Tasks")}</dt><dd>{executor.tasks_count}</dd>
            </div>
            <div>
              <dt>{gettext("Requests")}</dt><dd>{number(executor.requests)}</dd>
            </div>
            <div>
              <dt>{gettext("Input")}</dt><dd>{tokens(executor.input_tokens)}</dd>
            </div>
            <div>
              <dt>{gettext("Output")}</dt><dd>{tokens(executor.output_tokens)}</dd>
            </div>
            <div>
              <dt>{gettext("Merged tasks")}</dt><dd>{merged(executor.merged)}</dd>
            </div>
            <div>
              <dt>{gettext("Time to merge")}</dt><dd>{hours(executor.merged.median_hours)}</dd>
            </div>
          </dl>

          <p :if={executor.direct != []} class="ab-meta">
            Diretas: {names(executor.direct)}
          </p>
          <p :if={executor.outside != []} class="ab-meta">
            Fora do board: {names(executor.outside)}
          </p>
          <p :if={executor.unknown > 0} class="ab-meta">
            {gettext("No repository: %{count}", count: executor.unknown)}
          </p>
          <p :if={executor.tasks != []} class="ab-meta">
            {gettext("Tasks:")}
            <button
              :for={task <- executor.tasks}
              type="button"
              class="ab-link"
              phx-click="open"
              phx-value-id={task.id}
            >#{task.number}</button>
          </p>
        </article>
      </div>

      <div :if={@report} class="ab-executors__days">
        <h3 class="ab-label">{gettext("Per day")}</h3>
        <div :if={@days_data == []} class="ab-sec__empty">
          {gettext("No usage lines in this window's ledger.")}
        </div>
        <article :for={day <- @days_data} class="ab-exec-day">
          <header>
            <h4>{day_label(day.date)}</h4>
            <span class="ab-data-sm ab-faint">{day.date}</span>
          </header>
          <dl class="ab-exec-day__rows">
            <div :for={source <- @sources}>
              <dt>{label(source)}</dt>
              <dd>{day_value(Map.get(day.by_source, source), source)}</dd>
            </div>
          </dl>
        </article>
        <p class="ab-meta">
          {gettext(
            "UTC days, as recorded in the usage ledger. \"—\" means no usage that day; \"unknown\" means the source could not be read. The Codex quota is the latest reading, not a daily value."
          )}
        </p>
      </div>
    </section>
    """
  end

  defp days_data(nil), do: []

  defp days_data(%{daily: daily}) do
    daily
    |> Enum.group_by(& &1.day)
    |> Enum.sort_by(fn {day, _rows} -> day end, :desc)
    |> Enum.map(fn {day, rows} -> %{date: day, by_source: Map.new(rows, &{&1.source, &1})} end)
  end

  defp label(source), do: Map.get(@labels, source, source)

  defp day_label(date), do: Time.day_label(date, Date.utc_today()) <> " (UTC)"

  defp tag(%{source: source} = executor) do
    cond do
      source == "codex" and executor.quota -> gettext("measured")
      source != "codex" and executor.cost -> gettext("estimated")
      true -> gettext("unknown")
    end
  end

  defp tag_class(%{source: "codex", quota: quota}) when not is_nil(quota), do: "ab-tag--agent"
  defp tag_class(%{cost: cost}) when not is_nil(cost), do: "ab-tag--you"
  defp tag_class(_executor), do: "ab-tag--stale"

  defp value(%{source: "codex"} = executor) do
    case executor.quota do
      %{used_percent: percent} ->
        gettext("%{percent}% of weekly quota", percent: percent(percent))

      nil ->
        gettext("unknown")
    end
  end

  defp value(%{cost: nil}), do: gettext("unknown")
  defp value(%{cost: %{micros: micros, complete?: true, unknown: 0}}), do: "≈ #{money(micros)}"
  defp value(%{cost: %{micros: micros}}), do: "≥ #{money(micros)}"

  defp subtitle(%{source: "dsh"}),
    do:
      gettext(
        "Estimated in US$ using board prices; unpriced cache reads make this a lower bound."
      )

  defp subtitle(%{source: "claude_code"}),
    do:
      gettext(
        "Estimated at the Max subscription list price: reference only, not billed. Actual quota is unknown."
      )

  defp subtitle(%{source: "codex"}),
    do: gettext("Measured within the weekly window of the ChatGPT plan; no USD value for Codex.")

  defp day_value(nil, _source), do: "—"

  defp day_value(row, source) do
    cost =
      cond do
        source == "codex" -> gettext("unknown")
        is_nil(row.cost) -> gettext("unknown")
        row.cost.complete? -> "≈ " <> money(row.cost.micros)
        true -> "≥ " <> money(row.cost.micros)
      end

    cost <> " · " <> token_line(row)
  end

  defp token_line(row) do
    "#{tokens(row.input_tokens)} in / #{tokens(row.output_tokens)} out"
  end

  defp merged(%{tasks: 0, rate: nil}), do: "—"

  defp merged(%{merged: merged, tasks: tasks, rate: rate}),
    do: "#{merged}/#{tasks} (#{percent(rate * 100)}%)"

  defp hours(nil), do: "—"

  defp hours(hours) do
    value = :erlang.float_to_binary(hours / 1.0, decimals: 1) |> String.replace(".", ",")
    "#{value} h"
  end

  defp number(n), do: Integer.to_string(n)

  defp tokens(0), do: "—"

  defp tokens(n) when n >= 1_000_000,
    do: "#{float(n / 1_000_000)}M"

  defp tokens(n) when n >= 1000, do: "#{float(n / 1000)}k"
  defp tokens(n), do: Integer.to_string(n)

  defp float(value),
    do: :erlang.float_to_binary(value / 1.0, decimals: 1) |> String.replace(".", ",")

  defp percent(value) when is_float(value),
    do: value |> :erlang.float_to_binary(decimals: 0) |> String.replace(".", ",")

  defp percent(value), do: Integer.to_string(value)

  defp money(micros) do
    cents = div(micros + 5_000, 10_000)

    "US$ #{div(cents, 100)},#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp names(list) do
    shown = Enum.take(list, 4)
    more = length(list) - length(shown)
    text = Enum.map_join(shown, ", ", fn {name, count} -> "#{name} (#{count})" end)
    if more > 0, do: text <> " e mais #{more}", else: text
  end
end
