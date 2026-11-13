defmodule AgentBoard.ProjectStages do
  @moduledoc "Local task checks selected by the owner; the worker reads the same catalog and file."
  @catalog Path.expand("../../priv/merge_gate/stages.json", __DIR__)
  @external_resource @catalog
  @commands @catalog |> File.read!() |> Jason.decode!()

  @rules_path Path.expand("../../priv/merge_gate/stack-rules.json", __DIR__)
  @external_resource @rules_path
  @rules @rules_path |> File.read!() |> Jason.decode!()
  def groups,
    do:
      @rules
      |> Enum.sort_by(fn {id, rule} -> {rule["mode"] != "always", id} end)
      |> Enum.group_by(fn {_, rule} -> rule["stack"] end, &elem(&1, 0))
      |> Enum.sort()

  def rule(id), do: Map.fetch!(@rules, id)

  def profile(repo, checkout) do
    case call(repo, "profile", [checkout || AgentBoard.Runners.repo_path(repo)]) do
      {json, 0} -> Jason.decode(json)
      _ -> {:error, :unavailable}
    end
  end

  def choices, do: Enum.sort_by(@commands, &elem(&1, 0))
  def command(id), do: Map.fetch(@commands, id)

  def load(repo) do
    case call(repo, "get", []) do
      {json, 0} -> Jason.decode(json)
      _ -> {:error, :unavailable}
    end
  end

  def save(repo, changes, expected) when is_map(changes) do
    case call(repo, "rules", Enum.map([changes, expected], &Jason.encode!/1)) do
      {_, 0} -> :ok
      _ -> {:error, :not_saved}
    end
  end

  def save(repo, ids, expected) when is_list(ids) and is_list(expected) do
    if Enum.all?(ids ++ expected, &Map.has_key?(@commands, &1)) and
         length(ids) <= map_size(@commands) do
      case call(repo, "save", Enum.map([ids, expected], &Jason.encode!/1)) do
        {_, 0} -> :ok
        _ -> {:error, :not_saved}
      end
    else
      {:error, :invalid}
    end
  end

  def save(_, _, _), do: {:error, :invalid}

  defp call(%{owner: owner, name: name}, action, args) do
    script = Application.app_dir(:agent_board, "priv/merge_gate/task_stages.py")
    # Tests can isolate the subprocess home without changing the LiveView's home.
    env = Application.get_env(:agent_board, :project_stages_env, [])

    System.cmd("python3", [script, action, "#{owner}/#{name}" | args],
      env: env,
      stderr_to_stdout: true
    )
  rescue
    ErlangError -> {"", 1}
  end
end
