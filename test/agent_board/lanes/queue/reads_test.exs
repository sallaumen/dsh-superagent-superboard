defmodule AgentBoard.Lanes.Queue.ReadsTest do
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Lanes}

  test "an empty queue needs only the queued tasks, even to count possible repeats" do
    {:ok, repo} = Board.add_repository("fixture", "empty-queue")
    {page, reads} = reads(fn -> Lanes.queue(repo, filter: :dupes) end)
    assert %{items: [], counts: %{all: 0, dupes: 0}, total: 0, hidden: 0, filters: []} = page
    assert Enum.map(reads, &elem(&1, 0)) == ["tasks"]
  end

  test "one lookup resolves both relationship roles, without repeating a shared origin" do
    {:ok, repo} = Board.add_repository("fixture", "queue-relations")
    parent = task(repo, 7, "done")
    child = task(repo, 8, "queued", %{origin_task_id: parent.id})
    task(repo, 9, "queued", %{origin_task_id: parent.id, blocker_for_task_id: child.id})

    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    {page, reads} = reads(fn -> Lanes.queue(repo) end)

    assert Enum.map(page.items, &{&1.number, &1.sub}) == [
             {9, "unblocks #8"},
             {8, "split from #7"}
           ]

    assert page.counts.split == 2
    assert [_, _] = for({"tasks", params} <- reads, do: params)
  end

  test "only visible held cards read their open blockers; an empty filter reads none" do
    {:ok, repo} = Board.add_repository("fixture", "visible-waits")
    first = task(repo, 12, "queued", %{held: true})
    second = task(repo, 14, "queued", %{held: true})
    open = task(repo, 9, "running")
    at = ~U[2026-11-16 12:00:00Z]

    Repo.insert_all(
      AgentBoard.Board.TaskDependency,
      for(
        t <- [first, second],
        do: %{
          task_id: t.id,
          blocked_by_task_id: open.id,
          inserted_at: at,
          updated_at: at
        }
      )
    )

    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    {page, queries} = reads(fn -> Lanes.queue(repo, limit: 1) end)
    assert [%{number: 12, sub: "waiting for #9"}] = page.items
    assert %{total: 2, hidden: 1} = page
    assert [params] = for({"task_dependencies", params} <- queries, do: params)
    assert [first.id] in params

    {empty, queries} = reads(fn -> Lanes.queue(repo, filter: :dupes) end)
    assert %{items: [], total: 0, counts: %{all: 2}} = empty
    refute List.keymember?(queries, "task_dependencies", 0)
  end

  defp task(repo, n, state, attrs \\ %{}) do
    %AgentBoard.Board.Task{
      repository_id: repo.id,
      kind: "issue",
      number: n,
      title: "Task #{n}",
      state: state
    }
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end

  def record(_event, _measurements, %{source: source, params: params}, {pid, ref})
      when pid == self() and is_binary(source),
      do: send(pid, {ref, source, params})

  def record(_event, _measurements, _meta, _config), do: :ok

  defp reads(fun) do
    ref = make_ref()

    :ok =
      :telemetry.attach(ref, [:agent_board, :repo, :query], &__MODULE__.record/4, {self(), ref})

    try do
      {fun.(), collect(ref)}
    after
      :telemetry.detach(ref)
    end
  end

  defp collect(ref) do
    receive do
      {^ref, source, params} -> [{source, params} | collect(ref)]
    after
      0 -> []
    end
  end
end
