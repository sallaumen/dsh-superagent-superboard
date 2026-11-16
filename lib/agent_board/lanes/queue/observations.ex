defmodule AgentBoard.Lanes.Queue.Observations do
  @moduledoc "The persisted facts used to display one repository's queue."

  import Ecto.Query

  alias AgentBoard.Board.{PullRequest, Task, TaskDependency}
  alias AgentBoard.Repo

  @doc "Read the ordered queue, merged titles, and linked task numbers."
  @spec load(map()) :: %{
          rows: [map()],
          merged: [map()],
          related_numbers: map()
        }
  def load(repository) do
    rows = queued_rows(repository)
    merged = if rows == [], do: [], else: merged_pulls(repository)
    related_numbers = related_numbers(rows)
    %{rows: rows, merged: merged, related_numbers: related_numbers}
  end

  defp queued_rows(repository) do
    Repo.all(
      from t in Task,
        where: t.repository_id == ^repository.id and t.state == "queued",
        order_by: [
          desc: fragment("? IS NOT NULL", t.blocker_for_task_id),
          asc: t.inserted_at,
          asc: t.id
        ],
        select: %{
          id: t.id,
          number: t.number,
          title: t.title,
          inserted_at: t.inserted_at,
          origin_task_id: t.origin_task_id,
          blocker_for_task_id: t.blocker_for_task_id,
          held: t.held,
          released_at: t.released_at,
          executor: t.executor
        }
    )
  end

  defp merged_pulls(repository) do
    Repo.all(
      from p in PullRequest,
        where: p.repository_id == ^repository.id and p.state == "merged",
        select: %{id: p.id, number: p.number, title: p.title}
    )
  end

  defp related_numbers(rows) do
    ids =
      rows
      |> Enum.flat_map(&[&1.origin_task_id, &1.blocker_for_task_id])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if ids == [] do
      %{}
    else
      Repo.all(from t in Task, where: t.id in ^ids, select: {t.id, t.number}) |> Map.new()
    end
  end

  @doc "Read unresolved blocker numbers only for the supplied held tasks."
  @spec open_dependencies([integer()]) :: %{optional(integer()) => [integer()]}
  def open_dependencies([]), do: %{}

  def open_dependencies(ids) do
    from([d, blocker: b] in TaskDependency.with_open_blocker(),
      where: d.task_id in ^ids,
      order_by: b.number,
      select: {d.task_id, b.number}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end
end
