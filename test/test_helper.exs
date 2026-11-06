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

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(AgentBoard.Repo, :manual)
