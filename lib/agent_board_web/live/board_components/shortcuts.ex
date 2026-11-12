defmodule AgentBoardWeb.BoardComponents.Shortcuts do
  @moduledoc "The keyboard reference, shown as a layer so the board stays put."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Controls, only: [kbd: 1]

  def shortcuts(assigns) do
    ~H"""
    <div class="panel-shortcuts">
      <dl class="ab-keys">
        <dt><.kbd key="J" /><.kbd key="K" /></dt>
        <dd>{gettext("Next / Previous")}</dd>
        <dt><.kbd key="↵" /></dt>
        <dd>{gettext("Open in dashboard")}</dd>
        <dt><.kbd key="Esc" /></dt>
        <dd>{gettext("Close the panel or layer, or stop the speech or answer")}</dd>
        <dt><.kbd key="N" /></dt>
        <dd>{gettext("New request")}</dd>
        <dt><.kbd key={gettext("Space")} /><.kbd key={gettext("Space")} /></dt>
        <dd>{gettext("Open Chat")}</dd>
        <dt><.kbd key="V" /></dt>
        <dd>{gettext("Dictate a request in the composer")}</dd>
        <dt><.kbd key="1" />–<.kbd key="5" /></dt>
        <dd>{gettext("Switch panel tab")}</dd>
        <dt><.kbd key="?" /></dt>
        <dd>{gettext("This list")}</dd>
      </dl>
    </div>
    """
  end
end
