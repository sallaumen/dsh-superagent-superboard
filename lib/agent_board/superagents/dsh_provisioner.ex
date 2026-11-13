defmodule AgentBoard.Superagents.DshProvisioner do
  @moduledoc """
  Real provisioning for a new project: copy a ready superagent profile,
  rewrite its port/state, start it, copy the source/policy/prompts/executor
  configuration, validate setup and roll back a failed half-project.

  A machine's first agent (`:first`) has no profile to copy. Its profile is
  created the way the prototype's own install does it: `dsh <profile>
  --from-default-profile web --dump-config`, then `dsh plugin --profile
  <profile> add link:<the agent's code>`, then the patch with the port and the
  state folder. That first command replaces a profile that exists, so it runs
  only for a name that is not on disk. The agent's code is cloned and built
  when the machine does not have it (`Prototype.install/1`), and the bot's
  `gh` wrapper is written when missing. The agent is then configured from its
  own defaults, with the bot's CLI and, when the board knows who the owner is
  on GitHub, the owner as the one person allowed to ask. Two things stay the
  person's: `dsh` itself with a model, and the bot's sign-in; without them
  this stops before creating anything.
  """
  @behaviour AgentBoard.Superagents.Provisioner

  alias AgentBoard.{AgentAccess, Superagents}
  alias AgentBoard.Superagents.{Bot, BotAccess, DshManager, Policy, Prototype, Superagent}

  @wrapper """
  #!/bin/sh
  unset GH_TOKEN GITHUB_TOKEN
  GH_CONFIG_DIR="$HOME/.config/gh-agent" exec gh "$@"
  """

  @doc false
  @impl true
  def provision(%Superagent{} = superagent, %Superagent{} = source, attrs) do
    # Nothing is touched until the target is known to be free: what is on disk
    # before this attempt is not this attempt's to remove.
    with :ok <- validate(attrs),
         :ok <- target_free(superagent, source),
         :ok <- ensure_bot_access(superagent, source) do
      build(superagent, source, attrs, File.exists?(superagent.state_dir))
    end
  end

  def provision(%Superagent{} = superagent, :first, attrs) do
    with :ok <- validate(attrs),
         :ok <- first_target_free(superagent),
         :ok <- first_ready() do
      build_first(superagent, attrs, File.exists?(superagent.state_dir))
    end
  end

  def provision(_superagent, nil, _attrs), do: {:error, :source_required}

  @doc """
  Whether this machine can take a first agent: `dsh` in the board's PATH and
  a GitHub sign-in for the bot. Read before the owner is asked to confirm.
  """
  @impl true
  def first_ready do
    cond do
      not dsh?() -> {:error, :dsh_missing}
      not Bot.signed_in?() -> {:error, :bot_missing}
      true -> manager_tools()
    end
  end

  # `:dsh_on_path` stands in for this machine's PATH in tests.
  defp dsh? do
    case Application.get_env(:agent_board, :dsh_on_path) do
      nil -> System.find_executable("dsh") != nil
      found -> found
    end
  end

  # BusyBox has a ps binary but cannot list the process fields the manager needs.
  # Probe only the board process, discarding its output (no command lines logged).
  defp manager_tools do
    case System.cmd("/usr/bin/env", ["ps", "-ww", "-p", System.pid(), "-o", "pid=,ucomm=,args="],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      _other -> {:error, :ps_missing}
    end
  end

  defp first_target_free(superagent) do
    to = profile_dir(superagent.profile)

    cond do
      not is_binary(to) -> {:error, :invalid_profile}
      not inside_state?(superagent.state_dir) -> {:error, :invalid_state_dir}
      File.exists?(to) -> {:error, :profile_exists}
      true -> :ok
    end
  end

  # What is on disk before the profile exists (the agent's code, the bot's
  # wrapper) stays after a failure: neither is this project's alone.
  defp build_first(superagent, attrs, state_existed?) do
    with :ok <- Prototype.install(runner()),
         :ok <- bot_wrapper(),
         :ok <- first_bot_access(superagent) do
      attrs = Map.merge(attrs, %{cli: Bot.cli(), allowed: owner()})

      with :ok <- create_profile(superagent),
           :ok <- start(superagent),
           :ok <- wait_api(superagent, 60),
           :ok <- configure(superagent, superagent, attrs),
           :ok <- wait_ready(superagent, 60) do
        {:ok,
         %{profile: superagent.profile, port: superagent.port, state_dir: superagent.state_dir}}
      else
        {:error, reason} -> undo(superagent, reason, state_existed?)
      end
    end
  end

  # Every command of the install is a tool this module or `Prototype` names,
  # run through env with its arguments as separate words: never a shell
  # string, and nothing a request typed. A test replaces it.
  defp runner, do: Application.get_env(:agent_board, :first_agent_runner, &through_env/2)

  defp through_env(words, opts), do: System.cmd("/usr/bin/env", words, opts)

  # The source refuses a repository the bot cannot push to: the owner's token
  # invites it and its own CLI accepts, as for every other project. A bot the
  # board cannot name is not a failure here: saving the settings still checks.
  defp first_bot_access(superagent) do
    with {:ok, bot} <- Bot.login(),
         %{owner: _, name: _} = repository <- repository_of(superagent) do
      BotAccess.ensure(repository, bot, Bot.cli())
    else
      _unknown -> :ok
    end
  end

  # The one person a first agent listens to is whoever the board's token is.
  defp owner do
    case AgentBoard.GitHub.login() do
      {:ok, login} -> [login]
      _unknown -> []
    end
  end

  defp bot_wrapper do
    cli = Bot.cli()

    # The path is the board's own setting (`Bot.cli/0`), not outside data;
    # written the way this module writes a profile's patch.
    if File.exists?(cli) do
      :ok
    else
      with :ok <- :filelib.ensure_dir(cli),
           :ok <- :file.write_file(cli, @wrapper) do
        :file.change_mode(cli, 0o755)
      end
    end
  end

  defp create_profile(superagent) do
    dir = profile_dir(superagent.profile)
    # dsh writes under DSH_HOME: the same folder the board reads profiles from.
    opts = [env: [{"DSH_HOME", Path.dirname(Path.expand(Superagents.profiles_root()))}]]

    with :ok <-
           dsh([superagent.profile, "--from-default-profile", "web", "--dump-config"], opts),
         :ok <-
           dsh(
             ["plugin", "--profile", superagent.profile, "add", "link:" <> Prototype.home()],
             opts
           ),
         true <- File.dir?(dir) || {:error, :profile_not_created},
         :ok <- :file.write_file(Path.join(dir, "cordis.patch.yml"), first_patch(superagent)) do
      :filelib.ensure_dir(Path.join(superagent.state_dir, "work"))
      :ok
    end
  end

  defp dsh(args, opts) do
    case runner().(["dsh" | args], [stderr_to_stdout: true] ++ opts) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, {:command, "dsh", String.slice(output, -500, 500)}}
    end
  rescue
    exception -> {:error, {:command, "dsh", Exception.message(exception)}}
  end

  defp first_patch(superagent) do
    """
    - id: webserver
      config:
        host: 127.0.0.1
        port: #{superagent.port}
    - id: dsh-superagent
      config:
        stateDir: #{superagent.state_dir}
    """
  end

  defp build(superagent, source, attrs, state_existed?) do
    with :ok <- copy_profile(superagent, source),
         :ok <- start(superagent),
         :ok <- wait_api(superagent, 60),
         :ok <- configure(superagent, source, attrs),
         :ok <- wait_ready(superagent, 60) do
      {:ok,
       %{profile: superagent.profile, port: superagent.port, state_dir: superagent.state_dir}}
    else
      {:error, reason} -> undo(superagent, reason, state_existed?)
    end
  end

  # The bot and its CLI are the ones the source profile already uses. A source
  # that cannot say is not a failure here: saving the settings still checks.
  defp ensure_bot_access(superagent, source) do
    with {:ok, 200, state} <- get(source, "/state"),
         {:ok, 200, settings} <- get(source, "/settings"),
         bot when is_binary(bot) <- get_in(state, ["setup", "accounts", "agent"]),
         {:ok, bot} <- AgentAccess.normalize_login(bot),
         %{"value" => %{"config" => %{"cli" => cli}}} when is_binary(cli) and cli != "" <-
           github_source(settings),
         %{owner: _, name: _} = repository <- repository_of(superagent) do
      BotAccess.ensure(repository, bot, cli)
    else
      _unknown -> :ok
    end
  end

  defp github_source(settings) do
    Enum.find(settings["sources"] || [], &(&1["id"] == "github"))
  end

  defp repository_of(superagent), do: AgentBoard.Repo.preload(superagent, :repository).repository

  defp target_free(superagent, source) do
    from = profile_dir(source.profile)
    to = profile_dir(superagent.profile)

    cond do
      not (is_binary(from) and is_binary(to)) -> {:error, :invalid_profile}
      not inside_state?(superagent.state_dir) -> {:error, :invalid_state_dir}
      not File.dir?(from) -> {:error, :source_profile_missing}
      File.exists?(to) -> {:error, :profile_exists}
      true -> :ok
    end
  end

  defp validate(%{path: path}) do
    if is_binary(path) and File.dir?(path) and File.exists?(Path.join(path, ".git")),
      do: :ok,
      else: {:error, :checkout_missing}
  end

  defp validate(_attrs), do: {:error, :checkout_missing}

  defp copy_profile(superagent, source) do
    to = profile_dir(superagent.profile)

    with :ok <- copy_tree(profile_dir(source.profile), to),
         :ok <- rewrite_patch(to, superagent) do
      :filelib.ensure_dir(Path.join(superagent.state_dir, "work"))
      :ok
    end
  end

  defp profile_dir(profile) do
    root = Path.expand(Superagents.profiles_root())
    path = Path.expand(Path.join(root, profile))
    if Path.dirname(path) == root, do: path, else: nil
  end

  defp state_root, do: Superagents.state_root()

  defp inside_state?(path) do
    root = state_root()
    String.starts_with?(Path.expand(path), root <> "/")
  end

  defp rewrite_patch(dir, superagent) do
    patch = Path.join(dir, "cordis.patch.yml")

    case :file.read_file(patch) do
      {:ok, text} ->
        text =
          text
          |> String.replace(~r/port:\s*\d+/, "port: #{superagent.port}", global: false)
          |> String.replace(~r/stateDir:\s*.*/, "stateDir: #{superagent.state_dir}",
            global: false
          )

        :file.write_file(patch, text)

      {:error, _} ->
        {:error, :profile_patch_missing}
    end
  end

  # A fresh profile starts in "waiting for setup" (exit 3). Its API must
  # be reachable so configure/3 can supply the repository and bot.
  defp start(superagent) do
    case DshManager.start(superagent) do
      {:error, {:manager, 3, _output}} -> :ok
      result -> result
    end
  end

  defp wait_api(superagent, attempts) do
    Enum.reduce_while(1..attempts, {:error, :timeout}, fn _attempt, _acc ->
      case get(superagent, "/state") do
        {:ok, 200, _body} ->
          {:halt, :ok}

        _ ->
          Process.sleep(1_000)
          {:cont, {:error, :timeout}}
      end
    end)
  end

  defp wait_ready(superagent, attempts) do
    Enum.reduce_while(1..attempts, {:error, :timeout}, fn _attempt, _acc ->
      case ready_result(superagent) do
        :ok ->
          {:halt, :ok}

        {:error, reason} ->
          {:halt, {:error, reason}}

        :wait ->
          Process.sleep(1_000)
          {:cont, {:error, :timeout}}
      end
    end)
  end

  defp ready_result(superagent) do
    case get(superagent, "/state") do
      {:ok, 200, body} -> ready_state(body)
      _ -> :wait
    end
  end

  defp setup_detail(%{"problem" => %{"detail" => detail}}) when is_binary(detail), do: detail
  defp setup_detail(%{"detail" => detail}) when is_binary(detail), do: detail
  defp setup_detail(_setup), do: nil

  defp ready_state(body) do
    setup = body["setup"]
    health = body["health"] || %{}

    cond do
      setup_detail(setup) -> {:error, {:setup, setup_detail(setup)}}
      get_in(health, ["runtime", "state"]) == "ready" -> :ok
      true -> :wait
    end
  end

  defp configure(superagent, source, attrs) do
    with {:ok, 200, source_settings} <- get(source, "/settings"),
         {:ok, 200, new_settings} <- get(superagent, "/settings"),
         {:ok, 200, source_prompts} <- get(source, "/prompts"),
         {:ok, 200, new_prompts} <- get(superagent, "/prompts"),
         :ok <- put_source(superagent, source_settings, new_settings, attrs),
         :ok <- wait_api(superagent, 60),
         {:ok, 200, after_source} <- get(superagent, "/settings"),
         :ok <- put_executor(superagent, source_settings, after_source, attrs),
         :ok <- put_policy(superagent, source_settings, after_source, attrs),
         :ok <- put_prompts(superagent, source_prompts, new_prompts) do
      :ok
    else
      {:ok, status, _body} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  # `attrs.cli` is the bot's CLI for a first agent, whose own settings have none.
  defp put_source(superagent, source_settings, new_settings, attrs) do
    source = source_block(source_settings)
    current = source_block(new_settings)

    if is_map(source) and is_map(current) do
      config = get_in(source, ["value", "config"]) || source["config"] || %{}
      config = Map.put(config, "repository", repository(superagent))
      config = Map.put(config, "observeIssues", true)
      config = if attrs[:cli], do: Map.put(config, "cli", attrs.cli), else: config

      ok(
        put(superagent, "/settings/source:github", %{
          "value" => Map.put(current["value"] || %{}, "config", config),
          "revision" => current["revision"] || 0
        })
      )
    else
      {:error, :source_block_missing}
    end
  end

  defp put_executor(superagent, source_settings, new_settings, attrs) do
    source = get_in(source_settings, ["blocks", "executor"])
    current = get_in(new_settings, ["blocks", "executor"])
    value = source["value"] || %{}

    value =
      value
      |> Map.put("maxWorkers", Map.get(attrs, :workers, 3))
      |> Map.put("directory", Path.join(superagent.state_dir, "work"))
      |> Map.put("prepare", prepare(attrs.path))

    if source && current do
      ok(
        put(superagent, "/settings/executor", %{
          "value" => value,
          "revision" => current["revision"] || 0
        })
      )
    else
      {:error, :executor_block_missing}
    end
  end

  # `attrs.allowed` are the logins a first agent starts listening to: until
  # its list has someone, no request becomes a ticket.
  defp put_policy(superagent, source_settings, new_settings, attrs) do
    source = get_in(source_settings, ["blocks", "policy"])
    current = get_in(new_settings, ["blocks", "policy"])

    if source && current do
      ok(
        put(superagent, "/settings/policy", %{
          "value" => allowing(source["value"], attrs[:allowed]),
          "revision" => current["revision"] || 0
        })
      )
    else
      {:error, :policy_block_missing}
    end
  end

  defp allowing(%{} = value, [_login | _rest] = logins) do
    sources = if is_map(value["sources"]), do: value["sources"], else: %{}
    github = if is_map(sources["github"]), do: sources["github"], else: %{}
    github = Map.put(github, "allowed", Enum.map(logins, &%{"id" => &1}))
    Map.put(value, "sources", Map.put(sources, "github", github))
  end

  defp allowing(value, _none), do: value

  # A new agent is born with the board's policy (`Superagents.Policy`), not
  # with whatever text the source agent holds today; the source only lends
  # the other keys of the config (its skills).
  defp put_prompts(superagent, source_prompts, new_prompts) do
    config = get_in(source_prompts, ["current", "config"])
    base = get_in(new_prompts, ["current", "revision"]) || 0

    if is_map(config) do
      config = Map.merge(config, Policy.base())
      ok(put(superagent, "/prompts", %{"config" => config, "baseRevision" => base}))
    else
      {:error, :prompts_missing}
    end
  end

  defp ok({:ok, 200, _body}), do: :ok
  # The agent says what is wrong (no push access, say); the status alone does not.
  defp ok({:ok, _status, %{"error" => detail}}) when is_binary(detail), do: {:error, detail}
  defp ok({:ok, status, _body}), do: {:error, {:http, status}}
  defp ok({:error, reason}), do: {:error, reason}

  defp source_block(settings) do
    (settings["sources"] || [])
    |> Enum.find(&(&1["id"] == "github"))
    |> case do
      nil -> nil
      source -> %{"value" => source["value"] || %{}, "revision" => source["revision"] || 0}
    end
  end

  defp prepare(path) do
    quoted = shell_quote(path)

    ~s|git -C #{quoted} fetch --no-tags "https://github.com/$DSH_SUPERAGENT_GITHUB_REPOSITORY.git" "${DSH_SUPERAGENT_GITHUB_PR_HEAD:-HEAD}:refs/dsh-superagent/$DSH_SUPERAGENT_TICKET" && git -C #{quoted} worktree add -b "agent/$DSH_SUPERAGENT_NAME" "$DSH_SUPERAGENT_DIR" "refs/dsh-superagent/$DSH_SUPERAGENT_TICKET"|
  end

  defp shell_quote(value), do: "'" <> String.replace(to_string(value), "'", "'\"'\"'") <> "'"

  defp repository(superagent) do
    case AgentBoard.Repo.preload(superagent, :repository).repository do
      %{owner: owner, name: name} -> "#{owner}/#{name}"
      _ -> ""
    end
  end

  # An agent that would not stop keeps its files: deleting them under a running
  # process would leave it with nothing on the board to stop it. A state
  # directory from before this attempt (a removed project leaves one) stays.
  defp undo(superagent, reason, state_existed?) do
    case DshManager.stop(superagent) do
      :ok ->
        remove_tree(profile_dir(superagent.profile))
        unless state_existed?, do: remove_tree(superagent.state_dir)
        {:error, reason}

      {:error, stop_failure} ->
        {:error, {:still_running, reason, stop_failure}}
    end
  end

  defp copy_tree(from, to) do
    case System.cmd("/bin/cp", ["-R", from, to], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, {:copy, String.slice(output, 0, 300)}}
    end
  end

  # Does not follow symlinks: a profile's node_modules points into a shared store.
  defp remove_tree(path), do: :file.del_dir_r(path)

  defp get(superagent, path), do: request(superagent, :get, path, nil)
  defp put(superagent, path, body), do: request(superagent, :put, path, body)

  defp request(superagent, method, path, body) do
    opts = [
      url: url(superagent) <> path,
      headers: [{"x-orchestrator-request", "1"}],
      receive_timeout: 5_000,
      retry: false
    ]

    opts = if body, do: Keyword.put(opts, :json, body), else: opts

    case Req.request([method: method] ++ opts) do
      {:ok, %{status: status, body: body}} when status >= 400 ->
        require Logger
        Logger.warning("provision #{method} #{path} -> #{status} #{inspect(body)}")
        {:ok, status, body}

      {:ok, %{status: status, body: body}} ->
        {:ok, status, body}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp url(superagent), do: "http://127.0.0.1:#{superagent.port}/orchestrator/api"
end
