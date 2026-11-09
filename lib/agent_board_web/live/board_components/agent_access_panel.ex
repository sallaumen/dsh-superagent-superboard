defmodule AgentBoardWeb.BoardComponents.AgentAccessPanel do
  @moduledoc """
  Settings → Agent access: for each project, who asked and was refused, who
  is cleared, and how to add someone. It reads only while it is on screen;
  every change goes through `AgentBoard.Actions`, and the projects, people
  and issues a button acts on come from the server's own read.
  """
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1]

  alias AgentBoard.{Actions, AgentAccess}
  alias AgentBoardWeb.BoardComponents.AgentAction

  @collaborators_ttl_ms :timer.minutes(10)

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       projects: [],
       loaded: false,
       loading: false,
       collaborators: %{},
       collaborators_at: nil,
       candidates: %{},
       form_errors: %{},
       checking: MapSet.new(),
       notice: nil
     )}
  end

  @impl true
  def update(%{refresh: true}, socket), do: {:ok, load(socket)}

  def update(assigns, socket) do
    was_visible = socket.assigns[:visible] == true
    socket = assign(socket, assigns)
    %{visible: visible, loaded: loaded, loading: loading} = socket.assigns

    # Coming back to the section reads again; the screen may be old by then.
    if visible and not loading and not (loaded and was_visible) do
      {:ok, load(socket)}
    else
      {:ok, socket}
    end
  end

  defp load(%{assigns: %{visible: false}} = socket), do: socket

  defp load(socket) do
    superagents = socket.assigns.superagents

    socket
    |> assign(loading: true)
    |> start_async(:load, fn -> AgentAccess.overview(superagents) end)
    |> maybe_load_collaborators(superagents)
  end

  # The one read here that spends the GitHub quota, so it waits a while.
  defp maybe_load_collaborators(socket, superagents) do
    if fresh?(socket.assigns.collaborators_at) do
      socket
    else
      socket
      |> assign(collaborators_at: System.monotonic_time(:millisecond))
      |> start_async(:collaborators, fn -> read_collaborators(superagents) end)
    end
  end

  defp fresh?(nil), do: false
  defp fresh?(at), do: System.monotonic_time(:millisecond) - at < @collaborators_ttl_ms

  defp read_collaborators(superagents) do
    Map.new(superagents, fn superagent ->
      case AgentAccess.collaborators(superagent) do
        {:ok, roles} -> {superagent.id, roles}
        {:error, _reason} -> {superagent.id, :unknown}
      end
    end)
  end

  @impl true
  def handle_async(:load, {:ok, fresh}, socket) do
    {:noreply,
     assign(socket,
       projects: AgentAccess.keep_last_good(socket.assigns.projects, fresh),
       loaded: true,
       loading: false
     )}
  end

  def handle_async(:load, {:exit, _reason}, socket) do
    {:noreply,
     assign(socket,
       loaded: true,
       loading: false,
       notice: gettext("Could not read access right now. The last reading is still shown.")
     )}
  end

  def handle_async(:collaborators, {:ok, roles}, socket),
    do: {:noreply, assign(socket, collaborators: roles)}

  def handle_async(:collaborators, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, collaborators_at: nil)}

  def handle_async({:candidate, id}, {:ok, candidate}, socket) do
    {:noreply,
     socket
     |> update(:checking, &MapSet.delete(&1, id))
     |> update(:candidates, &Map.put(&1, id, candidate))}
  end

  def handle_async({:candidate, id}, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> update(:checking, &MapSet.delete(&1, id))
     |> update(
       :form_errors,
       &Map.put(&1, id, gettext("Could not check this account. Try again."))
     )}
  end

  @impl true
  def handle_event("check_person", %{"project" => id, "login" => login}, socket) do
    case {project(socket, id), AgentAccess.normalize_login(login)} do
      {nil, _login} ->
        {:noreply, socket}

      {project, {:error, :invalid_login}} ->
        {:noreply,
         socket
         |> update(:candidates, &Map.delete(&1, project.id))
         |> update(:form_errors, &Map.put(&1, project.id, gettext("That is not a GitHub login.")))}

      {project, {:ok, login}} ->
        {:noreply, check_person(socket, project, login)}
    end
  end

  def handle_event("clear_candidate", %{"project" => id}, socket) do
    case project(socket, id) do
      nil -> {:noreply, socket}
      project -> {:noreply, update(socket, :candidates, &Map.delete(&1, project.id))}
    end
  end

  # The login must be one the server just listed for this project: an event
  # cannot set aside a request the screen does not have.
  def handle_event("dismiss_request", %{"project" => id, "login" => login}, socket) do
    with %{} = project <- project(socket, id),
         %{} = request <- Enum.find(project.requests, &(&1.login == login)),
         {:ok, _text} <- dismiss(project, request) do
      {:noreply, load(socket)}
    else
      {:error, text} when is_binary(text) -> {:noreply, assign(socket, notice: text)}
      _gone -> {:noreply, socket}
    end
  end

  defp dismiss(project, request) do
    Actions.run(
      :dismiss_access_request,
      %{superagent: project.superagent, login: request.login},
      Actions.owner(:ui)
    )
  end

  defp check_person(socket, project, login) do
    if listed?(project, login) do
      socket
      |> update(:candidates, &Map.delete(&1, project.id))
      |> update(
        :form_errors,
        &Map.put(&1, project.id, gettext("@%{login} is already allowed.", login: login))
      )
    else
      superagent = project.superagent

      socket
      |> update(:form_errors, &Map.delete(&1, project.id))
      |> update(:candidates, &Map.delete(&1, project.id))
      |> update(:checking, &MapSet.put(&1, project.id))
      |> start_async({:candidate, project.id}, fn ->
        AgentAccess.candidate(superagent, login)
      end)
    end
  end

  defp listed?(project, login) do
    Enum.any?(project.allowed, &(String.downcase(&1.login) == String.downcase(login)))
  end

  defp project(socket, id) do
    Enum.find(socket.assigns.projects, &(to_string(&1.id) == to_string(id)))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="ab-access">
      <p :if={@notice} class="ab-access__notice" role="status">{@notice}</p>
      <p :if={@loading and not @loaded} class="ab-meta" role="status">{gettext("Reading access…")}</p>
      <p :if={@loaded and @projects == []} class="ab-meta">
        {gettext("No project has a DeepSeek agent yet. Add one under Superagents.")}
      </p>

      <section
        :for={project <- @projects}
        id={"access-project-#{project.id}"}
        class="ab-access__project"
        aria-labelledby={"access-project-#{project.id}-title"}
      >
        <header class="ab-access__head">
          <h4 id={"access-project-#{project.id}-title"}>{project.repository}</h4>
          <span class="ab-meta">
            {ngettext("%{count} allowed", "%{count} allowed", length(project.allowed))}
            <span :if={project.requests != []}>
              · {ngettext("%{count} waiting", "%{count} waiting", length(project.requests))}
            </span>
          </span>
        </header>

        <p :if={project.state != :ok} class="ab-access__notice" role="status">
          {gettext("This agent is not answering, so access cannot be changed right now.")}
          <span :if={project.allowed != []}>{gettext("The last reading is shown below.")}</span>
        </p>
        <p :if={project.state == :ok and project.reason} class="ab-access__notice" role="status">
          {gettext("Could not read the refused mentions of this agent.")}
        </p>

        <.waiting
          project={project}
          myself={@myself}
          tz_offset={@tz_offset}
          roles={Map.get(@collaborators, project.id)}
        />
        <.cleared
          project={project}
          roles={Map.get(@collaborators, project.id)}
        />
        <.add_person
          project={project}
          myself={@myself}
          candidate={Map.get(@candidates, project.id)}
          error={Map.get(@form_errors, project.id)}
          checking={MapSet.member?(@checking, project.id)}
        />
      </section>
    </div>
    """
  end

  attr :project, :map, required: true
  attr :myself, :any, required: true
  attr :tz_offset, :integer, default: 0
  attr :roles, :any, default: nil

  defp waiting(assigns) do
    ~H"""
    <div class="ab-access__block">
      <h5>{gettext("Waiting for access")}</h5>
      <p :if={@project.state == :ok and @project.requests == []} class="ab-meta">
        {gettext("Nobody mentioned the bot without being allowed.")}
      </p>
      <ul :if={@project.requests != []} class="ab-access__list">
        <li :for={request <- @project.requests} class="ab-access__row">
          <div class="ab-access__who">
            <a href={profile(request.login)} target="_blank" rel="noopener" class="ab-access__login">
              @{request.login}
            </a>
            <span class="ab-meta">
              {ngettext("%{count} mention", "%{count} mentions", request.mentions)} · {when_at(
                request.last_at,
                @tz_offset
              )} · {role_text(@roles, request.login)}
            </span>
            <ul :if={request.issues != []} class="ab-access__issues">
              <li :for={issue <- request.issues}>
                <a href={issue.url} target="_blank" rel="noopener">#{issue.number}</a>
                <span :if={issue.title} class="ab-access__title">{issue.title}</span>
                <span :if={not issue.runnable} class="ab-meta">· {gettext("already handled")}</span>
              </li>
            </ul>
          </div>
          <div :if={@project.state == :ok} class="ab-access__actions">
            <.live_component
              :if={request.rerun != []}
              module={AgentAction}
              id={"access-grant-run-#{@project.id}-#{request.key}"}
              mode={:grant_agent_access}
              tone={:primary}
              superagent={@project.superagent}
              login={request.login}
              rerun={request.rerun}
              label={rerun_label(request.rerun)}
              confirm_label={gettext("Allow and run")}
              busy_label={gettext("Allowing…")}
            />
            <.live_component
              module={AgentAction}
              id={"access-grant-#{@project.id}-#{request.key}"}
              mode={:grant_agent_access}
              tone={if request.rerun == [], do: :primary, else: :quiet}
              superagent={@project.superagent}
              login={request.login}
              rerun={[]}
              label={gettext("Allow")}
              confirm_label={gettext("Allow")}
              busy_label={gettext("Allowing…")}
            />
            <button
              type="button"
              class="ab-btn ab-btn--sm ab-btn--quiet"
              phx-click="dismiss_request"
              phx-value-project={@project.id}
              phx-value-login={request.login}
              phx-target={@myself}
              aria-label={gettext("Set aside the request from %{login}", login: request.login)}
            >
              {gettext("Set aside")}
            </button>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  attr :project, :map, required: true
  attr :roles, :any, default: nil

  defp cleared(assigns) do
    ~H"""
    <div class="ab-access__block">
      <h5>{gettext("Allowed")}</h5>
      <p :if={@project.state == :ok and @project.allowed == []} class="ab-meta">
        {gettext("Nobody is allowed, so this agent takes no work.")}
      </p>
      <ul :if={@project.allowed != []} class="ab-access__list">
        <li :for={person <- @project.allowed} class="ab-access__row">
          <div class="ab-access__who">
            <a href={profile(person.login)} target="_blank" rel="noopener" class="ab-access__login">
              @{person.login}
            </a>
            <span class="ab-meta">
              <span :if={person.name}>{person.name} ·</span>
              {if AgentAccess.owner?(@project.superagent, person.login),
                do: gettext("repository owner"),
                else: role_text(@roles, person.login)}
            </span>
          </div>
          <div
            :if={@project.state == :ok and not AgentAccess.owner?(@project.superagent, person.login)}
            class="ab-access__actions"
          >
            <.live_component
              module={AgentAction}
              id={"access-revoke-#{@project.id}-#{String.downcase(person.login)}"}
              mode={:revoke_agent_access}
              tone={:quiet}
              superagent={@project.superagent}
              login={person.login}
              label={gettext("Revoke")}
              confirm_label={gettext("Revoke")}
              busy_label={gettext("Revoking…")}
            />
          </div>
        </li>
      </ul>
    </div>
    """
  end

  attr :project, :map, required: true
  attr :myself, :any, required: true
  attr :candidate, :map, default: nil
  attr :error, :string, default: nil
  attr :checking, :boolean, default: false

  defp add_person(assigns) do
    ~H"""
    <div :if={@project.state == :ok} class="ab-access__block">
      <h5>{gettext("Add a person")}</h5>
      <form
        id={"access-add-#{@project.id}"}
        class="ab-access__form"
        phx-submit="check_person"
        phx-target={@myself}
      >
        <input type="hidden" name="project" value={@project.id} />
        <label>
          <span>{gettext("GitHub login")}</span>
          <input
            name="login"
            required
            autocomplete="off"
            spellcheck="false"
            autocapitalize="off"
            aria-describedby={@error && "access-add-#{@project.id}-error"}
            aria-invalid={@error && "true"}
          />
        </label>
        <button type="submit" class="ab-btn ab-btn--sm" disabled={@checking}>
          {if @checking, do: gettext("Checking…"), else: gettext("Check")}
        </button>
      </form>
      <p :if={@error} id={"access-add-#{@project.id}-error"} class="ab-access__error" role="alert">
        {@error}
      </p>

      <div :if={@candidate} class="ab-access__candidate" id={"access-candidate-#{@project.id}"}>
        <ul class="ab-access__checklist">
          <li class={check_class(@candidate.exists == true)}>
            <.ico name={check_icon(@candidate.exists == true)} />{exists_text(@candidate)}
          </li>
          <li :if={@candidate.exists != false} class={check_class(collaborator?(@candidate))}>
            <.ico name={check_icon(collaborator?(@candidate))} />{collaborator_text(@candidate)}
          </li>
        </ul>
        <div class="ab-access__actions">
          <.live_component
            :if={@candidate.exists != false}
            module={AgentAction}
            id={"access-grant-new-#{@project.id}-#{String.downcase(@candidate.login)}"}
            mode={:grant_agent_access}
            tone={:primary}
            superagent={@project.superagent}
            login={@candidate.login}
            rerun={[]}
            label={gettext("Allow @%{login}", login: @candidate.login)}
            confirm_label={gettext("Allow")}
            busy_label={gettext("Allowing…")}
          />
          <button
            type="button"
            class="ab-btn ab-btn--sm ab-btn--quiet"
            phx-click="clear_candidate"
            phx-value-project={@project.id}
            phx-target={@myself}
          >
            {gettext("Cancel")}
          </button>
        </div>
      </div>

      <details class="ab-access__guide">
        <summary>{gettext("What to tell a new person")}</summary>
        <p class="ab-meta">
          {gettext(
            "Being allowed here is not enough: the person also needs access to the repository."
          )}
        </p>
        <p class="ab-access__howto">{how_to_ask(@project.repository)}</p>
      </details>
    </div>
    """
  end

  defp profile(login), do: "https://github.com/#{login}"

  defp when_at(at, offset) do
    "#{AgentBoardWeb.Time.local_time(at, offset)} · " <>
      AgentBoardWeb.Time.ago(AgentBoardWeb.Time.age_seconds(at, DateTime.utc_now()))
  end

  defp rerun_label([%{number: number}]), do: gettext("Allow and run #%{number}", number: number)

  defp rerun_label(rerun),
    do: gettext("Allow and run %{count} issues", count: length(rerun))

  defp role_text(nil, _login), do: gettext("checking GitHub")
  defp role_text(:unknown, _login), do: gettext("GitHub not checked")

  defp role_text(roles, login) do
    case roles[String.downcase(login)] do
      nil -> gettext("no access to the repository")
      role -> gettext("%{role} access", role: role)
    end
  end

  defp exists_text(%{exists: true, login: login}),
    do: gettext("@%{login} exists on GitHub", login: login)

  defp exists_text(%{exists: false, login: login}),
    do: gettext("GitHub has no account named @%{login}", login: login)

  defp exists_text(%{login: login}),
    do: gettext("Could not check @%{login} on GitHub", login: login)

  defp collaborator?(%{role: role}), do: role not in [nil, "none"]

  defp collaborator_text(%{exists: :unknown}), do: gettext("Repository access not checked")

  defp collaborator_text(%{role: role}) when role in [nil, "none"],
    do: gettext("No access to the repository: add them on GitHub first")

  defp collaborator_text(%{role: role}),
    do: gettext("Repository access: %{role}", role: role)

  defp check_class(true), do: "is-ok"
  defp check_class(false), do: "is-missing"

  defp check_icon(true), do: "check"
  defp check_icon(false), do: "close"

  defp how_to_ask(repository) do
    gettext(
      "To ask the agent for work, open an issue in %{repository} and write @%{bot} in its body.",
      repository: repository,
      bot: AgentAccess.bot_login()
    )
  end
end
