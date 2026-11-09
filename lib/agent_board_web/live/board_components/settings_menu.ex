defmodule AgentBoardWeb.BoardComponents.SettingsMenu do
  @moduledoc "The board-wide settings panel, with one section visible at a time."
  use AgentBoardWeb, :live_component

  import Phoenix.LiveView, only: [push_patch: 2]

  alias AgentBoardWeb.BoardNavigation
  alias AgentBoardWeb.Components.{SystemPanel, VoicePanel}

  @section_keys ~w(inspect dispatch voice summary repositories appearance language version)

  attr :dispatch_paused, :boolean, default: false
  attr :progress, :list, default: []
  attr :board_locale, :string, default: "en"
  attr :return_to, :string, default: "/"

  @impl true
  def mount(socket), do: {:ok, assign(socket, section: "dispatch")}

  @impl true
  def update(assigns, socket) do
    previous = socket.assigns[:section]
    socket = assign(socket, Map.delete(assigns, :section))

    # The URL's section wins when it names one; otherwise keep the current
    # one (or repositories before a repo is selected).
    section =
      case assigns[:section] do
        key when key in @section_keys -> key
        _ -> if socket.assigns[:repo], do: previous, else: "repositories"
      end

    {:ok, assign(socket, section: section)}
  end

  @impl true
  def handle_event("select_section", %{"section" => section}, socket) do
    allowed = section in @section_keys

    section =
      if allowed and (socket.assigns[:repo] || section not in ~w(inspect dispatch)),
        do: section,
        else: socket.assigns.section

    {:noreply,
     socket
     |> assign(section: section)
     |> push_patch(to: BoardNavigation.settings_path(socket.assigns[:repo], section))}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :sections, sections())

    ~H"""
    <div id={@id} class="settings-layout">
      <nav class="settings-nav" aria-label={gettext("Settings sections")}>
        <button
          :for={{key, label} <- @sections}
          :if={@repo || key not in ~w(inspect dispatch)}
          type="button"
          class={["settings-nav__item", @section == key && "is-current"]}
          aria-current={if @section == key, do: "page", else: nil}
          aria-controls="settings-current-section"
          phx-click="select_section"
          phx-value-section={key}
          phx-target={@myself}
        >
          {label}
          <span
            :if={key == "version" and @version.state in [:behind, :restart]}
            class="settings-nav__notice"
            aria-label={version_summary(@version)}
          ></span>
        </button>
      </nav>

      <div id="settings-current-section" class="settings-content">
        <section
          :if={@repo}
          hidden={@section != "inspect"}
          class="settings-pane"
          aria-labelledby="settings-inspect-title"
        >
          <h3 id="settings-inspect-title">{gettext("Inspect")}</h3>
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
          :if={@repo}
          hidden={@section != "dispatch"}
          class="settings-pane settings-pane--dispatch"
          aria-labelledby="settings-dispatch-title"
        >
          <h3 id="settings-dispatch-title">{gettext("Local dispatch")}</h3>
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
            active={@active}
          />
        </section>

        <section
          hidden={@section != "voice"}
          class="settings-pane"
          aria-labelledby="settings-voice-title"
        >
          <h3 id="settings-voice-title">{gettext("Voice")}</h3>
          <p class="settings-pane__intro">
            {gettext("Choose how to speak with the board and when it replies aloud.")}
          </p>
          <VoicePanel.voice_panel voice={@voice} repo={@repo != nil} />
          <div class="settings-actions">
            <button type="button" phx-click="speak"><.icon name="hero-speaker-wave" class="size-4" />{gettext(
              "Speak status"
            )}</button>
          </div>
          <p class="settings-pane__note">
            {gettext(
              "Press Space twice to speak. Creating and stopping tasks wait for your confirmation."
            )}
          </p>
        </section>

        <section
          hidden={@section != "summary"}
          class="settings-pane"
          aria-labelledby="settings-summary-title"
        >
          <h3 id="settings-summary-title">{gettext("Daily summary")}</h3>
          <p class="settings-pane__intro">
            {gettext("Choose whether the board prepares a daily summary and when.")}
          </p>
          <.live_component
            module={AgentBoardWeb.BoardComponents.DailySummarySettings}
            id="settings-daily-summary-section"
            expanded={true}
          />
        </section>

        <section
          hidden={@section != "repositories"}
          class="settings-pane"
          aria-labelledby="settings-repositories-title"
        >
          <h3 id="settings-repositories-title">{gettext("Repositories")}</h3>
          <p class="settings-pane__intro">{gettext("Track another repository on this board.")}</p>
          <form id="track-repo" phx-submit="add" class="settings-track-form">
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
            <button type="submit" phx-disable-with={gettext("Tracking…")}>{gettext("Track")}</button>
          </form>
        </section>

        <section
          hidden={@section != "appearance"}
          class="settings-pane"
          aria-labelledby="settings-appearance-title"
        >
          <h3 id="settings-appearance-title">{gettext("Appearance")}</h3>
          <p class="settings-pane__intro">{gettext("Choose the theme for this browser.")}</p>
          <Layouts.theme_toggle />
        </section>

        <section
          hidden={@section != "language"}
          class="settings-pane"
          aria-labelledby="settings-language-title"
        >
          <h3 id="settings-language-title">{gettext("Board language")}</h3>
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

        <section
          hidden={@section != "version"}
          class="settings-pane"
          aria-labelledby="settings-version-title"
        >
          <h3 id="settings-version-title">{gettext("Version")}</h3>
          <p class="settings-pane__intro">
            {gettext("Check the board version and available updates.")}
          </p>
          <SystemPanel.version_panel version={@version} busy={@busy} progress={@progress} />
        </section>
      </div>
    </div>
    """
  end

  defp sections do
    [
      {"inspect", gettext("Inspect")},
      {"dispatch", gettext("Local dispatch")},
      {"voice", gettext("Voice")},
      {"summary", gettext("Daily summary")},
      {"repositories", gettext("Repositories")},
      {"appearance", gettext("Appearance")},
      {"language", gettext("Language")},
      {"version", gettext("Version")}
    ]
  end

  defp version_summary(%{state: :behind}), do: gettext("Update available")
  defp version_summary(%{state: :restart}), do: gettext("Restart pending")
  defp version_summary(%{state: :up_to_date}), do: gettext("Up to date")
  defp version_summary(%{state: :ahead}), do: gettext("Ahead of main")
  defp version_summary(_), do: gettext("Unknown status")
end
