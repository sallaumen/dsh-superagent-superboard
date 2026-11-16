defmodule AgentBoard.LocalCI.Validation do
  @moduledoc "Interpret a workpad validation against the head recorded for its pull request."

  @doc "Only known, conflicting SHAs contradict the recorded outcome; either SHA may be abbreviated."
  @spec state(%{sha: String.t() | nil, passed?: boolean()}, String.t() | nil) ::
          :pass | :fail | :stale
  def state(%{sha: sha, passed?: passed?}, head) do
    cond do
      is_binary(sha) and is_binary(head) and not same_commit?(sha, head) -> :stale
      passed? -> :pass
      true -> :fail
    end
  end

  defp same_commit?(sha, head) do
    sha = String.downcase(sha)
    head = String.downcase(head)
    String.starts_with?(head, sha) or String.starts_with?(sha, head)
  end
end
