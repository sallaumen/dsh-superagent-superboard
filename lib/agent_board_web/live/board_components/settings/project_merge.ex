defmodule AgentBoardWeb.BoardComponents.Settings.ProjectMerge do
  @moduledoc "The default branch's merge requirements and the selected worker's configuration."
  use AgentBoardWeb, :live_component
  alias AgentBoard.{Actions, ProjectMergePolicy, ProjectStages}

  @impl true
  def mount(socket),
    do:
      {:ok,
       assign(socket,
         policy: nil,
         last_policy: nil,
         enforcement: nil,
         stage_ids: nil,
         stage_notice: nil,
         stack: nil,
         profile: nil
       )}

  @impl true
  def update(assigns, socket) do
    load? = assigns.visible and !socket.assigns[:visible]
    socket = assign(socket, assigns)
    {:ok, if(load?, do: load(socket), else: socket)}
  end

  defp load(socket) do
    repo = socket.assigns.repo

    checkout = socket.assigns[:checkout]

    socket
    |> assign(policy: nil, stage_ids: nil, stage_notice: nil)
    |> start_async(:stage_ids, fn -> ProjectStages.profile(repo, checkout) end)
    |> start_async(:policy, fn -> ProjectMergePolicy.load(repo) end)
  end

  @impl true
  def handle_event("refresh", _, socket) do
    if id = socket.assigns.agent_id,
      do: send_update(socket.assigns.guard_owner, refresh_guard: id)

    {:noreply, load(socket)}
  end

  def handle_event("choose_stack", %{"stack" => stack}, socket) do
    if List.keymember?(ProjectStages.groups(), stack, 0),
      do: {:noreply, assign(socket, stack: stack, stage_notice: nil)},
      else: {:noreply, socket}
  end

  def handle_event("save_stages", %{"rules" => rules}, socket) when is_map(rules) do
    %{profile: profile, repo: repo, visible: visible, stack: stack} = socket.assigns
    allowed = List.keyfind(ProjectStages.groups(), stack, 0)

    with true <- visible && is_map(profile) && allowed != nil,
         true <-
           Enum.all?(rules, fn {id, m} ->
             id in elem(allowed, 1) and m in ~w(always changed off)
           end),
         changes = Map.reject(rules, fn {i, m} -> profile["modes"][i] == m end),
         :ok <-
           Actions.run(
             :set_project_stages,
             %{repository: repo, ids: changes, expected: profile["stored"]},
             Actions.owner(:ui)
           ) do
      {:noreply, socket |> load() |> assign(stage_notice: :saved)}
    else
      _ -> {:noreply, assign(socket, stage_notice: :error)}
    end
  end

  defp stage_label(id) do
    case id do
      "mix-format" -> gettext("Format")
      "cargo-format" -> gettext("Format")
      "mix-lint" -> gettext("Lint")
      "npm-lint" -> gettext("Lint")
      "npm-e2e" -> gettext("Browser tests")
      "npm-build" -> gettext("Build")
      "go-vet" -> gettext("Static analysis")
      _ -> gettext("Tests")
    end
  end

  @impl true
  def handle_async(:policy, {:ok, %{result: {:ok, _}} = value}, socket),
    do: {:noreply, assign(socket, policy: value, last_policy: value)}

  def handle_async(:stage_ids, {:ok, {:ok, profile}}, socket) do
    groups = ordered_groups(profile)
    ids = for {id, mode} <- profile["modes"], mode != "off", do: id

    {:noreply,
     assign(socket,
       stage_ids: ids,
       profile: profile,
       stack: socket.assigns.stack || elem(hd(groups), 0)
     )}
  end

  def handle_async(:stage_ids, _, socket),
    do: {:noreply, assign(socket, stage_ids: :unavailable)}

  def handle_async(key, {:ok, value}, socket), do: {:noreply, assign(socket, key, value)}

  def handle_async(:policy, {:exit, _}, socket),
    do: {:noreply, assign(socket, policy: %{result: :unavailable})}

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="ab-policy" aria-labelledby={@id <> "-title"}>
      <div class="ab-merge-heading">
        <h4 id={@id <> "-title"}>{gettext("Project policy")}</h4>
        <button
          class="ab-btn ab-btn--sm"
          type="button"
          phx-click="refresh"
          phx-target={@myself}
          disabled={is_nil(@policy) || is_nil(@enforcement)}
        >{gettext("Refresh")}</button>
      </div>
      <section id={@id <> "-stages"} class="ab-quality">
        <header>
          <h5>{gettext("Quality rules")}</h5>
          <p class="ab-meta">
            {gettext("Tests and checks for this project. Merge requirements below still apply.")}
          </p>
        </header>
        <%= if is_list(@stage_ids) and not is_nil(@profile) do %>
          <p class="ab-quality__source">{profile_label(@profile)}</p>
          <div class="ab-quality__editor">
            <form
              id={@id <> "-language-form"}
              phx-change="choose_stack"
              phx-target={@myself}
              class="ab-quality__stack"
            >
              <label for={@id <> "-language"}>{gettext("Technology")}</label>
              <select class="voice-select" id={@id <> "-language"} name="stack">
                <option
                  :for={{name, ids} <- ordered_groups(@profile)}
                  value={name}
                  selected={name == @stack}
                >
                  {name}{if Enum.any?(ids, &(&1 in @profile["detected"])),
                    do: " · " <> gettext("Detected")}
                </option>
              </select>
            </form>
            <form id={@id <> "-stage-form"} phx-submit="save_stages" phx-target={@myself}>
              <div :for={id <- stack_ids(@stack)} class="ab-quality__rule">
                <label for={@id <> "-" <> id}>
                  <strong>{stage_label(id)}</strong>
                  <code>{command(id)}</code>
                  <small
                    :if={@profile["available"] and id not in @profile["detected"]}
                    class="ab-meta"
                  >{gettext("Not detected in this checkout")}</small>
                </label>
                <select class="voice-select" id={@id <> "-" <> id} name={"rules[#{id}]"}>
                  <option
                    :for={{mode, label} <- modes()}
                    value={mode}
                    selected={@profile["modes"][id] == mode}
                  >
                    {label}
                  </option>
                </select>
              </div>
              <button class="ab-btn ab-btn--sm" type="submit">{gettext("Save checks")}</button>
            </form>
          </div>
        <% else %>
          <p class="ab-meta">
            {if @stage_ids == :unavailable,
              do: gettext("Could not read the local checks. Refresh to try again."),
              else: gettext("Loading…")}
          </p>
        <% end %>
        <p :if={@stage_notice} role="status">
          {if @stage_notice == :saved,
            do: gettext("Local checks saved for this project."),
            else: gettext("Checks were not saved. Refresh to load the current selection.")}
        </p>
      </section>
      <div class="ab-merge-body" aria-live="polite">
        <h5>{gettext("Merge requirements")}</h5>
        <p class="ab-merge-summary">
          <span class={@enforcement == :active && "ab-status--run"}>{guard_label(@enforcement)}</span>
          <%= if match?(%{result: {:ok, _}}, @policy) do %>
            <span aria-hidden="true">·</span>
            <span>{if elem(@policy.result, 1)["review"],
              do: gettext("Independent approval required"),
              else: gettext("Independent approval not required")}</span>
          <% end %>
        </p>
        <p :if={@policy && @policy[:source] == :machine && @policy.result != :missing}>
          {gettext("Merge policy configured on this machine")}
        </p>
        <%= case @policy do %>
          <% %{result: {:ok, policy}} -> %>
            <details
              id={@id <> "-checks"}
              class="ab-merge-checklist"
              phx-mounted={JS.ignore_attributes("open")}
            >
              <summary>
                <strong>{ngettext(
                  "View %{count} required check",
                  "View %{count} required checks",
                  length(policy["local"]) + length(policy["github"])
                )}</strong>
                <span>{gettext("%{local} and %{hosted} on GitHub",
                  local: ngettext("%{count} local", "%{count} local", length(policy["local"])),
                  hosted: length(policy["github"])
                )}</span>
              </summary>
              <div class="ab-merge-lists">
                <div :for={
                  {label, names} <- [
                    {gettext("Local checks"), policy["local"]},
                    {gettext("GitHub checks"), policy["github"]}
                  ]
                }>
                  <h5>{label}</h5>
                  <p :if={names == []} class="ab-meta">{gettext("None configured")}</p>
                  <ul>
                    <li :for={name <- names}>{name}</li>
                  </ul>
                </div>
              </div>
            </details>
          <% %{result: :missing} -> %>
            <p :if={!is_list(@stage_ids) or @stage_ids == []}>
              {gettext("No merge policy configured for this project.")}
            </p>
            <p :if={is_list(@stage_ids) and @stage_ids != []}>
              {gettext("The selected checks and an independent approval are required to merge.")}
            </p>
          <% %{result: :invalid} -> %>
            <p>
              {gettext("The merge guard rejects this policy.")}
              <a
                :if={@policy.url}
                class="ab-link"
                href={@policy.url}
                target="_blank"
                rel="noopener noreferrer"
              >{gettext("View merge policy on GitHub")}</a>
            </p>
          <% %{result: :unavailable} -> %>
            <p>{gettext("Could not read the repository policy.")}</p>
            <a
              :if={@last_policy && @last_policy.url}
              class="ab-link"
              href={@last_policy.url}
              target="_blank"
              rel="noopener noreferrer"
            >
              {gettext("Last verified policy · %{revision}",
                revision: String.slice(@last_policy.sha, 0, 8)
              )}
            </a>
          <% _ -> %>
            <p>{gettext("Reading merge requirements…")}</p>
        <% end %>
        <p :if={@policy && @policy[:branch] && @policy[:source] != :machine} class="ab-merge-revision">
          <a
            :if={@policy.url && match?({:ok, _}, @policy.result)}
            class="ab-link"
            href={@policy.url}
            target="_blank"
            rel="noopener noreferrer"
          >
            {gettext("View policy on %{branch}", branch: @policy.branch)}
          </a>
          <span :if={!@policy.url || !match?({:ok, _}, @policy.result)}>{@policy.branch}</span>
          <code title={@policy.sha}>{String.slice(@policy.sha, 0, 8)}</code>
        </p>
      </div>
    </section>
    """
  end

  def guard_label(:active), do: gettext("Guard active")
  def guard_label(:inactive), do: gettext("Guard inactive")
  def guard_label(:no_agent), do: gettext("Guard not applicable")
  def guard_label(:unknown), do: gettext("Guard unverified")
  def guard_label(nil), do: gettext("Checking guard…")

  defp ordered_groups(p),
    do:
      Enum.sort_by(ProjectStages.groups(), fn {name, ids} ->
        {not Enum.any?(ids, &(&1 in p["detected"])), name}
      end)

  defp stack_ids(stack), do: elem(List.keyfind(ProjectStages.groups(), stack, 0), 1)

  defp modes,
    do: [
      {"always", gettext("Every task")},
      {"changed", gettext("On related changes")},
      {"off", gettext("Off")}
    ]

  defp command(id) do
    {:ok, args} = ProjectStages.command(id)
    Enum.join(args, " ")
  end

  defp profile_label(%{"available" => false}),
    do:
      gettext(
        "Waiting for a local checkout. Defaults will apply when the worker detects the stack."
      )

  defp profile_label(%{"detected" => []}),
    do: gettext("No supported toolchain detected. You can choose rules manually.")

  defp profile_label(%{"stored" => nil}),
    do: gettext("Recommended rules are active automatically for the detected stack.")

  defp profile_label(_), do: gettext("Project preferences are active for this checkout.")
end
