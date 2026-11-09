defmodule AgentBoard.Superagents.DshProvisionerTest do
  @moduledoc """
  A provisioning the agent refuses, against a real HTTP agent and real
  directories: the half-project goes away and the agent's own reason comes back.
  """
  use ExUnit.Case, async: false

  alias AgentBoard.Board.Repository
  alias AgentBoard.Superagents.{DshProvisioner, Superagent}

  defmodule RefusingAgent do
    @moduledoc false
    import Plug.Conn

    @api "/orchestrator/api"

    def init(options), do: options

    def call(conn, _options) do
      {:ok, _body, conn} = read_body(conn)
      {status, body} = answer(conn.method, String.replace_prefix(conn.request_path, @api, ""))
      conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
    end

    defp answer("GET", "/state"), do: {200, %{health: %{runtime: %{state: "ready"}}}}

    defp answer("GET", "/settings") do
      {200,
       %{
         sources: [%{id: "github", value: %{config: %{}}, revision: 0}],
         blocks: %{executor: %{value: %{}, revision: 0}, policy: %{value: %{}, revision: 0}}
       }}
    end

    defp answer("GET", "/prompts"), do: {200, %{current: %{config: %{}, revision: 0}}}

    defp answer("PUT", "/settings/source:github"),
      do: {400, %{error: "@bot cannot push to owner/name."}}

    defp answer(_method, _path), do: {404, %{error: "unexpected"}}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "provisioner-#{System.pid()}-#{System.unique_integer()}")
    profiles = Path.join(root, "profiles")
    states = Path.join(root, "state")
    checkout = Path.join(root, "checkout")
    File.mkdir_p!(Path.join(profiles, "source"))
    File.mkdir_p!(Path.join(checkout, ".git"))
    File.mkdir_p!(states)
    File.write!(Path.join([profiles, "source", "cordis.patch.yml"]), "port: 1\nstateDir: /x\n")

    # A profile holds symlinks into a package store; removing it must not follow them.
    outside = Path.join(root, "package-store")
    File.mkdir_p!(outside)
    File.write!(Path.join(outside, "kept"), "kept")
    File.mkdir_p!(Path.join([profiles, "source", "node_modules"]))
    File.ln_s!(outside, Path.join([profiles, "source", "node_modules", "package"]))

    manager = Path.join(root, "manager.py")
    File.write!(manager, "")

    for {key, value} <- [
          dsh_profiles_dir: profiles,
          dsh_state_root: states,
          superagent_manager_script: manager
        ] do
      previous = Application.get_env(:agent_board, key)
      Application.put_env(:agent_board, key, value)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:agent_board, key, previous),
          else: Application.delete_env(:agent_board, key)
      end)
    end

    on_exit(fn -> File.rm_rf(root) end)

    server = start_supervised!({Bandit, plug: RefusingAgent, port: 0, ip: :loopback})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    %{root: root, profiles: profiles, states: states, checkout: checkout, port: port}
  end

  test "a refused configuration undoes the project and says why", context do
    source = %Superagent{profile: "source", port: context.port, state_dir: "/unused"}
    state_dir = Path.join(context.states, "new")

    project = %Superagent{
      profile: "new",
      port: context.port,
      state_dir: state_dir,
      repository_id: 1,
      repository: %Repository{id: 1, owner: "owner", name: "name"}
    }

    assert {:error, "@bot cannot push to owner/name."} =
             DshProvisioner.provision(project, source, %{path: context.checkout})

    refute File.exists?(Path.join(context.profiles, "new"))
    refute File.exists?(state_dir)
    assert File.read!(Path.join([context.root, "package-store", "kept"])) == "kept"
  end

  defp project(context) do
    %Superagent{
      profile: "new",
      port: context.port,
      state_dir: Path.join(context.states, "new"),
      repository_id: 1,
      repository: %Repository{id: 1, owner: "owner", name: "name"}
    }
  end

  defp source(context), do: %Superagent{profile: "source", port: context.port, state_dir: "/x"}

  test "a profile this attempt did not create is left alone", context do
    project = project(context)
    profile = Path.join(context.profiles, "new")
    File.mkdir_p!(profile)
    File.mkdir_p!(project.state_dir)
    File.write!(Path.join(project.state_dir, "orchestrator.sqlite"), "tickets")

    assert {:error, :profile_exists} =
             DshProvisioner.provision(project, source(context), %{path: context.checkout})

    assert File.dir?(profile)
    assert File.read!(Path.join(project.state_dir, "orchestrator.sqlite")) == "tickets"
  end

  test "a checkout that does not exist touches nothing", context do
    project = project(context)
    profile = Path.join(context.profiles, "new")
    File.mkdir_p!(profile)

    assert {:error, :checkout_missing} =
             DshProvisioner.provision(project, source(context), %{path: "/does/not/exist"})

    assert File.dir?(profile)
  end

  test "a state directory that was already there survives a refusal", context do
    project = project(context)
    File.mkdir_p!(project.state_dir)
    File.write!(Path.join(project.state_dir, "orchestrator.sqlite"), "kept from a removal")

    assert {:error, _reason} =
             DshProvisioner.provision(project, source(context), %{path: context.checkout})

    refute File.exists?(Path.join(context.profiles, "new"))

    assert File.read!(Path.join(project.state_dir, "orchestrator.sqlite")) ==
             "kept from a removal"
  end

  test "an agent that will not stop keeps its files and says so", context do
    File.write!(
      Path.join(context.root, "manager.py"),
      "import sys\nsys.exit(1 if sys.argv[-1] == 'stop' else 0)\n"
    )

    project = project(context)

    assert {:error, {:still_running, "@bot cannot push to owner/name.", {:manager, 1, _output}}} =
             DshProvisioner.provision(project, source(context), %{path: context.checkout})

    assert File.dir?(Path.join(context.profiles, "new"))
  end
end
