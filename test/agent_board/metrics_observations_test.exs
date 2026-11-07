defmodule AgentBoard.MetricsObservationsTest do
  @moduledoc "The throughput block reads what the board recorded; what it never read is unknown."
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{Commit, PullRequest, Task}
  alias AgentBoard.Metrics.Observations

  @now ~U[2026-11-07 01:25:40Z]

  defp at(seconds_ago), do: DateTime.add(@now, -seconds_ago, :second)

  setup do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    %{repo: repo, agent: %{ok: true, at: @now, tickets: [], error: nil}}
  end

  defp task!(repo, attrs) do
    %Task{}
    |> Task.changeset(
      Map.merge(%{repository_id: repo.id, kind: "issue", title: "t", state: "queued"}, attrs)
    )
    |> Repo.insert!()
    |> then(fn task ->
      # inserted_at is the board's own clock; the test pins it.
      if attrs[:inserted_at],
        do:
          Repo.update_all(from(t in Task, where: t.id == ^task.id),
            set: [inserted_at: attrs.inserted_at]
          )

      task
    end)
  end

  defp pull!(repo, attrs) do
    %PullRequest{}
    |> PullRequest.changeset(
      Map.merge(%{repository_id: repo.id, title: "pr", state: "merged"}, attrs)
    )
    |> Repo.insert!()
  end

  defp ticket(numbers, threads, outcome, ended_at) do
    %{
      "numbers" => numbers,
      "own_threads" => threads,
      "ended_outcome" => outcome,
      "ended_at" => ended_at,
      "channel_urls" =>
        Enum.map(numbers, &"https://github.com/sallaumen/arena-rogue/issues/#{&1}")
    }
  end

  test "done, opened and merged come from the tables, inside the week", %{
    repo: repo,
    agent: agent
  } do
    task!(repo, %{number: 1, state: "done", state_changed_at: at(100), inserted_at: at(9000)})

    task!(repo, %{
      number: 2,
      state: "done",
      state_changed_at: at(8 * 86_400),
      inserted_at: at(9 * 86_400)
    })

    task!(repo, %{number: 3, state: "queued", inserted_at: at(50)})
    pull!(repo, %{number: 10, opened_at: at(600), merged_at: at(60)})
    pull!(repo, %{number: 11, opened_at: at(600), merged_at: nil, state: "open"})

    obs = Observations.read(repo, agent, now: @now, load: {:error, :not_configured})

    assert obs.done == {:ok, [at(100)]}
    assert obs.opened == {:ok, [at(9000), at(50)]} or obs.opened == {:ok, [at(50), at(9000)]}
    assert obs.merged == {:ok, [at(60)]}
    assert obs.load == {:error, :not_configured}
  end

  test "commits are unknown until a sync read the branch", %{repo: repo, agent: agent} do
    assert Observations.read(repo, agent, now: @now, load: {:error, :x}).commits ==
             {:unknown, :never_synced}

    Board.log_event(repo.id, "sync", "sallaumen/arena-rogue", %{"commits" => 0, "errors" => 0})
    assert Observations.read(repo, agent, now: @now, load: {:error, :x}).commits == {:ok, []}

    %Commit{}
    |> Commit.changeset(%{repository_id: repo.id, sha: "abc", committed_at: at(30)})
    |> Repo.insert!()

    assert Observations.read(repo, agent, now: @now, load: {:error, :x}).commits ==
             {:ok, [at(30)]}
  end

  test "ended tickets count only for this repository and only when the agent answered",
       %{repo: repo} do
    tickets = [
      ticket([1], [10], "merged", at(100)),
      ticket([2], [], "completed", at(200)),
      ticket([3], [], "stopped", at(300)),
      ticket([4], [], "merged", nil),
      Map.put(ticket([5], [], "merged", at(400)), "channel_urls", [
        "https://github.com/other/repo/issues/5"
      ])
    ]

    agent = %{ok: true, at: @now, tickets: tickets, error: nil}

    assert Observations.read(repo, agent, now: @now, load: {:error, :x}).tickets ==
             {:ok, [at(100), at(200)]}

    down = %{ok: false, at: nil, tickets: [], error: :enoent}

    assert Observations.read(repo, down, now: @now, load: {:error, :x}).tickets ==
             {:unknown, :agent_unavailable}
  end

  test "a task is queued from its arrival until it started or changed state", %{
    repo: repo,
    agent: agent
  } do
    task!(repo, %{number: 1, state: "queued", inserted_at: at(1000)})

    task!(repo, %{
      number: 2,
      state: "running",
      inserted_at: at(2000),
      started_at: at(500),
      state_changed_at: at(400)
    })

    task!(repo, %{number: 3, state: "done", inserted_at: at(3000), state_changed_at: at(900)})
    # Left the queue at an unknown instant: not a span.
    task!(repo, %{number: 4, state: "done", inserted_at: at(3000)})

    spans = Observations.read(repo, agent, now: @now, load: {:error, :x}).queue

    assert Enum.sort(spans) ==
             Enum.sort([{at(1000), nil}, {at(2000), at(500)}, {at(3000), at(900)}])
  end

  test "a cycle joins the ticket's issue, its own PR and that PR's merge", %{repo: repo} do
    task!(repo, %{number: 1, state: "done", inserted_at: at(5000)})
    pull!(repo, %{number: 10, opened_at: at(4000), merged_at: at(1000)})
    pull!(repo, %{number: 12, opened_at: at(3000), merged_at: at(500)})

    tickets = [
      ticket([1], [10, 12], "merged", at(500)),
      ticket([2], [99], "merged", at(500)),
      ticket([1], [], "merged", at(500))
    ]

    agent = %{ok: true, at: @now, tickets: tickets, error: nil}

    assert Observations.read(repo, agent, now: @now, load: {:error, :x}).cycles ==
             [%{issue_at: at(5000), pr_at: at(3000), merged_at: at(500)}]
  end
end
