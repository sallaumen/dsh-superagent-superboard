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

  test "the threads a ticket opened itself are its own PRs", %{db: db} do
    follows = [
      %{"thread" => "github:28", "own" => true},
      %{"thread" => "github:30", "own" => false},
      %{"thread" => "slack:abc", "own" => true}
    ]

    insert(db, Map.put(@sample, "follows", follows))

    assert [ticket] = AgentState.tickets()
    assert ticket["own_threads"] == [28]
  end

  test "a ticket without follows has no own threads", %{db: db} do
    insert(db, @sample)
    assert [ticket] = AgentState.tickets()
    assert ticket["own_threads"] == []
  end

  test "an ended ticket keeps its outcome and the instant it ended", %{db: db} do
    ended = %{"at" => "2026-11-04T14:54:06.000Z", "by" => "executor", "outcome" => "merged"}
    insert(db, Map.put(@sample, "ended", ended))

    assert [ticket] = AgentState.tickets()
    assert ticket["ended_outcome"] == "merged"
    assert ticket["ended_at"] == ~U[2026-11-04 14:54:06.000Z]
  end

  test "a ticket that has not ended has no ended_at", %{db: db} do
    insert(db, @sample)

    assert [ticket] = AgentState.tickets()
    assert ticket["ended_at"] == nil
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

  test "a ticket names its repository, and two repositories can share a number" do
    ticket =
      AgentState.normalize(%{
        "id" => "t1",
        "channels" => [
          %{"address" => %{"url" => "https://github.com/sallaumen/arena-rogue/issues/12"}}
        ],
        "assignments" => [],
        "mandate" => %{"basis" => %{"scope" => %{"number" => 12}}}
      })

    assert ticket["repository"] == "sallaumen/arena-rogue"

    assert AgentState.same_repository?(ticket, %{owner: "sallaumen", name: "arena-rogue"})
    refute AgentState.same_repository?(ticket, %{owner: "sallaumen", name: "o_colmex"})

    legacy = AgentState.normalize(%{"assignments" => [], "channels" => []})
    assert legacy["repository"] == nil
    assert AgentState.same_repository?(legacy, %{owner: "sallaumen", name: "o_colmex"})
  end

  test "two superagent state files are merged by repository" do
    first =
      Path.join(
        System.tmp_dir!(),
        "agent-state-first-#{System.unique_integer([:positive])}.sqlite"
      )

    second =
      Path.join(
        System.tmp_dir!(),
        "agent-state-second-#{System.unique_integer([:positive])}.sqlite"
      )

    previous = Application.get_env(:agent_board, :state_dbs)

    for {path, repo, number} <- [{first, "arena-rogue", 71}, {second, "o_colmex", 72}] do
      {:ok, db} = Exqlite.Sqlite3.open(path)
      :ok = Exqlite.Sqlite3.execute(db, "create table ticket (value text)")

      ticket =
        @sample
        |> Map.put("channels", [
          %{"address" => %{"url" => "https://github.com/sallaumen/#{repo}/issues/#{number}"}}
        ])

      insert(db, ticket)
      Exqlite.Sqlite3.close(db)
    end

    Application.put_env(:agent_board, :state_dbs, [first, second])
    on_exit(fn -> Application.put_env(:agent_board, :state_dbs, previous) end)

    snapshot = AgentState.snapshot()
    assert snapshot.ok

    assert snapshot.tickets |> Enum.map(& &1["repository"]) |> Enum.sort() == [
             "sallaumen/arena-rogue",
             "sallaumen/o_colmex"
           ]
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
