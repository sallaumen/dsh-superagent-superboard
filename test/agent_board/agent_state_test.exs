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

  test "a person's message the worker read is the ticket's answer", %{db: db} do
    assignments = [
      %{"id" => "old", "state" => "ended"},
      %{"id" => "now", "state" => "running", "report" => %{"state" => "waiting"}}
    ]

    input = fn fields ->
      Map.merge(%{"kind" => "trigger", "human" => true, "deliveredTo" => "now"}, fields)
    end

    inputs = [
      input.(%{"readAt" => "2026-11-10T17:45:12.054Z"}),
      input.(%{"readAt" => "2026-11-10T17:20:00.000Z"}),
      # not read yet, from a machine, a note, delivered to another Assignment
      input.(%{"at" => "2026-11-10T19:00:00.000Z"}),
      input.(%{"human" => nil, "readAt" => "2026-11-10T19:00:00.000Z"}),
      input.(%{"kind" => "note", "readAt" => "2026-11-10T19:00:00.000Z"}),
      input.(%{"deliveredTo" => "old", "readAt" => "2026-11-10T19:00:00.000Z"}),
      "not an input"
    ]

    insert(db, Map.merge(@sample, %{"assignments" => assignments, "inputs" => inputs}))
    insert(db, @sample)

    assert [answered, plain] = AgentState.snapshot().tickets
    assert answered["answered_at"] == ~U[2026-11-10 17:45:12.054Z]
    assert plain["answered_at"] == nil
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
        "agent-state-first-#{System.pid()}-#{System.unique_integer([:positive])}.sqlite"
      )

    second =
      Path.join(
        System.tmp_dir!(),
        "agent-state-second-#{System.pid()}-#{System.unique_integer([:positive])}.sqlite"
      )

    previous = Application.get_env(:agent_board, :state_dbs)

    # unique_integer restarts with the VM: a file left here collides with a later run.
    on_exit(fn ->
      for path <- [first, second], suffix <- ["", "-wal", "-shm"], do: File.rm(path <> suffix)
      Application.put_env(:agent_board, :state_dbs, previous)
    end)

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

  # The database belongs to the agent: a read before the agent first boots
  # must not create an empty one in its state folder.
  test "reading a missing database in an existing folder does not create it" do
    dir = Path.join(System.tmp_dir!(), "agent-state-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    db = Path.join(dir, "orchestrator.sqlite")
    Application.put_env(:agent_board, :state_db, db)

    assert {:error, _reason} = AgentState.read()
    refute File.exists?(db)
  end

  test "explicit state_db wins over the fallback" do
    Application.put_env(:agent_board, :state_db, "/tmp/explicit.sqlite")
    assert AgentState.path() == "/tmp/explicit.sqlite"
  end

  defp insert(db, ticket) do
    json = Jason.encode!(ticket) |> String.replace("'", "''")
    :ok = Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('#{json}')")
  end

  describe "a ticket row in a shape the board did not expect" do
    # The runner owns this JSON and its shape moves with its version. A row
    # that disagrees loses the field, never every board load.
    for {label, ticket} <- [
          {"a channel number that is not a number",
           %{"channels" => [%{"address" => %{"number" => "abc"}}]}},
          {"a channel that is not an object", %{"channels" => ["github"]}},
          {"an address that is not an object", %{"channels" => [%{"address" => "x"}]}},
          {"channels that are not a list", %{"channels" => %{"a" => 1}}},
          {"assignments that are an object", %{"assignments" => %{"a" => 1}}},
          {"assignments that are a string", %{"assignments" => "x"}},
          {"an assignment that is a string", %{"assignments" => ["x"]}},
          {"a report that is a string", %{"assignments" => [%{"report" => "x"}]}},
          {"ended that is a string", %{"ended" => "x"}},
          {"execution that is a string", %{"execution" => "x"}},
          {"a mandate that is a string", %{"mandate" => "x"}},
          {"follows that are a string", %{"follows" => "x"}}
        ] do
      test "normalizes #{label}" do
        assert %{"numbers" => numbers, "reports" => reports} =
                 normalized = AgentState.normalize(unquote(Macro.escape(ticket)))

        assert numbers == []
        assert reports == []
        assert is_map(normalized["execution"])
      end
    end

    test "a summary or title that is not text reads as absent" do
      normalized =
        AgentState.normalize(%{
          "title" => %{"a" => 1},
          "assignments" => [%{"report" => %{"state" => "failed", "summary" => %{"a" => 1}}}]
        })

      assert normalized["title"] == nil
      assert normalized["report_summary"] == nil
      assert [%{"summary" => nil}] = normalized["reports"]
      assert [%{"summary" => nil}] = normalized["assignments"]
    end

    test "a number past what GitHub's tables hold is dropped" do
      normalized =
        AgentState.normalize(%{
          "channels" => [%{"address" => %{"number" => "9999999999"}}],
          "follows" => [%{"own" => true, "thread" => "github:9999999999"}]
        })

      assert normalized["numbers"] == []
      assert normalized["own_threads"] == []
    end
  end
end
