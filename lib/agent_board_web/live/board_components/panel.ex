defmodule AgentBoardWeb.BoardComponents.Panel do
  @moduledoc "Native dialog shell; region content remains mounted for draft preservation."
  use AgentBoardWeb, :html

  alias AgentBoardWeb.BoardComponents.{Controls, VoicePresence}
  alias AgentBoardWeb.BoardNotice

  attr :icon, :string, default: nil
  attr :name, :string, required: true
  attr :title, :string, required: true
  attr :active, :boolean, required: true
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def shell(assigns) do
    ~H"""
    <dialog id={"panel-#{@name}"} aria-labelledby={"panel-title-#{@name}"} class="board-dialog">
      <header class="panel-heading">
        <h2 id={"panel-title-#{@name}"} tabindex="-1">
          <Controls.ico :if={@icon} name={@icon} />{@title}
        </h2>
        <button
          type="button"
          phx-click="close"
          aria-label={gettext("Close %{title}", title: @title)}
          class="panel-close"
        ><.icon
          name="hero-x-mark"
          class="size-4 shrink-0"
        />{gettext("Close")}</button>
      </header>
      <p class="panel-reconnect text-warning" role="status">
        {gettext("Reconnecting · showing saved data")}
      </p>
      <BoardNotice.notices :if={@active} flash={@flash} prefix={"panel-#{@name}"} />
      <div class="panel-scroll">{render_slot(@inner_block)}</div>
      <VoicePresence.stage :if={@active} id={"voice-presence-#{@name}"} />
    </dialog>
    """
  end
end
