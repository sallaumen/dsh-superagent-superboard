defmodule AgentBoard.Lanes.Queue.ReadsTest do
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Lanes}

  test "an empty queue needs only the queued tasks, even to count possible repeats" do
    {:ok, repo} = Board.add_repository("fixture", "empty-queue")
    {page, reads} = reads(fn -> Lanes.queue(repo, filter: :dupes) end)
    assert %{items: [], counts: %{all: 0, dupes: 0}, total: 0, hidden: 0, filters: []} = page
    assert Enum.map(reads, &elem(&1, 0)) == ["tasks"]
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
