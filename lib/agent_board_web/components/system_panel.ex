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
      class="border-t border-base-content/10 px-5 py-4"
      aria-label="Version"
    >
      <h2 class="mb-3 flex items-center gap-3 text-[11px] uppercase tracking-[0.16em] text-base-content/75">
        <span>Version</span>
        <span class={["text-[10px] normal-case", tone(@version.state)]}>{label(@version)}</span>
      </h2>

      <div class="flex flex-wrap items-center gap-3 text-[11px]">
        <span class="text-base-content/75">
          running <code class="text-base-content">{@version.served || "unknown"}</code>
        </span>

        <span :if={@version.available} class="text-base-content/75">
          main <code class="text-base-content">{@version.available}</code>
        </span>

        <span :if={@version.dirty} class="text-warning">uncommitted changes</span>

        <button
          type="button"
          phx-click="check_version"
          disabled={@busy}
          class="border border-base-content/20 px-2 py-1 text-[10px] uppercase tracking-wide hover:bg-base-content/5 disabled:opacity-40"
        >
          Check
        </button>

        <button
          :if={@version.state == :behind}
          type="button"
          phx-click="update"
          disabled={@busy}
          class="bg-warning px-3 py-1 text-[10px] font-bold uppercase tracking-wide text-warning-content hover:brightness-110 disabled:opacity-40"
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
