defmodule AgentBoardWeb.Components.SystemPanel do
  @moduledoc """
  The version card: what this node runs, what main has, the commits between
  them and the only two ways to update it.

  Presentation lives here and nowhere else, so a design pass can restyle this
  file without touching `BoardLive` or `AgentBoard.System.*`. The contract is
  the three assigns: `version` (a `AgentBoard.System.Version.status/0` map),
  `busy` (a call is running) and the two events `check_version` and `update`;
  `restart` is the third event, for a checkout already ahead.
  """

  use Phoenix.Component
  use Gettext, backend: AgentBoardWeb.Gettext

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]

  attr :version, :map, required: true
  attr :busy, :boolean, default: false
  attr :progress, :list, default: []

  def version_panel(assigns) do
    ~H"""
    <section
      id="version-panel"
      class="version-panel"
      aria-labelledby="version-title"
      phx-hook="BoardRestart"
    >
      <header class="version-panel__head">
        <div>
          <h4 id="version-title" class="version-panel__title">
            <span class={["version-panel__state", tone(@version)]}>
              <.glyph kind={state_glyph(@version)} />{title(@version)}
            </span>
          </h4>
          <p class="version-panel__summary">{summary(@version)}</p>
        </div>
        <button
          id="version-check"
          type="button"
          class="ab-btn ab-btn--sm"
          phx-click="check_version"
          disabled={@busy}
        >{gettext("Check again")}</button>
      </header>

      <p :if={@version.dirty} class="version-panel__dirty">
        {gettext("There are uncommitted changes in the checkout.")}
      </p>

      <ol
        :if={@version.commits != []}
        class="version-commits"
        aria-label={gettext("Commits between the running board and main")}
      >
        <li :for={commit <- @version.commits}>
          <code>{commit.sha}</code>
          <span class="version-commits__title">{commit.title}</span>
          <span :if={commit.pr} class="version-commits__pr">#{commit.pr}</span>
        </li>
      </ol>

      <p :if={@version.state == :behind and @version.commits == []} class="ab-meta">
        {ngettext(
          "Main is %{count} commit ahead; the list of commits could not be read.",
          "Main is %{count} commits ahead; the list of commits could not be read.",
          @version.behind || 0
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

      <p :if={interruption(@version)} class="version-panel__interruption">
        {interruption(@version)}
      </p>

      <div class="version-panel__actions">
        <button
          :if={@version.state != :restart}
          type="button"
          class="ab-btn"
          phx-click="restart"
          disabled={@busy}
        >{gettext("Restart only")}</button>

        <button
          :if={@version.state == :behind}
          type="button"
          class="ab-btn ab-btn--primary"
          phx-click="update"
          disabled={@busy}
          title={gettext("Pull main, prepare the build and restart the board.")}
        >{gettext("Update and restart")}</button>

        <button
          :if={@version.state == :restart}
          type="button"
          class="ab-btn ab-btn--primary"
          phx-click="restart"
          disabled={@busy}
        >{gettext("Restart to apply")}</button>
      </div>
    </section>
    """
  end

  defp title(%{state: :behind}), do: gettext("New version on main")
  defp title(%{state: :restart}), do: gettext("New code downloaded; restart pending")
  defp title(%{state: :up_to_date}), do: gettext("Up to date with main")
  defp title(%{state: :ahead}), do: gettext("This checkout is ahead of main")
  defp title(_version), do: gettext("Could not compare with main")

  defp summary(%{state: :behind} = version) do
    ahead =
      ngettext(
        "Main is %{count} commit ahead.",
        "Main is %{count} commits ahead.",
        version.behind || 0
      )

    gettext("You run %{served}. Main is at %{available}.",
      served: short(version.served),
      available: short(version.available)
    ) <> " " <> ahead
  end

  defp summary(%{state: :restart} = version) do
    gettext(
      "The checkout is at %{available}; this process still runs %{served}.",
      served: short(version.served),
      available: short(version.available)
    )
  end

  defp summary(%{state: :up_to_date} = version),
    do: gettext("You run %{served}.", served: short(version.served))

  defp summary(%{state: :ahead} = version) do
    gettext("You run %{served}; main is at %{available}.",
      served: short(version.served),
      available: short(version.available)
    )
  end

  defp summary(version),
    do: gettext("The running commit is %{served}.", served: short(version.served))

  defp interruption(%{state: :behind}) do
    gettext(
      "Updating restarts the board: live tracking and running agents stop for a few seconds. Nothing updates on its own."
    )
  end

  defp interruption(%{state: :restart}) do
    gettext(
      "The new code is already in the checkout. Restart to apply it; the board is unavailable for a few seconds."
    )
  end

  defp interruption(_version), do: nil

  defp state_glyph(%{state: :behind}), do: :stale
  defp state_glyph(%{state: :restart}), do: :stale
  defp state_glyph(%{state: :up_to_date}), do: :run
  defp state_glyph(%{state: :ahead}), do: :queue
  defp state_glyph(_version), do: :unknown

  defp tone(:behind), do: "is-stale"
  defp tone(:restart), do: "is-stale"
  defp tone(:up_to_date), do: "is-ok"
  defp tone(:ahead), do: "is-queue"
  defp tone(_state), do: "is-faint"

  defp short(nil), do: "—"
  defp short(sha), do: sha
end
