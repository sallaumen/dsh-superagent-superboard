# The board reads the runner's sqlite on mount. Tests get an empty ticket
# table so the agent source answers deterministically and no developer's real
# runner state leaks into a test.
state_db =
  Path.join(
    System.tmp_dir!(),
    "agent-board-test-state-#{System.unique_integer([:positive])}.sqlite"
  )

File.rm(state_db)
{:ok, state_conn} = Exqlite.Sqlite3.open(state_db)
:ok = Exqlite.Sqlite3.execute(state_conn, "create table ticket (value text)")
Exqlite.Sqlite3.close(state_conn)
Application.put_env(:agent_board, :state_db, state_db)

System.at_exit(fn _status ->
  for suffix <- ["", "-wal", "-shm"], do: File.rm(state_db <> suffix)
end)

# Private contexts (`AgentBoard.Board.PrivateContext`) go to a folder of this
# run, emptied first: never the owner's, never the last run's files.
private_root =
  Path.join(System.tmp_dir!(), "agent-board-private-test#{System.get_env("MIX_TEST_PARTITION")}")

File.rm_rf!(private_root)
Application.put_env(:agent_board, :private_root, private_root)
System.at_exit(fn _status -> File.rm_rf(private_root) end)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(AgentBoard.Repo, :manual)
