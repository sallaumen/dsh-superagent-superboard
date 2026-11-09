defmodule AgentBoard.System.Git do
  @moduledoc """
  The few git reads the version panel needs, from the checkout this node runs.

  Every command is a fixed argument list against the project root -- nothing
  here takes input from a request, so there is no command injection surface.
  A missing git or a non-repository answers `{:error, reason}` instead of
  raising: the board still works without version information.
  """

  @type result :: {:ok, String.t()} | {:error, term()}

  @doc "The project root: where mix was started."
  @spec root() :: String.t()
  def root, do: File.cwd!()

  @doc "Runs git with the given fixed arguments in the project root."
  @spec run([String.t()]) :: result()
  def run(args) do
    case System.cmd("git", args, cd: root(), stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, status} -> {:error, {status, String.trim(output)}}
    end
  end

  @doc "The short sha of HEAD."
  @spec head() :: result()
  def head, do: run(["rev-parse", "--short", "HEAD"])

  @doc "The short sha of origin/main, as last fetched."
  @spec origin_main() :: result()
  def origin_main, do: run(["rev-parse", "--short", "origin/main"])

  @doc "How many commits HEAD is behind origin/main."
  @spec behind() :: {:ok, non_neg_integer()} | {:error, term()}
  def behind do
    case run(["rev-list", "--count", "HEAD..origin/main"]) do
      {:ok, count} -> parse_count(count)
      error -> error
    end
  end

  @doc """
  The commits between two revisions, newest first, each with `sha`, `title`
  and an optional pull request number. A missing revision is an empty list,
  so a board that cannot fetch main still renders.
  """
  @spec commits(String.t() | nil, String.t() | nil, pos_integer()) ::
          {:ok, [map()]} | {:error, term()}
  def commits(from, to, limit \\ 10)
  def commits(nil, _to, _limit), do: {:ok, []}
  def commits(_from, nil, _limit), do: {:ok, []}
  def commits(from, from, _limit), do: {:ok, []}

  def commits(from, to, limit) when is_binary(from) and is_binary(to) do
    with {:ok, output} <-
           run([
             "log",
             "--max-count=#{limit}",
             "--format=%h%x1f%s",
             "#{from}..#{to}"
           ]) do
      commits =
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&parse_commit/1)

      {:ok, commits}
    end
  end

  @doc false
  def parse_commit(line) do
    case String.split(line, <<0x1F>>, parts: 2) do
      [sha, title] ->
        pr =
          case Regex.run(~r/#(\d+)/, title) do
            [_, number] -> String.to_integer(number)
            _ -> nil
          end

        %{sha: sha, title: title, pr: pr}

      _ ->
        %{sha: String.slice(line, 0, 12), title: line, pr: nil}
    end
  end

  @doc "Whether the working tree has uncommitted changes."
  @spec dirty?() :: boolean()
  def dirty? do
    case run(["status", "--porcelain"]) do
      {:ok, ""} -> false
      {:ok, _changes} -> true
      {:error, _} -> false
    end
  end

  @doc "Fetches origin/main, without touching the working tree."
  @spec fetch() :: :ok | {:error, term()}
  def fetch do
    case run(["fetch", "--quiet", "origin", "main"]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp parse_count(text) do
    case Integer.parse(text) do
      {count, ""} when count >= 0 -> {:ok, count}
      _ -> {:error, :unparseable}
    end
  end
end
