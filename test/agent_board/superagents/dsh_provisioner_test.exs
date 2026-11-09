defmodule AgentBoard.Superagents.DshProvisionerTest do
  @moduledoc "A failed attempt undoes what it made, and only that."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.Superagents.{DshProvisioner, Superagent}

  setup do
    root = Path.join(System.tmp_dir!(), "provisioner-#{System.unique_integer([:positive])}")
    profiles = Path.join(root, "profiles")
    state = Path.join(root, "state")
    File.mkdir_p!(Path.join(profiles, "superagent"))
    File.mkdir_p!(state)

    File.write!(
      Path.join([profiles, "superagent", "cordis.patch.yml"]),
      "port: 1\nstateDir: /x\n"
    )

    # A manager that cannot start anything: the attempt fails after the copy.
    manager = Path.join(root, "manager.py")
    File.write!(manager, "import sys\nsys.exit(3)\n")

    checkout = Path.join(root, "checkout")
    File.mkdir_p!(Path.join(checkout, ".git"))

    keys = [:dsh_profiles_dir, :dsh_state_dir, :superagent_manager_script]
    previous = Map.new(keys, &{&1, Application.get_env(:agent_board, &1)})
    Application.put_env(:agent_board, :dsh_profiles_dir, profiles)
    Application.put_env(:agent_board, :dsh_state_dir, state)
    Application.put_env(:agent_board, :superagent_manager_script, manager)

    on_exit(fn ->
      for {key, value} <- previous do
        if value,
          do: Application.put_env(:agent_board, key, value),
          else: Application.delete_env(:agent_board, key)
      end

      File.rm_rf!(root)
    end)

    {:ok, repo} =
      AgentBoard.Board.add_repository("fixture", "prov-#{System.unique_integer([:positive])}")

    row = %Superagent{
      id: 1,
      repository_id: repo.id,
      profile: "superagent-new",
      port: 1,
      state_dir: Path.join(state, "superagent-new")
    }

    {:ok,
     root: root,
     profiles: profiles,
     row: row,
     source: %Superagent{profile: "superagent", port: 1},
     attrs: %{path: checkout, workers: 1}}
  end

  test "removes a directory and keeps what a link inside it points at", %{root: root} do
    shared = Path.join(root, "prototype")
    File.mkdir_p!(shared)
    File.write!(Path.join(shared, "keep.txt"), "important")

    profile = Path.join(root, "profile")
    File.mkdir_p!(Path.join(profile, "node_modules"))
    File.write!(Path.join(profile, "cordis.patch.yml"), "port: 1\n")
    File.ln_s!(shared, Path.join([profile, "node_modules", "dsh-superagent"]))

    DshProvisioner.remove_tree(profile)

    refute File.exists?(profile)
    assert File.read!(Path.join(shared, "keep.txt")) == "important"
  end

  test "a path that is not there is fine", %{root: root} do
    assert :ok = DshProvisioner.remove_tree(Path.join(root, "nothing"))
  end

  test "a failed attempt removes the profile it copied", context do
    %{row: row, source: source, attrs: attrs, profiles: profiles} = context

    assert {:error, _reason} = DshProvisioner.provision(row, source, attrs)

    refute File.exists?(Path.join(profiles, "superagent-new"))
    assert File.exists?(Path.join([profiles, "superagent", "cordis.patch.yml"]))
  end

  test "a profile that was already there is left alone", context do
    %{row: row, source: source, attrs: attrs, profiles: profiles} = context
    theirs = Path.join([profiles, "superagent-new", "theirs.txt"])
    File.mkdir_p!(Path.dirname(theirs))
    File.write!(theirs, "not ours")

    assert {:error, :profile_exists} = DshProvisioner.provision(row, source, attrs)
    assert File.read!(theirs) == "not ours"
  end

  test "state that was already there is left alone", context do
    %{row: row, source: source, attrs: attrs, profiles: profiles} = context
    theirs = Path.join(row.state_dir, "orchestrator.sqlite")
    File.mkdir_p!(row.state_dir)
    File.write!(theirs, "not ours")

    assert {:error, :state_exists} = DshProvisioner.provision(row, source, attrs)
    assert File.read!(theirs) == "not ours"
    refute File.exists?(Path.join(profiles, "superagent-new"))
  end
end
