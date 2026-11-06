defmodule AgentBoard.AgentStateTest do
  @moduledoc "The runner's sqlite is read-only evidence: tickets, heartbeat and failure."
  use ExUnit.Case, async: false

  alias AgentBoard.AgentState

  @sample %{
    "mandate" => %{"basis" => %{"scope" => %{"number" => 42}}},
    "channels" => [%{"address" => %{"number" => "43"}}],
    "assignments" => [
      %{
        "state" => "running",
        "startedAt" => "2026-11-06T12:48:16.637Z",
        "idleAt" => nil,
        "report" => %{
          "state" => "ready",
          "summary" => "PR #26 is ready",
          "at" => "2026-11-06T13:10:22.367Z"
        }
      }
    ],
    "updatedAt" => "2026-11-06T13:10:22.367Z",
    "execution" => %{"directory" => "/tmp/work"}
  }

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "agent-state-test-#{System.pid()}-#{System.unique_integer([:positive])}.sqlite"
      )

    File.rm(path)
    previous = Application.get_env(:agent_board, :state_db)
    {:ok, db} = Exqlite.Sqlite3.open(path)
    :ok = Exqlite.Sqlite3.execute(db, "create table ticket (value text)")

    on_exit(fn ->
      Exqlite.Sqlite3.close(db)
      for suffix <- ["", "-wal", "-shm"], do: File.rm(path <> suffix)
      Application.put_env(:agent_board, :state_db, previous)
    end)

    Application.put_env(:agent_board, :state_db, path)

    %{db: db, path: path}
  end

  test "normalizes the ticket fields the board reads", %{db: db} do
    insert(db, @sample)

    snapshot = AgentState.snapshot()
    assert snapshot.ok
    assert [ticket] = snapshot.tickets
    assert ticket["numbers"] == [42, 43]
    assert ticket["assignment"] == "running"
    assert ticket["report"] == "ready"
    assert ticket["report_summary"] == "PR #26 is ready"
    assert %DateTime{} = ticket["started_at"]
    assert ticket["idle_at"] == nil
    assert ticket["execution"]["directory"] == "/tmp/work"
  end

  test "the heartbeat comes from the sqlite file", %{db: db} do
    insert(db, @sample)

    assert %DateTime{} = AgentState.heartbeat_at()
  end

  test "invalid JSON is ignored instead of crashing the board", %{db: db} do
    insert(db, @sample)
    Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('not json')")

    snapshot = AgentState.snapshot()
    assert length(snapshot.tickets) == 1
  end

  test "a missing database is an error, not an empty agent" do
    Application.put_env(:agent_board, :state_db, "/does/not/exist.sqlite")

    assert {:error, _reason} = AgentState.read()
    assert AgentState.tickets() == []
    assert %{ok: false, tickets: []} = AgentState.snapshot()
  end

  test "explicit state_db wins over the fallback" do
    Application.put_env(:agent_board, :state_db, "/tmp/explicit.sqlite")
    assert AgentState.path() == "/tmp/explicit.sqlite"
  end

  defp insert(db, ticket) do
    json = Jason.encode!(ticket) |> String.replace("'", "''")
    :ok = Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('#{json}')")
  end
end
