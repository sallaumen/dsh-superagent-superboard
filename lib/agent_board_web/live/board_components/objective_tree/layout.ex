defmodule AgentBoardWeb.BoardComponents.ObjectiveTree.Layout do
  @moduledoc "Positions the tasks and dependency lines in the objective tree."

  @node_width 196
  @node_height 104
  @column_gap 44
  @row_gap 12

  @doc "Places the tasks and their lines. `edges` are `{task_id, blocked_by_id}`."
  @spec build([map()], [{term(), term()}]) :: map()
  def build(tasks, edges) do
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
end
