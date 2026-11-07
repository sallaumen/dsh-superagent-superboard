defmodule AgentBoardWeb.BoardComponents.Shortcuts do
  @moduledoc "The keyboard reference, shown as a layer so the board stays put."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Controls, only: [kbd: 1]

  def shortcuts(assigns) do
    ~H"""
    <div class="panel-shortcuts">
      <dl class="ab-keys">
        <dt><.kbd key="J" /><.kbd key="K" /></dt>
        <dd>Próxima / anterior</dd>
        <dt><.kbd key="↵" /></dt>
        <dd>Abrir no painel</dd>
        <dt><.kbd key="Esc" /></dt>
        <dd>Fechar painel ou camada</dd>
        <dt><.kbd key="N" /></dt>
        <dd>Novo pedido</dd>
        <dt><.kbd key="Espaço" /><.kbd key="Espaço" /></dt>
        <dd>
          Conversar com o agente: fale e pare, ele envia sozinho. Diga "ajuda" para a lista do que pedir
        </dd>
        <dt><.kbd key="Esc" /></dt>
        <dd>Cancelar a fala ou a resposta em andamento</dd>
        <dt><.kbd key="V" /></dt>
        <dd>Ditar um pedido no composer</dd>
        <dt><.kbd key="1" />–<.kbd key="4" /></dt>
        <dd>Trocar aba do painel</dd>
        <dt><.kbd key="?" /></dt>
        <dd>Esta lista</dd>
      </dl>
    </div>
    """
  end
end
