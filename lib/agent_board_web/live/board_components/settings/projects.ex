defmodule AgentBoardWeb.BoardComponents.Settings.Projects do
  @moduledoc """
  Settings → Projects: one row per repository, its DeepSeek agent, state,
  worker limit and who may call it. A repository tracked without an agent
  gets a short row whose button fills the add form, which asks first.

  The row opens in place. Access and refusals come from `BoardLive`'s
  `agent_access_projects` read; the expandable block only asks GitHub for the
  collaborators' roles. Every change goes through the action registry, and
  the row's error is shown under the row instead of a separate list at the
  end.
  """
  use AgentBoardWeb, :live_component

  alias AgentBoardWeb.BoardNotice

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]

  alias AgentBoard.Actions
  alias AgentBoard.GitHub
  alias AgentBoard.Orchestrator
  alias AgentBoard.Superagents
  alias AgentBoard.Superagents.RuntimeSync
  alias AgentBoardWeb.BoardComponents.AgentAction

  alias AgentBoardWeb.BoardComponents.Settings.{
    ProjectAccess,
    ProjectLeftovers,
    ProjectMerge,
    ProjectPolicy
  }

  alias AgentBoardWeb.BoardNavigation
  alias AgentBoardWeb.Locale
  alias AgentBoardWeb.Time

  attr :project_path, :string, required: true
  attr :repo, :map, default: nil
  attr :active, :boolean, default: false
  attr :superagents, :list, default: []
  attr :access_projects, :list, default: []
  attr :repos, :list, default: []
  attr :project_pending, :any, default: nil
  attr :provisioning, :boolean, default: false
  attr :tz_offset, :integer, default: 0

  @impl true
  def mount(socket) do
    {:ok, assign(socket, expanded: nil, detail: "merge", workers: 1, prefill: %{}, installed: [])}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      assign(
        socket,
        :checking_runtimes,
        Enum.any?(socket.assigns.superagents, &(runtime_status(&1) == "waiting"))
      )

    expanded =
      case socket.assigns.expanded do
        nil ->
          nil

        id ->
          if Enum.any?(socket.assigns.superagents, &(to_string(&1.id) == to_string(id))) or
               Enum.any?(socket.assigns.repos, &("repo-#{&1.id}" == id)),
             do: to_string(id),
             else: nil
      end

    # Agents installed outside the board: a few small files, read only while
    # this section is on screen.
    {:ok,
     socket
     |> assign(expanded: expanded, github_configured?: GitHub.configured?())
     |> read_profiles()}
  end

  defp read_profiles(socket) do
    if socket.assigns.active and socket.assigns.project_path == "agent" do
      installed = Superagents.unregistered()
      source? = match?({:ok, _}, Superagents.default_source())
      readiness = if installed == [] and not source?, do: Superagents.first_ready()
      assign(socket, installed: installed, source?: source?, first_ready: readiness)
    else
      assign(socket, installed: [], source?: false, first_ready: nil)
    end
  end

  @impl true
  def handle_event("toggle_project", %{"id" => id}, socket) do
    id = to_string(id)
    expanded = if to_string(socket.assigns.expanded) == id, do: nil, else: id
    {:noreply, assign(socket, expanded: expanded, detail: "merge")}
  end

  def handle_event("project_detail", %{"id" => id, "section" => section}, socket)
      when section in ~w(merge access instructions maintenance) do
    {:noreply,
     if(socket.assigns.expanded == id, do: assign(socket, :detail, section), else: socket)}
  end

  def handle_event("prefill_project", %{"owner" => owner, "name" => name}, socket) do
    {:noreply,
     socket
     |> assign(prefill: %{"owner" => owner, "name" => name})
     |> push_patch(
       to: BoardNavigation.settings_path(socket.assigns.repo, "projects", %{"path" => "agent"})
     )}
  end

  def handle_event("refresh_profiles", _params, socket) do
    {:noreply,
     socket |> read_profiles() |> BoardNotice.notify(:info, gettext("Profile list refreshed."))}
  end

  def handle_event("change_workers", %{"delta" => delta}, socket) do
    delta = if to_string(delta) == "-1", do: -1, else: 1
    workers = socket.assigns.workers + delta

    {:noreply, assign(socket, :workers, workers |> max(1) |> min(max_workers()))}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :tracked, tracked_only(assigns.repos, assigns.superagents))

    ~H"""
    <div id={@id} class="ab-projects">
      <p
        :if={@superagents == [] and @tracked == [] and @project_path != "agent"}
        class="ab-projects__empty"
        role="status"
      >
        {gettext("No project yet. Add a repository below to get started.")}
      </p>

      <p :if={@superagents != [] or @tracked != []} class="ab-projects__summary" role="status">
        <span :if={@superagents != []}>{gettext("%{ready} of %{total} on",
          ready: ready_count(@superagents),
          total: length(@superagents)
        )}</span>
        <span :if={@superagents != []} aria-hidden="true">·</span>
        <span :if={@superagents != []}>
          {ngettext("%{count} agent", "%{count} agents", agent_total(@superagents))}
        </span>
        <span :if={@superagents != [] and @tracked != []} aria-hidden="true">·</span>
        <span :if={@tracked != []}>
          {ngettext("%{count} without an agent", "%{count} without an agent", length(@tracked))}
        </span>
      </p>

      <form
        :if={@superagents != []}
        action={~p"/superagents/synchronize"}
        method="post"
        class="ab-projects__maintenance"
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <input type="hidden" name="confirm" value={sync_phrase(@superagents)} />
        <p class="ab-meta">
          {gettext(
            "Idle agents update now. Busy agents update automatically after their last task finishes and the queue is empty."
          )}
        </p>
        <p id="runtime-targets" class="ab-meta">{sync_phrase(@superagents)}</p>
        <button
          class="ab-btn"
          type="submit"
          disabled={@checking_runtimes}
          aria-describedby="runtime-targets"
        >
          {if @checking_runtimes,
            do: gettext("Synchronizing…"),
            else: gettext("Sync agent runtimes")}
        </button>
      </form>

      <ul
        :if={@superagents != [] or @tracked != []}
        class="ab-projects__list"
        aria-label={gettext("Projects")}
      >
        <li
          :for={superagent <- @superagents}
          id={"project-#{superagent.id}"}
          class="ab-project"
          data-expanded={to_string(expanded?(@expanded, superagent))}
        >
          <div class="ab-project__row">
            <div class="ab-project__identity">
              <p class="ab-project__name">
                <span class="ab-project__owner">{owner(superagent)}/</span><strong>{name(superagent)}</strong>
              </p>
              <p :if={result = runtime_status(superagent)} class="ab-meta" role="status">
                {sync_result(result)}
              </p>
              <p class="ab-project__access">
                <span
                  :if={waiting_count(access_project(@access_projects, superagent)) > 0}
                  class="ab-project__waiting"
                >
                  <.glyph kind={:you} />
                  {ngettext(
                    "%{count} waiting for access",
                    "%{count} waiting for access",
                    waiting_count(access_project(@access_projects, superagent))
                  )}
                </span>
                <span :if={waiting_count(access_project(@access_projects, superagent)) == 0}>
                  {access_summary(
                    access_project(@access_projects, superagent),
                    superagent,
                    @tz_offset
                  )}
                </span>
              </p>
            </div>

            <div class="ab-project__state">
              <span class={["ab-status", state_status(superagent)]}>
                <.glyph kind={state_glyph(superagent)} />
                {state_word(superagent)}
              </span>
              <span :if={desired_line(superagent)} class="ab-meta">{desired_line(superagent)}</span>
            </div>

            <div class="ab-project__agents">
              <button
                type="button"
                class="ab-btn ab-btn--sm ab-btn--icon"
                aria-label={
                  gettext("One fewer agent in %{project}", project: project_name(superagent))
                }
                phx-click="superagent_scale"
                phx-value-id={superagent.id}
                phx-value-delta="-1"
                disabled={superagent.max_workers <= 1}
              >−</button>
              <span
                class="ab-project__agent-count"
                title={gettext("Agents configured for this project")}
              >
                {superagent.max_workers}<span class="ab-sr">{gettext("agents")}</span>
              </span>
              <button
                type="button"
                class="ab-btn ab-btn--sm ab-btn--icon"
                aria-label={
                  gettext("One more agent in %{project}", project: project_name(superagent))
                }
                phx-click="superagent_scale"
                phx-value-id={superagent.id}
                phx-value-delta="1"
                disabled={superagent.max_workers >= max_workers()}
              >+</button>
            </div>

            <div class="ab-project__profile">
              <code title={superagent.profile}>{superagent.profile}</code>
            </div>

            <div class="ab-project__actions">
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
              <button
                type="button"
                class="ab-btn ab-btn--icon ab-btn--sm"
                aria-expanded={to_string(expanded?(@expanded, superagent))}
                aria-controls={"project-#{superagent.id}-details"}
                aria-label={
                  if expanded?(@expanded, superagent),
                    do: gettext("Close %{project}", project: project_name(superagent)),
                    else: gettext("Open %{project}", project: project_name(superagent))
                }
                phx-click="toggle_project"
                phx-value-id={superagent.id}
                phx-target={@myself}
              >
                <.icon
                  name="hero-chevron-down"
                  class={["size-4", expanded?(@expanded, superagent) && "rotate-180"]}
                />
              </button>
            </div>
          </div>

          <div
            :if={error_text(superagent)}
            class="ab-project__error"
            role="status"
            id={"project-#{superagent.id}-error"}
          >
            <p>{error_text(superagent)}</p>
            <details :if={technical_details?(superagent)} class="ab-project__error-details">
              <summary>{gettext("Technical details")}</summary>
              <code>{superagent.last_error}</code>
            </details>
            <.live_component
              :if={remote_action(superagent) == :retry_provision_superagent}
              module={AgentAction}
              id={"project-retry_provision_superagent-#{superagent.id}"}
              mode={:retry_provision_superagent}
              tone={:primary}
              superagent={superagent}
              label={remote_label(superagent)}
              confirm_label={remote_label(superagent)}
              busy_label={gettext("Applying…")}
            />
            <button
              :if={is_nil(superagent.last_error)}
              type="button"
              class="ab-btn ab-btn--sm ab-btn--quiet"
              phx-click="toggle_project"
              phx-value-id={superagent.id}
              phx-target={@myself}
            >
              {gettext("Open controls")}
            </button>
          </div>

          <div
            id={"project-#{superagent.id}-details"}
            class="ab-project__details"
            hidden={not expanded?(@expanded, superagent)}
          >
            <div class="ab-project-switch" role="group" aria-label={gettext("Project controls")}>
              <button
                :for={
                  {section, label} <- [
                    {"merge", gettext("Merge")},
                    {"access", gettext("Access")},
                    {"instructions", gettext("Instructions")},
                    {"maintenance", gettext("Maintenance")}
                  ]
                }
                type="button"
                aria-pressed={to_string(@detail == section)}
                aria-controls={"project-#{superagent.id}-view-#{section}"}
                phx-click="project_detail"
                phx-value-id={superagent.id}
                phx-value-section={section}
                phx-target={@myself}
              >{label}</button>
            </div>
            <div id={"project-#{superagent.id}-view-merge"} hidden={@detail != "merge"}>
              <.live_component
                :if={superagent.repository}
                module={ProjectMerge}
                id={"project-#{superagent.id}-merge"}
                repo={superagent.repository}
                agent={superagent}
                visible={@active and expanded?(@expanded, superagent)}
              />
            </div>
            <div id={"project-#{superagent.id}-view-access"} hidden={@detail != "access"}>
              <.live_component
                module={ProjectAccess}
                id={"project-#{superagent.id}-access"}
                project={access_project(@access_projects, superagent)}
                superagent={superagent}
                visible={@active and expanded?(@expanded, superagent)}
                tz_offset={@tz_offset}
              />
            </div>
            <div id={"project-#{superagent.id}-view-instructions"} hidden={@detail != "instructions"}>
              <.live_component
                module={ProjectPolicy}
                id={"project-#{superagent.id}-policy-panel"}
                superagent={superagent}
                visible={@active and expanded?(@expanded, superagent)}
              />
            </div>
            <div id={"project-#{superagent.id}-view-maintenance"} hidden={@detail != "maintenance"}>
              <.live_component
                module={ProjectLeftovers}
                id={"project-#{superagent.id}-leftovers-panel"}
                superagent={superagent}
                visible={@active and expanded?(@expanded, superagent)}
              />

              <div class="ab-project__foot">
                <details class="ab-project__fold">
                  <summary>{gettext("State folder")}</summary>
                  <code>{superagent.state_dir}</code>
                </details>
                <details class="ab-project__fold">
                  <summary>{gettext("dsh panel")}</summary>
                  <.form
                    for={%{}}
                    action={~p"/superagents/#{superagent.id}/panel"}
                    method="post"
                    target="_blank"
                    rel="noopener"
                    id={"project-#{superagent.id}-panel-form"}
                  >
                    <button type="submit" class="ab-btn ab-btn--sm">
                      {gettext("Open the panel signed in")}
                    </button>
                  </.form>
                </details>
                <details :if={technical_details?(superagent)} class="ab-project__fold">
                  <summary>{gettext("Technical details")}</summary>
                  <code>{superagent.last_error}</code>
                </details>
                <div class="ab-project__foot-actions">
                  <.live_component
                    :if={remote_action(superagent) in [:start_superagent, :stop_superagent]}
                    module={AgentAction}
                    id={"project-#{remote_action(superagent)}-#{superagent.id}"}
                    mode={remote_action(superagent)}
                    tone={if remote_action(superagent) == :stop_superagent, do: :halt, else: :primary}
                    superagent={superagent}
                    label={remote_label(superagent)}
                    confirm_label={remote_label(superagent)}
                    busy_label={gettext("Applying…")}
                  />
                  <.live_component
                    module={AgentAction}
                    id={"project-remove-#{superagent.id}"}
                    mode={:remove_superagent}
                    tone={:halt}
                    superagent={superagent}
                    label={gettext("Archive project…")}
                    confirm_label={gettext("Archive project")}
                    cancel_label={gettext("Keep")}
                    busy_label={gettext("Archiving…")}
                  />
                </div>
              </div>
            </div>
          </div>
        </li>

        <li :for={repo <- @tracked} id={"tracked-#{repo.id}"} class="ab-project ab-project--tracked">
          <div class="ab-project__row">
            <div class="ab-project__identity">
              <p class="ab-project__name">
                <span class="ab-project__owner">{repo.owner}/</span><strong>{repo.name}</strong>
              </p>
              <p class="ab-project__access">
                {gettext(
                  "GitHub tracking is on. No agent is connected to this board for this repository."
                )}
              </p>
            </div>

            <div class="ab-project__state">
              <span class="ab-status ab-status--queue">
                <.glyph kind={:queue} />
                {gettext("No agent")}
              </span>
            </div>

            <div class="ab-project__actions">
              <button
                type="button"
                class="ab-btn ab-btn--sm"
                phx-click="toggle_project"
                phx-value-id={"repo-#{repo.id}"}
                phx-target={@myself}
                aria-expanded={to_string(@expanded == "repo-#{repo.id}")}
                aria-controls={"tracked-#{repo.id}-merge"}
              >{gettext("Merge requirements")}</button>
              <button
                type="button"
                class="ab-btn ab-btn--sm"
                aria-label={
                  gettext("Connect an agent for %{project}", project: "#{repo.owner}/#{repo.name}")
                }
                phx-click={
                  JS.push("prefill_project",
                    value: %{owner: repo.owner, name: repo.name},
                    target: @myself
                  )
                }
                disabled={@provisioning}
              >
                {gettext("Connect agent…")}
              </button>
            </div>
          </div>
          <div
            id={"tracked-#{repo.id}-merge"}
            hidden={@expanded != "repo-#{repo.id}"}
            class="ab-project__details"
          >
            <.live_component
              module={ProjectMerge}
              id={"tracked-#{repo.id}-merge-policy"}
              repo={repo}
              agent={nil}
              visible={@active and @expanded == "repo-#{repo.id}"}
            />
          </div>
        </li>
      </ul>

      <details
        class="ab-project-add"
        id="project-setup-options"
        open={@project_path in ["github", "agent"] or (@superagents == [] and @tracked == [])}
      >
        <summary class="ab-link">{gettext("Add project")}</summary>
        <nav class="setup-paths" aria-label={gettext("Project setup")}>
          <.link
            :for={
              {path, label} <- [
                {"github", gettext("Use GitHub only")},
                {"agent", gettext("Connect the Super Agent")}
              ]
            }
            patch={BoardNavigation.settings_path(@repo, "projects", %{"path" => path})}
            aria-current={
              (@project_path == path || (@project_path == "list" && path == "github")) && "page"
            }
            class={[
              "ab-btn",
              (@project_path == path || (@project_path == "list" && path == "github")) &&
                "ab-btn--primary"
            ]}
          >
            {label}
          </.link>
        </nav>
        <section
          :if={@project_path == "agent"}
          class="ab-project-add"
          id="agent-install"
          aria-labelledby="agent-install-title"
        >
          <h3 id="agent-install-title">{gettext("Connect a DeepSeek profile")}</h3>
          <p :if={@installed == [] && !@source?} class="ab-meta">
            {case @first_ready do
              {:error, :dsh_missing} ->
                gettext(
                  "No profile found. Install DeepSeek Harness and its dsh command on the machine running the board. Then look for profiles again."
                )

              {:error, :ps_missing} ->
                gettext(
                  "The agent needs a full ps command to start. Install procps (procps-ng on Alpine), then review the installation again."
                )

              {:error, :bot_missing} ->
                gettext(
                  "The Harness is installed. Sign in to GitHub with a separate bot account, then look for profiles again."
                )

              :ok ->
                gettext(
                  "No profile found. Enter the repository and its local checkout below to review the first agent installation."
                )

              _ ->
                gettext(
                  "No profile found. Follow the Super Agent setup guide, then look for profiles again."
                )
            end}
            <code :if={@first_ready == {:error, :bot_missing}} class="break-all">{AgentBoard.Setup.bot_login_command()}</code>
          </p>
          <p :if={@installed != []} class="ab-meta">
            {gettext(
              "A profile was found on this machine. Choose it below to connect the repository it already watches."
            )}
          </p>
          <p :if={@installed == [] && @source?} class="ab-meta">
            {gettext(
              "A local profile is available. Use it to create an agent for another repository below."
            )}
          </p>
          <div class="setup-paths">
            <a
              class="ab-link"
              href="https://www.deepseek.com/en/harness/"
              target="_blank"
              rel="noopener noreferrer"
            >{gettext("Download DeepSeek Harness")}</a>
            <a
              class="ab-link"
              href={first_install_guide()}
              target="_blank"
              rel="noopener noreferrer"
            >{gettext("Super Agent setup guide")}</a>
            <button
              type="button"
              class="ab-btn ab-btn--sm"
              phx-click="refresh_profiles"
              phx-target={@myself}
            >{gettext("Look for profiles again")}</button>
          </div>
        </section>
        <section
          :if={@project_path == "agent" && @installed != []}
          id="installed-agents"
          class="ab-project-add"
          aria-labelledby="installed-agents-title"
        >
          <h3 id="installed-agents-title">
            {gettext("Agents on this machine the board does not follow")}
          </h3>
          <p class="ab-meta">
            {gettext(
              "They were installed outside the board. Adding one asks the agent which repository it serves and starts following it; the agent's configuration is not changed."
            )}
          </p>
          <ul class="ab-installed">
            <li :for={entry <- @installed} id={"installed-#{entry.name}"}>
              <div class="ab-installed__identity">
                <code>{entry.name}</code>
                <span class="ab-meta">{gettext("port %{port}", port: entry.port)}</span>
              </div>
              <.live_component
                module={AgentAction}
                id={"adopt-#{entry.name}"}
                mode={:adopt_superagent}
                tone={:primary}
                profile={entry.name}
                port={entry.port}
                label={gettext("Add to the board…")}
                confirm_label={gettext("Add to the board")}
                busy_label={gettext("Adding…")}
              />
            </li>
          </ul>
        </section>

        <section
          id="add-project"
          class="ab-project-add"
          aria-labelledby="add-project-title"
        >
          <h3 id="add-project-title" class="sr-only">{gettext("Add project")}</h3>
          <p :if={@project_path != "agent" and @github_configured?} class="ab-meta">
            {gettext(
              "A GitHub token is configured. Enter the repository owner and name. Tracking does not start an agent."
            )}
          </p>
          <p :if={@project_path != "agent" and not @github_configured?} class="ab-meta">
            {gettext(
              "To follow issues and pull requests, set GITHUB_TOKEN in .env.local and restart the board. Read access is enough. Then enter the repository below."
            )}
            <a
              class="ab-link"
              href="https://github.com/settings/tokens"
              target="_blank"
              rel="noopener noreferrer"
            >{gettext("GitHub token settings")}</a>
          </p>
          <p :if={@project_path == "agent"} class="ab-meta">
            {gettext("Review the repository, local folder and worker limit before confirming.")}
          </p>

          <form id="track-repo" phx-submit="add_project" class="ab-project-add__form">
            <label>
              <span>{gettext("Owner")}</span>
              <input name="owner" placeholder="octocat" value={@prefill["owner"]} required />
            </label>
            <label>
              <span>{gettext("Repository")}</span>
              <input
                name="name"
                placeholder={gettext("project-name")}
                value={@prefill["name"]}
                required
              />
            </label>
            <input :if={@project_path == "agent"} type="hidden" name="create_agent" value="true" />
            <div :if={@project_path == "agent"} class="ab-project-add__path">
              <label>
                <span>{gettext("Local folder, with .git")}</span>
                <input
                  id="add-project-path"
                  name="path"
                  placeholder={gettext("~/projects/project-name")}
                  aria-describedby="add-project-path-hint"
                />
              </label>
              <p id="add-project-path-hint" class="ab-project-add__hint">
                {gettext("Empty uses ~/projects/project-name.")}
              </p>
            </div>

            <div
              :if={@project_path == "agent"}
              class="ab-project-add__workers"
              role="group"
              aria-label={gettext("Initial agents")}
            >
              <span>{gettext("Agents")}</span>
              <button
                type="button"
                class="ab-btn ab-btn--sm ab-btn--icon"
                aria-label={gettext("One fewer initial agent")}
                phx-click="change_workers"
                phx-value-delta="-1"
                phx-target={@myself}
                disabled={@workers <= 1 or @provisioning}
              >−</button>
              <input
                class="ab-project-add__worker-input"
                type="number"
                name="workers"
                value={@workers}
                min="1"
                max={max_workers()}
                step="1"
                aria-label={gettext("Initial agents")}
                disabled={@provisioning}
              />
              <button
                type="button"
                class="ab-btn ab-btn--sm ab-btn--icon"
                aria-label={gettext("One more initial agent")}
                phx-click="change_workers"
                phx-value-delta="1"
                phx-target={@myself}
                disabled={@workers >= max_workers() or @provisioning}
              >+</button>
            </div>

            <button
              type="submit"
              class="ab-btn ab-btn--primary ab-project-add__submit"
              phx-disable-with={gettext("Adding…")}
              disabled={@provisioning}
            >
              {if @project_path == "agent",
                do: gettext("Review agent setup"),
                else: gettext("Track repository")}
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
            <p class="ab-meta">
              {ngettext(
                "Initial agents: %{count}",
                "Initial agents: %{count}",
                @project_pending.params.workers
              )}
            </p>
            <div class="ab-act__buttons">
              <button
                type="button"
                class="ab-btn ab-btn--sm ab-btn--primary"
                phx-click="add_project_confirm"
                phx-disable-with={
                  if first_agent?(@project_pending),
                    do: gettext("Installing…"),
                    else: gettext("Creating…")
                }
                disabled={@provisioning}
              >
                {if first_agent?(@project_pending),
                  do: gettext("Install the agent"),
                  else: gettext("Create superagent")}
              </button>
              <button
                type="button"
                class="ab-btn ab-btn--sm ab-btn--quiet"
                phx-click="add_project_cancel"
                disabled={@provisioning}
              >
                {gettext("Not now")}
              </button>
            </div>
          </div>
        </section>
      </details>
    </div>
    """
  end

  defp max_workers, do: Orchestrator.worker_range().last

  defp tracked_only(repos, superagents) do
    with_agent = MapSet.new(superagents, & &1.repository_id)
    Enum.reject(repos, &MapSet.member?(with_agent, &1.id))
  end

  defp expanded?(expanded, superagent), do: to_string(expanded) == to_string(superagent.id)

  defp ready_count(superagents),
    do: Enum.count(superagents, &(&1.observed_state == "ready"))

  defp agent_total(superagents), do: Enum.sum(Enum.map(superagents, & &1.max_workers))

  defp sync_phrase(agents),
    do:
      Actions.phrase(
        :sync_agent_runtimes,
        %{targets: RuntimeSync.targets(agents)},
        Locale.language()
      )

  defp runtime_status(%{runtime_sync: %{"status" => status}}), do: status
  defp runtime_status(_), do: nil

  defp sync_result("waiting"), do: gettext("Waiting to check")
  defp sync_result("updated"), do: gettext("Harness updated")
  defp sync_result("current"), do: gettext("Harness already current")
  defp sync_result("paused"), do: gettext("Skipped: agent paused")

  defp sync_result("pending"),
    do: gettext("Update pending — waiting for work and queue to finish")

  defp sync_result("changed"), do: gettext("Skipped: agent state changed")
  defp sync_result("identity"), do: gettext("Skipped: project identity changed")
  defp sync_result("unavailable"), do: gettext("Skipped: agent unavailable")
  defp sync_result("in_progress"), do: gettext("Another synchronization is in progress")

  defp sync_result("failed"),
    do: gettext("Could not verify the update. Check the agent before retrying.")

  defp project_name(%{repository: %{owner: owner, name: name}}), do: "#{owner}/#{name}"
  defp project_name(_superagent), do: gettext("this project")

  defp first_install_guide do
    page =
      if AgentBoardWeb.Locale.language() == "pt-BR",
        do: "primeiros-passos.md#conectar-o-super-agent",
        else: "getting-started.md#connect-the-super-agent"

    "https://github.com/sallaumen/dsh-superagent-superboard/blob/main/docs/" <> page
  end

  defp owner(%{repository: %{owner: owner}}), do: owner
  defp owner(_superagent), do: gettext("repository removed")

  defp name(%{repository: %{name: name}}), do: name
  defp name(_superagent), do: ""

  defp access_project(projects, superagent) do
    Enum.find(projects, &(to_string(&1.id) == to_string(superagent.id)))
  end

  defp waiting_count(nil), do: 0
  defp waiting_count(%{requests: requests}), do: length(requests)

  defp access_summary(nil, _superagent, _tz_offset), do: gettext("Reading access…")

  defp access_summary(%{state: :unavailable}, _superagent, _tz_offset),
    do: gettext("Access unavailable")

  defp access_summary(project, superagent, tz_offset) do
    allowed =
      case length(project.allowed) do
        0 -> gettext("No one with access")
        count -> ngettext("%{count} person with access", "%{count} people with access", count)
      end

    allowed <> " · " <> last_read(superagent, tz_offset)
  end

  defp last_read(%{observed_at: nil}, _tz_offset), do: gettext("no reading")

  defp last_read(%{observed_at: at}, tz_offset) do
    gettext("read at %{time}", time: Time.local_time(at, tz_offset))
  end

  defp state_glyph(%{observed_state: "ready"}), do: :run
  defp state_glyph(%{observed_state: "paused"}), do: :stale
  defp state_glyph(%{observed_state: "error"}), do: :blocked
  defp state_glyph(%{observed_state: "starting"}), do: :queue
  defp state_glyph(%{observed_state: "stopped"}), do: :queue
  defp state_glyph(_superagent), do: :unknown

  defp state_word(%{observed_state: "ready"}), do: gettext("On")
  defp state_word(%{observed_state: "paused"}), do: gettext("Paused")
  defp state_word(%{observed_state: "error"}), do: gettext("Not starting")
  defp state_word(%{observed_state: "starting"}), do: gettext("Starting")
  defp state_word(%{observed_state: "stopped"}), do: gettext("Stopped")
  defp state_word(_superagent), do: gettext("No reading")

  defp state_status(%{observed_state: "ready"}), do: "ab-status--run"
  defp state_status(%{observed_state: "paused"}), do: "ab-status--stale"
  defp state_status(%{observed_state: "error"}), do: "ab-status--halt"
  defp state_status(%{observed_state: "starting"}), do: "ab-status--queue"
  defp state_status(%{observed_state: "stopped"}), do: "ab-status--queue"
  defp state_status(_superagent), do: "ab-status--queue"

  defp desired_line(%{provision_failed_at: %DateTime{}}), do: gettext("setup did not finish")

  defp desired_line(%{desired_state: "running", observed_state: state})
       when state in ["ready", "starting"],
       do: nil

  defp desired_line(%{desired_state: "paused", observed_state: "paused"}), do: nil

  defp desired_line(%{desired_state: "stopped", observed_state: state})
       when state in ["stopped", "unknown"],
       do: nil

  defp desired_line(%{desired_state: "running"}), do: gettext("should be on")
  defp desired_line(%{desired_state: "paused"}), do: gettext("should be paused")
  defp desired_line(%{desired_state: "stopped"}), do: gettext("should be stopped")
  defp desired_line(_superagent), do: nil

  defp first_agent?(pending),
    do: is_map(pending) and pending[:action] == :install_first_superagent

  defp error_text(%{last_error: nil, observed_state: "error"}) do
    gettext("The agent is in an error state. Open the controls to try again.")
  end

  defp error_text(%{last_error: nil}), do: nil

  defp error_text(%{last_error: error} = superagent) do
    cond do
      # A failed setup that says in words what to fix is shown, not pointed at.
      superagent.provision_failed_at && words?(error) ->
        error

      String.contains?(String.downcase(error), "rate limit") ->
        gettext("GitHub reached its reading limit. Wait for the quota to renew and check again.")

      String.contains?(String.downcase(error), "não aponta") or
        String.contains?(String.downcase(error), "does not point") or
          String.contains?(String.downcase(error), "no repository") ->
        gettext(
          "The GitHub source does not point to any repository, so the agent does not start. Its %{count} agents stay stopped until this is fixed.",
          count: superagent.max_workers
        )

      String.length(error) > 160 ->
        gettext("The agent reported an error. Open the technical details to see the cause.")

      true ->
        error
    end
  end

  # An Elixir term (`{:manager, 1, ...}`, `%Req.TransportError{}`, `:timeout`) is not a sentence.
  defp words?(error), do: not String.starts_with?(error, ["{", "%", ":"])

  defp technical_details?(%{last_error: nil}), do: false
  defp technical_details?(superagent), do: error_text(superagent) != superagent.last_error

  # A project whose setup failed has nothing to start: it is set up again.
  defp remote_action(%{provision_failed_at: %DateTime{}, observed_state: "error"} = superagent)
       when is_binary(superagent.checkout_path),
       do: :retry_provision_superagent

  # A retry is running, or there is nothing stored to retry with.
  defp remote_action(%{provision_failed_at: %DateTime{}}), do: nil

  defp remote_action(superagent)
       when superagent.observed_state in ["stopped", "unknown", "error"],
       do: :start_superagent

  defp remote_action(_superagent), do: :stop_superagent

  defp remote_label(superagent) do
    case remote_action(superagent) do
      :retry_provision_superagent -> gettext("Try again")
      :start_superagent -> gettext("Start")
      _other -> gettext("Stop")
    end
  end
end
