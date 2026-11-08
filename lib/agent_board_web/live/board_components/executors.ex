defmodule AgentBoardWeb.BoardComponents.Executors do
  @moduledoc """
  O painel "Executores": os últimos 7 ou 30 dias de Claude Code, Codex e
  DeepSeek, cada um na sua moeda, lidos do livro de uso
  (`AgentBoard.Usage.Report`).

  Os tokens são medidos; o US$ é estimado e a cota do Codex é a leitura mais
  recente. Um valor sem fonte é "desconhecido", nunca zero, e os executores
  nunca são somados. O painel lê uma vez quando abre ou quando a janela
  muda; um render não consulta o banco de novo.
  """
  use AgentBoardWeb, :html

  alias AgentBoard.Time

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
          <p id="executors-title" class="ab-label">Últimos {@days} dias</p>
          <p class="ab-meta">
            Tokens medidos. Cada executor na sua moeda, nunca somados.
          </p>
        </div>
        <div class="ab-executors__range" role="group" aria-label="Janela do painel">
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

      <div :if={is_nil(@report)} class="ab-sec__empty">Lendo o livro de uso…</div>

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
              <dt>Sessões</dt><dd>{executor.executions}</dd>
            </div>
            <div>
              <dt>Tarefas</dt><dd>{executor.tasks_count}</dd>
            </div>
            <div>
              <dt>Requisições</dt><dd>{number(executor.requests)}</dd>
            </div>
            <div>
              <dt>Entrada</dt><dd>{tokens(executor.input_tokens)}</dd>
            </div>
            <div>
              <dt>Saída</dt><dd>{tokens(executor.output_tokens)}</dd>
            </div>
            <div>
              <dt>Mescladas</dt><dd>{merged(executor.merged)}</dd>
            </div>
            <div>
              <dt>Tempo até o merge</dt><dd>{hours(executor.merged.median_hours)}</dd>
            </div>
          </dl>

          <p :if={executor.direct != []} class="ab-meta">
            Diretas: {names(executor.direct)}
          </p>
          <p :if={executor.outside != []} class="ab-meta">
            Fora do board: {names(executor.outside)}
          </p>
          <p :if={executor.unknown > 0} class="ab-meta">
            Sem repositório: {executor.unknown}
          </p>
          <p :if={executor.tasks != []} class="ab-meta">
            Tarefas:
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
        <h3 class="ab-label">Por dia</h3>
        <div :if={@days_data == []} class="ab-sec__empty">
          Nenhuma linha no livro de uso nesta janela.
        </div>
        <article :for={day <- @days_data} class="ab-exec-day">
          <header>
            <h4>{Time.day_label(day.date, Date.utc_today())}</h4>
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
          Dias UTC, como o livro. "—" é dia sem uso; "desconhecido" é fonte sem
          leitura. A cota do Codex é a leitura mais recente, não um valor por dia.
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

  defp tag(%{source: source} = executor) do
    cond do
      source == "codex" and executor.quota -> "medido"
      source != "codex" and executor.cost -> "estimado"
      true -> "desconhecido"
    end
  end

  defp tag_class(%{source: "codex", quota: quota}) when not is_nil(quota), do: "ab-tag--agent"
  defp tag_class(%{cost: cost}) when not is_nil(cost), do: "ab-tag--you"
  defp tag_class(_executor), do: "ab-tag--stale"

  defp value(%{source: "codex"} = executor) do
    case executor.quota do
      %{used_percent: percent} -> "#{percent(percent)}% da cota semanal"
      nil -> "desconhecido"
    end
  end

  defp value(%{cost: nil}), do: "desconhecido"
  defp value(%{cost: %{micros: micros, complete?: true, unknown: 0}}), do: "≈ #{money(micros)}"
  defp value(%{cost: %{micros: micros}}), do: "≥ #{money(micros)}"

  defp subtitle(%{source: "dsh"}),
    do: "Estimado em US$ pela tabela do board; cache sem preço deixa um mínimo."

  defp subtitle(%{source: "claude_code"}),
    do:
      "Estimado a preço de lista da assinatura Max: referência, não fatura. A cota real é desconhecida."

  defp subtitle(%{source: "codex"}),
    do: "Medido na janela semanal do plano ChatGPT; não há valor em US$ para o Codex."

  defp day_value(nil, _source), do: "—"

  defp day_value(row, source) do
    cost =
      cond do
        source == "codex" -> "desconhecido"
        is_nil(row.cost) -> "desconhecido"
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
