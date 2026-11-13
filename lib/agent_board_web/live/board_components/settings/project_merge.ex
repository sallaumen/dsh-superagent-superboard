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
         stage_notice: nil
       )}

  @impl true
  def update(assigns, socket) do
    load? = assigns.visible and !socket.assigns[:visible]
    socket = assign(socket, assigns)
    {:ok, if(load?, do: load(socket), else: socket)}
  end

  defp load(socket) do
    repo = socket.assigns.repo

    socket
    |> assign(policy: nil, stage_ids: nil, stage_notice: nil)
    |> start_async(:stage_ids, fn -> ProjectStages.load(repo) end)
    |> start_async(:policy, fn -> ProjectMergePolicy.load(repo) end)
  end

  @impl true
  def handle_event("refresh", _, socket) do
    if id = socket.assigns.agent_id,
      do: send_update(socket.assigns.guard_owner, refresh_guard: id)

    {:noreply, load(socket)}
  end

  def handle_event("save_stages", params, socket) do
    %{stage_ids: current, repo: repo, visible: visible} = socket.assigns
    ids = params["stages"] || []

    with true <- visible and is_list(current) and is_list(ids),
         :ok <-
           Actions.run(
             :set_project_stages,
             %{repository: repo, ids: ids, expected: current},
             Actions.owner(:ui)
           ) do
      {:noreply, assign(socket, stage_ids: ids, stage_notice: :saved)}
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
      _ -> gettext("Tests")
    end
  end

  @impl true
  def handle_async(:policy, {:ok, %{result: {:ok, _}} = value}, socket),
    do: {:noreply, assign(socket, policy: value, last_policy: value)}

  def handle_async(:stage_ids, {:ok, {:ok, ids}}, socket),
    do: {:noreply, assign(socket, stage_ids: ids)}

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
      <details
        class="ab-merge-checklist"
        id={@id <> "-stages"}
        phx-mounted={JS.ignore_attributes("open")}
      >
        <summary>
          <strong>{gettext("Local task checks")}</strong>
          <span :if={is_list(@stage_ids)}>{ngettext(
            "1 selected",
            "%{count} selected",
            length(@stage_ids)
          )}</span>
        </summary>
        <p>
          {gettext(
            "Choose checks for this project. They run in the task folder and do not require GitHub Actions."
          )}
        </p>
        <form
          :if={is_list(@stage_ids)}
          id={@id <> "-stage-form"}
          phx-submit="save_stages"
          phx-target={@myself}
        >
          <div class="ab-merge-lists">
            <fieldset :for={{tool, choices} <- stage_groups()}>
              <legend>{tool}</legend>
              <label :for={{id, command} <- choices} class="ab-stage-choice">
                <input type="checkbox" name="stages[]" value={id} checked={id in @stage_ids} />
                <span>{stage_label(id)} <code class="ab-meta">{Enum.join(command, " ")}</code></span>
              </label>
            </fieldset>
          </div>
          <button class="ab-btn ab-btn--sm" type="submit">{gettext("Save checks")}</button>
        </form>
        <p :if={@stage_ids == :unavailable}>
          {gettext("Could not read the local checks. Refresh to try again.")}
        </p>
        <p :if={is_nil(@stage_ids)}>{gettext("Loading…")}</p>
        <p aria-live="polite">
          <span :if={@stage_notice == :saved}>{gettext("Local checks saved for this project.")}</span>
          <span :if={@stage_notice == :error}>{gettext(
            "Checks were not saved. Refresh to load the current selection."
          )}</span>
        </p>
      </details>
      <div class="ab-merge-body" aria-live="polite">
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

  defp stage_groups do
    groups = %{
      "mix" => "Elixir",
      "npm" => "Node.js",
      "cargo" => "Rust",
      "python3" => "Python",
      "composer" => "PHP"
    }

    ProjectStages.choices()
    |> Enum.group_by(fn {_, [cmd | _]} -> Map.fetch!(groups, cmd) end)
    |> Enum.sort()
  end
end
