defmodule AgentBoard.PortableSetupTest do
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{AgentAccess, AgentState, Board, Executors, Superagents}

  @tag :tmp_dir
  test "new and GitHub-only boards do not adopt another profile or address an unrelated bot", %{
    tmp_dir: root
  } do
    state = Path.join(root, "state")
    other = Path.join([state, "superagent-unrelated", "orchestrator.sqlite"])
    File.mkdir_p!(Path.dirname(other))
    File.write!(other, "unrelated profile")

    for {key, value} <- [
          state_db: nil,
          state_dbs: nil,
          dsh_state_root: state,
          agent_login: nil,
          agent_gh_config: Path.join(root, "gh-agent")
        ] do
      previous = Application.fetch_env(:agent_board, key)
      Application.put_env(:agent_board, key, value)

      on_exit(fn ->
        case previous do
          {:ok, prior} -> Application.put_env(:agent_board, key, prior)
          :error -> Application.delete_env(:agent_board, key)
        end
      end)
    end

    assert Board.list_repositories() == []
    assert Superagents.list() == []
    assert AgentAccess.bot_login() == nil
    assert Executors.issue_body("Fix the timer", "dsh") == "Fix the timer"

    {:ok, project} = Board.add_repository("example", "clock")
    assert Board.list_repositories() == [project]
    assert AgentState.paths() == []
    assert %{tickets: [], error: :no_registered_agent} = AgentState.snapshot()

    Application.put_env(:agent_board, :state_db, other)
    assert AgentState.paths() == [other]
  end
end
