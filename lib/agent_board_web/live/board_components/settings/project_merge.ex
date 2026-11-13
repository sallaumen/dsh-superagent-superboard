defmodule AgentBoardWeb.BoardComponents.Settings.ProjectMerge do
  @moduledoc "The default branch's merge requirements and the selected worker's configuration."
  use AgentBoardWeb, :live_component
  alias AgentBoard.ProjectMergePolicy

  @impl true
  def mount(socket), do: {:ok, assign(socket, policy: nil, last_policy: nil, enforcement: nil)}

  @impl true
  def update(assigns, socket) do
    load? = assigns.visible and !socket.assigns[:visible]
    socket = assign(socket, assigns)
    {:ok, if(load?, do: load(socket), else: socket)}
  end

  defp load(socket) do
    repo = socket.assigns.repo

    socket
    |> assign(:policy, nil)
    |> start_async(:policy, fn -> ProjectMergePolicy.load(repo) end)
  end

  @impl true
  def handle_event("refresh", _, socket) do
    if id = socket.assigns.agent_id,
      do: send_update(socket.assigns.guard_owner, refresh_guard: id)

    {:noreply, load(socket)}
  end

  @impl true
  def handle_async(:policy, {:ok, %{result: {:ok, _}} = value}, socket),
    do: {:noreply, assign(socket, policy: value, last_policy: value)}

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
            <p>{gettext("No merge policy configured for this project.")}</p>
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
end
