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
    assigns =
      assigns
      |> assign(:label, label(assigns.version))
      |> assign(:short, short(assigns.version))

    ~H"""
    <button
      :if={@version.state in [:behind, :restart]}
      id="version-behind"
      type="button"
      class={["ab-version-behind", @class]}
      phx-click="show_panel"
      phx-value-panel="settings"
      aria-label={@label <> ". Abrir Versão para atualizar."}
      title={@label <> ". O board reinicia para aplicar."}
    >
      <span class="ab-version-behind__dot" aria-hidden="true"></span>
      <span class="ab-version-behind__long">{@label}</span>
      <span class="ab-version-behind__short" aria-hidden="true">{@short}</span>
    </button>
    """
  end

  defp label(%{state: :restart}), do: "main baixada; reinicie"
  defp label(%{behind: 1}), do: "main avançou: 1 commit"
  defp label(%{behind: n}) when is_integer(n) and n > 0, do: "main avançou: #{n} commits"
  defp label(_version), do: "main avançou"

  defp short(%{state: :restart}), do: "reiniciar"
  defp short(%{behind: n}) when is_integer(n) and n > 0, do: "main +#{n}"
  defp short(_version), do: "main"
end
