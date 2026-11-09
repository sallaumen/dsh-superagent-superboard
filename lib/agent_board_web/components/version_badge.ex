defmodule AgentBoardWeb.Components.VersionBadge do
  @moduledoc """
  A persistent warning that main moved after the running board booted.

  The badge is a button: it opens Configurações, where the human sees both
  shas, the warning and the manual update. It never updates anything.
  """

  use Phoenix.Component

  attr :version, :map, required: true
  attr :class, :string, default: nil

  def version_badge(assigns) do
    assigns = assign(assigns, :count, count(assigns.version))

    ~H"""
    <button
      :if={@version.state == :behind}
      id="version-behind"
      type="button"
      class={["ab-version-behind", @class]}
      phx-click="show_panel"
      phx-value-panel="settings"
      aria-label={label(@count) <> ". Abrir Versão para atualizar; o board reinicia."}
      title={label(@count) <> ". Atualizar reinicia o board."}
    >
      <span class="ab-version-behind__dot" aria-hidden="true"></span>
      <span class="ab-version-behind__long">{label(@count)}</span>
      <span class="ab-version-behind__short" aria-hidden="true">main +{@count || "?"}</span>
    </button>
    """
  end

  defp count(%{behind: count}) when is_integer(count) and count > 0, do: count
  defp count(_version), do: nil

  defp label(nil), do: "main avançou"
  defp label(1), do: "main avançou: 1 commit"
  defp label(n), do: "main avançou: #{n} commits"
end
