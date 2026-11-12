# Every temporary path a test makes comes from System.tmp_dir!/0, and most of
# them are named with System.unique_integer/1, which repeats between two runs
# of the suite (two worktrees, two agents at once): one run would share or
# delete the other's files. This run gets its own TMPDIR, named by the OS
# process, so every such path is its own.
run_tmp = Path.join(System.tmp_dir!(), "agent-board-test-run-#{System.pid()}")
File.rm_rf!(run_tmp)
File.mkdir_p!(run_tmp)
System.put_env("TMPDIR", run_tmp)
System.at_exit(fn _status -> File.rm_rf(run_tmp) end)

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
# run, emptied first: never the owner's, never the last run's files. The OS
# process id keeps two suites running at once (two worktrees, two agents) from
# emptying each other's folder mid-test.
private_root =
  Path.join(
    System.tmp_dir!(),
    "agent-board-private-test#{System.get_env("MIX_TEST_PARTITION")}-#{System.pid()}"
  )

File.rm_rf!(private_root)
Application.put_env(:agent_board, :private_root, private_root)
System.at_exit(fn _status -> File.rm_rf(private_root) end)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(AgentBoard.Repo, :manual)
