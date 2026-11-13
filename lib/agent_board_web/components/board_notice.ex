defmodule AgentBoardWeb.BoardNotice do
  @moduledoc "Transient action feedback belongs to the page or its active native dialog."
  use AgentBoardWeb, :html

  # A LiveComponent's flash is private to it unless it navigates. Forward the
  # outcome to the owning LiveView so it can render it above the active surface.
  def notify(socket, kind, text) when kind in [:info, :error] and is_binary(text) do
    send(self(), {:board_notice, kind, text})
    socket
  end

  attr :flash, :map, required: true
  attr :prefix, :string, default: "flash"

  def notices(assigns) do
    ~H"""
    <div class="board-notices">
      <div
        :for={kind <- [:info, :error]}
        :if={message = Phoenix.Flash.get(@flash, kind)}
        id={"#{@prefix}-#{kind}"}
        class="board-notice"
        data-kind={kind}
        phx-hook="BoardNotice"
      >
        <.icon
          name={if kind == :error, do: "hero-exclamation-circle", else: "hero-information-circle"}
          class="size-5"
        />
        <p role={if kind == :error, do: "alert", else: "status"}>{message}</p>
        <button
          type="button"
          aria-label={gettext("Dismiss")}
          phx-click={JS.push("lv:clear-flash", value: %{key: kind})}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    """
  end
end
