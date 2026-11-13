defmodule AgentBoard.Superagents.DshProvisionerTest do
  @moduledoc """
  A provisioning the agent refuses, against a real HTTP agent and real
  directories: the half-project goes away and the agent's own reason comes back.
  """
  use ExUnit.Case, async: false

  alias AgentBoard.Board.Repository
  alias AgentBoard.Superagents.{DshProvisioner, Policy, Superagent}

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

  defmodule AccountAgent do
    @moduledoc false
    import Plug.Conn

    def init(options), do: options

    def call(conn, _options) do
      {:ok, _body, conn} = read_body(conn)

      body =
        if String.ends_with?(conn.request_path, "/state"),
          do: %{setup: %{accounts: %{agent: "robo"}}},
          else: %{sources: [%{id: "github", value: %{config: %{cli: "/bin/true"}}}]}

      conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(body))
    end
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

  test "a bot the board cannot give access to stops before anything is created", context do
    server =
      start_supervised!({Bandit, plug: AccountAgent, port: 0, ip: :loopback}, id: :accounts)

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    previous = Application.get_env(:agent_board, :github_client)
    Req.Test.set_req_test_to_shared(%{})

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(base_url: "https://api.github.test", plug: {Req.Test, __MODULE__}, retry: false)
    end)

    on_exit(fn ->
      Req.Test.set_req_test_to_private(%{})

      if previous,
        do: Application.put_env(:agent_board, :github_client, previous),
        else: Application.delete_env(:agent_board, :github_client)
    end)

    Req.Test.stub(__MODULE__, fn
      %{method: "GET"} = conn ->
        Req.Test.json(conn, %{"role_name" => "read"})

      %{method: "PUT"} = conn ->
        conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"message" => "no"})
    end)

    source = %Superagent{profile: "source", port: port, state_dir: "/x"}

    assert {:error, text} =
             DshProvisioner.provision(project(context), source, %{path: context.checkout})

    assert text =~ "@robo"
    refute File.exists?(Path.join(context.profiles, "new"))
  end

  describe "a machine's first agent" do
    defmodule FreshAgent do
      @moduledoc "An agent as it first boots: its own defaults, and every save reported to the test."
      import Plug.Conn

      @api "/orchestrator/api"

      def init(options), do: options

      def call(conn, _options) do
        {:ok, body, conn} = read_body(conn)
        path = String.replace_prefix(conn.request_path, @api, "")
        if conn.method == "PUT", do: send(:first_agent_test, {:saved, path, Jason.decode!(body)})

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(answer(path)))
      end

      defp answer("/state"), do: %{health: %{runtime: %{state: "ready"}}}

      defp answer("/settings") do
        %{
          sources: [
            %{
              id: "github",
              revision: 0,
              value: %{
                enabled: true,
                config: %{repository: "", cli: "", pollSeconds: 60, observeIssues: false}
              }
            }
          ],
          blocks: %{
            executor: %{
              revision: 0,
              value: %{model: nil, maxWorkers: 3, directory: "", prepare: "", blockedCommands: []}
            },
            policy: %{revision: 0, value: %{rules: [%{id: "example"}], sources: %{}}}
          }
        }
      end

      defp answer("/prompts"),
        do: %{current: %{revision: 0, config: %{communication: "old", skills: %{kept: "yes"}}}}

      defp answer(_path), do: %{saved: true}
    end

    setup context do
      Process.register(self(), :first_agent_test)
      home = Path.join(context.root, "agent-code")
      File.mkdir_p!(Path.join(home, "scripts"))
      File.write!(Path.join(home, "scripts/dsh-superagent"), "")
      File.mkdir_p!(Path.join(context.root, "gh-agent"))
      File.write!(Path.join(context.root, "gh-agent/hosts.yml"), "")
      test = self()

      # dsh as the rehearsal showed it: the first command leaves the profile's folder.
      runner = fn ["dsh" | args], opts ->
        send(test, {:dsh, args, opts[:env]})

        case args do
          [profile, "--from-default-profile", "web", "--dump-config"] ->
            File.mkdir_p!(Path.join(context.profiles, profile))
            File.write!(Path.join([context.profiles, profile, "cordis.patch.yml"]), "[]\n")
            {"", 0}

          ["plugin" | _rest] ->
            Process.get(:plugin_answer, {"", 0})
        end
      end

      for {key, value} <- [
            dsh_on_path: true,
            dsh_superagent_home: home,
            agent_gh_config: Path.join(context.root, "gh-agent"),
            agent_gh_cli: Path.join(context.root, "bin/gh-agent"),
            first_agent_runner: runner,
            github_client: fn ->
              Req.new(
                base_url: "https://api.github.test",
                plug: {Req.Test, __MODULE__},
                retry: false
              )
            end
          ] do
        previous = Application.get_env(:agent_board, key)
        Application.put_env(:agent_board, key, value)

        on_exit(fn ->
          if previous,
            do: Application.put_env(:agent_board, key, previous),
            else: Application.delete_env(:agent_board, key)
        end)
      end

      Req.Test.set_req_test_to_shared(%{})
      on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)
      Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"login" => "octo"}) end)

      server = start_supervised!({Bandit, plug: FreshAgent, port: 0, ip: :loopback}, id: :fresh)
      {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

      %{home: home, first: %{project(context) | profile: "first", port: port}}
    end

    test "gets a profile of its own, the bot's CLI and the owner as the one allowed", context do
      %{first: first, home: home} = context

      # The real manager appends /orchestrator/api itself and returns 3
      # until the first repository is configured.
      File.write!(Path.join(context.root, "manager.py"), """
      import os, sys
      assert sys.argv[sys.argv.index('--url') + 1] == 'http://127.0.0.1:#{first.port}'
      assert 'GH_TOKEN' not in os.environ and 'GITHUB_TOKEN' not in os.environ
      sys.exit(3 if sys.argv[-1] == 'start' else 0)
      """)

      assert {:ok, %{profile: "first"}} =
               DshProvisioner.provision(first, :first, %{path: context.checkout, workers: 2})

      # The profile: created by dsh under the folder the board reads, then the plugin.
      dsh_home = Path.dirname(context.profiles)

      assert_received {:dsh, ["first", "--from-default-profile", "web", "--dump-config"],
                       [{"DSH_HOME", ^dsh_home}]}

      plugin = "link:" <> home
      assert_received {:dsh, ["plugin", "--profile", "first", "add", ^plugin], _env}

      patch = File.read!(Path.join([context.profiles, "first", "cordis.patch.yml"]))
      assert patch =~ "port: #{first.port}"
      assert patch =~ "stateDir: #{first.state_dir}"
      assert patch =~ "- id: dsh-superagent"

      # The bot's wrapper, written because it was not there.
      cli = Path.join(context.root, "bin/gh-agent")
      assert File.read!(cli) =~ ~s(GH_CONFIG_DIR="$HOME/.config/gh-agent" exec gh "$@")
      assert Bitwise.band(File.stat!(cli).mode, 0o111) != 0
      # Even a caller with owner credentials must run gh as the bot.
      fake_gh = Path.join(Path.dirname(cli), "gh")

      File.write!(
        fake_gh,
        "#!/bin/sh\ntest -z \"$GH_TOKEN$GITHUB_TOKEN\" && echo \"$GH_CONFIG_DIR\""
      )

      File.chmod!(fake_gh, 0o755)

      assert {identity_dir, 0} =
               System.cmd(cli, ["api", "user"],
                 env: [
                   {"PATH", Path.dirname(cli)},
                   {"GH_TOKEN", "owner"},
                   {"GITHUB_TOKEN", "owner"}
                 ]
               )

      assert String.trim(identity_dir) == Path.expand("~/.config/gh-agent")

      # The settings: the agent's own defaults, with what a first agent lacks.
      assert_received {:saved, "/settings/source:github", %{"value" => %{"config" => source}}}

      assert %{
               "repository" => "owner/name",
               "cli" => guarded,
               "observeIssues" => true,
               "pollSeconds" => 60
             } = source

      assert File.read!(guarded) =~ "guard.py"
      assert File.read!(guarded) =~ cli

      assert_received {:saved, "/settings/executor", %{"value" => executor}}
      assert executor["maxWorkers"] == 2
      assert executor["directory"] == Path.join(first.state_dir, "work")
      assert executor["prepare"] =~ context.checkout

      assert_received {:saved, "/settings/policy", %{"value" => policy}}
      assert policy["rules"] == [%{"id" => "example"}]
      assert policy["sources"]["github"]["allowed"] == [%{"id" => "octo"}]

      assert_received {:saved, "/prompts", %{"config" => prompts}}
      assert prompts["communication"] == Policy.base()["communication"]
      assert prompts["skills"] == %{"kept" => "yes"}
    end

    test "never runs dsh for a profile that is already on disk", context do
      File.mkdir_p!(Path.join(context.profiles, "first"))
      File.write!(Path.join([context.profiles, "first", "cordis.patch.yml"]), "mine\n")

      assert DshProvisioner.provision(context.first, :first, %{path: context.checkout}) ==
               {:error, :profile_exists}

      refute_received {:dsh, _args, _env}
      assert File.read!(Path.join([context.profiles, "first", "cordis.patch.yml"])) == "mine\n"
    end

    test "a plugin that does not install undoes the profile and says what dsh said", context do
      Process.put(:plugin_answer, {"ERR_PNPM_LINK no such package", 1})

      assert {:error, {:command, "dsh", "ERR_PNPM_LINK no such package"}} =
               DshProvisioner.provision(context.first, :first, %{path: context.checkout})

      refute File.exists?(Path.join(context.profiles, "first"))
      refute File.exists?(context.first.state_dir)
    end

    test "stops before anything without dsh or without the bot's sign-in", context do
      File.rm!(Path.join(context.root, "gh-agent/hosts.yml"))
      assert DshProvisioner.first_ready() == {:error, :bot_missing}

      assert DshProvisioner.provision(context.first, :first, %{path: context.checkout}) ==
               {:error, :bot_missing}

      Application.put_env(:agent_board, :dsh_on_path, false)
      assert DshProvisioner.first_ready() == {:error, :dsh_missing}
      refute_received {:dsh, _args, _env}
      refute File.exists?(Path.join(context.root, "bin/gh-agent"))
    end
  end
end
