defmodule AgentBoard.DependencyDeliveryTest do
  use AgentBoard.DataCase, async: true
  alias AgentBoard.Board.{Repository, Task}
  alias AgentBoard.{DependencyDelivery, Repo}

  test "a completed sibling cannot wake a parent until every linked task has finished; use only its original ticket" do
    repo = Repo.insert!(%Repository{owner: "owner", name: "game"})
    parent = task(repo, 471, "blocked", nil)
    task(repo, 472, "done", parent.id)
    other = task(repo, 473, "running", parent.id)
    blocked = ~U[2026-11-16 12:00:00Z]
    ended = ~U[2026-11-16 12:01:00Z]

    parent_ticket = %{
      "id" => "parent",
      "origin_issue" => 471,
      "repository" => "owner/game",
      "stopped" => false,
      "archived" => false,
      "report_at" => blocked,
      "report" => "blocked",
      "assignment" => "running",
      "idle_at" => blocked,
      "assignment_id" => "same-assignment"
    }

    child = fn n ->
      %{
        "id" => "child#{n}",
        "origin_issue" => n,
        "repository" => "owner/game",
        "ended_outcome" => "completed",
        "ended_at" => ended,
        "report" => "ready",
        "own_threads" => []
      }
    end

    children = [child.(472), child.(473)]

    owner = self()

    Req.Test.stub(__MODULE__, fn conn ->
      case conn.method do
        "GET" ->
          Req.Test.json(conn, %{
            "completedDependencyInput" => true,
            "paused" => false,
            "setup" => %{"accounts" => %{"repository" => "owner/game"}}
          })

        "POST" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(owner, {:wake, conn.request_path, Jason.decode!(body)})
          Req.Test.json(conn, %{"outcome" => "delivered"})
      end
    end)

    client = Req.new(base_url: "http://local", plug: {Req.Test, __MODULE__})

    run = fn ts -> DependencyDelivery.reconcile(ts, client: client) end
    assert [] == run.([parent_ticket | children])
    other |> Ecto.Changeset.change(state: "done") |> Repo.update!()
    assert [] == run.([parent_ticket, child.(472)])

    assert [] ==
             run.([parent_ticket, Map.put(child.(472), "repository", "other/game"), child.(473)])

    assert [] == run.([parent_ticket | Enum.map(children, &Map.put(&1, "ended_at", blocked))])
    refute_received {:wake, _, _}
    # A successful worker inventory is not proof that GitHub accepted its output.
    other |> Ecto.Changeset.change(github_issue_status: "not_planned") |> Repo.update!()
    assert [] == run.([parent_ticket | children])
    refute_received {:wake, _, _}

    Repo.reload!(other)
    |> Ecto.Changeset.change(github_issue_status: "completed")
    |> Repo.update!()

    # The cancelled predecessor stays in history; its selected successor supplies the receipt.
    cancelled = task(repo, 474, "closed", parent.id)
    cancelled |> Ecto.Changeset.change(github_issue_status: "not_planned") |> Repo.update!()
    assert [] == run.([parent_ticket | children])

    Repo.reload!(cancelled)
    |> Ecto.Changeset.change(
      blocker_decision: %{
        "kind" => "replaced",
        "replacement" => 473,
        "reason" => "different source"
      }
    )
    |> Repo.update!()

    assert [{:ok, "delivered"}] == run.([parent_ticket | children])

    assert_received {:wake, "/tickets/parent/dependencies-completed",
                     %{
                       "assignment" => "same-assignment",
                       "children" => [%{"number" => 472}, %{"number" => 473}]
                     }}

    assert [] ==
             run.([
               Map.put(parent_ticket, "dependency_inputs", ["dependency:child472:child473"])
               | children
             ])

    waived = task(repo, 475, "closed", parent.id)

    waived
    |> Ecto.Changeset.change(
      blocker_decision: %{"kind" => "waived", "requested_at" => DateTime.to_iso8601(ended)}
    )
    |> Repo.update!()

    assert [] == run.([parent_ticket | children])
    refute_received {:wake, _, _}
  end

  defp task(repo, n, state, parent) do
    Repo.insert!(%Task{
      repository_id: repo.id,
      number: n,
      title: "task #{n}",
      state: state,
      github_issue_status: "completed",
      blocker_for_task_id: parent
    })
  end
end
