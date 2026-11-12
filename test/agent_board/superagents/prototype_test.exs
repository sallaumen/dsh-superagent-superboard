defmodule AgentBoard.Superagents.PrototypeTest do
  @moduledoc "Where the agent's code is, and installing it on a machine that has none."
  # The home and the profiles folder are application settings.
  use AgentBoard.DataCase, async: false

  alias AgentBoard.Settings
  alias AgentBoard.Superagents.Prototype

  setup do
    root = Path.join(System.tmp_dir!(), "prototype-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "profiles"))

    # No home set for the application, and the owner's own folder nowhere.
    for {key, value} <- [
          dsh_profiles_dir: Path.join(root, "profiles"),
          dsh_superagent_home: nil,
          dsh_superagent_legacy_home: Path.join(root, "legacy")
        ] do
      previous = Application.get_env(:agent_board, key)

      if value,
        do: Application.put_env(:agent_board, key, value),
        else: Application.delete_env(:agent_board, key)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:agent_board, key, previous),
          else: Application.delete_env(:agent_board, key)
      end)
    end

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, target: Path.join(root, "dsh-superagent")}
  end

  # A git that leaves a checkout with the manager in it, and a pnpm that works.
  defp working(test) do
    fn [tool | args], opts ->
      send(test, {:ran, tool, args, opts[:cd]})
      if tool == "git", do: File.mkdir_p!(Path.join(List.last(args), "scripts"))
      if tool == "git", do: File.write!(Path.join(List.last(args), "scripts/dsh-superagent"), "")
      {"", 0}
    end
  end

  test "a board that never installed it finds it where it always was", %{root: root} do
    assert Prototype.home() == Path.join(root, "legacy")
    assert Prototype.manager() == Path.join(root, "legacy/scripts/dsh-superagent")
  end

  test "a machine without it gets the public repository cloned, built and remembered",
       %{target: target} do
    assert Prototype.target() == target
    assert Prototype.install(working(self())) == :ok

    assert_received {:ran, "git", ["clone", "--depth", "1", url, ^target], nil}
    assert url == "https://github.com/deepseek-ai/dsh-superagent-prototype.git"
    assert_received {:ran, "pnpm", ["install"], ^target}
    assert_received {:ran, "pnpm", ["build"], ^target}

    # From now on this is where every agent's manager is.
    assert Settings.get("dsh_superagent_home") == target
    assert Prototype.home() == target

    # A second install has nothing to do.
    assert Prototype.install(fn _, _ -> flunk("nothing to run") end) == :ok
  end

  test "a step that fails stops the install, names the tool and remembers nothing" do
    failing = fn
      ["git" | _args], _opts -> {"", 0}
      ["pnpm" | _args], _opts -> {"ERR_PNPM_FETCH no network", 1}
    end

    assert {:error, {:command, "pnpm", "ERR_PNPM_FETCH no network"}} = Prototype.install(failing)
    assert Settings.get("dsh_superagent_home") == nil
  end

  test "a folder at the target that is not the agent's code is left alone", %{target: target} do
    File.mkdir_p!(target)
    File.write!(Path.join(target, "notes.txt"), "mine")

    assert Prototype.install(fn _, _ -> flunk("nothing to run") end) ==
             {:error, {:prototype_in_the_way, target}}

    assert File.read!(Path.join(target, "notes.txt")) == "mine"
  end
end
