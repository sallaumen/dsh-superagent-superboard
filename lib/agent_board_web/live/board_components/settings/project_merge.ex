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
    %{repo: repo, agent: agent} = socket.assigns

    socket
    |> assign(policy: nil, enforcement: nil)
    |> start_async(:policy, fn -> ProjectMergePolicy.load(repo) end)
    |> start_async(:enforcement, fn -> ProjectMergePolicy.enforcement(agent, repo) end)
  end

  @impl true
  def handle_event("refresh", _, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_async(:policy, {:ok, %{result: {:ok, _}} = value}, socket),
    do: {:noreply, assign(socket, policy: value, last_policy: value)}

  def handle_async(key, {:ok, value}, socket), do: {:noreply, assign(socket, key, value)}

  def handle_async(:policy, {:exit, _}, socket),
    do: {:noreply, assign(socket, policy: %{result: :unavailable})}

  def handle_async(:enforcement, {:exit, _}, socket),
    do: {:noreply, assign(socket, enforcement: :unknown)}

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="ab-policy" aria-labelledby={@id <> "-title"}>
      <div class="ab-merge-heading">
        <h4 id={@id <> "-title"}>{gettext("Merge requirements")}</h4>
        <button
          class="ab-btn ab-btn--sm"
          type="button"
          phx-click="refresh"
          phx-target={@myself}
          disabled={is_nil(@policy) || is_nil(@enforcement)}
        >{gettext("Refresh")}</button>
      </div>
      <div class="ab-merge-body" aria-live="polite">
        <dl class="ab-merge-facts">
          <div>
            <dt>{gettext("DeepSeek merge guard")}</dt>
            <dd class={@enforcement == :active && "ab-status--run"}>{guard_label(@enforcement)}</dd>
          </div>
          <div :if={match?(%{result: {:ok, _}}, @policy)}>
            <dt>{gettext("Independent approval")}</dt>
            <dd>
              {if elem(@policy.result, 1)["review"],
                do: gettext("Required"),
                else: gettext("Not required")}
            </dd>
          </div>
          <div :if={@policy && @policy[:branch]}>
            <dt>{gettext("Default branch")}</dt>
            <dd>
              <a
                :if={@policy.url && match?({:ok, _}, @policy.result)}
                class="ab-link"
                href={@policy.url}
                title={gettext("View merge policy on GitHub")}
                target="_blank"
                rel="noopener noreferrer"
              >
                <code>{@policy.branch}@{String.slice(@policy.sha, 0, 8)}</code>
              </a>
              <code :if={!@policy.url || !match?({:ok, _}, @policy.result)}>{@policy.branch}@{String.slice(
                @policy.sha,
                0,
                8
              )}</code>
            </dd>
          </div>
        </dl>
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
                <strong>{gettext("Merge checks")}</strong>
                <span>{gettext("Local checks")}: {length(policy["local"])} · {gettext("GitHub checks")}: {length(
                  policy["github"]
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
      </div>
    </section>
    """
  end

  defp guard_label(:active), do: gettext("Active")
  defp guard_label(:inactive), do: gettext("Inactive")
  defp guard_label(:no_agent), do: gettext("No agent connected")
  defp guard_label(:unknown), do: gettext("Could not verify")
  defp guard_label(nil), do: gettext("Checking…")
end
