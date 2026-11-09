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
  use Gettext, backend: AgentBoardWeb.Gettext

  attr :version, :map, required: true
  attr :busy, :boolean, default: false
  attr :progress, :list, default: []

  def version_panel(assigns) do
    ~H"""
    <section
      id="version-panel"
      class="version-panel"
      aria-label={gettext("Version")}
      phx-hook="BoardRestart"
    >
      <h2 class="version-heading">
        <span>{gettext("Version")}</span>
        <span class={["version-status", tone(@version.state)]}><span
          class="status-mark"
          aria-hidden="true"
        ></span>{label(@version)}</span>
      </h2>

      <p
        :if={@version.state in [:behind, :restart]}
        id="version-restart-warning"
        class="version-warning"
        role="note"
      >
        {if @version.state == :restart,
          do:
            gettext(
              "The new code is in the checkout, but this process still runs the old commit. Restart to apply it; the board will be unavailable for a few seconds."
            ),
          else:
            gettext(
              "Update and restart is manual. The board restarts to load new code; live tracking and running agents may be interrupted for a few seconds. Nothing updates automatically."
            )}
      </p>

      <ol
        :if={@progress != []}
        id="update-progress"
        class="version-progress"
        aria-label={gettext("Update progress")}
      >
        <li :for={step <- @progress} data-state={step.state}>
          <span class="version-progress__mark" aria-hidden="true"></span>
          <span>{step.label}</span>
        </li>
      </ol>

      <div class="version-details">
        <span class="text-base-content/75">
          {gettext("running")} <code class="text-base-content">{@version.served || "unknown"}</code>
        </span>

        <span class="text-base-content/75">
          main <code class="text-base-content">{@version.available || "unknown"}</code>
        </span>

        <span :if={@version.dirty} class="text-warning">{gettext("uncommitted changes")}</span>

        <button
          type="button"
          phx-click="check_version"
          disabled={@busy}
          class="version-check"
        >
          {gettext("Check")}
        </button>

        <button
          :if={@version.state == :behind}
          type="button"
          phx-click="update"
          disabled={@busy}
          aria-describedby="version-restart-warning"
          title={
            gettext("Updates the checkout and restarts the board; running agents may be interrupted.")
          }
          class="version-update bg-warning text-warning-content hover:brightness-110"
        >
          {gettext("Update and restart")}
        </button>

        <button
          type="button"
          phx-click="restart"
          disabled={@busy}
          aria-describedby={@version.state == :restart && "version-restart-warning"}
          class={[
            "version-check",
            @version.state == :restart &&
              "version-update bg-warning text-warning-content hover:brightness-110"
          ]}
        >
          {if @version.state == :restart, do: gettext("Restart to apply"), else: gettext("Restart")}
        </button>
      </div>
    </section>
    """
  end

  defp label(%{state: :up_to_date}), do: gettext("up to date")

  defp label(%{state: :behind, behind: n}) when is_integer(n),
    do: ngettext("%{count} commit behind", "%{count} commits behind", n)

  defp label(%{state: :behind}), do: gettext("behind")
  defp label(%{state: :restart}), do: gettext("Update downloaded; restart")
  defp label(%{state: :ahead}), do: gettext("ahead of main")
  defp label(_version), do: gettext("unknown")

  defp tone(:up_to_date), do: "text-success"
  defp tone(:behind), do: "text-warning"
  defp tone(:restart), do: "text-warning"
  defp tone(:ahead), do: "text-info"
  defp tone(_state), do: "text-base-content/75"
end
