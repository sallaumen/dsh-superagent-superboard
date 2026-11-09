defmodule AgentBoardWeb.BoardComponents.SettingsMenu do
  @moduledoc "Secondary board controls grouped behind a native disclosure."
  use AgentBoardWeb, :live_component

  alias AgentBoardWeb.Components.{SystemPanel, VoicePanel}

  attr :dispatch_paused, :boolean, default: false
  attr :settings_panel, :boolean, default: false

  @impl true
  def render(assigns) do
    ~H"""
    <details
      id={@id}
      phx-hook="BoardMenu"
      data-board-menu
      open={@settings_panel}
      class="board-settings"
      data-update-ready={to_string(@version.state in [:behind, :restart])}
    >
      <summary aria-label="Configurações">
        <.icon name="hero-cog-6-tooth" class="size-4" />
        <span class="settings-menu-label">Configurações</span>
        <.icon name="hero-chevron-down" class="settings-chevron size-3" />
      </summary>
      <div class="board-settings-body">
        <h2>Configurações</h2>

        <div class={["settings-layout", @settings_panel && "is-panel"]}>
          <nav :if={@settings_panel} class="settings-nav" aria-label="Seções das configurações">
            <a href="#settings-inspect">Inspecionar</a>
            <a href="#settings-dispatch">Despacho local</a>
            <a href="#settings-voice-section">Voz</a>
            <a href="#settings-daily-summary-section">Resumo do dia</a>
            <a href="#settings-repositories-section">Repositórios</a>
            <a href="#settings-appearance-section">Aparência</a>
            <a href="#settings-system-section">Versão</a>
          </nav>

          <div class="settings-content">
            <section :if={@repo} class="settings-shortcuts" aria-labelledby="settings-inspect">
              <h3 id="settings-inspect">Inspecionar</h3>
              <div class="settings-actions">
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

            <section :if={@repo} class="settings-shortcuts" aria-labelledby="settings-dispatch">
              <h3 id="settings-dispatch">Despacho local</h3>
              <div class="settings-actions">
                <button
                  id="toggle-dispatch"
                  type="button"
                  phx-click="toggle_dispatch"
                >
                  <.icon
                    name={if @dispatch_paused, do: "hero-play", else: "hero-pause"}
                    class="size-4"
                  />
                  {if @dispatch_paused, do: "Retomar despacho", else: "Pausar despacho"}
                </button>
              </div>
              <p class="text-xs leading-relaxed text-base-content/75">
                {if @dispatch_paused,
                  do: "Pausado: o que já roda continua e nenhuma execução nova começa.",
                  else: "Ligado: Claude Code e Codex podem ser despachados por uma ação confirmada."}
              </p>

              <.live_component
                :if={@settings_panel}
                module={AgentBoardWeb.BoardComponents.DispatchSettings}
                id="dispatch-settings"
              />
            </section>

            <details id="settings-voice-section" class="settings-fold" open={@settings_panel}>
              <summary>
                <span class="settings-fold-label">Voz <small>Fala e retorno</small></span>
                <.icon name="hero-chevron-down" class="settings-fold-chevron size-4" />
              </summary>
              <div class="settings-fold-content">
                <VoicePanel.voice_panel voice={@voice} repo={@repo != nil} />
                <div class="settings-actions">
                  <button type="button" phx-click="speak">
                    <.icon name="hero-speaker-wave" class="size-4" />Falar status
                  </button>
                </div>
                <p class="text-xs leading-relaxed text-base-content/75">
                  No board, aperte Espaço duas vezes, fale e pare: o agente responde em voz. Criar e parar esperam o seu “sim”; arquivar é um clique e Retomar desfaz.
                </p>
              </div>
            </details>

            <.live_component
              module={AgentBoardWeb.BoardComponents.DailySummarySettings}
              id="settings-daily-summary-section"
            />

            <details id="settings-repositories-section" class="settings-fold" open={@settings_panel}>
              <summary>
                <span class="settings-fold-label">Repositórios
                <small>Acompanhar outro repositório</small></span>
                <.icon name="hero-chevron-down" class="settings-fold-chevron size-4" />
              </summary>
              <div class="settings-fold-content">
                <form id="track-repo" phx-submit="add" class="settings-track-form">
                  <input name="owner" placeholder="dono" aria-label="Dono" />
                  <input name="name" placeholder="nome do repo" aria-label="Nome do repositório" />
                  <button type="submit" phx-disable-with="Tracking…">Acompanhar</button>
                </form>
              </div>
            </details>

            <details id="settings-appearance-section" class="settings-fold" open={@settings_panel}>
              <summary>
                <span class="settings-fold-label">Aparência <small>Temas claro e escuro</small></span>
                <.icon name="hero-chevron-down" class="settings-fold-chevron size-4" />
              </summary>
              <div class="settings-fold-content"><Layouts.theme_toggle /></div>
            </details>

            <details id="settings-system-section" class="settings-fold" open={@settings_panel}>
              <summary>
                <span class="settings-fold-label">Versão <small>{version_summary(@version)}</small></span>
                <.icon name="hero-chevron-down" class="settings-fold-chevron size-4" />
              </summary>
              <div class="settings-fold-content">
                <SystemPanel.version_panel version={@version} busy={@busy} />
              </div>
            </details>
          </div>
        </div>
      </div>
    </details>
    """
  end

  defp version_summary(%{state: :behind}), do: "Atualização disponível"
  defp version_summary(%{state: :restart}), do: "Reinício pendente"
  defp version_summary(%{state: :up_to_date}), do: "Em dia"
  defp version_summary(%{state: :ahead}), do: "À frente da main"
  defp version_summary(_), do: "Status desconhecido"
end
