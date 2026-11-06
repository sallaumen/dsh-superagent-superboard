defmodule AgentBoardWeb.BoardComponents.FrozenBanner do
  @moduledoc "The banner that tells the board is showing saved data, never current data."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1]
  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]

  attr :freshness, :map, required: true

  def frozen_banner(assigns) do
    ~H"""
    <div :if={@freshness.frozen?} class="ab-frozen" role="status">
      <.glyph kind={:stale} />
      <span>
        <strong>Mostrando o que sabíamos às {time(@freshness.at)}.</strong>
        Tempos e contagens estão parados; o agente pode ter avançado.
      </span>
      <span class="ab-top__spacer"></span>
      <button type="button" class="ab-btn ab-btn--sm" phx-click="sync_now">
        <.ico name="retry" />Tentar agora
      </button>
    </div>

    <div :if={not @freshness.frozen?} id="reconnect-banner" class="ab-frozen" role="status">
      <.glyph kind={:stale} />
      <span>
        <strong>Reconectando.</strong>
        Mostrando o que sabíamos às {time(@freshness.at)}; os tempos estão parados.
      </span>
      <span class="ab-top__spacer"></span>
      <button type="button" class="ab-btn ab-btn--sm" phx-click="sync_now">
        <.ico name="retry" />Tentar agora
      </button>
    </div>
    """
  end

  defp time(nil), do: "—"
  defp time(%DateTime{} = at), do: Calendar.strftime(at, "%H:%M")
end
