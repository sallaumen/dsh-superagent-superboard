defmodule AgentBoard.RepoOverviewQueryTest do
  @moduledoc """
  The Hoje overview must not issue one pull-request query per ready task.
  The query count is the contract: 12 ready tasks with linked merged PRs
  took 18 statements before the batch and 7 after it (telemetry probe).
  """
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{Comment, PullRequest, Task}

  test "ready tasks do not add one PR query each" do
    {:ok, repo} = Board.add_repository("fixture", "overview")

    for i <- 1..12 do
      task =
        %Task{}
        |> Task.changeset(%{
          repository_id: repo.id,
          kind: "issue",
          number: i,
          title: "Ready #{i}",
          state: "ready"
        })
        |> Repo.insert!()

      %Comment{}
      |> Comment.changeset(%{
        task_id: task.id,
        kind: "agent",
        body: "https://github.com/fixture/overview/pull/#{1000 + i}"
      })
      |> Repo.insert!()

      %PullRequest{}
      |> PullRequest.changeset(%{
        repository_id: repo.id,
        number: 1000 + i,
        title: "PR #{i}",
        state: "merged"
      })
      |> Repo.insert!()
    end

    parent = self()
    id = "repo-overview-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      id,
      [:agent_board, :repo, :query],
      fn _event, _measurements, _metadata, _config -> send(parent, :query) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)

    result = Board.repo_overview()
    queries = drain(0)
    :telemetry.detach(id)

    assert result[repo.id].you == 0
    assert queries <= 8, "expected a bounded query count, got #{queries} for 12 ready tasks"
  end

  defp drain(count) do
    receive do
      :query -> drain(count + 1)
    after
      0 -> count
    end
  end
end
