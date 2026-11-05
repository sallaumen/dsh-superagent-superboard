defmodule AgentBoardWeb.Components.SystemPanel do
  @moduledoc """
  The version panel: what this node runs, what main has, and the only way to
  update it.

  Presentation lives here and nowhere else, so a design pass can restyle this
  file without touching `BoardLive` or `AgentBoard.System.*`. The contract is
  the three assigns: `version` (a `AgentBoard.System.Version.status/0` map),
  `busy` (a call is running) and the two events `check_version` and `update`.
  """

  use Phoenix.Component

  attr :version, :map, required: true
  attr :busy, :boolean, default: false

  def version_panel(assigns) do
    ~H"""
    <section
      id="version-panel"
      class="version-panel"
      aria-label="Version"
    >
      <h2 class="version-heading">
        <span>Version</span>
        <span class={["version-status", tone(@version.state)]}><span
          class="status-mark"
          aria-hidden="true"
        ></span>{label(@version)}</span>
      </h2>

      <div class="version-details">
        <span class="text-base-content/75">
          running <code class="text-base-content">{@version.served || "unknown"}</code>
        </span>

        <span class="text-base-content/75">
          main <code class="text-base-content">{@version.available || "unknown"}</code>
        </span>

        <span :if={@version.dirty} class="text-warning">uncommitted changes</span>

        <button
          type="button"
          phx-click="check_version"
          disabled={@busy}
          class="version-check"
        >
          Check
        </button>

        <button
          :if={@version.state == :behind}
          type="button"
          phx-click="update"
          disabled={@busy}
          class="version-update bg-warning text-warning-content hover:brightness-110"
        >
          Update & restart
        </button>
      </div>
    </section>
    """
  end

  defp label(%{state: :up_to_date}), do: "up to date"
  defp label(%{state: :behind, behind: n}) when is_integer(n), do: "#{n} commit(s) behind"
  defp label(%{state: :behind}), do: "behind"
  defp label(%{state: :ahead}), do: "ahead of main"
  defp label(_version), do: "unknown"

  defp tone(:up_to_date), do: "text-success"
  defp tone(:behind), do: "text-warning"
  defp tone(:ahead), do: "text-info"
  defp tone(_state), do: "text-base-content/75"
end
