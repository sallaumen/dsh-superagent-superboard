defmodule AgentBoard.AgentWorktree do
  @moduledoc """
  The observable step of a running assignment: the worktree's uncommitted
  changes or its last commit.

  This is evidence from the filesystem, not the executor's private log. When
  the directory is missing, not a git repository, or gives no signal, the
  answer is `nil` and the board omits the step instead of inventing one.
  """

  @max_subject 80

  @doc """
  A step for the ticket, or nil.

  `%{kind: :edit, code: path}` for uncommitted work; `%{kind: :commit,
  code: sha, note: subject}` for the last commit.
  """
  @spec step(map() | nil) :: map() | nil
  def step(%{"execution" => %{"directory" => dir}}) when is_binary(dir) do
    dir = Path.expand(dir)

    if File.dir?(dir) do
      case changed_files(dir) do
        [file | _rest] -> %{kind: :edit, code: file, note: nil}
        [] -> last_commit(dir)
      end
    end
  end

  def step(_ticket), do: nil

  defp changed_files(dir) do
    case git(dir, ["status", "--porcelain=v1", "--untracked-files=no"]) do
      {:ok, ""} ->
        []

      {:ok, output} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&String.slice(&1, 3..-1//-1))
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.uniq()
        |> Enum.sort_by(&mtime(dir, &1), :desc)

      :error ->
        []
    end
  end

  defp last_commit(dir) do
    case git(dir, ["log", "-1", "--format=%h%x00%s"]) do
      {:ok, output} ->
        case String.split(output, "\0", parts: 2) do
          [sha, subject] when sha != "" -> %{kind: :commit, code: sha, note: truncate(subject)}
          _ -> nil
        end

      :error ->
        nil
    end
  end

  defp mtime(dir, file) do
    case File.stat(Path.join(dir, file), time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> mtime
      _ -> 0
    end
  end

  defp git(dir, args) do
    case System.cmd("git", ["-C", dir | args], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      _ -> :error
    end
  rescue
    _exception -> :error
  end

  defp truncate(subject) when byte_size(subject) <= @max_subject, do: subject
  defp truncate(subject), do: String.slice(subject, 0, @max_subject) <> "…"
end
