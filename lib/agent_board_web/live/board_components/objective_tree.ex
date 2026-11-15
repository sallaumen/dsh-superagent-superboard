defmodule AgentBoardWeb.BoardComponents.ObjectiveTree do
  @moduledoc """
  How the tasks of an objective connect: each task one column after the deepest
  task it waits for, joined by lines.

  The text of each task says the same as the lines, so a phone (which stacks
  the tasks and hides the lines) and a screen reader lose nothing. It reports
  what is true: only a held task really waits; others may already be running.
  """
  use AgentBoardWeb, :html

  alias AgentBoard.Actions
  alias AgentBoardWeb.BoardComponents.ObjectiveTree.{DependencyStatus, Layout}

  attr :objective, :map, required: true
  attr :repo, :map, required: true

  def objective_tree(assigns) do
    assigns =
      assign(assigns, :layout, Layout.build(assigns.objective.tasks, assigns.objective.edges))

    ~H"""
    <details
      id={"objective-tree-#{@objective.id}"}
      class="ab-objective__tree"
      phx-mounted={JS.ignore_attributes(["open"])}
    >
      <summary>{gettext("See how the tasks connect")}</summary>
      <div
        class="ab-tree"
        tabindex="0"
        role="group"
        aria-label={gettext("Tasks of %{title}", title: @objective.title)}
      >
        <div
          class="ab-tree__canvas"
          style={"--tree-width: #{@layout.width}px; --tree-height: #{@layout.height}px"}
        >
          <svg
            class="ab-tree__lines"
            width={@layout.width}
            height={@layout.height}
            viewBox={"0 0 #{@layout.width} #{@layout.height}"}
            aria-hidden="true"
          >
            <path :for={edge <- @layout.edges} d={edge.path} />
          </svg>
          <button
            :for={node <- @layout.nodes}
            id={"objective-tree-node-#{node.id}"}
            type="button"
            class="ab-tree__node"
            data-state={node.state}
            style={"--node-x: #{node.x}px; --node-y: #{node.y}px"}
            phx-click="open"
            phx-value-id={node.id}
          >
            <span class="ab-tree__head">
              <span class="ab-need__id">#{node.number}</span>
              <span class="ab-meta">{state_word(node.state)}</span>
            </span>
            <span class="ab-tree__title">{node.title}</span>
            <span class="ab-meta ab-tree__why">{why(node)}</span>
          </button>
        </div>
      </div>
      <div :if={held(@layout) != []} class="ab-tree__release">
        <button
          :for={node <- held(@layout)}
          type="button"
          class="ab-btn ab-btn--sm"
          phx-click="release_task"
          phx-value-id={node.id}
          phx-value-confirm={phrase(node, @repo)}
          data-confirm={phrase(node, @repo)}
        >
          {gettext("Call the agent on #%{number}", number: node.number)}
        </button>
      </div>
      <a
        :if={@objective.issue_url}
        class="ab-btn ab-btn--sm ab-btn--quiet"
        href={@objective.issue_url}
        target="_blank"
        rel="noopener noreferrer"
      >
        {gettext("Open issue")}<span class="ab-sr">{gettext("(opens GitHub in a new tab)")}</span>
      </a>
    </details>
    """
  end

  defp held(layout), do: Enum.filter(layout.nodes, &Map.get(&1, :held, false))

  defp phrase(node, repo),
    do:
      Actions.phrase(
        :release_task,
        %{task: node, repository: repo},
        AgentBoardWeb.Locale.language()
      )

  defp why(node) do
    case DependencyStatus.classify(node) do
      :call_failed ->
        gettext("Could not call the agent")

      :no_dependency ->
        gettext("No dependency")

      :finished ->
        gettext("Finished")

      :starting_soon ->
        gettext("Starting soon")

      :ready_to_start ->
        gettext("Ready to start")

      :dependencies_finished ->
        gettext("Dependencies finished")

      {:waiting_for, numbers} ->
        gettext("Waits for %{tasks}", tasks: links(numbers))

      {:depends_on_open, numbers} ->
        gettext("Depends on %{tasks}, still open", tasks: links(numbers))
    end
  end

  defp links(numbers), do: Enum.map_join(numbers, ", ", &"##{&1}")

  defp state_word("done"), do: gettext("merged")
  defp state_word("closed"), do: gettext("closed issue")
  defp state_word("queued"), do: gettext("in the queue")
  defp state_word("running"), do: gettext("running")
  defp state_word("retrying"), do: gettext("retrying")
  defp state_word("question"), do: gettext("question")
  defp state_word("ready"), do: gettext("ready for review")
  defp state_word("blocked"), do: gettext("blocked")
  defp state_word("stopped"), do: gettext("stopped")
  defp state_word("archived"), do: gettext("archived")
  defp state_word(other), do: other
end
