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

  @node_width 196
  @node_height 104
  @column_gap 44
  @row_gap 12

  attr :objective, :map, required: true
  attr :repo, :map, required: true

  def objective_tree(assigns) do
    assigns = assign(assigns, :layout, layout(assigns.objective.tasks, assigns.objective.edges))

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

  @doc "Places the tasks and their lines. `edges` are `{task_id, blocked_by_id}`."
  @spec layout([map()], [{term(), term()}]) :: map()
  def layout(tasks, edges) do
    by_id = Map.new(tasks, &{&1.id, &1})
    edges = Enum.filter(edges, fn {task, blocker} -> by_id[task] && by_id[blocker] end)
    blockers = Enum.group_by(edges, &elem(&1, 0), &elem(&1, 1))
    columns = Map.new(tasks, &{&1.id, column(&1.id, blockers, MapSet.new())})

    nodes =
      tasks
      |> Enum.group_by(&columns[&1.id])
      |> Enum.flat_map(&place_column(&1, blockers, by_id))
      |> Enum.sort_by(&{&1.column, &1.y})

    positions = Map.new(nodes, &{&1.id, &1})

    %{
      nodes: nodes,
      edges: Enum.map(edges, fn {task, blocker} -> line(positions[blocker], positions[task]) end),
      width: extent(nodes, :x, @node_width),
      height: extent(nodes, :y, @node_height)
    }
  end

  defp column(id, blockers, seen) do
    case Enum.reject(Map.get(blockers, id, []), &MapSet.member?(seen, &1)) do
      [] ->
        0

      waiting ->
        1 + (waiting |> Enum.map(&column(&1, blockers, MapSet.put(seen, id))) |> Enum.max())
    end
  end

  defp place_column({column, tasks}, blockers, by_id) do
    tasks
    |> Enum.sort_by(& &1.number)
    |> Enum.with_index()
    |> Enum.map(fn {task, row} ->
      waiting = blockers |> Map.get(task.id, []) |> Enum.map(&by_id[&1])

      Map.merge(task, %{
        column: column,
        x: column * (@node_width + @column_gap),
        y: row * (@node_height + @row_gap),
        waiting: Enum.sort_by(waiting, & &1.number)
      })
    end)
  end

  defp line(from, to) do
    {x1, y1} = {from.x + @node_width, from.y + div(@node_height, 2)}
    {x2, y2} = {to.x, to.y + div(@node_height, 2)}
    bend = div(@column_gap, 2)

    %{path: "M#{x1} #{y1} C#{x1 + bend} #{y1}, #{x2 - bend} #{y2}, #{x2} #{y2}"}
  end

  defp extent([], _axis, _size), do: 0

  defp extent(nodes, axis, size),
    do: (nodes |> Enum.map(&Map.fetch!(&1, axis)) |> Enum.max()) + size

  defp held(layout), do: Enum.filter(layout.nodes, &Map.get(&1, :held, false))

  defp phrase(node, repo),
    do:
      Actions.phrase(
        :release_task,
        %{task: node, repository: repo},
        AgentBoardWeb.Locale.language()
      )

  defp why(%{held: true, released_at: %DateTime{}}), do: gettext("Could not call the agent")

  defp why(%{waiting: []}), do: gettext("No dependency")

  defp why(%{state: state}) when state in ~w(done closed), do: gettext("Finished")

  defp why(%{waiting: waiting} = node) do
    case Enum.reject(waiting, &finished?/1) do
      [] -> finished_label(node)
      open -> open_label(node, links(open))
    end
  end

  defp finished_label(%{held: true}), do: gettext("Starting soon")
  defp finished_label(%{state: "queued"}), do: gettext("Ready to start")
  defp finished_label(_node), do: gettext("Dependencies finished")

  defp open_label(%{held: true}, tasks), do: gettext("Waits for %{tasks}", tasks: tasks)

  defp open_label(_node, tasks),
    do: gettext("Depends on %{tasks}, still open", tasks: tasks)

  defp finished?(%{state: state}), do: state in ~w(done closed)

  defp links(tasks), do: Enum.map_join(tasks, ", ", &"##{&1.number}")

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
