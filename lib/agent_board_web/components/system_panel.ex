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
      aria-label="Versão"
      phx-hook="BoardRestart"
    >
      <h2 class="version-heading">
        <span>Versão</span>
        <span class={["version-status", tone(@version.state)]}><span
          class="status-mark"
          aria-hidden="true"
        ></span>{label(@version)}</span>
      </h2>

      <p
        :if={@version.state == :behind}
        id="version-restart-warning"
        class="version-warning"
        role="note"
      >
        Atualizar e reiniciar é manual. O board reinicia para carregar o código
        novo; o acompanhamento em tempo real e agentes em execução podem ser
        interrompidos por alguns segundos. Nada é atualizado sozinho.
      </p>

      <div class="version-details">
        <span class="text-base-content/75">
          rodando <code class="text-base-content">{@version.served || "unknown"}</code>
        </span>

        <span class="text-base-content/75">
          main <code class="text-base-content">{@version.available || "unknown"}</code>
        </span>

        <span :if={@version.dirty} class="text-warning">alterações não commitadas</span>

        <button
          type="button"
          phx-click="check_version"
          disabled={@busy}
          class="version-check"
        >
          Verificar
        </button>

        <button
          :if={@version.state == :behind}
          type="button"
          phx-click="update"
          disabled={@busy}
          aria-describedby="version-restart-warning"
          title="Atualiza o checkout e reinicia o board; agentes em execução podem ser interrompidos."
          class="version-update bg-warning text-warning-content hover:brightness-110"
        >
          Atualizar e reiniciar
        </button>

        <button
          type="button"
          phx-click="restart"
          disabled={@busy}
          class="version-check"
        >
          Reiniciar
        </button>
      </div>
    </section>
    """
  end

  defp label(%{state: :up_to_date}), do: "em dia"
  defp label(%{state: :behind, behind: n}) when is_integer(n), do: "#{n} commit(s) atrás"
  defp label(%{state: :behind}), do: "atrás"
  defp label(%{state: :ahead}), do: "à frente da main"
  defp label(_version), do: "desconhecido"

  defp tone(:up_to_date), do: "text-success"
  defp tone(:behind), do: "text-warning"
  defp tone(:ahead), do: "text-info"
  defp tone(_state), do: "text-base-content/75"
end
