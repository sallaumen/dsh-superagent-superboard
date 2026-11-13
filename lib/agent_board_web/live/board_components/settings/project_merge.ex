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
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h4 id={@id <> "-title"}>{gettext("Merge requirements")}</h4>
        <button
          class="ab-btn ab-btn--sm"
          type="button"
          phx-click="refresh"
          phx-target={@myself}
          disabled={is_nil(@policy) || is_nil(@enforcement)}
        >{gettext("Refresh")}</button>
      </div>
      <div aria-live="polite" class="grid gap-2">
        <p><strong>{gettext("DeepSeek merge guard")}</strong> · {guard_label(@enforcement)}</p>
        <p :if={@policy && @policy[:branch]} class="ab-meta break-all">
          {gettext("Default branch")} ·
          <code>{@policy.branch}@{String.slice(@policy.sha, 0, 8)}</code>
        </p>
        <%= case @policy do %>
          <% %{result: {:ok, policy}} -> %>
            <p>
              {if policy["review"],
                do: gettext("Independent approval required by policy"),
                else: gettext("No independent approval required by policy")}
            </p>
            <div class="grid gap-3 sm:grid-cols-2">
              <div :for={
                {label, names} <- [
                  {gettext("Local checks"), policy["local"]},
                  {gettext("GitHub checks"), policy["github"]}
                ]
              }>
                <h5>{label}</h5>
                <p :if={names == []} class="ab-meta">{gettext("None configured")}</p>
                <ul>
                  <li :for={name <- names} class="[overflow-wrap:anywhere]">{name}</li>
                </ul>
              </div>
            </div>
            <a class="ab-link" href={@policy.url} target="_blank" rel="noopener noreferrer">{gettext(
              "View merge policy on GitHub"
            )}</a>
          <% %{result: :missing} -> %>
            <p>{gettext("No merge policy on this branch.")}</p>
          <% %{result: :invalid} -> %>
            <p>
              {gettext("The merge guard rejects this policy.")}
              <a class="ab-link" href={@policy.url} target="_blank" rel="noopener noreferrer">{gettext(
                "View merge policy on GitHub"
              )}</a>
            </p>
          <% %{result: :unavailable} -> %>
            <p>{gettext("Could not read the repository policy.")}</p>
            <a
              :if={@last_policy}
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
