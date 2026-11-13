defmodule AgentBoardWeb.MergeProgressTest do
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{PullRequest, Task}

  @head String.duplicate("a", 40)

  test "open PR updates parallel checks, the blocking check and stale evidence", %{conn: conn} do
    root = Path.join(System.tmp_dir!(), "merge-progress-#{System.unique_integer([:positive])}")
    old = System.get_env("SUPERBOARD_GATE_DIR")
    System.put_env("SUPERBOARD_GATE_DIR", root)

    on_exit(fn ->
      if old,
        do: System.put_env("SUPERBOARD_GATE_DIR", old),
        else: System.delete_env("SUPERBOARD_GATE_DIR")

      File.rm_rf!(root)
    end)

    {:ok, repo} = Board.add_repository("fixture", "progress")

    task =
      Repo.insert!(
        Task.changeset(%Task{}, %{
          repository_id: repo.id,
          number: 12,
          kind: "issue",
          state: "ready",
          title: "Delivery",
          body: "https://github.com/fixture/progress/pull/42"
        })
      )

    pr =
      Repo.insert!(
        PullRequest.changeset(%PullRequest{}, %{
          repository_id: repo.id,
          number: 42,
          title: "Delivery",
          state: "open",
          head_sha: @head
        })
      )

    {:ok, view, _} =
      live(conn, "/?repo=fixture/progress&panel=conversation&task=#{task.id}&tab=pr")

    assert has_element?(view, ".ab-merge-progress", "Ainda não há registro")
    dir = Path.join(root, "fixture/progress")
    File.mkdir_p!(dir)
    rows = for n <- ["Mix", "Node"], do: %{name: n, source: "local", state: "running"}

    snapshot = %{
      repo: "fixture/progress",
      pr: 42,
      head: @head,
      observed_at: System.system_time(:second),
      state: "checking",
      checks: rows
    }

    write = fn s -> File.write!(Path.join(dir, "42.json"), Jason.encode!(s)) end
    write.(snapshot)
    send(view.pid, :merge_check_tick)
    assert has_element?(view, ".ab-merge-progress", "2 verificações em paralelo")
    assert has_element?(view, ".ab-merge-progress li", "Node")

    write.(
      %{
        snapshot
        | state: "blocked",
          checks: [%{hd(rows) | state: "passed"}, %{List.last(rows) | state: "failed"}]
      }
      |> Map.put(:reason, "checks_outstanding")
    )

    send(view.pid, :merge_check_tick)
    assert has_element?(view, ".ab-merge-progress", "Node falhou")

    Repo.update!(PullRequest.changeset(pr, %{head_sha: String.duplicate("b", 40)}))
    send(view.pid, :board_updated)
    send(view.pid, :merge_check_tick)
    assert has_element?(view, ".ab-merge-progress", "Aguardando verificações da revisão atual")
    refute has_element?(view, ".ab-merge-progress li")
  end
end
