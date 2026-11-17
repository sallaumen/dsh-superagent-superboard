defmodule AgentBoard.PortableSetupTest do
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{AgentAccess, AgentState, Board, Executors, Orchestrator, Superagents}

  @tag :tmp_dir
  test "new and GitHub-only boards do not adopt another profile or address an unrelated bot", %{
    tmp_dir: root
  } do
    state = Path.join(root, "state")
    other = Path.join([state, "superagent-unrelated", "orchestrator.sqlite"])
    File.mkdir_p!(Path.dirname(other))
    File.write!(other, "unrelated profile")

    for {key, value} <- [
          orchestrator_api: nil,
          orchestrator_client: nil,
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
    assert Orchestrator.client_for(project) == nil
    assert AgentState.paths() == []
    assert %{tickets: [], error: :no_registered_agent} = AgentState.snapshot()

    Application.put_env(:agent_board, :state_db, other)
    assert AgentState.paths() == [other]
  end

  test "export cannot write active project rules through a checkout or linked policy file" do
    root = Path.join(System.tmp_dir!(), "policy-export-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    checkout = Path.join(root, "checkout")
    directory = Path.join(root, "export")
    File.mkdir_p!(Path.join(checkout, ".git"))
    File.mkdir_p!(directory)
    canonical = Path.join(checkout, "scope.md")
    File.write!(canonical, "shared rules")
    linked = Path.join(root, "checkout-link")
    File.ln_s!(checkout, linked)
    File.ln_s!(canonical, Path.join(directory, "scope.md"))

    for {dest, message} <- [
          {Path.join(linked, "rules"), "outside a Git checkout"},
          {directory, "regular file"}
        ] do
      {output, status} =
        System.cmd("sh", ["scripts/agent/prompts.sh", "get"],
          env: [{"SUPERAGENT_PROMPTS_DIR", dest}, {"SUPERAGENT_API", "http://127.0.0.1:1"}],
          stderr_to_stdout: true
        )

      assert status != 0
      assert output =~ message
    end

    assert File.read!(canonical) == "shared rules"
  end
end
