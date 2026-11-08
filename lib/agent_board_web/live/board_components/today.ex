defmodule AgentBoardWeb.BoardComponents.Today do
  @moduledoc """
  A visão "Hoje": o que precisa do dono nos dois repositórios numa lista só,
  com o repositório em cada item, o que está rodando e o gasto do dia em cada
  moeda (`docs/research/alfred.md`, 3.4 e F2.1).

  A leitura vem de `Board.today/0` e `Usage.Report.today/0`, calculadas na
  mesma carga do board; o componente não consulta o banco. Dado que chega não
  anima (`docs/ui-motion.md`).
  """
  use AgentBoardWeb, :html

  alias AgentBoard.Time

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

  def today_view(assigns) do
    now = DateTime.utc_now()

    assigns =
      assigns
      |> assign(:now, now)
      |> assign(:spend_rows, spend_rows(assigns.spend))
      |> assign(:date_label, date_label(now, assigns.offset))

    ~H"""
    <section id="today" class="ab-today" aria-labelledby="today-title">
      <header class="ab-today__head">
        <div>
          <p class="ab-label">Hoje</p>
          <h1 id="today-title">{@date_label}</h1>
        </div>
        <div id="today-spend" class="ab-today__spend" aria-label="Gasto do dia">
          <span :for={row <- @spend_rows} class="ab-today__money" title={row.title}>
            {row.label} <b>{row.value}</b>
          </span>
        </div>
      </header>

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
              <span class={["ab-tag", tag_class(item.state)]}>{state_label(item.state)}</span>
              <span class="ab-meta">{ago(item.at, @now)}</span>
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
              <span class="ab-tag ab-tag--agent">{state_label(item.state)}</span>
              <span class="ab-meta">{ago(item.at, @now)}</span>
            </button>
          </li>
        </ol>
      </section>

      <p class="ab-meta ab-today__note">
        O repositório aparece em cada item. O gasto é por executor, na moeda de
        cada um, e nunca somado. "Não rodou" é um dia sem chamadas; "desconhecido"
        é fonte sem leitura.
      </p>
    </section>
    """
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
    at = DateTime.add(now, offset * 60, :second)
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
