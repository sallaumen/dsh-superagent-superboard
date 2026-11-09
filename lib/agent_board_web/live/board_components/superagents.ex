defmodule AgentBoardWeb.BoardComponents.Superagents do
  @moduledoc "The DeepSeek superagents registered on this board, one per project."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1]
  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]

  alias AgentBoardWeb.BoardComponents.AgentAction

  attr :superagents, :list, required: true
  attr :repos, :list, required: true
  attr :provision_preview, :any, default: nil
  attr :provisioning, :boolean, default: false
  attr :tz_offset, :integer, default: 0

  def superagents(assigns) do
    total_agents = Enum.sum(Enum.map(assigns.superagents, & &1.max_workers))
    ready = Enum.count(assigns.superagents, &(&1.observed_state == "ready"))
    available = available_repos(assigns.repos, assigns.superagents)

    assigns =
      assigns
      |> assign(:total_agents, total_agents)
      |> assign(:ready_agents, ready)
      |> assign(:available_repos, available)

    ~H"""
    <section id="superagents-panel" class="ab-superagents">
      <header class="ab-superagents__head">
        <div>
          <div class="ab-superagents__title">
            <h2>Superagentes DeepSeek</h2>
            <span class="ab-tag">{length(@superagents)} projetos</span>
            <span
              class="ab-tag ab-tag--agent"
              title="Soma dos limites de agentes configurados em cada projeto"
            >{@total_agents} agentes</span>
          </div>
          <p class="ab-meta">
            Cada projeto tem a própria pilha de agentes. <b>{@total_agents}</b>
            configurados no total, {@ready_agents} projetos ligados; o board observa os processos
            e não os inicia como filhos.
          </p>
        </div>
        <a href="#superagent-add" class="ab-btn ab-btn--sm ab-btn--primary">
          <.ico name="plus" />Adicionar projeto
        </a>
      </header>

      <p :if={@superagents == []} class="ab-empty ab-superagents__empty">
        Nenhum superagent registrado. Use “Adicionar projeto” abaixo para criar o primeiro.
      </p>

      <div :if={@superagents != []} class="ab-table-wrap ab-superagents__table-wrap">
        <table class="ab-superagent-table">
          <caption class="ab-sr">Superagentes por projeto, estado, agentes e última leitura</caption>
          <thead>
            <tr>
              <th scope="col">Projeto</th>
              <th scope="col">Estado</th>
              <th scope="col">Agentes</th>
              <th scope="col">Profile · porta</th>
              <th scope="col">Última leitura</th>
              <th scope="col"><span class="ab-sr">Ações</span></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={superagent <- @superagents} id={"superagent-#{superagent.id}"}>
              <td class="ab-superagent-table__project" data-label="Projeto">
                <b>
                  {if superagent.repository,
                    do: "#{superagent.repository.owner}/#{superagent.repository.name}",
                    else: "repositório removido"}
                </b>
                <code class="ab-superagent-table__path">{superagent.state_dir}</code>
              </td>
              <td data-label="Estado">
                <span class={["ab-status", state_status(superagent.observed_state)]}>
                  <.glyph kind={state_glyph(superagent.observed_state)} />
                  {state_label(superagent.observed_state)}
                </span>
                <span class="ab-meta">{state_line(superagent)}</span>
              </td>
              <td class="ab-superagent-table__agents" data-label="Agentes">
                <span class="ab-agent-stack" aria-hidden="true">
                  <i :for={slot <- 1..32} class={slot <= superagent.max_workers && "is-on"}></i>
                </span>
                <span class="ab-superagent__workers">
                  <button
                    type="button"
                    class="ab-btn ab-btn--sm"
                    aria-label={"Menos um agente em #{repo_name(superagent)}"}
                    phx-click="superagent_scale"
                    phx-value-id={superagent.id}
                    phx-value-delta="-1"
                    disabled={superagent.max_workers <= 1}
                  >−</button>
                  <span title={"#{superagent.max_workers} agentes configurados neste projeto"}>
                    {superagent.max_workers}<span class="ab-sr"> agentes</span>
                  </span>
                  <button
                    type="button"
                    class="ab-btn ab-btn--sm"
                    aria-label={"Mais um agente em #{repo_name(superagent)}"}
                    phx-click="superagent_scale"
                    phx-value-id={superagent.id}
                    phx-value-delta="1"
                    disabled={superagent.max_workers >= 32}
                  >+</button>
                </span>
              </td>
              <td data-label="Profile · porta">
                <code>{superagent.profile}</code>
                <span class="ab-data-sm ab-faint">{superagent.port}</span>
              </td>
              <td data-label="Última leitura">
                <span class="ab-data-sm">{observed_at(superagent.observed_at, @tz_offset)}</span>
                <span class="ab-meta">{observed_age(superagent.observed_at)}</span>
              </td>
              <td class="ab-superagent-table__actions" data-label="Ações">
                <button
                  :if={superagent.observed_state == "ready"}
                  type="button"
                  class="ab-btn ab-btn--sm"
                  phx-click="superagent_command"
                  phx-value-id={superagent.id}
                  phx-value-action="pause"
                >
                  Pausar
                </button>
                <button
                  :if={superagent.observed_state == "paused"}
                  type="button"
                  class="ab-btn ab-btn--sm"
                  phx-click="superagent_command"
                  phx-value-id={superagent.id}
                  phx-value-action="resume"
                >
                  Retomar
                </button>

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

                <details class="ab-superagent-menu">
                  <summary class="ab-btn ab-btn--icon ab-btn--sm" aria-label="Mais ações">
                    <.ico name="grip" />
                  </summary>
                  <div class="ab-superagent-menu__body">
                    <p class="ab-superagent-menu__hint">
                      Para o processo e arquiva profile e state em <code>~/.agent_board/archived-superagents</code>. Nada é apagado.
                    </p>
                    <.live_component
                      module={AgentAction}
                      id={"superagent-remove-#{superagent.id}"}
                      mode={:remove_superagent}
                      tone={:halt}
                      superagent={superagent}
                      label="Arquivar projeto…"
                      confirm_label="Arquivar projeto"
                      cancel_label="Manter"
                      busy_label="Arquivando…"
                    />
                  </div>
                </details>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p
        :if={@superagents != [] and Enum.any?(@superagents, & &1.last_error)}
        class="ab-superagents__errors"
        role="status"
      >
        <.ico name="warning" />
        <span :for={superagent <- @superagents} :if={superagent.last_error}>
          <b>{superagent.repository && superagent.repository.name}:</b> {superagent.last_error}
        </span>
      </p>

      <p :if={@superagents != []} class="ab-superagents__note">
        O contador de agentes é por projeto. Para tirar um projeto do board, use <b>⋯ → Arquivar projeto</b>: o processo para e o profile/state ficam em <code>~/.agent_board/archived-superagents</code>; nada é apagado.
      </p>

      <section id="superagent-add" class="ab-superagent-add" aria-labelledby="superagent-add-title">
        <h3 id="superagent-add-title">Adicionar projeto</h3>
        <p class="ab-meta">
          Escolha um repositório já acompanhado e um profile de origem que já funciona.
          O board cria o profile, reserva a porta, copia o estado e inicia o processo com
          a sua própria pilha de agentes.
        </p>

        <div :if={@available_repos == []} class="ab-superagent-add__empty">
          <p class="ab-meta">
            Todos os repositórios acompanhados já têm um superagent.
            Adicione outro repositório em Configurações → Repositórios.
          </p>
          <button
            type="button"
            class="ab-btn ab-btn--sm"
            phx-click="show_panel"
            phx-value-panel="settings"
          >Abrir Configurações</button>
        </div>

        <form
          :if={@available_repos != []}
          phx-submit="provision_review"
          class="ab-superagent-add__form"
        >
          <label>
            <span>Repositório</span>
            <select name="repository_id" required>
              <option value="">Escolha o repositório</option>
              <option :for={repo <- @available_repos} value={repo.id}>
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
            <span>Agentes iniciais</span>
            <input name="workers" type="number" min="1" max="32" step="1" value="3" required />
          </label>
          <button type="submit" class="ab-btn ab-btn--sm ab-btn--primary">Revisar</button>
        </form>

        <div :if={@provision_preview} class="ab-superagent-add__preview">
          <p>{@provision_preview.phrase}</p>
          <p class="ab-meta">
            Agentes iniciais: <b>{@provision_preview.params.workers}</b>.
            Você poderá mudar o limite depois, projeto a projeto.
          </p>
          <div class="ab-act__buttons">
            <button
              type="button"
              class="ab-btn ab-btn--sm ab-btn--primary"
              phx-click="provision_confirm"
              disabled={@provisioning}
            >
              {if @provisioning, do: "Adicionando…", else: "Adicionar e iniciar"}
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
      </section>
    </section>
    """
  end

  defp repo_name(%{repository: %{owner: owner, name: name}}), do: "#{owner}/#{name}"
  defp repo_name(_superagent), do: "este projeto"

  defp available_repos(repos, superagents) do
    taken = MapSet.new(superagents, & &1.repository_id)
    Enum.reject(repos, &MapSet.member?(taken, &1.id))
  end

  defp remote_action(superagent)
       when superagent.observed_state in ["stopped", "unknown", "error"],
       do: :start_superagent

  defp remote_action(_superagent), do: :stop_superagent

  defp remote_label(superagent),
    do: if(remote_action(superagent) == :start_superagent, do: "Ligar", else: "Parar")

  defp state_line(superagent) do
    cond do
      superagent.desired_state == "running" and superagent.observed_state == "ready" ->
        "como desejado"

      superagent.desired_state == "paused" and superagent.observed_state == "paused" ->
        "como desejado"

      superagent.desired_state == "stopped" and
          superagent.observed_state in ["stopped", "unknown"] ->
        "como desejado"

      true ->
        "desejado #{desired_label(superagent.desired_state)}"
    end
  end

  defp state_glyph("ready"), do: :run
  defp state_glyph("paused"), do: :stale
  defp state_glyph("error"), do: :blocked
  defp state_glyph(_state), do: :queue

  defp state_label("ready"), do: "ligado"
  defp state_label("starting"), do: "iniciando"
  defp state_label("paused"), do: "pausado"
  defp state_label("stopped"), do: "parado"
  defp state_label("error"), do: "erro"
  defp state_label(_), do: "sem leitura"

  defp state_status("ready"), do: "ab-status--run"
  defp state_status("paused"), do: "ab-status--stale"
  defp state_status("error"), do: "ab-status--halt"
  defp state_status(_), do: "ab-status--queue"

  defp desired_label("running"), do: "ligado"
  defp desired_label("paused"), do: "pausado"
  defp desired_label("stopped"), do: "parado"
  defp desired_label(value), do: value

  defp observed_at(nil, _offset), do: "nunca"
  defp observed_at(%DateTime{} = at, offset), do: AgentBoard.Time.local_time(at, offset)

  defp observed_age(nil), do: "sem leitura"

  defp observed_age(%DateTime{} = at) do
    AgentBoard.Time.ago(AgentBoard.Time.age_seconds(at, DateTime.utc_now()))
  end
end
