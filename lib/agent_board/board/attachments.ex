defmodule AgentBoard.Board.Attachments do
  @moduledoc """
  Files that travel with a request: screenshots and interface mocks.

  GitHub has no API for an issue attachment, and the agent only sees a file in
  its checkout, so they live in the target repository, on a branch of their
  own that nobody merges. The path holds the file's hash: the same file is the
  same path, which makes a retry safe, and no part of it is free text except a
  name reduced to safe characters. The content is reference, never instruction.
  """

  alias AgentBoard.GitHub

  @branch "board-attachments"
  @accepted ~w(.png .jpg .jpeg .webp .gif .svg .html .pdf .zip)
  @max_bytes 20_000_000
  @max_files 8

  def branch, do: @branch
  def accepted, do: @accepted
  def max_bytes, do: @max_bytes
  def max_files, do: @max_files

  @doc "Stores the files on the attachments branch, creating it the first time."
  @spec store(map(), [%{name: String.t(), content: binary()}], term()) ::
          {:ok, [%{name: String.t(), path: String.t()}]} | {:error, Exception.t()}
  def store(_repository, [], _client), do: {:ok, []}

  def store(%{owner: owner, name: name}, files, client) do
    unless GitHub.branch_exists?(client, owner, name, @branch) do
      GitHub.create_branch_from_head(client, owner, name, @branch)
    end

    {:ok, Enum.map(files, &put(client, owner, name, &1))}
  rescue
    exception -> {:error, exception}
  end

  defp put(client, owner, repo, %{name: name, content: content}) do
    safe = safe_name(name)
    path = "#{hash(content)}/#{safe}"

    GitHub.put_new_file(client, owner, repo, @branch, path, content, "Attach #{safe}")
    %{name: safe, path: path}
  end

  defp hash(content), do: :sha256 |> :crypto.hash(content) |> Base.encode16(case: :lower)

  @doc "A file name with nothing that could leave its folder or break a URL or a command."
  @spec safe_name(String.t()) :: String.t()
  def safe_name(name) do
    name
    |> Path.basename()
    |> String.replace(~r/[^A-Za-z0-9._-]/, "_")
    |> String.trim_leading(".")
    |> String.slice(-100, 100)
    |> then(&if(&1 == "", do: "file", else: &1))
  end
end
