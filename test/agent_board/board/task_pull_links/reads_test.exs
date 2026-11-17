defmodule AgentBoard.Board.TaskPullLinks.ReadsTest do
  use AgentBoard.DataCase, async: true
  alias AgentBoard.Board
  alias AgentBoard.Board.{PullRequest, Task}

  test "named and ticket lookups each read only requested repository/number pairs" do
    {:ok, a} = Board.add_repository("fixture", "a")
    {:ok, b} = Board.add_repository("fixture", "b")

    for repo <- [a, b], n <- [3, 4, 5, 6] do
      Repo.insert!(%PullRequest{
        repository_id: repo.id,
        number: n,
        title: "PR #{n}",
        state: "open"
      })
    end

    named_a = task(a, 11, "https://github.com/fixture/a/pull/3")
    named_b = task(b, 12, "https://github.com/fixture/b/pull/4")
    thread_a = task(a, 13, nil)
    thread_b = task(b, 14, nil)
    tickets = %{13 => %{"own_threads" => [5]}, 14 => %{"own_threads" => [6]}}
    ref = make_ref()

    :ok =
      :telemetry.attach(ref, [:agent_board, :repo, :query], &__MODULE__.record/4, {self(), ref})

    try do
      pulls = Board.linked_pull_requests([named_a, named_b, thread_a, thread_b], tickets)

      assert Map.new(pulls, fn {id, p} -> {id, {p.repository_id, p.number}} end) ==
               %{
                 named_a.id => {a.id, 3},
                 named_b.id => {b.id, 4},
                 thread_a.id => {a.id, 5},
                 thread_b.id => {b.id, 6}
               }

      assert_received {^ref, 2}
      assert_received {^ref, 2}
      refute_received {^ref, _}
    after
      :telemetry.detach(ref)
    end
  end

  defp task(repo, number, body) do
    Repo.insert!(%Task{
      repository_id: repo.id,
      kind: "issue",
      number: number,
      title: "Task #{number}",
      state: "ready",
      body: body
    })
  end

  def record(
        _event,
        _measure,
        %{source: "pull_requests", result: {:ok, %{num_rows: n}}},
        {pid, ref}
      )
      when pid == self(), do: send(pid, {ref, n})

  def record(_event, _measure, _meta, _config), do: :ok
end
