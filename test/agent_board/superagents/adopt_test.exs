defmodule AgentBoard.Superagents.AdoptTest do
  @moduledoc "An agent installed outside the board: listed, adopted from what it says of itself, never copied into a second one."
  # The profiles folder and the manager are application settings.
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Actions, Board, Superagents}
  alias AgentBoard.Superagents.{FakeManager, FakeProvisioner}

  @identity %{repository: "fixture/adopted", bot: "fixture-bot", max_workers: 4}

  setup do
    root = Path.join(System.tmp_dir!(), "adopt-#{System.unique_integer([:positive])}")
    profiles = Path.join(root, "profiles")

    # The agent, a profile that is not one, and a folder with no patch.
    profile!(profiles, "superagent", """
    - id: webserver
      config:
        host: 127.0.0.1
        port: 3301
    - id: dsh-superagent
      config:
        stateDir: #{root}/state/superagent
    """)

    profile!(profiles, "desktop", """
    - id: webserver
      config:
        port: 3300
    """)

    File.mkdir_p!(Path.join(profiles, "headless"))

    {:ok, _pid} = FakeManager.start()
    previous = Application.get_env(:agent_board, :superagent_manager)
    Application.put_env(:agent_board, :superagent_manager, FakeManager)
    Application.put_env(:agent_board, :dsh_profiles_dir, profiles)

    on_exit(fn ->
      Application.put_env(:agent_board, :dsh_profiles_dir, "/nonexistent-dsh-profiles")

      if previous,
        do: Application.put_env(:agent_board, :superagent_manager, previous),
        else: Application.delete_env(:agent_board, :superagent_manager)

      File.rm_rf!(root)
    end)

    %{state_dir: Path.join(root, "state/superagent")}
  end

  # What the registry's action does, without its gate.
  defp adopt(profile) do
    with {:ok, candidate} <- Superagents.adoptable(profile),
         {:ok, _tracked} <- Board.add_repository(candidate.owner, candidate.name) do
      Superagents.adopt(candidate, Board.find_repository(candidate.owner, candidate.name))
    end
  end

  defp profile!(profiles, name, patch) do
    File.mkdir_p!(Path.join(profiles, name))
    File.write!(Path.join([profiles, name, "cordis.patch.yml"]), patch)
  end

  test "only a profile that loads dsh-superagent, and that no row names, waits to be added",
       %{state_dir: state_dir} do
    assert [%{name: "superagent", port: 3301, state_dir: ^state_dir}] = Superagents.unregistered()

    {:ok, repo} = Board.add_repository("fixture", "already")

    {:ok, _row} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent",
        port: 3301,
        state_dir: state_dir
      })

    assert Superagents.unregistered() == []
  end

  test "an agent that answers is registered for the repository it names, as it is",
       %{state_dir: state_dir} do
    FakeManager.put_identity("superagent", @identity)

    assert {:ok, superagent} = adopt("superagent")

    assert %{
             profile: "superagent",
             port: 3301,
             state_dir: ^state_dir,
             max_workers: 4,
             desired_state: "running",
             repository: %{owner: "fixture", name: "adopted"}
           } = superagent

    assert [%{action: "adopt", detail: "superagent"}] = Superagents.events(superagent)
    assert Superagents.unregistered() == []
  end

  test "a stopped agent is started first, then asked" do
    FakeManager.put_identity("superagent", {:after_start, @identity})

    assert {:ok, %{repository: %{name: "adopted"}}} = adopt("superagent")
  end

  test "an agent that never answers is not registered" do
    assert {:error, :econnrefused} = adopt("superagent")
    assert Superagents.list() == []
  end

  test "an agent that names no repository is not registered, and nothing is tracked" do
    FakeManager.put_identity("superagent", %{@identity | repository: nil})

    assert adopt("superagent") == {:error, :no_repository}
    assert Superagents.list() == []
    assert Board.find_repository("fixture", "adopted") == nil
  end

  test "a repository that already has an agent keeps it" do
    {:ok, repo} = Board.add_repository("fixture", "adopted")

    {:ok, _row} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-adopted",
        port: 3302,
        state_dir: "/tmp/superagent-adopted"
      })

    FakeManager.put_identity("superagent", @identity)

    assert adopt("superagent") == {:error, :already_registered}
    assert length(Superagents.list()) == 1
  end

  test "a profile that is not waiting is refused" do
    assert adopt("desktop") == {:error, :not_found}
    assert adopt("nobody") == {:error, :not_found}
  end

  test "a new project is refused for a repository an installed agent already serves" do
    FakeManager.put_identity("superagent", @identity)
    {:ok, served} = Board.add_repository("fixture", "adopted")
    {:ok, other} = Board.add_repository("fixture", "another")

    assert Superagents.provision(served, "superagent", %{path: "/tmp/x"}, FakeProvisioner) ==
             {:error, {:already_installed, "superagent"}}

    assert Superagents.list() == []

    # Another repository may still take a copy of that profile.
    assert {:ok, %{profile: "superagent-another"}} =
             Superagents.provision(other, "superagent", %{path: "/tmp/x"}, FakeProvisioner)
  end

  test "adding is a red action: its sentence, then the result with the project's name" do
    FakeManager.put_identity("superagent", @identity)
    params = %{profile: "superagent", port: 3301}

    assert {:error, {:unconfirmed, phrase}} =
             Actions.run(:adopt_superagent, params, Actions.owner(:ui))

    assert phrase =~ "superagent (porta 3301)"
    assert Superagents.list() == []

    assert {:ok, text} =
             Actions.run(:adopt_superagent, params, Actions.owner(:ui), confirm: phrase)

    assert text =~ "fixture/adopted"
  end
end
