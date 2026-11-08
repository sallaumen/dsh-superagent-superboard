defmodule AgentBoard.Superagents.DshProvisioner do
  @moduledoc """
  Real provisioning for a new project: copy a ready superagent profile,
  rewrite its port/state, start it, copy the source/policy/prompts/executor
  configuration, validate setup and roll back a failed half-project.
  """
  @behaviour AgentBoard.Superagents.Provisioner

  alias AgentBoard.Superagents.{DshManager, Superagent}

  @doc false
  def provision(%Superagent{} = superagent, %Superagent{} = source, attrs) do
    with :ok <- validate(attrs),
         :ok <- copy_profile(superagent, source),
         :ok <- start(superagent),
         :ok <- wait_api(superagent, 30),
         :ok <- configure(superagent, source, attrs),
         :ok <- wait_ready(superagent, 60) do
      {:ok,
       %{profile: superagent.profile, port: superagent.port, state_dir: superagent.state_dir}}
    else
      {:error, reason} ->
        rollback(superagent)
        {:error, reason}
    end
  end

  def provision(_superagent, nil, _attrs), do: {:error, :source_required}

  defp validate(%{path: path}) do
    if is_binary(path) and File.dir?(path) and File.exists?(Path.join(path, ".git")),
      do: :ok,
      else: {:error, :checkout_missing}
  end

  defp validate(_attrs), do: {:error, :checkout_missing}

  defp copy_profile(superagent, source) do
    from = profile_dir(source.profile)
    to = profile_dir(superagent.profile)

    with true <- File.dir?(from) || {:error, :source_profile_missing},
         false <- File.exists?(to) || {:error, :profile_exists},
         :ok <- copy_tree(from, to),
         :ok <- rewrite_patch(to, superagent) do
      :filelib.ensure_dir(Path.join(superagent.state_dir, "work"))
      :ok
    else
      {:error, reason} -> {:error, reason}
      true -> {:error, :profile_exists}
      false -> {:error, :checkout_missing}
    end
  end

  defp profile_dir(profile) do
    root = Path.expand("~/.dsh/profiles")
    path = Path.expand(Path.join(root, profile))
    if Path.dirname(path) == root, do: path, else: nil
  end

  defp state_root, do: Path.expand("~/.dsh/state")

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
      {_output, 0} -> :ok
      {output, code} -> {:error, {:manager, code, String.slice(output, 0, 500)}}
    end
  rescue
    exception -> {:error, exception}
  end

  defp wait_api(superagent, attempts), do: wait(superagent, attempts, &(&1.status == 200))

  defp wait_ready(superagent, attempts) do
    wait(superagent, attempts, fn
      %{status: 200, body: body} ->
        setup = body["setup"]
        health = body["health"] || %{}

        (is_nil(setup) or is_nil(setup["detail"])) and
          get_in(health, ["runtime", "state"]) == "ready"

      _ ->
        false
    end)
  end

  defp wait(superagent, attempts, fun) do
    Enum.reduce_while(1..attempts, {:error, :timeout}, fn _attempt, _acc ->
      case check(superagent, fun) do
        :ok -> {:halt, :ok}
        :cont -> {:cont, {:error, :timeout}}
      end
    end)
  end

  defp check(superagent, fun) do
    case get(superagent, "/state") do
      {:ok, 200, body} ->
        if fun.(%{status: 200, body: body}) do
          :ok
        else
          Process.sleep(1_000)
          :cont
        end

      _ ->
        Process.sleep(1_000)
        :cont
    end
  end

  defp configure(superagent, source, attrs) do
    with {:ok, 200, source_settings} <- get(source, "/settings"),
         {:ok, 200, new_settings} <- get(superagent, "/settings"),
         {:ok, 200, source_prompts} <- get(source, "/prompts"),
         {:ok, 200, new_prompts} <- get(superagent, "/prompts"),
         {:ok, _} <- put_source(superagent, source_settings, new_settings),
         :ok <- wait_api(superagent, 30),
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
      config = source["config"] || %{}
      config = Map.put(config, "repository", repository(superagent))
      config = Map.put(config, "enabled", true)
      config = Map.put(config, "observeIssues", true)

      put(superagent, "/settings/source:github", %{
        "value" => Map.put(current, "config", config),
        "revision" => current["revision"] || 0
      })
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
      put(superagent, "/settings/executor", %{
        "value" => value,
        "revision" => current["revision"] || 0
      })
    else
      {:error, :executor_block_missing}
    end
  end

  defp put_policy(superagent, source_settings, new_settings) do
    source = get_in(source_settings, ["blocks", "policy"])
    current = get_in(new_settings, ["blocks", "policy"])

    if source && current do
      put(superagent, "/settings/policy", %{
        "value" => source["value"],
        "revision" => current["revision"] || 0
      })
    else
      {:error, :policy_block_missing}
    end
  end

  defp put_prompts(superagent, source_prompts, new_prompts) do
    config = get_in(source_prompts, ["current", "config"])
    base = get_in(new_prompts, ["current", "revision"]) || 0

    if is_map(config),
      do: put(superagent, "/prompts", %{"config" => config, "baseRevision" => base}),
      else: {:error, :prompts_missing}
  end

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

  defp rollback(superagent) do
    DshManager.stop(superagent)
    if profile = profile_dir(superagent.profile), do: remove_tree(profile)
    if inside_state?(superagent.state_dir), do: remove_tree(superagent.state_dir)
    :ok
  end

  defp copy_tree(from, to) do
    case :file.read_file_info(from) do
      {:ok, %{type: :directory}} -> copy_directory(from, to)
      {:ok, _file} -> :file.copy(from, to)
      {:error, reason} -> {:error, reason}
    end
  end

  defp copy_directory(from, to) do
    :filelib.ensure_dir(to)

    with {:ok, entries} <- :file.list_dir(from) do
      copy_entries(entries, from, to)
    end
  end

  defp copy_entries(entries, from, to) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case copy_tree(Path.join(from, entry), Path.join(to, entry)) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp remove_tree(path) do
    case :file.read_file_info(path) do
      {:ok, %{type: :directory}} ->
        with {:ok, entries} <- :file.list_dir(path) do
          Enum.each(entries, &remove_tree(Path.join(path, &1)))
        end

        :file.del_dir(path)

      {:ok, _file} ->
        :file.delete(path)

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

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
      {:ok, %{status: status, body: body}} -> {:ok, status, body}
      {:error, exception} -> {:error, exception}
    end
  end

  defp url(superagent), do: "http://127.0.0.1:#{superagent.port}/orchestrator/api"
end
