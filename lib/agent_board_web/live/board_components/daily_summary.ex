defmodule AgentBoardWeb.BoardComponents.DailySummary do
  @moduledoc """
  The summary of the day under the digest: what was done, what failed and
  still needs the owner, what the board did on its own and what each
  executor spent. It renders the facts stored in the row
  (`AgentBoard.DailySummary.Entry`), never a recomputation; it arrives with
  a broadcast and leaves when dismissed, without motion (`docs/ui-motion.md`:
  data that arrives is not animated). The `DailySummaryVoice` hook asks to
  speak it from a tab the owner has interacted with.
  """
  use AgentBoardWeb, :html

  alias AgentBoard.Time

  @labels %{"deepseek" => "DeepSeek", "claude" => "Claude Code", "codex" => "Codex"}

  attr :entry, :map, required: true
  attr :tz_offset, :integer, default: 0

  def daily_summary(assigns) do
    content = assigns.entry.content

    assigns =
      assign(assigns,
        merged: content["merged"] || %{},
        needs: content["needs"] || %{},
        sync_errors: content["sync_errors"] || 0,
        retries: content["retries"] || %{},
        spend: content["spend"] || []
      )

    ~H"""
    <section
      id="daily-summary"
      class="ab-daily"
      aria-labelledby="daily-summary-title"
      phx-hook="DailySummaryVoice"
      data-id={@entry.id}
      data-spoken={to_string(not is_nil(@entry.spoken_at))}
    >
      <header class="ab-daily__head">
        <h2 id="daily-summary-title">Resumo do dia</h2>
        <span class="ab-daily__since">
          desde {Time.since_label(@entry.window_start, @tz_offset, @entry.generated_at)}
        </span>
        <button
          id="daily-summary-dismiss"
          type="button"
          class="ab-btn ab-btn--sm ab-daily__dismiss"
          phx-click="dismiss_daily_summary"
          phx-value-id={@entry.id}
          data-daily-dismiss
          aria-label="Dispensar o resumo do dia"
        >
          Dispensar
        </button>
      </header>
      <dl class="ab-daily__rows">
        <div>
          <dt>Feito</dt>
          <dd>
            {merged_text(@merged["count"] || 0)}<.refs items={@merged["items"] || []} />
          </dd>
        </div>
        <div>
          <dt>Falhas e pendências</dt>
          <dd>
            {needs_text(@needs)}<.refs items={@needs["items"] || []} />{sync_text(@sync_errors)}
          </dd>
        </div>
        <div>
          <dt>O board fez sozinho</dt>
          <dd>{retries_text(@retries)}</dd>
        </div>
        <div>
          <dt>Gasto</dt>
          <dd class="ab-daily__spend">
            <span :for={line <- @spend} title={spend_title(line)}>
              {label(line)} <b>{spend_text(line)}</b>
            </span>
          </dd>
        </div>
      </dl>
    </section>
    """
  end

  attr :items, :list, required: true

  defp refs(assigns) do
    ~H"""
    <span :if={@items != []} class="ab-daily__refs" phx-no-format> (<%= for {item, i} <- Enum.with_index(@items) do %><%= if i > 0 do %>, <% end %><a href={item["url"]} title={"#{item["repo"]}: #{item["title"]}"} target="_blank" rel="noopener noreferrer">#{item["number"]}</a><% end %>)</span>
    """
  end

  defp merged_text(0), do: "Nenhum PR mesclado"
  defp merged_text(1), do: "1 PR mesclado"
  defp merged_text(n), do: "#{n} PRs mesclados"

  defp needs_text(needs) do
    blocked = needs["blocked"] || 0
    waiting = needs["waiting"] || 0

    case {blocked, waiting} do
      {0, 0} -> "Nada esperando você"
      {b, 0} -> "#{b} #{plural(b, "bloqueada", "bloqueadas")}"
      {0, w} -> "#{w} esperando você"
      {b, w} -> "#{b} #{plural(b, "bloqueada", "bloqueadas")}, #{w} esperando você"
    end
  end

  defp sync_text(n) when is_integer(n) and n > 0,
    do: "; a sincronização falhou #{n} #{plural(n, "vez", "vezes")}"

  defp sync_text(_n), do: nil

  defp retries_text(%{"sent" => sent} = retries) when is_integer(sent) and sent > 0 do
    tasks = retries["tasks"] || 0
    refused = retries["not_accepted"] || 0

    head =
      "#{sent} #{plural(sent, "nova tentativa automática", "novas tentativas automáticas")}" <>
        if(tasks > 1, do: " em #{tasks} tarefas", else: "")

    if refused > 0,
      do: "#{head}; #{refused} não #{plural(refused, "foi aceita", "foram aceitas")}",
      else: head
  end

  defp retries_text(_retries), do: "Nenhuma nova tentativa automática"

  defp label(line), do: Map.get(@labels, line["executor"], line["executor"])

  defp spend_text(%{"status" => "measured", "currency" => "quota"} = line) do
    "#{percent(line["percent"])}% da cota semanal"
  end

  defp spend_text(%{"status" => "measured", "micros" => micros} = line) when is_integer(micros) do
    cond do
      micros < 5_000 -> "menos de US$ 0,01" <> list_mark(line)
      line["complete"] == false -> "≥ #{dollars(micros)}" <> list_mark(line)
      true -> "≈ #{dollars(micros)}" <> list_mark(line)
    end
  end

  defp spend_text(%{"status" => "none"}), do: "não rodou"
  defp spend_text(_line), do: "desconhecido"

  defp list_mark(%{"reference" => "list"}), do: " (lista)"
  defp list_mark(_line), do: ""

  defp percent(value) when is_float(value),
    do: value |> :erlang.float_to_binary(decimals: 0) |> String.replace(".", ",")

  defp percent(value), do: to_string(value)

  defp spend_title(%{"status" => "measured", "currency" => "quota"} = line) do
    "Cota semanal do plano ChatGPT: #{percent(line["percent"])}% usada." <>
      if(line["resets_at"],
        do: " Renova em #{line["resets_at"]}.",
        else: " Sem hora de renovação na leitura."
      ) <>
      " Não há valor em dólar para o Codex."
  end

  defp spend_title(%{"status" => "measured"} = line) do
    requests = line["requests"]
    models = Enum.join(line["models"] || [], ", ")

    prefix =
      if line["reference"] == "list",
        do:
          "Preço de lista do Claude Max; é uma referência, não a fatura, e a cota real é desconhecida",
        else: "Estimado pelo preço de tabela"

    prefix <>
      if(is_integer(requests), do: ", #{requests} chamadas", else: "") <>
      if(models != "", do: " (#{models})", else: "") <>
      if(line["complete"] == false,
        do: "; um tipo de token sem preço faz disto um mínimo",
        else: ""
      )
  end

  defp spend_title(%{"status" => "none"}), do: "Nenhuma chamada na janela do resumo"

  defp spend_title(%{"reason" => "no_source"}),
    do: "Sem fonte de uso: o board ainda não lê este executor"

  defp spend_title(%{"reason" => "no_quota"}),
    do: "Sem leitura da cota semanal do Codex"

  defp spend_title(%{"reason" => "zstd_missing"}),
    do: "Sem o zstd no PATH, as transcrições não podem ser lidas"

  defp spend_title(%{"reason" => "no_price"}),
    do: "O modelo usado não tem preço na tabela do board"

  defp spend_title(_line), do: "As transcrições não puderam ser lidas"

  defp dollars(micros) do
    cents = div(micros + 5_000, 10_000)

    "US$ #{div(cents, 100)},#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp plural(1, one, _many), do: one
  defp plural(_n, _one, many), do: many
end
