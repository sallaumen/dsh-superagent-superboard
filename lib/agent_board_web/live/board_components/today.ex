defmodule AgentBoardWeb.BoardComponents.Today do
  @moduledoc """
  A visão "Hoje": o que precisa do dono nos dois repositórios numa lista só,
  com o repositório em cada item, o que está rodando e o gasto do dia em cada
  moeda (`docs/research/alfred.md`, 3.4 e F2.1).

  A leitura vem de `Overview.today/2` e `Usage.Report.today/0`, calculadas na
  mesma carga do board; o componente não consulta o banco. Dado que chega não
  anima (`docs/ui-motion.md`).
  """
  use AgentBoardWeb, :html

  alias AgentBoard.Time
  import AgentBoardWeb.Components.VersionBadge, only: [version_badge: 1]
  import AgentBoardWeb.BoardComponents.DailySummary, only: [daily_summary: 1]

  @sources ["dsh", "claude_code", "codex"]
  @labels %{"dsh" => "DeepSeek", "claude_code" => "Claude Code", "codex" => "Codex"}
  @states %{
    "blocked" => "bloqueado",
    "question" => "pergunta",
    "ready" => "para revisar",
    "running" => "rodando"
  }

  attr :today, :map, required: true
  attr :spend, :map, default: nil
  attr :offset, :integer, default: 0
  attr :now, :any, default: nil
  attr :version, :map, default: %{state: :unknown}
  attr :daily_summary, :map, default: nil

  def today_view(assigns) do
    now = assigns.now || DateTime.utc_now()

    assigns =
      assigns
      |> assign(:now, now)
      |> assign(:spend_rows, spend_rows(assigns.spend))
      |> assign(:date_label, date_label(now, assigns.offset))
      |> assign(:projects, Map.get(assigns.today, :projects, []))
      |> assign(:trend, trend_bars(Map.get(assigns.today, :trend, [])))
      |> assign(:merged_today, Map.get(assigns.today, :merged_today, 0))
      |> assign(:seen_today, Map.get(assigns.today, :seen_today, 0))
      |> assign(:queued, length(Map.get(assigns.today, :queue, [])))

    ~H"""
    <section id="today" class="ab-today" aria-labelledby="today-title">
      <header class="ab-today__head">
        <div class="ab-today__title-row">
          <h1 id="today-title">Hoje</h1>
          <span class="ab-today__date">{@date_label}</span>
          <.version_badge version={@version} />
        </div>
        <p class="ab-meta ab-today__scope">
          Todos os projetos acompanhados · dados registrados no board
        </p>
      </header>

      <section id="today-overview" class="ab-today__overview" aria-label="Hoje até agora">
        <div class="ab-today__metric">
          <span class="ab-label">PRs mesclados hoje</span>
          <strong>{@merged_today}</strong>
          <span class="ab-meta">registrados no board</span>
        </div>
        <div class="ab-today__metric">
          <span class="ab-label">Issues vistas hoje</span>
          <strong>{@seen_today}</strong>
          <span class="ab-meta">primeira leitura pelo board</span>
        </div>
        <div class="ab-today__metric">
          <span class="ab-label">Na fila agora</span>
          <strong>{@queued}</strong>
          <span class="ab-meta">em todos os projetos</span>
        </div>
      </section>

      <section id="today-needs" class="ab-today__section" aria-labelledby="today-needs-title">
        <div class="ab-sec__head">
          <h2 id="today-needs-title">Precisa de você</h2>
          <span class="ab-sec__count">{length(@today.needs)}</span>
        </div>

        <p :if={@today.needs == []} class="ab-sec__empty">
          Nada esperando você nos repositórios do board.
        </p>

        <ol :if={@today.needs != []} class="ab-today__list">
          <li :for={item <- @today.needs}>
            <button
              type="button"
              class="ab-today__item"
              phx-click="open_any"
              phx-value-id={item.id}
            >
              <span class="ab-today__repo">{item.repo}</span>
              <span class="ab-today__num">#{item.number}</span>
              <span class="ab-today__title">{item.title}</span>
              <span class={["ab-tag", "ab-today__state", tag_class(item.state)]}>
                {state_label(item.state)}
              </span>
              <span class="ab-meta ab-today__age">{ago(item.at, @now)}</span>
              <span class="ab-today__action">{action_label(item.state)}</span>
            </button>
          </li>
        </ol>
      </section>

      <section id="today-running" class="ab-today__section" aria-labelledby="today-running-title">
        <div class="ab-sec__head">
          <h2 id="today-running-title">Rodando agora</h2>
          <span class="ab-sec__count">{length(@today.running)}</span>
        </div>

        <p :if={@today.running == []} class="ab-sec__empty">Nada rodando agora.</p>

        <ol :if={@today.running != []} class="ab-today__list">
          <li :for={item <- @today.running}>
            <button
              type="button"
              class="ab-today__item"
              phx-click="open_any"
              phx-value-id={item.id}
            >
              <span class="ab-today__repo">{item.repo}</span>
              <span class="ab-today__num">#{item.number}</span>
              <span class="ab-today__title">{item.title}</span>
              <span class="ab-tag ab-tag--agent ab-today__state">
                {item[:executor_name] || state_label(item.state)}
              </span>
              <span class="ab-meta ab-today__age">{elapsed(item[:started_at], @now)}</span>
              <span class="ab-today__action">Abrir</span>
            </button>
          </li>
        </ol>
      </section>

      <section id="today-projects" class="ab-today__section" aria-labelledby="today-projects-title">
        <div class="ab-sec__head">
          <h2 id="today-projects-title">Por projeto</h2>
          <span class="ab-sec__count">{length(@projects)}</span>
        </div>
        <p :if={@projects == []} class="ab-sec__empty">Nenhum projeto acompanhado.</p>
        <div :if={@projects != []} class="ab-today__projects-wrap">
          <table class="ab-today__projects">
            <thead>
              <tr>
                <th scope="col">Projeto</th><th scope="col">Precisa de você</th><th scope="col">
                  Rodando
                </th><th scope="col">Fila</th><th scope="col">PRs hoje</th><th scope="col">
                  Leitura
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={project <- @projects}>
                <th scope="row">
                  <button
                    type="button"
                    class="ab-today__project-link"
                    phx-click="select"
                    phx-value-repo={project.name}
                  >{project.name}</button>
                </th>
                <td data-label="Precisa de você">{project.needs}</td><td data-label="Rodando">
                  {project.running}
                </td><td data-label="Fila">{project.queued}</td><td data-label="PRs hoje">
                  {project.merged}
                </td>
                <td
                  class={
                    if(project.unknown,
                      do: "ab-today__freshness ab-today__freshness--unknown",
                      else: "ab-today__freshness"
                    )
                  }
                  data-label="Leitura"
                >
                  {freshness_label(project)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section id="today-trend" class="ab-today__section" aria-labelledby="today-trend-title">
        <div class="ab-sec__head">
          <h2 id="today-trend-title">PRs mesclados · 7 dias</h2>
        </div>
        <p class="ab-meta ab-today__note">
          Pela data de mesclagem, entre os PRs registrados no board. Os dias seguem seu horário local.
        </p>
        <ol class="ab-today__trend" aria-label="PRs mesclados nos últimos sete dias">
          <li :for={bar <- @trend} aria-label={bar.description}>
            <span class="ab-today__bar-number">{bar.count}</span>
            <span class="ab-today__bar-track"><span
              class="ab-today__bar"
              style={"height: #{bar.height}%"}
            ></span></span>
            <span class="ab-today__bar-day">{bar.label}</span>
          </li>
        </ol>
      </section>

      <section id="today-spend" class="ab-today__section" aria-label="Gasto do dia">
        <div class="ab-sec__head">
          <h2>Uso hoje</h2>
        </div>
        <div class="ab-today__spend">
          <span :for={row <- @spend_rows} class="ab-today__money" title={row.title}>
            {row.label} <b>{row.value}</b>
          </span>
        </div>
      </section>

      <section
        :if={@daily_summary}
        id="today-daily-report"
        class="ab-today__section"
        aria-label="Último resumo gerado pelo board"
      >
        <.daily_summary entry={@daily_summary} tz_offset={@offset} />
      </section>

      <footer class="ab-today__legend" aria-label="Legenda">
        <span><i class="ab-g ab-g--run"></i>rodando</span>
        <span><i class="ab-g ab-g--you"></i>espera você</span>
        <span><i class="ab-g ab-g--halt"></i>bloqueado ou falhou</span>
        <span><i class="ab-g ab-g--queue"></i>na fila</span>
      </footer>
    </section>
    """
  end

  defp freshness_label(%{last_sync: nil}), do: "sem leitura"
  defp freshness_label(%{unknown: true, last_sync: %{kind: "sync_error"}}), do: "falhou"
  defp freshness_label(%{unknown: true}), do: "atrasada"
  defp freshness_label(_project), do: "atualizada"

  defp trend_bars([]), do: []

  defp trend_bars(trend) do
    top = trend |> Enum.map(& &1.count) |> Enum.max() |> max(1)
    today = List.last(trend).date

    Enum.map(trend, fn point ->
      %{
        count: point.count,
        label: Time.short_day_label(point.date, today),
        description: "#{Time.day_label(point.date, today)}: #{point.count} PRs mesclados",
        height: round(point.count / top * 100)
      }
    end)
  end

  defp spend_rows(nil) do
    for source <- @sources,
        do: %{
          label: Map.fetch!(@labels, source),
          value: "desconhecido",
          title: "Sem leitura do livro de uso para hoje"
        }
  end

  defp spend_rows(spend) do
    Enum.map(@sources, fn source ->
      %{
        label: Map.fetch!(@labels, source),
        value: value(source, spend),
        title: title(source, spend)
      }
    end)
  end

  defp value("codex", spend) do
    case spend.quota do
      %{used_percent: percent} -> "#{percent(percent)}% da cota semanal"
      nil -> "desconhecido"
    end
  end

  defp value(source, spend) do
    case Map.get(spend.by_source, source) do
      nil ->
        "não rodou"

      %{status: :none} ->
        "não rodou"

      %{status: :unknown} ->
        "desconhecido"

      %{cost: nil} ->
        "desconhecido"

      %{cost: %{micros: micros, complete?: true}} ->
        "≈ #{money(micros)}"

      %{cost: %{micros: micros}} ->
        "≥ #{money(micros)}"
    end
  end

  defp title("codex", spend) do
    case spend.quota do
      %{used_percent: percent, resets_at: at} when is_binary(at) ->
        "Cota semanal do plano ChatGPT: #{percent(percent)}% usada; renova em #{at}."

      %{used_percent: percent} ->
        "Cota semanal do plano ChatGPT: #{percent(percent)}% usada."

      nil ->
        "Sem leitura da cota semanal do Codex"
    end
  end

  defp title("claude_code", _spend),
    do: "Estimado a preço de lista do Claude Max; é uma referência, não a fatura."

  defp title("dsh", _spend), do: "Estimado em US$ pela tabela do board."

  defp date_label(now, offset) do
    at = DateTime.add(now, -offset * 60, :second)
    "#{weekday(at)} #{at.day} de #{month(at)}"
  end

  defp weekday(at) do
    ~w(segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado domingo)
    |> Enum.at(Date.day_of_week(DateTime.to_date(at)) - 1)
  end

  defp month(at) do
    ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)
    |> Enum.at(at.month - 1)
  end

  defp state_label(state), do: Map.get(@states, state, state)

  defp action_label("blocked"), do: "Abrir"
  defp action_label("question"), do: "Responder"
  defp action_label("ready"), do: "Revisar"
  defp action_label(_state), do: "Abrir"

  defp elapsed(nil, _now), do: "agora"

  defp elapsed(%DateTime{} = at, now),
    do: AgentBoard.Time.duration(AgentBoard.Time.age_seconds(at, now))

  defp tag_class("blocked"), do: "ab-tag--halt"
  defp tag_class("question"), do: "ab-tag--you"
  defp tag_class("ready"), do: "ab-tag--you"
  defp tag_class(_state), do: "ab-tag--agent"

  defp ago(nil, _now), do: "agora"
  defp ago(at, now), do: Time.ago(Time.age_seconds(at, now))

  defp percent(value) when is_float(value),
    do: value |> :erlang.float_to_binary(decimals: 0) |> String.replace(".", ",")

  defp percent(value), do: Integer.to_string(value)

  defp money(micros) do
    cents = div(micros + 5_000, 10_000)

    "US$ #{div(cents, 100)},#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end
end
