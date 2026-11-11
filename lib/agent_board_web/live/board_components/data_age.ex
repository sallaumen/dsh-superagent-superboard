defmodule AgentBoardWeb.BoardComponents.DataAge do
  @moduledoc "A stored timestamp with a browser clock; it never fetches data."
  use Phoenix.Component
  use Gettext, backend: AgentBoardWeb.Gettext

  attr :id, :string, required: true
  attr :at, :any, default: nil
  attr :label, :string, required: true
  attr :sync, :boolean, default: false

  def stamp(assigns) do
    ~H"""
    <time
      id={@id}
      datetime={iso(@at)}
      title={if @at, do: Calendar.strftime(@at, "%Y-%m-%d %H:%M:%S UTC"), else: gettext("unknown")}
      phx-hook="DataAge"
      data-at={iso(@at)}
      data-now={DateTime.to_iso8601(DateTime.utc_now())}
      data-label={@label}
      data-sync={to_string(@sync)}
      class="data-age text-[11px] text-base-content/75"
    >
      {@label}: {if @at, do: Calendar.strftime(@at, "%Y-%m-%d %H:%M UTC"), else: gettext("unknown")}
    </time>
    """
  end

  defp iso(nil), do: nil
  defp iso(dt), do: DateTime.to_iso8601(dt)
end
