defmodule AgentBoardWeb.BoardComponents.SettingsMenu do
  @moduledoc "The board-wide settings panel, with one section visible at a time."
  use AgentBoardWeb, :live_component

  alias AgentBoardWeb.Components.{SystemPanel, VoicePanel}

  @sections [
    {"inspect", "Inspecionar"},
    {"dispatch", "Despacho local"},
    {"voice", "Voz"},
    {"summary", "Resumo do dia"},
    {"repositories", "Repositórios"},
    {"appearance", "Aparência"},
    {"version", "Versão"}
  ]

  attr :dispatch_paused, :boolean, default: false

  @impl true
  def mount(socket), do: {:ok, assign(socket, section: "dispatch")}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    section = if socket.assigns[:repo], do: socket.assigns.section, else: "repositories"
    {:ok, assign(socket, section: section)}
  end

  @impl true
  def handle_event("select_section", %{"section" => section}, socket) do
    allowed = Enum.any?(@sections, fn {key, _label} -> key == section end)

    section =
      if allowed and (socket.assigns[:repo] || section not in ~w(inspect dispatch)),
        do: section,
        else: socket.assigns.section

    {:noreply, assign(socket, section: section)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :sections, @sections)

    ~H"""
    <div id={@id} class="settings-layout">
      <nav class="settings-nav" aria-label="Seções das configurações">
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
          <h3 id="settings-inspect-title">Inspecionar</h3>
          <p class="settings-pane__intro">
            Acompanhe o que o board fez e como cada executor está trabalhando.
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
            ><.icon name="hero-clock" class="size-4" />Atividade</button>
            <button
              id="open-ai"
              type="button"
              phx-click="show_panel"
              phx-value-panel="ai"
              data-panel-trigger
              aria-haspopup="dialog"
              aria-controls="panel-ai"
            ><.icon name="hero-cpu-chip" class="size-4" />Chamadas de IA</button>
            <button
              id="open-executors"
              type="button"
              phx-click="show_panel"
              phx-value-panel="executors"
              data-panel-trigger
              aria-haspopup="dialog"
              aria-controls="panel-executors"
            ><.icon name="hero-bolt" class="size-4" />Executores</button>
          </div>
        </section>

        <section
          :if={@repo}
          hidden={@section != "dispatch"}
          class="settings-pane settings-pane--dispatch"
          aria-labelledby="settings-dispatch-title"
        >
          <h3 id="settings-dispatch-title">Despacho local</h3>
          <p class="settings-pane__intro">
            Claude Code e Codex rodam nesta máquina. Cada executor usa seus próprios limites e sua própria forma de cobrança.
          </p>
          <div class="settings-pause">
            <div>
              <strong>Pausa global</strong>
              <p>
                {if @dispatch_paused,
                  do: "Nenhum despacho novo começa. Execuções em andamento continuam.",
                  else: "Despachos novos podem começar após sua confirmação."}
              </p>
            </div>
            <button
              id="toggle-dispatch"
              type="button"
              class="settings-pause__switch"
              role="switch"
              aria-label="Pausa global do despacho local"
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
          <h3 id="settings-voice-title">Voz</h3>
          <p class="settings-pane__intro">
            Escolha como falar com o board e quando ele responde em voz.
          </p>
          <VoicePanel.voice_panel voice={@voice} repo={@repo != nil} />
          <div class="settings-actions">
            <button type="button" phx-click="speak"><.icon name="hero-speaker-wave" class="size-4" />Falar status</button>
          </div>
          <p class="settings-pane__note">
            Aperte Espaço duas vezes para falar. Criar e parar tarefas esperam sua confirmação.
          </p>
        </section>

        <section
          hidden={@section != "summary"}
          class="settings-pane"
          aria-labelledby="settings-summary-title"
        >
          <h3 id="settings-summary-title">Resumo do dia</h3>
          <p class="settings-pane__intro">
            Escolha se o board prepara um resumo diário e em que horário.
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
          <h3 id="settings-repositories-title">Repositórios</h3>
          <p class="settings-pane__intro">Acompanhe outro repositório neste board.</p>
          <form id="track-repo" phx-submit="add" class="settings-track-form">
            <label><span>Dono</span><input name="owner" placeholder="sallaumen" required /></label>
            <label><span>Repositório</span><input name="name" placeholder="nome-do-projeto" required /></label>
            <button type="submit" phx-disable-with="Acompanhando…">Acompanhar</button>
          </form>
        </section>

        <section
          hidden={@section != "appearance"}
          class="settings-pane"
          aria-labelledby="settings-appearance-title"
        >
          <h3 id="settings-appearance-title">Aparência</h3>
          <p class="settings-pane__intro">Escolha o tema para este navegador.</p>
          <Layouts.theme_toggle />
        </section>

        <section
          hidden={@section != "version"}
          class="settings-pane"
          aria-labelledby="settings-version-title"
        >
          <h3 id="settings-version-title">Versão</h3>
          <p class="settings-pane__intro">Confira a versão do board e as atualizações disponíveis.</p>
          <SystemPanel.version_panel version={@version} busy={@busy} />
        </section>
      </div>
    </div>
    """
  end

  defp version_summary(%{state: :behind}), do: "Atualização disponível"
  defp version_summary(%{state: :restart}), do: "Reinício pendente"
  defp version_summary(%{state: :up_to_date}), do: "Em dia"
  defp version_summary(%{state: :ahead}), do: "À frente da main"
  defp version_summary(_), do: "Status desconhecido"
end
