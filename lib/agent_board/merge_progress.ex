defmodule AgentBoard.MergeProgress do
  @moduledoc """
  A read-only view of the managed worker's atomic merge-check snapshot.
  The key is repository + PR, and the recorded head must match the board's
  last observed PR head. Missing evidence is distinct from a passed check.
  """

  @states ~w(checking blocked merging merged)
  @check_states ~w(queued running passed failed pending missing ambiguous skipped)

  def read(%{owner: owner, name: name}, number, head)
      when is_integer(number) and number > 0 do
    slug = String.downcase("#{owner}/#{name}")

    with true <- Regex.match?(~r/\A[a-z0-9_-]+\/[a-z0-9_.-]+\z/, slug) and name not in [".", ".."],
         {:ok, text} <- read_record(root(), slug, number),
         {:ok, snapshot} <- Jason.decode(text) do
      snapshot_for(snapshot, slug, number, head)
    else
      _ -> nil
    end
  end

  def read(_repo, _number, _head), do: nil

  # Slug components are validated above; refuse links in worker-owned directories
  # and cap the actual read even if the file was replaced since lstat.
  defp read_record(root, slug, number) do
    [owner, project] = String.split(slug, "/")
    owner_dir = Path.join(root, owner)
    project_dir = Path.join(owner_dir, project)
    path = Path.join(project_dir, "#{number}.json")

    with {:ok, %{type: :directory}} <- File.lstat(owner_dir),
         {:ok, %{type: :directory}} <- File.lstat(project_dir),
         {:ok, %{type: :regular}} <- File.lstat(path),
         {:ok, fd} <- :file.open(path, [:read, :raw, :binary]) do
      try do
        case :file.pread(fd, 0, 131_073) do
          {:ok, bytes} when byte_size(bytes) <= 131_072 -> {:ok, bytes}
          _ -> :error
        end
      after
        :file.close(fd)
      end
    else
      _ -> :error
    end
  end

  defp snapshot_for(
         %{
           "repo" => stored,
           "pr" => n,
           "head" => sha,
           "state" => state,
           "checks" => rows,
           "observed_at" => at
         } = snapshot,
         slug,
         n,
         head
       )
       when is_binary(stored) and is_binary(sha) and state in @states and is_integer(at) and
              is_list(rows) do
    if String.downcase(stored) == slug and Enum.all?(rows, &valid_check?/1) do
      freshness(snapshot, sha == head, System.system_time(:second) - at)
    end
  end

  defp snapshot_for(_, _, _, _), do: nil

  defp freshness(snapshot, false, _age),
    do: Map.merge(snapshot, %{"state" => "stale", "checks" => []})

  defp freshness(%{"state" => state} = snapshot, true, age)
       when state in ["checking", "merging"] and age > 90,
       do: Map.put(snapshot, "state", "unconfirmed")

  defp freshness(snapshot, true, _age), do: snapshot

  defp root,
    do: System.get_env("SUPERBOARD_GATE_DIR") || Path.expand("~/.local/state/superboard/merge")

  defp valid_check?(%{"name" => n, "source" => src, "state" => s}),
    do: is_binary(n) and src in ["local", "github"] and s in @check_states

  defp valid_check?(_), do: false
end
