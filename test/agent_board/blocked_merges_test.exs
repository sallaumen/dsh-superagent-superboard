defmodule AgentBoard.Sync.BlockedMergesTest do
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, TicketOverlay}
  alias AgentBoard.Board.{Event, Repository, Task}
  alias AgentBoard.Sync.BlockedMerges
  @now ~U[2026-11-13 11:00:00Z]

  setup do
    repo = Repo.insert!(Repository.changeset(%Repository{}, %{owner: "owner", name: "game"}))

    task =
      Repo.insert!(
        Task.changeset(%Task{}, %{
          repository_id: repo.id,
          kind: "issue",
          number: 42,
          title: "Test",
          state: "blocked"
        })
      )

    ticket = %{
      "repository" => "owner/game",
      "numbers" => [42],
      "own_threads" => [50],
      "id" => "my-ticket",
      "started_at" => DateTime.add(@now, -60),
      "ended_at" => nil,
      "report" => "blocked"
    }

    %{task: task, repo: repo, ticket: ticket}
  end

  defp client(fun), do: Req.new(base_url: "https://api.github.com", plug: fun)

  defp closer do
    %{
      "__typename" => "PullRequest",
      "number" => 50,
      "mergedAt" => DateTime.to_iso8601(@now),
      "repository" => %{"nameWithOwner" => "Owner/Game"}
    }
  end

  defp issue(pr),
    do: %{
      "number" => 42,
      "state" => "CLOSED",
      "timelineItems" => %{"nodes" => [%{"__typename" => "ClosedEvent", "closer" => pr}]}
    }

  defp response(conn, evidence), do: Req.Test.json(conn, %{data: %{repository: %{i42: evidence}}})

  test "only the PR that closed this issue resolves the block and broadcasts once", %{
    repo: r,
    task: t,
    ticket: ticket
  } do
    Board.subscribe(r.id)

    api =
      client(fn conn ->
        assert {"POST", "/graphql"} == {conn.method, conn.request_path}
        send(self(), :checked)
        response(conn, issue(closer()))
      end)

    assert :ok = BlockedMerges.check(api, [ticket], @now)
    assert_receive :checked
    assert_receive :board_updated
    assert Repo.get!(Task, t.id).state == "done"
    assert :ok = TicketOverlay.apply(r, 42, "blocked", @now)
    assert :ok = BlockedMerges.check(api, [ticket], @now)
    refute_received :checked
    refute_received :board_updated
    assert [%{payload: %{"pull" => 50, "ticket" => "my-ticket"}}] = Repo.all(Event)
  end

  test "a manual close, another PR, an old merge and a reopened issue are not evidence", %{
    task: t,
    ticket: ticket
  } do
    for evidence <- [
          issue(nil),
          issue(Map.put(closer(), "number", 49)),
          issue(put_in(closer(), ["repository", "nameWithOwner"], "another/game")),
          issue(Map.put(closer(), "mergedAt", "2025-01-01T00:00:00Z")),
          Map.put(issue(closer()), "state", "OPEN")
        ] do
      assert :ok = BlockedMerges.check(client(&response(&1, evidence)), [ticket], @now)
    end

    assert Repo.get!(Task, t.id).state == "blocked"
  end

  test "a human stop during the check wins", %{task: t, ticket: ticket} do
    api =
      client(fn conn ->
        Repo.update!(Ecto.Changeset.change(t, stopped: true))
        response(conn, issue(closer()))
      end)

    assert :ok = BlockedMerges.check(api, [ticket], @now)
    assert %{state: "blocked", stopped: true} = Repo.get!(Task, t.id)
  end

  test "partial data and rate limits leave the board untouched", %{task: t, ticket: ticket} do
    api =
      client(
        &Req.Test.json(&1, %{
          errors: [%{type: "FORBIDDEN"}],
          data: %{repository: %{i42: issue(closer())}}
        })
      )

    assert :ok = BlockedMerges.check(api, [ticket], @now)
    limited = client(&Req.Test.json(&1, %{errors: [%{type: "RATE_LIMITED"}]}))
    assert {:snooze, 60} = BlockedMerges.check(limited, [ticket], @now)
    assert Repo.get!(Task, t.id).state == "blocked"
  end
end
