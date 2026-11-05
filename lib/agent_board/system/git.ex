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
