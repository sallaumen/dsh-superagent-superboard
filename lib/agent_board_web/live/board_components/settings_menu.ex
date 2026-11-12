defmodule AgentBoardWeb.BoardComponents.SettingsMenu do
  @moduledoc "The board-wide settings panel, with one of its sections visible at a time."
  use AgentBoardWeb, :live_component

  import Phoenix.LiveView, only: [push_patch: 2]

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]

  alias AgentBoardWeb.BoardComponents.Settings.{Activity, Costs, Execution, Projects, Setup}
  alias AgentBoardWeb.BoardNavigation
  alias AgentBoardWeb.Components.{SystemPanel, VoicePanel}

  @section_keys ~w(setup projects execution costs voice system logs)

  attr :active, :boolean, default: false
  attr :repo, :map, default: nil
  attr :version, :map, required: true
  attr :voice, :map, required: true
  attr :busy, :boolean, default: false
  attr :dispatch_paused, :boolean, default: false
  attr :progress, :list, default: []
  attr :superagents, :list, default: []
  attr :repos, :list, default: []
  attr :access_waiting, :integer, default: 0

  attr :log_view, :map, required: true

  attr :costs, :map, default: %{}, doc: "Settings → Costs page and window from the URL"

  attr :access_projects, :list, default: []
  attr :tickets, :list, default: []
  attr :ai_status, :any, default: :unknown
  attr :events, :list, default: []
  attr :codex_quota, :map, default: nil
  attr :provisioning, :boolean, default: false
  attr :tz_offset, :integer, default: 0
  attr :project_pending, :any, default: nil
  attr :board_locale, :string, default: "en"

  @impl true
  def mount(socket), do: {:ok, assign(socket, section: nil)}

  @impl true
  def update(assigns, socket) do
    previous = socket.assigns[:section]
    opening = assigns[:active] == true and socket.assigns[:active] != true
    socket = assign(socket, Map.delete(assigns, :section))

    # The panel stays mounted while closed: configuration is read on each
    # opening only. A required part missing opens AI and setup and marks it.
    socket =
      if opening,
        do: assign(socket, setup_next: AgentBoard.Setup.next_step(AgentBoard.Setup.checklist())),
        else: assign_new(socket, :setup_next, fn -> nil end)

    # The URL's section wins when it names one; otherwise keep the current one.
    section = select_section(assigns[:section], previous, opening, socket.assigns.setup_next)
    {:ok, assign(socket, section: section)}
  end

  defp select_section(key, _previous, _opening, _next) when key in @section_keys, do: key

  defp select_section(_key, previous, opening, next)
       when previous == "logs" or (opening and is_nil(previous)),
       do: if(next, do: "setup", else: "projects")

  defp select_section(_key, previous, _opening, _next), do: previous

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

            <span :if={key == "setup" and @setup_next} class="settings-nav__marks">
              <span
                class="settings-nav__mark settings-nav__mark--halt"
                title={gettext("Next step: %{part}", part: @setup_next.title)}
              >
                <.glyph kind={:blocked} />
                <span class="ab-sr">{gettext("Next step: %{part}", part: @setup_next.title)}</span>
              </span>
            </span>

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
          hidden={@section != "setup"}
          class="settings-pane settings-pane--setup"
          aria-labelledby="settings-setup-title"
        >
          <h3 id="settings-setup-title">{gettext("AI and setup")}</h3>
          <p class="settings-pane__intro">
            {gettext(
              "The board uses AI in three roles. Here you see which one does what, what it costs, and whether each part is ready."
            )}
          </p>
          <.live_component
            module={Setup}
            id="settings-setup"
            active={@active == true and @section == "setup"}
            parent={@myself}
            tz_offset={@tz_offset}
          />
        </section>

        <section
          hidden={@section != "projects"}
          class="settings-pane settings-pane--projects"
          aria-labelledby="settings-projects-title"
        >
          <h3 id="settings-projects-title">{gettext("Projects")}</h3>
          <p class="settings-pane__intro">
            {gettext("Each project is a repository, its DeepSeek agent and who can call it.")}
          </p>
          <.live_component
            module={Projects}
            id="settings-projects"
            active={@active == true and @section == "projects"}
            superagents={@superagents}
            repos={@repos}
            access_projects={@access_projects}
            project_pending={@project_pending}
            provisioning={@provisioning}
            tz_offset={@tz_offset}
          />
        </section>

        <section
          hidden={@section != "execution"}
          class="settings-pane settings-pane--execution"
          aria-labelledby="settings-execution-title"
        >
          <h3 id="settings-execution-title">{gettext("Execution")}</h3>
          <p class="settings-pane__intro">
            {gettext(
              "Claude Code and Codex run on this machine; DeepSeek runs through GitHub. Here are their caps and models."
            )}
          </p>
          <.live_component
            module={Execution}
            id="settings-execution"
            active={@active == true and @section == "execution"}
            dispatch_paused={@dispatch_paused}
            tickets={@tickets}
            ai_status={@ai_status}
            parent={@myself}
            tz_offset={@tz_offset}
          />
        </section>

        <section
          hidden={@section != "costs"}
          class="settings-pane settings-pane--costs"
          aria-labelledby="settings-costs-title"
        >
          <h3 id="settings-costs-title">{gettext("Costs")}</h3>
          <p class="settings-pane__intro">
            {gettext(
              "What the agent, the board's own AI and the voice spent, each in the currency it is charged in."
            )}
          </p>
          <.live_component
            module={Costs}
            id="settings-costs"
            active={@active == true and @section == "costs"}
            repo={@repo}
            params={@costs}
            tickets={@tickets}
            tz_offset={@tz_offset}
          />
        </section>

        <section
          hidden={@section != "voice"}
          class="settings-pane settings-pane--voice"
          aria-labelledby="settings-voice-title"
        >
          <header class="settings-pane__head">
            <div>
              <h3 id="settings-voice-title">{gettext("Voice and summary")}</h3>
              <p class="settings-pane__intro">
                {gettext(
                  "How you talk to the board, when it answers aloud and the summary of the day."
                )}
              </p>
              <button
                id="voice-costs-link"
                type="button"
                class="ab-link"
                phx-click="select_section"
                phx-value-section="costs"
                phx-target={@myself}
              >{gettext("The ElevenLabs plan and what the voice spent are in Costs")}</button>
            </div>
            <button
              id="speak-status"
              type="button"
              class="ab-btn ab-btn--sm"
              phx-click="speak"
            ><.icon
              name="hero-speaker-wave"
              class="size-4"
            />{gettext("Speak the state now")}</button>
          </header>

          <div
            id="voice-panel"
            phx-hook="VoicePlayer"
            class="voice-layout"
            data-volume={@voice.volume}
            data-lang={@voice.language}
          >
            <div class="voice-layout__column">
              <VoicePanel.input_controls voice={@voice} repo={@repo != nil} />
              <.live_component
                module={AgentBoardWeb.BoardComponents.DailySummarySettings}
                id="settings-daily-summary-section"
                expanded={true}
              />
            </div>
            <div class="voice-layout__column">
              <VoicePanel.output_controls voice={@voice} repo={@repo != nil} />
            </div>
          </div>
        </section>

        <AgentBoardWeb.BoardComponents.Settings.Logs.section
          :if={@active and @section == "logs"}
          {@log_view}
        />
        <section
          hidden={@section != "system"}
          class="settings-pane settings-pane--system"
          aria-labelledby="settings-system-title"
        >
          <h3 id="settings-system-title">{gettext("System")}</h3>
          <p class="settings-pane__intro">
            {gettext("The board version, how it appears in this browser and what it recorded.")}
          </p>

          <SystemPanel.version_panel version={@version} busy={@busy} progress={@progress} />

          <section class="settings-subpane" aria-labelledby="settings-browser-title">
            <h4 id="settings-browser-title">{gettext("In this browser")}</h4>
            <div class="settings-browser">
              <div class="settings-browser__field">
                <h5>{gettext("Theme")}</h5>
                <Layouts.theme_toggle id="settings-theme-toggle" />
              </div>
              <div class="settings-browser__field">
                <h5>{gettext("Board language")}</h5>
                <.form
                  for={%{}}
                  action={~p"/language"}
                  method="post"
                  id="board-language-form"
                  class="ab-segmented"
                  role="group"
                  aria-label={gettext("Board language")}
                >
                  <input
                    type="hidden"
                    name="return_to"
                    value={BoardNavigation.settings_path(@repo, @section)}
                  />
                  <button
                    type="submit"
                    name="locale"
                    value="en"
                    class="ab-segment"
                    aria-pressed={to_string(@board_locale == "en")}
                  >English</button>
                  <button
                    type="submit"
                    name="locale"
                    value="pt-BR"
                    class="ab-segment"
                    aria-pressed={to_string(@board_locale == "pt-BR")}
                  >Português (Brasil)</button>
                </.form>
                <p class="settings-pane__note">
                  {gettext("The voice speaks this language too.")}
                </p>
              </div>
            </div>
          </section>

          <.live_component
            :if={@repo}
            module={Activity}
            id="settings-activity"
            events={@events}
            repo={@repo}
            tz_offset={@tz_offset}
          />
        </section>
      </div>
    </div>
    """
  end

  defp sections do
    [
      {"setup", gettext("AI and setup")},
      {"projects", gettext("Projects")},
      {"execution", gettext("Execution")},
      {"costs", gettext("Costs")},
      {"voice", gettext("Voice and summary")},
      {"system", gettext("System")},
      {"logs", gettext("Logs")}
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
