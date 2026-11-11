defmodule AgentBoardWeb.BoardComponents.Controls do
  @moduledoc "The board's small shared pieces: 16px action icons and keyboard hints."
  use AgentBoardWeb, :html

  attr :name, :string, required: true

  @doc "A 16×16 stroke icon. The geometry is literal markup, never a runtime string."
  def ico(assigns) do
    ~H"""
    <svg class="ab-ico" viewBox="0 0 16 16" aria-hidden="true">
      <%= case @name do %>
        <% "check" -> %>
          <path d="M3 8.5l3.5 3.5L13 4.5" />
        <% "plus" -> %>
          <path d="M8 3v10M3 8h10" />
        <% "split" -> %>
          <path d="M3 3v3a3 3 0 0 0 3 3h0M13 13v-3a3 3 0 0 0-3-3H8M8 4v4M3 13l5-5" />
        <% "mic" -> %>
          <rect x="5.5" y="2" width="5" height="8" rx="2.5" />
          <path d="M3 8a5 5 0 0 0 10 0M8 13v1.5" />
        <% "stop" -> %>
          <rect x="4.5" y="4.5" width="7" height="7" rx="1.5" />
        <% "close" -> %>
          <path d="M4 4l8 8M12 4l-8 8" />
        <% "retry" -> %>
          <path d="M13 8a5 5 0 1 1-1.5-3.6M13 2.5V5h-2.5" />
        <% "grip" -> %>
          <circle cx="6" cy="4" r=".6" />
          <circle cx="10" cy="4" r=".6" />
          <circle cx="6" cy="8" r=".6" />
          <circle cx="10" cy="8" r=".6" />
          <circle cx="6" cy="12" r=".6" />
          <circle cx="10" cy="12" r=".6" />
        <% "ext" -> %>
          <path d="M9 3h4v4M13 3L7.5 8.5M11 9.5V13H3V5h3.5" />
        <% "send" -> %>
          <path d="M3 8h10M9 4l4 4-4 4" />
        <% "menu" -> %>
          <path d="M3 5h10M3 8h10M3 11h10" />
        <% "keys" -> %>
          <rect x="2" y="4" width="12" height="8" rx="1.5" />
          <path d="M5 7h0M8 7h0M11 7h0M5.5 9.5h5" />
        <% "log" -> %>
          <path d="M3 4h10M3 8h10M3 12h6" />
        <% "lock" -> %>
          <rect x="3.5" y="7" width="9" height="6.5" rx="1.5" />
          <path d="M5.5 7V5a2.5 2.5 0 0 1 5 0v2" />
        <% "cog" -> %>
          <circle cx="8" cy="8" r="2.2" />
          <path d="M8 1.8v1.6M8 12.6v1.6M1.8 8h1.6M12.6 8h1.6M3.6 3.6l1.1 1.1M11.3 11.3l1.1 1.1M12.4 3.6l-1.1 1.1M4.7 11.3l-1.1 1.1" />
        <% _ -> %>
          <path d="" />
      <% end %>
    </svg>
    """
  end

  attr :key, :string, required: true

  def kbd(assigns) do
    ~H"""
    <kbd class="ab-kbd">{@key}</kbd>
    """
  end
end
