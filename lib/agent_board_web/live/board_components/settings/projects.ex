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

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]

  alias AgentBoardWeb.BoardComponents.AgentAction
  alias AgentBoardWeb.BoardComponents.Settings.ProjectAccess
  alias AgentBoardWeb.Time

  attr :active, :boolean, default: false
  attr :superagents, :list, default: []
  attr :access_projects, :list, default: []
  attr :repos, :list, default: []
  attr :project_pending, :any, default: nil
  attr :provisioning, :boolean, default: false
  attr :tz_offset, :integer, default: 0

  @impl true
  def mount(socket) do
    {:ok, assign(socket, expanded: nil, workers: 1, create_agent: true, prefill: %{})}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    expanded =
      case socket.assigns.expanded do
        nil ->
          nil

        id ->
          if Enum.any?(socket.assigns.superagents, &(to_string(&1.id) == to_string(id))),
            do: to_string(id),
            else: nil
      end

    {:ok, assign(socket, :expanded, expanded)}
  end

  @impl true
  def handle_event("toggle_project", %{"id" => id}, socket) do
    id = to_string(id)
    expanded = if to_string(socket.assigns.expanded) == id, do: nil, else: id
    {:noreply, assign(socket, :expanded, expanded)}
  end

  def handle_event("prefill_project", %{"owner" => owner, "name" => name}, socket) do
    {:noreply, assign(socket, prefill: %{"owner" => owner, "name" => name}, create_agent: true)}
  end

  def handle_event("toggle_create_agent", _params, socket) do
    {:noreply, assign(socket, :create_agent, not socket.assigns.create_agent)}
  end

  def handle_event("change_workers", %{"delta" => delta}, socket) do
    delta = if to_string(delta) == "-1", do: -1, else: 1
    workers = socket.assigns.workers + delta

    {:noreply, assign(socket, :workers, workers |> max(1) |> min(32))}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :tracked, tracked_only(assigns.repos, assigns.superagents))

    ~H"""
    <div id={@id} class="ab-projects">
      <p :if={@superagents == [] and @tracked == []} class="ab-projects__empty" role="status">
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
                disabled={superagent.max_workers >= 32}
              >+</button>
            </div>

            <div class="ab-project__profile">
              <code>{superagent.profile}</code>
              <span class="ab-data-sm ab-faint">· :{superagent.port}</span>
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
            <details :if={superagent.last_error} class="ab-project__error-details">
              <summary>{gettext("Technical details")}</summary>
              <code>{superagent.last_error}</code>
            </details>
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
            <.live_component
              module={ProjectAccess}
              id={"project-#{superagent.id}-access"}
              project={access_project(@access_projects, superagent)}
              superagent={superagent}
              visible={@active and expanded?(@expanded, superagent)}
              tz_offset={@tz_offset}
            />

            <div class="ab-project__foot">
              <details class="ab-project__fold">
                <summary>{gettext("State folder")}</summary>
                <code>{superagent.state_dir}</code>
              </details>
              <details :if={superagent.last_error} class="ab-project__fold">
                <summary>{gettext("Technical details")}</summary>
                <code>{superagent.last_error}</code>
              </details>
              <div class="ab-project__foot-actions">
                <.live_component
                  :if={remote_action(superagent)}
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
        </li>

        <li :for={repo <- @tracked} id={"tracked-#{repo.id}"} class="ab-project ab-project--tracked">
          <div class="ab-project__row">
            <div class="ab-project__identity">
              <p class="ab-project__name">
                <span class="ab-project__owner">{repo.owner}/</span><strong>{repo.name}</strong>
              </p>
              <p class="ab-project__access">
                {gettext("The board follows it; no agent works on it.")}
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
                aria-label={
                  gettext("Create agent for %{project}", project: "#{repo.owner}/#{repo.name}")
                }
                phx-click={
                  JS.push("prefill_project",
                    value: %{owner: repo.owner, name: repo.name},
                    target: @myself
                  )
                  |> JS.focus(to: "#add-project-path")
                }
                disabled={@provisioning}
              >
                {gettext("Create agent…")}
              </button>
            </div>
          </div>
        </li>
      </ul>

      <section id="add-project" class="ab-project-add" aria-labelledby="add-project-title">
        <h3 id="add-project-title">{gettext("Add project")}</h3>
        <p class="ab-meta">
          {gettext(
            "Track a repository and, if you want, create its own DeepSeek agent. Nothing starts without your confirmation."
          )}
        </p>

        <form id="track-repo" phx-submit="add_project" class="ab-project-add__form">
          <label>
            <span>{gettext("Owner")}</span>
            <input name="owner" placeholder="sallaumen" value={@prefill["owner"]} required />
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
          <label class="ab-project-add__path">
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

          <label class="ab-project-add__create">
            <input
              type="checkbox"
              name="create_agent"
              value="true"
              checked={@create_agent}
              disabled={@provisioning}
              phx-click="toggle_create_agent"
              phx-target={@myself}
            />
            <span>{gettext("Create a DeepSeek agent for it")}</span>
          </label>

          <div class="ab-project-add__workers" role="group" aria-label={gettext("Initial agents")}>
            <span>{gettext("Agents")}</span>
            <button
              type="button"
              class="ab-btn ab-btn--sm ab-btn--icon"
              aria-label={gettext("One fewer initial agent")}
              phx-click="change_workers"
              phx-value-delta="-1"
              phx-target={@myself}
              disabled={@workers <= 1 or @provisioning or not @create_agent}
            >−</button>
            <input
              class="ab-project-add__worker-input"
              type="number"
              name="workers"
              value={@workers}
              min="1"
              max="32"
              step="1"
              aria-label={gettext("Initial agents")}
              disabled={not @create_agent or @provisioning}
            />
            <button
              type="button"
              class="ab-btn ab-btn--sm ab-btn--icon"
              aria-label={gettext("One more initial agent")}
              phx-click="change_workers"
              phx-value-delta="1"
              phx-target={@myself}
              disabled={@workers >= 32 or @provisioning or not @create_agent}
            >+</button>
          </div>

          <button
            type="submit"
            class="ab-btn ab-btn--primary ab-project-add__submit"
            phx-disable-with={gettext("Adding…")}
            disabled={@provisioning}
          >
            {gettext("Add project")}
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
              phx-disable-with={gettext("Creating…")}
              disabled={@provisioning}
            >
              {gettext("Create superagent")}
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
    </div>
    """
  end

  defp tracked_only(repos, superagents) do
    with_agent = MapSet.new(superagents, & &1.repository_id)
    Enum.reject(repos, &MapSet.member?(with_agent, &1.id))
  end

  defp expanded?(expanded, superagent), do: to_string(expanded) == to_string(superagent.id)

  defp ready_count(superagents),
    do: Enum.count(superagents, &(&1.observed_state == "ready"))

  defp agent_total(superagents), do: Enum.sum(Enum.map(superagents, & &1.max_workers))

  defp project_name(%{repository: %{owner: owner, name: name}}), do: "#{owner}/#{name}"
  defp project_name(_superagent), do: gettext("this project")

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

  defp error_text(%{last_error: nil, observed_state: "error"}) do
    gettext("The agent is in an error state. Open the controls to try again.")
  end

  defp error_text(%{last_error: nil}), do: nil

  defp error_text(%{last_error: error} = superagent) do
    cond do
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
