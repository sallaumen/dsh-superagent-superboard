defmodule AgentBoardWeb.BoardComponents.Superagents do
  @moduledoc "The DeepSeek superagents registered on this board, one per project."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1]

  alias AgentBoardWeb.BoardComponents.AgentAction

  attr :superagents, :list, required: true
  attr :repos, :list, required: true
  attr :provision_preview, :any, default: nil
  attr :tz_offset, :integer, default: 0

  def superagents(assigns) do
    ~H"""
    <section id="superagents-panel" class="ab-superagents">
      <header class="ab-superagents__head">
        <div>
          <h2>Superagents DeepSeek</h2>
          <p class="ab-meta">
            Um agente por projeto. O board observa o processo; não o inicia como filho.
          </p>
        </div>
        <span class="ab-tag ab-tag--agent">{length(@superagents)}</span>
      </header>

      <p :if={@superagents == []} class="ab-empty ab-superagents__empty">
        Nenhum superagent registrado. As fases seguintes adicionam projetos por aqui.
      </p>

      <div :if={@superagents != []} class="ab-superagents__list">
        <article :for={superagent <- @superagents} class="ab-superagent">
          <div class="ab-superagent__top">
            <div class="ab-superagent__name">
              <span class="ab-label">Projeto</span>
              <strong>
                {if superagent.repository,
                  do: "#{superagent.repository.owner}/#{superagent.repository.name}",
                  else: "repositório removido"}
              </strong>
            </div>
            <span class={["ab-tag", state_class(superagent.observed_state)]}>
              {state_label(superagent.observed_state)}
            </span>
          </div>

          <dl class="ab-superagent__facts">
            <div>
              <dt>Profile</dt><dd>{superagent.profile}</dd>
            </div>
            <div>
              <dt>Porta</dt><dd>{superagent.port}</dd>
            </div>
            <div>
              <dt>Workers</dt><dd>{superagent.max_workers}</dd>
            </div>
            <div>
              <dt>Desejado</dt><dd>{desired_label(superagent.desired_state)}</dd>
            </div>
            <div class="ab-superagent__wide">
              <dt>State dir</dt><dd class="ab-superagent__path">{superagent.state_dir}</dd>
            </div>
            <div class="ab-superagent__wide">
              <dt>Última leitura</dt>
              <dd>{observed_at(superagent.observed_at, @tz_offset)}</dd>
            </div>
          </dl>

          <p :if={superagent.last_error} class="ab-superagent__error" role="status">
            <.ico name="warning" /> {superagent.last_error}
          </p>

          <div class="ab-superagent__controls">
            <.live_component
              :if={remote_action(superagent)}
              module={AgentAction}
              id={"superagent-#{remote_action(superagent)}-#{superagent.id}"}
              mode={remote_action(superagent)}
              tone={if remote_action(superagent) == :stop_superagent, do: :halt, else: :primary}
              superagent={superagent}
              label={remote_label(superagent)}
              confirm_label={remote_label(superagent)}
              busy_label="Aplicando…"
            />

            <button
              :if={superagent.observed_state == "ready"}
              type="button"
              class="ab-btn ab-btn--sm ab-btn--quiet"
              phx-click="superagent_command"
              phx-value-id={superagent.id}
              phx-value-action="pause"
            >
              Pausar
            </button>
            <button
              :if={superagent.observed_state == "paused"}
              type="button"
              class="ab-btn ab-btn--sm ab-btn--quiet"
              phx-click="superagent_command"
              phx-value-id={superagent.id}
              phx-value-action="resume"
            >
              Retomar
            </button>

            <span class="ab-superagent__workers">
              <button
                type="button"
                class="ab-btn ab-btn--sm ab-btn--quiet"
                aria-label="Menos uma sessão"
                phx-click="superagent_scale"
                phx-value-id={superagent.id}
                phx-value-delta="-1"
                disabled={superagent.max_workers <= 1}
              >−</button>
              <span>{superagent.max_workers} sessões</span>
              <button
                type="button"
                class="ab-btn ab-btn--sm ab-btn--quiet"
                aria-label="Mais uma sessão"
                phx-click="superagent_scale"
                phx-value-id={superagent.id}
                phx-value-delta="1"
                disabled={superagent.max_workers >= 32}
              >+</button>
            </span>
          </div>
        </article>
      </div>

      <details class="ab-superagent-add">
        <summary>Adicionar projeto</summary>

        <p :if={@repos == []} class="ab-meta">
          Adicione um repositório em Configurações antes de provisionar o DeepSeek.
        </p>

        <form :if={@repos != []} phx-submit="provision_review" class="ab-superagent-add__form">
          <label>
            <span>Repositório</span>
            <select name="repository_id" required>
              <option value="">Escolha o repositório</option>
              <option :for={repo <- @repos} value={repo.id}>
                {repo.owner}/{repo.name}
              </option>
            </select>
          </label>
          <label>
            <span>Origem (profile que já funciona)</span>
            <select name="source_id" required>
              <option value="">Escolha o profile de origem</option>
              <option :for={source <- @superagents} value={source.id}>
                {source.profile} · {source.repository &&
                  "#{source.repository.owner}/#{source.repository.name}"}
              </option>
            </select>
          </label>
          <label>
            <span>Checkout local</span>
            <input name="path" required placeholder="~/projects/nome-do-projeto" />
          </label>
          <label>
            <span>Workers iniciais</span>
            <input name="workers" type="number" min="1" max="32" step="1" value="3" required />
          </label>
          <button type="submit" class="ab-btn ab-btn--sm ab-btn--primary">Revisar</button>
        </form>

        <div :if={@provision_preview} class="ab-superagent-add__preview">
          <p>{@provision_preview.phrase}</p>
          <div class="ab-act__buttons">
            <button
              type="button"
              class="ab-btn ab-btn--sm ab-btn--primary"
              phx-click="provision_confirm"
            >
              Criar projeto
            </button>
            <button
              type="button"
              class="ab-btn ab-btn--sm ab-btn--quiet"
              phx-click="provision_cancel"
            >
              Cancelar
            </button>
          </div>
        </div>
      </details>
    </section>
    """
  end

  defp remote_action(superagent)
       when superagent.observed_state in ["stopped", "unknown", "error"],
       do: :start_superagent

  defp remote_action(_superagent), do: :stop_superagent

  defp remote_label(superagent),
    do: if(remote_action(superagent) == :start_superagent, do: "Ligar", else: "Parar")

  defp state_label("ready"), do: "ligado"
  defp state_label("starting"), do: "iniciando"
  defp state_label("paused"), do: "pausado"
  defp state_label("stopped"), do: "parado"
  defp state_label("error"), do: "erro"
  defp state_label(_), do: "sem leitura"

  defp state_class("ready"), do: "ab-tag--agent"
  defp state_class("paused"), do: "ab-tag--stale"
  defp state_class("error"), do: "ab-tag--halt"
  defp state_class(_), do: "ab-tag--quiet"

  defp desired_label("running"), do: "ligado"
  defp desired_label("paused"), do: "pausado"
  defp desired_label("stopped"), do: "parado"
  defp desired_label(value), do: value

  defp observed_at(nil, _offset), do: "nunca"
  defp observed_at(%DateTime{} = at, offset), do: AgentBoard.Time.local_time(at, offset)
end
