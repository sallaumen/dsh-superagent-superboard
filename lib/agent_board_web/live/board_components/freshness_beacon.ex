defmodule AgentBoardWeb.BoardComponents.FreshnessBeacon do
  @moduledoc "The one place that says whether what is on screen is current."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1, status_mark: 1]

  attr :freshness, :map, required: true
  attr :tz_offset, :integer, default: 0

  def beacon(assigns) do
    assigns =
      assigns
      |> assign(:age_text, age_text(assigns.freshness, assigns.tz_offset))

    ~H"""
    <details id="sync-status" class="ab-sync">
      <summary
        class="ab-beacon"
        data-state={@freshness.state}
        aria-label={"Estado da sincronia: #{label(@freshness.state)}"}
      >
        <span class="ab-beacon__normal">
          <.glyph :if={@freshness.state == :live} kind={:run} live />
          <.glyph :if={@freshness.state in [:delayed, :offline]} kind={:stale} />
          <.glyph :if={@freshness.state == :unknown} kind={:unknown} />
          <i :if={@freshness.state == :reconnecting} class="ab-spin" aria-hidden="true"></i>
          <b>{label(@freshness.state)}</b>
          <span class="ab-beacon__age" data-age={@freshness.age_sec}>{@age_text}</span>
        </span>
        <span class="ab-beacon__reconnect">
          <i class="ab-spin" aria-hidden="true"></i>
          <b>Reconectando</b>
          <span class="ab-beacon__age">dados de {time(@freshness.at, @tz_offset)}</span>
        </span>
      </summary>

      <div class="ab-sync-pop" role="region" aria-label="Detalhes da sincronia">
        <h4>{@freshness.title}</h4>
        <div class="ab-meta">{@freshness.note}</div>
        <dl>
          <div :for={source <- @freshness.sources} class="ab-sync-pop__source">
            <dt>{source.label}</dt>
            <dd>
              <.status_mark kind={source.kind} word={source.word} />
              <span class="ab-meta">{source.detail}</span>
            </dd>
          </div>
        </dl>
        <p class="ab-meta ab-sync-pop__cadence">
          O GitHub é conferido a cada 5 minutos; o processo do agente, a cada 10 segundos.
        </p>
      </div>
    </details>
    """
  end

  defp label(:live), do: "Ao vivo"
  defp label(:delayed), do: "Atrasado"
  defp label(:reconnecting), do: "Reconectando"
  defp label(:offline), do: "Sem conexão"
  defp label(:unknown), do: "Sem dados ainda"

  defp age_text(%{state: :live, age_sec: sec}, _offset) when is_integer(sec),
    do: "há #{short(sec)}"

  defp age_text(%{state: :live}, _offset), do: "agora"

  defp age_text(%{state: state, at: nil}, _offset) when state in [:delayed, :offline],
    do: "dados de horário desconhecido"

  defp age_text(%{state: state} = freshness, offset) when state in [:delayed, :offline] do
    "dados de #{time(freshness.at, offset)} · #{ago(freshness.age_sec)}"
  end

  defp age_text(%{state: :reconnecting, at: nil}, _offset), do: "dados de horário desconhecido"

  defp age_text(%{state: :reconnecting} = freshness, offset),
    do: "dados de #{time(freshness.at, offset)}"

  defp age_text(_freshness, _offset), do: "aguardando 1ª sincronia"

  defp time(nil, _offset), do: "—"
  defp time(%DateTime{} = at, offset), do: AgentBoard.Time.local_time(at, offset)

  defp short(nil), do: "agora"
  defp short(sec) when sec < 60, do: "#{sec} s"
  defp short(sec) when sec < 3600, do: "#{div(sec, 60)} min"
  defp short(sec), do: "#{div(sec, 3600)} h"

  defp ago(nil), do: "há quanto tempo? desconhecido"
  defp ago(sec) when sec < 60, do: "há #{sec} s"
  defp ago(sec) when sec < 3600, do: "há #{div(sec, 60)} min"
  defp ago(sec) when sec < 86_400, do: "há #{div(sec, 3600)} h"
  defp ago(sec), do: "há #{div(sec, 86_400)} d"
end
