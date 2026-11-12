defmodule AgentBoard.Superagents.DshProvisioner do
  @moduledoc """
  Real provisioning for a new project: copy a ready superagent profile,
  rewrite its port/state, start it, copy the source/policy/prompts/executor
  configuration, validate setup and roll back a failed half-project.
  """
  @behaviour AgentBoard.Superagents.Provisioner

  alias AgentBoard.{AgentAccess, Superagents}
  alias AgentBoard.Superagents.{BotAccess, DshManager, Policy, Superagent}

  @doc false
  def provision(%Superagent{} = superagent, %Superagent{} = source, attrs) do
    # Nothing is touched until the target is known to be free: what is on disk
    # before this attempt is not this attempt's to remove.
    with :ok <- validate(attrs),
         :ok <- target_free(superagent, source),
         :ok <- ensure_bot_access(superagent, source) do
      build(superagent, source, attrs, File.exists?(superagent.state_dir))
    end
  end

  def provision(_superagent, nil, _attrs), do: {:error, :source_required}

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

  defp start(superagent) do
    args = [
      DshManager.script(),
      "--profile",
      superagent.profile,
      "--url",
      url(superagent),
      "start"
    ]

    case System.cmd("python3", args, stderr_to_stdout: true) do
      {output, 0} ->
        _ = output
        :ok

      {output, _code} when byte_size(output) > 0 ->
        # The manager treats a slow first boot as a failed start but leaves the
        # process running; the API check below is the real readiness gate.
        if String.contains?(output, "Startup health check timed out") do
          :ok
        else
          {:error, {:manager, 1, String.slice(output, 0, 500)}}
        end

      {output, code} ->
        {:error, {:manager, code, String.slice(output, 0, 500)}}
    end
  rescue
    exception -> {:error, exception}
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
         :ok <- put_source(superagent, source_settings, new_settings),
         :ok <- wait_api(superagent, 60),
         {:ok, 200, after_source} <- get(superagent, "/settings"),
         :ok <- put_executor(superagent, source_settings, after_source, attrs),
         :ok <- put_policy(superagent, source_settings, after_source),
         :ok <- put_prompts(superagent, source_prompts, new_prompts) do
      :ok
    else
      {:ok, status, _body} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp put_source(superagent, source_settings, new_settings) do
    source = source_block(source_settings)
    current = source_block(new_settings)

    if is_map(source) and is_map(current) do
      config = get_in(source, ["value", "config"]) || source["config"] || %{}
      config = Map.put(config, "repository", repository(superagent))
      config = Map.put(config, "observeIssues", true)

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

  defp put_policy(superagent, source_settings, new_settings) do
    source = get_in(source_settings, ["blocks", "policy"])
    current = get_in(new_settings, ["blocks", "policy"])

    if source && current do
      ok(
        put(superagent, "/settings/policy", %{
          "value" => source["value"],
          "revision" => current["revision"] || 0
        })
      )
    else
      {:error, :policy_block_missing}
    end
  end

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
