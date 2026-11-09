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
    has_errors = Enum.any?(assigns.superagents, &(&1.observed_state == "error"))
    available = available_repos(assigns.repos, assigns.superagents)

    assigns =
      assigns
      |> assign(:total_agents, total_agents)
      |> assign(:ready_agents, ready)
      |> assign(:has_errors, has_errors)
      |> assign(:available_repos, available)

    ~H"""
    <section id="superagents-panel" class="ab-superagents">
      <header class="ab-superagents__head">
        <div>
          <div :if={@superagents != []} class="ab-superagents__summary">
            <span>{length(@superagents)} {if length(@superagents) == 1,
              do: "projeto",
              else: "projetos"}</span>
            <span class={[
              "ab-superagents__summary-state",
              @has_errors && "is-error",
              @ready_agents == length(@superagents) && "is-all-ready"
            ]}>
              {@ready_agents}/{length(@superagents)} {gettext("on")}
            </span>
            <span title={gettext("Sum of agent limits configured per project")}>
              {ngettext("%{count} agent configured", "%{count} agents configured", @total_agents)}
            </span>
          </div>
          <p :if={@superagents != []} class="ab-meta">
            {gettext("Each project has its own agent limit.")}
          </p>
        </div>
        <a :if={@available_repos != []} href="#superagent-add" class="ab-btn ab-btn--primary">
          <.ico name="plus" />{gettext("Add project")}
        </a>
      </header>

      <p :if={@superagents == []} class="ab-empty ab-superagents__empty">
        {gettext("No superagents registered. Add a repository to get started.")}
      </p>

      <div :if={@superagents != []} class="ab-table-wrap ab-superagents__table-wrap">
        <table class="ab-superagent-table">
          <caption class="ab-sr">
            {gettext("Superagents by project, status, agents, and last read")}
          </caption>
          <thead>
            <tr>
              <th scope="col">{gettext("Project")}</th>
              <th scope="col">{gettext("Status")}</th>
              <th scope="col">{gettext("Agents")}</th>
              <th scope="col">{gettext("Profile · port")}</th>
              <th scope="col">{gettext("Last read")}</th>
              <th scope="col"><span class="ab-sr">{gettext("Actions")}</span></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={superagent <- @superagents} id={"superagent-#{superagent.id}"}>
              <td class="ab-superagent-table__project" data-label={gettext("Project")}>
                <b>
                  {if superagent.repository,
                    do: "#{superagent.repository.owner}/#{superagent.repository.name}",
                    else: gettext("repository removed")}
                </b>
                <details class="ab-superagent-table__details">
                  <summary>{gettext("State folder")}</summary>
                  <code class="ab-superagent-table__path">{superagent.state_dir}</code>
                </details>
              </td>
              <td class="ab-superagent-table__state" data-label={gettext("Status")}>
                <span class={["ab-status", state_status(superagent.observed_state)]}>
                  <.glyph kind={state_glyph(superagent.observed_state)} />
                  {state_label(superagent.observed_state)}
                </span>
                <span class="ab-meta">{state_line(superagent)}</span>
              </td>
              <td class="ab-superagent-table__agents" data-label={gettext("Agents")}>
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
                    {superagent.max_workers}<span class="ab-sr">{gettext("agents")}</span>
                  </span>
                  <button
                    type="button"
                    class="ab-btn ab-btn--sm"
                    aria-label={gettext("One more agent in %{repo}", repo: repo_name(superagent))}
                    phx-click="superagent_scale"
                    phx-value-id={superagent.id}
                    phx-value-delta="1"
                    disabled={superagent.max_workers >= 32}
                  >+</button>
                </span>
              </td>
              <td class="ab-superagent-table__profile" data-label={gettext("Profile · port")}>
                <code>{superagent.profile}</code>
                <span class="ab-data-sm ab-faint">{superagent.port}</span>
              </td>
              <td class="ab-superagent-table__read" data-label={gettext("Last read")}>
                <span class="ab-data-sm">{observed_at(superagent.observed_at, @tz_offset)}</span>
                <span class="ab-meta">{observed_age(superagent.observed_at)}</span>
              </td>
              <td class="ab-superagent-table__actions" data-label={gettext("Actions")}>
                <button
                  :if={superagent.observed_state == "ready"}
                  type="button"
                  class="ab-btn ab-btn--sm"
                  phx-click="superagent_command"
                  phx-value-id={superagent.id}
                  phx-value-action="pause"
                >
                  {gettext("Pause")}
                </button>
                <button
                  :if={superagent.observed_state == "paused"}
                  type="button"
                  class="ab-btn ab-btn--sm"
                  phx-click="superagent_command"
                  phx-value-id={superagent.id}
                  phx-value-action="resume"
                >
                  {gettext("Resume")}
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
                  <summary class="ab-btn ab-btn--icon ab-btn--sm" aria-label={gettext("More Actions")}>
                    <.ico name="grip" />
                  </summary>
                  <div class="ab-superagent-menu__body">
                    <p class="ab-superagent-menu__hint">
                      {gettext("Stops the process and archives the profile and state in")} <code>{gettext("~/.agent_board/archived-superagents")}</code>{gettext(
                        ". Nothing is deleted."
                      )}
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

      <div
        :if={@superagents != [] and Enum.any?(@superagents, & &1.last_error)}
        class="ab-superagents__errors"
        role="status"
      >
        <.ico name="warning" />
        <span :for={superagent <- @superagents} :if={superagent.last_error}>
          <b>{superagent.repository && superagent.repository.name}:</b>
          {error_summary(superagent.last_error)}
          <details :if={error_details?(superagent.last_error)}>
            <summary>{gettext("Technical details")}</summary>
            <code>{superagent.last_error}</code>
          </details>
        </span>
      </div>

      <div :if={@superagents != [] and @available_repos == []} class="ab-superagents__complete">
        <span>{gettext("All monitored repositories already have a superagent.")}</span>
        <button type="button" class="ab-btn" phx-click="show_panel" phx-value-panel="settings">
          {gettext("Add repository in Settings")}
        </button>
      </div>

      <section
        :if={@available_repos != []}
        id="superagent-add"
        class="ab-superagent-add"
        aria-labelledby="superagent-add-title"
      >
        <h3 id="superagent-add-title">{gettext("Add project")}</h3>
        <p class="ab-meta">
          {gettext(
            "Select a repository, source profile, and local checkout. You will review the data before starting the agent."
          )}
        </p>
        <form
          phx-submit="provision_review"
          class="ab-superagent-add__form"
        >
          <label>
            <span>{gettext("Repository")}</span>
            <select name="repository_id" required>
              <option value="">{gettext("Choose repository")}</option>
              <option :for={repo <- @available_repos} value={repo.id}>
                {repo.owner}/{repo.name}
              </option>
            </select>
          </label>
          <label>
            <span>{gettext("Source (working profile)")}</span>
            <select name="source_id" required>
              <option value="">{gettext("Choose source profile")}</option>
              <option :for={source <- @superagents} value={source.id}>
                {source.profile} · {source.repository &&
                  "#{source.repository.owner}/#{source.repository.name}"}
              </option>
            </select>
          </label>
          <label>
            <span>{gettext("Local checkout")}</span>
            <input name="path" required placeholder={gettext("~/projects/project-name")} />
          </label>
          <label>
            <span>{gettext("Initial Agents")}</span>
            <input name="workers" type="number" min="1" max="32" step="1" value="3" required />
          </label>
          <button type="submit" class="ab-btn ab-btn--sm ab-btn--primary">{gettext("Review")}</button>
        </form>

        <div :if={@provision_preview} class="ab-superagent-add__preview">
          <p>{@provision_preview.phrase}</p>
          <p class="ab-meta">
            {gettext("Initial Agents:")} <b>{@provision_preview.params.workers}</b>{gettext(
              ". You can change the limit later, project by project."
            )}
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
              {gettext("Cancel")}
            </button>
          </div>
        </div>
      </section>
    </section>
    """
  end

  defp repo_name(%{repository: %{owner: owner, name: name}}), do: "#{owner}/#{name}"
  defp repo_name(_superagent), do: "este projeto"

  defp error_summary(error) do
    cond do
      String.contains?(String.downcase(error), "rate limit exceeded") ->
        "O GitHub atingiu o limite de consultas. Aguarde a cota renovar e confira novamente."

      String.length(error) > 160 ->
        gettext("The agent reported an error. Open technical details to see the cause.")

      true ->
        error
    end
  end

  defp error_details?(error), do: error_summary(error) != error

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

  defp state_label("ready"), do: gettext("on")
  defp state_label("starting"), do: gettext("starting")
  defp state_label("paused"), do: gettext("paused")
  defp state_label("stopped"), do: gettext("stopped")
  defp state_label("error"), do: gettext("error")
  defp state_label(_), do: gettext("no reading")

  defp state_status("ready"), do: "ab-status--run"
  defp state_status("paused"), do: "ab-status--stale"
  defp state_status("error"), do: "ab-status--halt"
  defp state_status(_), do: "ab-status--queue"

  defp desired_label("running"), do: gettext("on")
  defp desired_label("paused"), do: gettext("paused")
  defp desired_label("stopped"), do: gettext("stopped")
  defp desired_label(value), do: value

  defp observed_at(nil, _offset), do: gettext("never")
  defp observed_at(%DateTime{} = at, offset), do: AgentBoardWeb.Time.local_time(at, offset)

  defp observed_age(nil), do: gettext("no reading")

  defp observed_age(%DateTime{} = at) do
    AgentBoardWeb.Time.ago(AgentBoardWeb.Time.age_seconds(at, DateTime.utc_now()))
  end
end
