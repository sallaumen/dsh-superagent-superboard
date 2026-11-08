defmodule AgentBoard.Sync.WorkerTest do
  @moduledoc "The Oban job: perform/1 runs the sync and reports success."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task
  alias AgentBoard.Sync.Worker
  import Ecto.Query

  test "perform/1 runs the sync and returns :ok with no repositories", _ctx do
    assert Worker.perform(%Oban.Job{args: %{}}) == :ok
  end

  @stub AgentBoard.Sync.WorkerTest.Stub

  defp client,
    do: Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)

  test "perform/1 syncs the active repositories", _ctx do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    Application.put_env(:agent_board, :github_client, fn -> client() end)
    on_exit(fn -> Application.delete_env(:agent_board, :github_client) end)

    Req.Test.stub(@stub, fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" ->
          Req.Test.json(conn, [
            %{
              "number" => 7,
              "title" => "W",
              "state" => "open",
              "html_url" => "https://github.com/x/y/issues/7",
              "user" => %{"login" => "s"},
              "updated_at" => "2026-11-04T00:00:00Z"
            }
          ])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    # Waited less than one cron period (a retry, a snooze that woke): it runs.
    waited = DateTime.add(DateTime.utc_now(), -4 * 60, :second)

    assert Worker.perform(%Oban.Job{args: %{}, scheduled_at: waited}) == :ok
    assert Repo.one(from t in Task, where: t.number == 7) != nil
    assert Enum.any?(Board.events(repo), &(&1.kind == "sync"))
  end

  test "perform/1 cancels a sync scheduled before the last cron run, without calling GitHub",
       _ctx do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    Application.put_env(:agent_board, :github_client, fn -> client() end)
    on_exit(fn -> Application.delete_env(:agent_board, :github_client) end)

    Req.Test.stub(@stub, fn conn -> flunk("superseded sync called #{conn.request_path}") end)

    # What Oban.Lifeline hands back after a restart: the original schedule.
    orphaned = DateTime.add(DateTime.utc_now(), -31 * 60, :second)

    assert {:cancel, reason} = Worker.perform(%Oban.Job{args: %{}, scheduled_at: orphaned})
    assert reason =~ "superseded"
    refute Enum.any?(Board.events(repo), &(&1.kind == "sync"))
  end
end
