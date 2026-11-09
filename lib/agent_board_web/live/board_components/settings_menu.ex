defmodule AgentBoardWeb.BoardComponents.SettingsMenu do
  @moduledoc "The board-wide settings panel, with one of four sections visible at a time."
  use AgentBoardWeb, :live_component

  import Phoenix.LiveView, only: [push_patch: 2]

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]
  import AgentBoardWeb.BoardComponents.Superagents, only: [superagents: 1]

  alias AgentBoardWeb.BoardComponents.AgentAccessPanel
  alias AgentBoardWeb.BoardNavigation
  alias AgentBoardWeb.Components.{SystemPanel, VoicePanel}

  @section_keys ~w(projects execution voice system)

  attr :active, :boolean, default: false
  attr :repo, :map, default: nil
  attr :version, :map, required: true
  attr :voice, :map, required: true
  attr :busy, :boolean, default: false
  attr :dispatch_paused, :boolean, default: false
  attr :progress, :list, default: []
  attr :superagents, :list, default: []
  attr :access_waiting, :integer, default: 0
  attr :codex_quota, :map, default: nil
  attr :repos, :list, default: []
  attr :sources, :list, default: []
  attr :provision_preview, :any, default: nil
  attr :provisioning, :boolean, default: false
  attr :tz_offset, :integer, default: 0
  attr :project_pending, :any, default: nil
  attr :board_locale, :string, default: "en"
  attr :return_to, :string, default: "/"

  @impl true
  def mount(socket), do: {:ok, assign(socket, section: "projects")}

  @impl true
  def update(assigns, socket) do
    previous = socket.assigns[:section]
    socket = assign(socket, Map.delete(assigns, :section))

    # The URL's section wins when it names one; otherwise keep the current
    # one. Projects is the first section whether or not a repository exists.
    section =
      case assigns[:section] do
        key when key in @section_keys -> key
        _ -> previous || "projects"
      end

    {:ok, assign(socket, section: section)}
  end

  @impl true
  def handle_event("select_section", %{"section" => section}, socket) do
    case BoardNavigation.canonical_settings_section(section) do
      nil ->
        {:noreply, socket}

      key ->
        {:noreply,
         socket
         |> assign(section: key)
         |> push_patch(to: BoardNavigation.settings_path(socket.assigns[:repo], key))}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:sections, sections())
      |> assign(:project_errors, project_errors(assigns.superagents))

    ~H"""
    <div id={@id} class="settings-layout">
      <nav class="settings-nav" aria-label={gettext("Settings sections")}>
        <div class="settings-nav__items">
          <button
            :for={{key, label} <- @sections}
            type="button"
            class={["settings-nav__item", @section == key && "is-current"]}
            aria-current={if @section == key, do: "page", else: nil}
            aria-controls="settings-current-section"
            phx-click="select_section"
            phx-value-section={key}
            phx-target={@myself}
          >
            <span class="settings-nav__label">{label}</span>

            <span :if={key == "projects"} class="settings-nav__marks">
              <span
                :if={@project_errors > 0}
                class="settings-nav__mark settings-nav__mark--halt"
                title={
                  ngettext(
                    "%{count} project with an error",
                    "%{count} projects with an error",
                    @project_errors
                  )
                }
              >
                <.glyph kind={:blocked} />
                <span>{@project_errors}</span>
                <span class="ab-sr">
                  {ngettext(
                    "%{count} project with an error",
                    "%{count} projects with an error",
                    @project_errors
                  )}
                </span>
              </span>
              <span
                :if={@access_waiting > 0}
                class="settings-nav__mark settings-nav__mark--you"
                title={
                  ngettext(
                    "%{count} person waiting for access",
                    "%{count} people waiting for access",
                    @access_waiting
                  )
                }
              >
                <.glyph kind={:you} />
                <span>{@access_waiting}</span>
                <span class="ab-sr">
                  {ngettext(
                    "%{count} person waiting for access",
                    "%{count} people waiting for access",
                    @access_waiting
                  )}
                </span>
              </span>
            </span>

            <span
              :if={key == "execution" and codex_quota_high?(@codex_quota)}
              class="settings-nav__hint"
              title={gettext("Codex quota is close to its limit")}
            >
              <.glyph kind={:stale} />
              <span>Codex {percent(@codex_quota.used_percent)}%</span>
              <span class="ab-sr">{gettext("Codex quota is close to its limit")}</span>
            </span>

            <span
              :if={key == "system" and @version.state in [:behind, :restart]}
              class="settings-nav__notice"
              aria-label={version_summary(@version)}
              title={version_summary(@version)}
            ></span>
          </button>
        </div>

        <div class="settings-nav__foot">
          <p class="settings-nav__foot-line">
            {gettext("Running")} <code>{short_sha(@version.served)}</code>
          </p>
          <p class="settings-nav__foot-line">{version_footer(@version)}</p>
          <button
            type="button"
            class="settings-nav__foot-link"
            phx-click="select_section"
            phx-value-section="system"
            phx-target={@myself}
          >
            {gettext("See update")}
          </button>
        </div>
      </nav>

      <div id="settings-current-section" class="settings-content">
        <section
          hidden={@section != "projects"}
          class="settings-pane"
          aria-labelledby="settings-projects-title"
        >
          <h3 id="settings-projects-title">{gettext("Projects")}</h3>
          <p class="settings-pane__intro">
            {gettext("Each project is a repository, its DeepSeek agent and who can call it.")}
          </p>

          <section class="settings-subpane" aria-labelledby="settings-repositories-title">
            <h4 id="settings-repositories-title">{gettext("Repositories")}</h4>
            <p class="settings-pane__intro">
              {gettext("Add a project in one click: the repository and its own DeepSeek agent.")}
            </p>
            <form id="track-repo" phx-submit="add_project" class="settings-track-form">
              <label><span>{gettext("Owner")}</span><input
                name="owner"
                placeholder="sallaumen"
                required
              /></label>
              <label><span>{gettext("Repository")}</span><input
                name="name"
                placeholder={gettext("project-name")}
                required
              /></label>
              <label><span>{gettext("Local checkout")}</span><input
                name="path"
                placeholder={gettext("~/projects/project-name (with .git)")}
              /></label>
              <button
                type="submit"
                class="ab-btn ab-btn--primary ab-btn--sm"
                phx-disable-with={gettext("Adding…")}
              >
                {gettext("Add project")}
              </button>
            </form>

            <form id="track-repo-only" phx-submit="add_track" class="settings-track-form">
              <label><span>{gettext("Owner")}</span><input
                name="owner"
                placeholder="sallaumen"
                required
              /></label>
              <label><span>{gettext("Repository")}</span><input
                name="name"
                placeholder={gettext("project-name")}
                required
              /></label>
              <button
                type="submit"
                class="ab-btn ab-btn--quiet ab-btn--sm"
                phx-disable-with={gettext("Tracking…")}
              >
                {gettext("Track only")}
              </button>
            </form>

            <div
              :if={@project_pending}
              id="add-project-confirm"
              class="ab-act__confirm"
              role="group"
              aria-labelledby="add-project-confirm-q"
            >
              <p id="add-project-confirm-q" class="ab-act__question">{@project_pending.phrase}</p>
              <div class="ab-act__buttons">
                <button
                  type="button"
                  class="ab-btn ab-btn--sm ab-btn--primary"
                  phx-click="add_project_confirm"
                  phx-disable-with={gettext("Creating…")}
                >
                  {gettext("Create superagent")}
                </button>
                <button
                  type="button"
                  class="ab-btn ab-btn--sm ab-btn--quiet"
                  phx-click="add_project_cancel"
                >
                  {gettext("Not now")}
                </button>
              </div>
            </div>
          </section>

          <section class="settings-subpane" aria-labelledby="settings-superagents-title">
            <h4 id="settings-superagents-title">{gettext("Superagents")}</h4>
            <p class="settings-pane__intro">
              {gettext("One DeepSeek agent per project, each with its own profile, port and state.")}
            </p>
            <.superagents
              superagents={@superagents}
              repos={@repos}
              sources={@sources}
              provision_preview={@provision_preview}
              provisioning={@provisioning}
              tz_offset={@tz_offset}
            />
          </section>

          <section class="settings-subpane" aria-labelledby="settings-access-title">
            <h4 id="settings-access-title">{gettext("Agent access")}</h4>
            <p class="settings-pane__intro">
              {gettext(
                "Who can put each project's agent to work by mentioning the bot, and who asked without being allowed."
              )}
            </p>
            <.live_component
              module={AgentAccessPanel}
              id="settings-agent-access"
              superagents={@superagents}
              visible={@active == true and @section == "projects"}
              tz_offset={@tz_offset}
            />
          </section>
        </section>

        <section
          hidden={@section != "execution"}
          class="settings-pane settings-pane--execution"
          aria-labelledby="settings-execution-title"
        >
          <h3 id="settings-execution-title">{gettext("Execution")}</h3>
          <p class="settings-pane__intro">
            {gettext(
              "Claude Code and Codex run on this machine; DeepSeek runs through GitHub. Each one is measured in its own currency."
            )}
          </p>

          <section :if={@repo} class="settings-subpane" aria-labelledby="settings-inspect-title">
            <h4 id="settings-inspect-title">{gettext("Inspect")}</h4>
            <p class="settings-pane__intro">
              {gettext("See what the board has done and how each executor is working.")}
            </p>
            <div class="settings-inspect-actions">
              <button
                id="open-activity"
                type="button"
                phx-click="show_panel"
                phx-value-panel="activity"
                data-panel-trigger
                aria-haspopup="dialog"
                aria-controls="panel-activity"
              ><.icon name="hero-clock" class="size-4" />{gettext("Activity")}</button>
              <button
                id="open-ai"
                type="button"
                phx-click="show_panel"
                phx-value-panel="ai"
                data-panel-trigger
                aria-haspopup="dialog"
                aria-controls="panel-ai"
              ><.icon name="hero-cpu-chip" class="size-4" />{gettext("AI calls")}</button>
              <button
                id="open-executors"
                type="button"
                phx-click="show_panel"
                phx-value-panel="executors"
                data-panel-trigger
                aria-haspopup="dialog"
                aria-controls="panel-executors"
              ><.icon name="hero-bolt" class="size-4" />{gettext("Executors")}</button>
            </div>
          </section>

          <section
            class="settings-subpane settings-subpane--dispatch"
            aria-labelledby="settings-dispatch-title"
          >
            <h4 id="settings-dispatch-title">{gettext("Local dispatch")}</h4>
            <p class="settings-pane__intro">
              {gettext(
                "Claude Code and Codex run on this machine. Each executor has its own limits and billing."
              )}
            </p>
            <div class="settings-pause">
              <div>
                <strong>{gettext("Global pause")}</strong>
                <p>
                  {if @dispatch_paused,
                    do: gettext("No new dispatch starts. Running tasks continue."),
                    else: gettext("New dispatches can start after your confirmation.")}
                </p>
              </div>
              <button
                id="toggle-dispatch"
                type="button"
                class="settings-pause__switch"
                role="switch"
                aria-label={gettext("Global pause for local dispatch")}
                aria-checked={to_string(@dispatch_paused)}
                phx-click="toggle_dispatch"
              ><span aria-hidden="true"></span></button>
            </div>
            <.live_component
              module={AgentBoardWeb.BoardComponents.DispatchSettings}
              id="dispatch-settings"
              active={@active and @section == "execution"}
            />
          </section>
        </section>

        <section
          hidden={@section != "voice"}
          class="settings-pane"
          aria-labelledby="settings-voice-title"
        >
          <h3 id="settings-voice-title">{gettext("Voice and summary")}</h3>
          <p class="settings-pane__intro">
            {gettext("How you talk to the board, when it answers aloud and the summary of the day.")}
          </p>

          <section class="settings-subpane" aria-labelledby="settings-voice-controls-title">
            <h4 id="settings-voice-controls-title">{gettext("Voice")}</h4>
            <VoicePanel.voice_panel voice={@voice} repo={@repo != nil} />
            <div class="settings-actions">
              <button type="button" phx-click="speak"><.icon
                name="hero-speaker-wave"
                class="size-4"
              />{gettext("Speak status")}</button>
            </div>
            <p class="settings-pane__note">
              {if @voice.input == "text",
                do:
                  gettext(
                    "Press Space twice to focus an open text field. Creating and stopping tasks wait for your confirmation."
                  ),
                else:
                  gettext(
                    "Press Space twice to start the selected input. Creating and stopping tasks wait for your confirmation."
                  )}
            </p>
          </section>

          <section class="settings-subpane" aria-labelledby="settings-summary-title">
            <h4 id="settings-summary-title">{gettext("Daily summary")}</h4>
            <p class="settings-pane__intro">
              {gettext("Choose whether the board prepares a daily summary and when.")}
            </p>
            <.live_component
              module={AgentBoardWeb.BoardComponents.DailySummarySettings}
              id="settings-daily-summary-section"
              expanded={true}
            />
          </section>
        </section>

        <section
          hidden={@section != "system"}
          class="settings-pane"
          aria-labelledby="settings-system-title"
        >
          <h3 id="settings-system-title">{gettext("System")}</h3>
          <p class="settings-pane__intro">
            {gettext("The board version, how it appears in this browser and what it recorded.")}
          </p>

          <section class="settings-subpane" aria-labelledby="settings-version-title">
            <h4 id="settings-version-title">{gettext("Version")}</h4>
            <p class="settings-pane__intro">
              {gettext("Check the board version and available updates.")}
            </p>
            <SystemPanel.version_panel version={@version} busy={@busy} progress={@progress} />
          </section>

          <section class="settings-subpane" aria-labelledby="settings-appearance-title">
            <h4 id="settings-appearance-title">{gettext("Appearance")}</h4>
            <p class="settings-pane__intro">{gettext("Choose the theme for this browser.")}</p>
            <Layouts.theme_toggle />
          </section>

          <section class="settings-subpane" aria-labelledby="settings-language-title">
            <h4 id="settings-language-title">{gettext("Language")}</h4>
            <p class="settings-pane__intro">
              {gettext(
                "Choose the language used by this browser. Voice language is set separately under Voice."
              )}
            </p>
            <.form
              for={%{}}
              action={~p"/language"}
              method="post"
              id="board-language-form"
              class="settings-actions"
              role="group"
              aria-label={gettext("Board language")}
            >
              <input type="hidden" name="return_to" value={@return_to} />
              <button
                type="submit"
                name="locale"
                value="en"
                aria-pressed={to_string(@board_locale == "en")}
              >English</button>
              <button
                type="submit"
                name="locale"
                value="pt-BR"
                aria-pressed={to_string(@board_locale == "pt-BR")}
              >Português (Brasil)</button>
            </.form>
          </section>
        </section>
      </div>
    </div>
    """
  end

  defp sections do
    [
      {"projects", gettext("Projects")},
      {"execution", gettext("Execution")},
      {"voice", gettext("Voice and summary")},
      {"system", gettext("System")}
    ]
  end

  defp project_errors(superagents) do
    Enum.count(superagents, &(&1.last_error || &1.observed_state == "error"))
  end

  defp codex_quota_high?(%{used_percent: percent}) when is_number(percent), do: percent >= 80
  defp codex_quota_high?(_quota), do: false

  defp percent(value) when is_float(value) do
    value |> :erlang.float_to_binary(decimals: 0) |> String.replace(".", ",")
  end

  defp percent(value), do: to_string(value)

  defp short_sha(nil), do: "—"
  defp short_sha(sha), do: sha

  defp version_footer(%{state: :behind, behind: count}) when is_integer(count) and count > 0,
    do: ngettext("%{count} commit behind main", "%{count} commits behind main", count)

  defp version_footer(%{state: :restart}),
    do: gettext("Restart pending to apply the new code")

  defp version_footer(%{state: :up_to_date}), do: gettext("Up to date with main")
  defp version_footer(%{state: :ahead}), do: gettext("Ahead of main")
  defp version_footer(_version), do: gettext("Could not compare with main")

  defp version_summary(%{state: :behind}), do: gettext("Update available")
  defp version_summary(%{state: :restart}), do: gettext("Restart pending")
  defp version_summary(%{state: :up_to_date}), do: gettext("Up to date")
  defp version_summary(%{state: :ahead}), do: gettext("Ahead of main")
  defp version_summary(_), do: gettext("Unknown status")
end
