defmodule AgentBoardWeb.BoardComponents.Settings.ProjectAccess do
  @moduledoc """
  The access block of one expanded project: who asked and was refused, who is
  cleared, and how to add someone.

  The project list and the refusals come from the board's own read
  (`AgentBoard.AgentAccess.overview/0`, loaded by `BoardLive`); this component
  only reads the GitHub collaborators for the person's role, at most once per
  ten minutes, and only while the row is open. Every change goes through
  `AgentBoard.Actions`.
  """
  use AgentBoardWeb, :live_component

  alias AgentBoardWeb.BoardNotice

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1]

  alias AgentBoard.{Actions, AgentAccess}
  alias AgentBoardWeb.BoardComponents.AgentAction

  @collaborators_ttl_ms :timer.minutes(10)

  attr :project, :any, default: nil
  attr :superagent, :any, required: true
  attr :visible, :boolean, default: false
  attr :tz_offset, :integer, default: 0

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       collaborators: nil,
       collaborators_at: nil,
       loaded_for: nil,
       candidates: %{},
       form_errors: %{},
       checking: false
     )}
  end

  @impl true
  def update(assigns, socket) do
    previous_id = socket.assigns[:loaded_for]
    socket = assign(socket, assigns)
    current_id = socket.assigns.superagent.id
    changed_project? = previous_id != current_id

    socket =
      if changed_project? do
        assign(socket,
          collaborators: nil,
          collaborators_at: nil,
          loaded_for: current_id,
          candidates: %{},
          form_errors: %{},
          checking: false
        )
      else
        socket
      end

    if socket.assigns.visible and
         (changed_project? or not fresh?(socket.assigns.collaborators_at)) do
      {:ok, load_collaborators(socket)}
    else
      {:ok, socket}
    end
  end

  defp fresh?(nil), do: false
  defp fresh?(at), do: System.monotonic_time(:millisecond) - at < @collaborators_ttl_ms

  defp load_collaborators(socket) do
    superagent = socket.assigns.superagent

    socket
    |> assign(collaborators_at: System.monotonic_time(:millisecond))
    |> start_async(:collaborators, fn ->
      case AgentAccess.collaborators(superagent) do
        {:ok, roles} -> roles
        {:error, _reason} -> :unknown
      end
    end)
  end

  @impl true
  def handle_async(:collaborators, {:ok, roles}, socket),
    do: {:noreply, assign(socket, :collaborators, roles)}

  def handle_async(:collaborators, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, collaborators_at: nil)}

  def handle_async({:candidate, id}, {:ok, candidate}, socket) do
    {:noreply,
     socket
     |> assign(:checking, false)
     |> update(:candidates, &Map.put(&1, id, candidate))}
  end

  def handle_async({:candidate, id}, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:checking, false)
     |> update(
       :form_errors,
       &Map.put(&1, id, gettext("Could not check this account. Try again."))
     )}
  end

  @impl true
  def handle_event("check_person", %{"login" => login}, socket) do
    case {socket.assigns.project, AgentAccess.normalize_login(login)} do
      {nil, _login} ->
        {:noreply, socket}

      {_project, {:error, :invalid_login}} ->
        {:noreply,
         socket
         |> update(:candidates, &Map.delete(&1, socket.assigns.superagent.id))
         |> update(
           :form_errors,
           &Map.put(&1, socket.assigns.superagent.id, gettext("That is not a GitHub login."))
         )}

      {project, {:ok, login}} ->
        {:noreply, check_person(socket, project, login)}
    end
  end

  def handle_event("clear_candidate", _params, socket) do
    {:noreply, update(socket, :candidates, &Map.delete(&1, socket.assigns.superagent.id))}
  end

  def handle_event("dismiss_request", %{"login" => login}, socket) do
    with %{} = project <- socket.assigns.project,
         %{} = request <- Enum.find(project.requests, &(&1.login == login)),
         {:ok, _text} <- dismiss(socket.assigns.superagent, request) do
      {:noreply, socket}
    else
      {:error, text} when is_binary(text) -> {:noreply, BoardNotice.notify(socket, :error, text)}
      _gone -> {:noreply, socket}
    end
  end

  defp dismiss(superagent, request) do
    Actions.run(
      :dismiss_access_request,
      %{superagent: superagent, login: request.login},
      Actions.owner(:ui),
      language: AgentBoardWeb.Locale.language()
    )
  end

  defp check_person(socket, project, login) do
    if listed?(project, login) do
      socket
      |> update(:candidates, &Map.delete(&1, socket.assigns.superagent.id))
      |> update(
        :form_errors,
        &Map.put(
          &1,
          socket.assigns.superagent.id,
          gettext("@%{login} is already allowed.", login: login)
        )
      )
    else
      superagent = socket.assigns.superagent

      socket
      |> update(:form_errors, &Map.delete(&1, socket.assigns.superagent.id))
      |> update(:candidates, &Map.delete(&1, socket.assigns.superagent.id))
      |> assign(:checking, true)
      |> start_async({:candidate, superagent.id}, fn ->
        AgentAccess.candidate(superagent, login)
      end)
    end
  end

  defp listed?(project, login) do
    Enum.any?(project.allowed, &(String.downcase(&1.login) == String.downcase(login)))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="ab-project-access">
      <%= if @visible do %>
        <p :if={is_nil(@project)} class="ab-meta" role="status">{gettext("Reading access…")}</p>

        <%= if @project do %>
          <p :if={@project.state != :ok} class="ab-project-access__notice" role="status">
            {gettext("This agent is not answering, so access cannot be changed right now.")}
            <span :if={@project.allowed != []}>{gettext("The last reading is shown below.")}</span>
          </p>
          <p
            :if={@project.state == :ok and @project.reason}
            class="ab-project-access__notice"
            role="status"
          >
            {gettext("Could not read the refused mentions of this agent.")}
          </p>

          <div class="ab-project-access__grid">
            <.waiting
              project={@project}
              superagent={@superagent}
              myself={@myself}
              tz_offset={@tz_offset}
              roles={@collaborators}
            />
            <div class="ab-project-access__right">
              <.cleared project={@project} roles={@collaborators} />
              <.add_person
                project={@project}
                myself={@myself}
                candidate={Map.get(@candidates, @superagent.id)}
                error={Map.get(@form_errors, @superagent.id)}
                checking={@checking}
              />
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :project, :map, required: true
  attr :superagent, :any, required: true
  attr :myself, :any, required: true
  attr :tz_offset, :integer, default: 0
  attr :roles, :any, default: nil

  defp waiting(assigns) do
    assigns = assign(assigns, :count, length(assigns.project.requests))

    ~H"""
    <section class="ab-project-access__waiting" aria-labelledby={"waiting-#{@superagent.id}"}>
      <h5 id={"waiting-#{@superagent.id}"}>
        {gettext("Waiting for access")}
        <span :if={@count > 0} class="ab-project-access__count">· {@count}</span>
      </h5>
      <p :if={@project.state == :ok and @project.requests == []} class="ab-meta">
        {gettext("Nobody mentioned the bot without being allowed.")}
      </p>
      <article
        :for={request <- @project.requests}
        class="ab-project-access__request"
        id={"access-request-#{@superagent.id}-#{request.key}"}
      >
        <p class="ab-project-access__request-line">
          <a
            href={profile(request.login)}
            target="_blank"
            rel="noopener noreferrer"
            class="ab-project-access__login"
          >
            @{request.login}<span class="ab-sr">{gettext("(opens GitHub in a new tab)")}</span>
          </a>
          {gettext("called the agent in")}
          <span
            :for={{issue, index} <- Enum.with_index(request.issues)}
            class="ab-project-access__issue"
          >
            <a href={issue.url} target="_blank" rel="noopener noreferrer">#{issue.number}<span class="ab-sr">{gettext(
              "(opens GitHub in a new tab)"
            )}</span></a><span :if={index < length(request.issues) - 1}>{gettext("and")}</span>
          </span>
          <span :if={request.issues == []}>{gettext("an issue")}</span>
          {gettext("without access.")}
        </p>
        <ul :if={Enum.any?(request.issues, & &1.title)} class="ab-project-access__issues">
          <li :for={issue <- request.issues} :if={issue.title}>
            <a href={issue.url} target="_blank" rel="noopener noreferrer">#{issue.number}<span class="ab-sr">{gettext(
              "(opens GitHub in a new tab)"
            )}</span></a>
            <span class="ab-project-access__issue-title">{issue.title}</span>
            <span :if={not issue.runnable} class="ab-meta">· {gettext("already handled")}</span>
          </li>
        </ul>
        <p class="ab-meta">
          {ngettext("%{count} mention", "%{count} mentions", request.mentions)} · {when_at(
            request.last_at,
            @tz_offset
          )} · {role_text(@roles, request.login)}
        </p>

        <p
          :if={repo_access(@roles, request.login) == :no}
          class="ab-project-access__warning"
        >
          {gettext("No access to the repository on GitHub. Add the person there first.")}
        </p>

        <div :if={@project.state == :ok} class="ab-project-access__actions">
          <.live_component
            :if={request.rerun != []}
            module={AgentAction}
            id={"access-grant-run-#{@superagent.id}-#{request.key}"}
            mode={:grant_agent_access}
            tone={:primary}
            superagent={@superagent}
            login={request.login}
            rerun={request.rerun}
            label={rerun_label(request.rerun)}
            confirm_label={gettext("Allow and run")}
            busy_label={gettext("Allowing…")}
          />
          <.live_component
            :if={request.rerun != []}
            module={AgentAction}
            id={"access-grant-#{@superagent.id}-#{request.key}"}
            mode={:grant_agent_access}
            tone={:quiet}
            superagent={@superagent}
            login={request.login}
            rerun={[]}
            label={gettext("Allow")}
            confirm_label={gettext("Allow")}
            busy_label={gettext("Allowing…")}
          />
          <.live_component
            :if={request.rerun == []}
            module={AgentAction}
            id={"access-grant-#{@superagent.id}-#{request.key}"}
            mode={:grant_agent_access}
            tone={:primary}
            superagent={@superagent}
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
            phx-value-login={request.login}
            phx-target={@myself}
            aria-label={gettext("Set aside the request from %{login}", login: request.login)}
          >
            {gettext("Set aside")}
          </button>
        </div>
      </article>
    </section>
    """
  end

  attr :project, :map, required: true
  attr :roles, :any, default: nil

  defp cleared(assigns) do
    ~H"""
    <section class="ab-project-access__cleared" aria-labelledby={"cleared-#{@project.id}"}>
      <h5 id={"cleared-#{@project.id}"}>
        {gettext("Who can call the agent")}
        <span :if={@project.allowed != []} class="ab-project-access__count">· {length(
          @project.allowed
        )}</span>
      </h5>
      <p :if={@project.state == :ok and @project.allowed == []} class="ab-meta">
        {gettext("Nobody is allowed, so this agent takes no work.")}
      </p>
      <ul :if={@project.allowed != []} class="ab-project-access__list">
        <li :for={person <- @project.allowed} class="ab-project-access__person">
          <div class="ab-project-access__who">
            <a
              href={profile(person.login)}
              target="_blank"
              rel="noopener noreferrer"
              class="ab-project-access__login"
            >
              @{person.login}<span class="ab-sr">{gettext("(opens GitHub in a new tab)")}</span>
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
            class="ab-project-access__person-actions"
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
    </section>
    """
  end

  attr :project, :map, required: true
  attr :myself, :any, required: true
  attr :candidate, :map, default: nil
  attr :error, :string, default: nil
  attr :checking, :boolean, default: false

  defp add_person(assigns) do
    ~H"""
    <section
      :if={@project.state == :ok}
      class="ab-project-access__add"
      aria-labelledby={"add-person-#{@project.id}"}
    >
      <h5 id={"add-person-#{@project.id}"}>{gettext("Add a person")}</h5>
      <form
        id={"access-add-#{@project.id}"}
        class="ab-project-access__form"
        phx-submit="check_person"
        phx-target={@myself}
      >
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
      <p
        :if={@error}
        id={"access-add-#{@project.id}-error"}
        class="ab-project-access__error"
        role="alert"
      >
        {@error}
      </p>

      <div
        :if={@candidate}
        class="ab-project-access__candidate"
        id={"access-candidate-#{@project.id}"}
      >
        <ul class="ab-project-access__checklist">
          <li class={check_class(@candidate.exists == true)}>
            <.ico name={check_icon(@candidate.exists == true)} />{exists_text(@candidate)}
          </li>
          <li :if={@candidate.exists != false} class={check_class(collaborator?(@candidate))}>
            <.ico name={check_icon(collaborator?(@candidate))} />{collaborator_text(@candidate)}
          </li>
        </ul>
        <div class="ab-project-access__actions">
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
            phx-target={@myself}
          >
            {gettext("Cancel")}
          </button>
        </div>
      </div>

      <details class="ab-project-access__guide">
        <summary>{gettext("What to tell a new person")}</summary>
        <p class="ab-meta">
          {gettext(
            "Being allowed here is not enough: the person also needs access to the repository."
          )}
        </p>
        <p class="ab-project-access__howto">{how_to_ask(@project.repository)}</p>
      </details>
    </section>
    """
  end

  defp profile(login), do: "https://github.com/#{login}"

  defp when_at(at, offset) do
    "#{AgentBoardWeb.Time.local_time(at, offset)} · " <>
      AgentBoardWeb.Time.ago(AgentBoardWeb.Time.age_seconds(at, DateTime.utc_now()))
  end

  defp rerun_label([%{number: number}]),
    do: gettext("Allow and run #%{number}", number: number)

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

  defp repo_access(nil, _login), do: :checking
  defp repo_access(:unknown, _login), do: :unknown

  defp repo_access(roles, login) when is_map(roles) do
    case roles[String.downcase(login)] do
      nil -> :no
      "none" -> :no
      _role -> :yes
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
