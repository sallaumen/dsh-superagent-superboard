defmodule AgentBoardWeb.BoardComponents.FrozenBanner do
  @moduledoc "The banner that tells the board is showing saved data, never current data."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1]
  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]

  attr :freshness, :map, required: true
  attr :tz_offset, :integer, default: 0

  def frozen_banner(assigns) do
    ~H"""
    <div :if={@freshness.frozen?} class="ab-frozen" role="status">
      <.glyph kind={:stale} />
      <span :if={@freshness.at}>
        <strong>Mostrando o que sabíamos às {time(@freshness.at, @tz_offset)}.</strong>
        Tempos e contagens estão parados; o agente pode ter avançado.
      </span>
      <span :if={is_nil(@freshness.at)}>
        <strong>Mostrando os últimos dados salvos.</strong>
        Não sabemos a hora da última sincronia; tempos e contagens estão parados.
      </span>
      <span class="ab-top__spacer"></span>
      <button type="button" class="ab-btn ab-btn--sm" phx-click="sync_now">
        <.ico name="retry" />Tentar agora
      </button>
    </div>

    <div :if={not @freshness.frozen?} id="reconnect-banner" class="ab-frozen" role="status">
      <.glyph kind={:stale} />
      <span :if={@freshness.at}>
        <strong>Reconectando.</strong>
        Mostrando o que sabíamos às {time(@freshness.at, @tz_offset)}; os tempos estão parados.
      </span>
      <span :if={is_nil(@freshness.at)}>
        <strong>Reconectando.</strong> Mostrando os últimos dados salvos; os tempos estão parados.
      </span>
      <span class="ab-top__spacer"></span>
      <button type="button" class="ab-btn ab-btn--sm" phx-click="sync_now">
        <.ico name="retry" />Tentar agora
      </button>
    </div>
    """
  end

  defp time(nil, _offset), do: "—"
  defp time(%DateTime{} = at, offset), do: AgentBoard.Time.local_time(at, offset)
end
