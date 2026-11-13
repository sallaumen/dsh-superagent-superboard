defmodule AgentBoard.ProjectMergePolicy do
  @moduledoc "Read-only evidence for a project's default branch and its DeepSeek GitHub source."
  alias AgentBoard.{GitHub, Superagents}
  alias AgentBoard.Superagents.Manager

  @policy_path ".github/superboard-merge.json"
  @sha ~r/\A[0-9a-f]{40}\z/

  def read(%{owner: owner, name: name}, client) do
    slug = "#{owner}/#{name}"

    with true <- Regex.match?(~r/\A[\w-]+\/[\w.-]+\z/, slug) and name not in [".", ".."],
         base = "/repos/#{slug}",
         {:ok, %{"default_branch" => branch}} when is_binary(branch) <- fetch(client, base),
         {:ok, %{"object" => %{"sha" => sha}}} when is_binary(sha) <-
           fetch(
             client,
             base <>
               "/git/ref/heads/" <> URI.encode(branch, &(&1 == ?/ or URI.char_unreserved?(&1)))
           ),
         true <- Regex.match?(@sha, sha) do
      result =
        case fetch(client, base <> "/contents/" <> @policy_path, ref: sha) do
          {:ok, %{"encoding" => "base64", "content" => content}} -> describe(content)
          :not_found -> :missing
          _ -> :unavailable
        end

      %{
        branch: branch,
        sha: sha,
        url: "https://github.com/#{slug}/blob/#{sha}/#{@policy_path}",
        result: result
      }
    else
      _ -> %{result: :unavailable}
    end
  end

  defp fetch(client, path, params \\ []) do
    case Req.get(client, url: path, params: params, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404}} -> :not_found
      _ -> :unavailable
    end
  end

  # Use the worker's own parser; none of the policy commands are run or displayed.
  defp describe(content) when is_binary(content) and byte_size(content) < 100_000 do
    case guard(["describe"], env: [{"SUPERBOARD_POLICY_CONTENT", content}]) do
      {json, 0} -> {:ok, Jason.decode!(json)}
      _ -> :invalid
    end
  end

  defp describe(_), do: :unavailable

  def enforcement(nil, _repo), do: :no_agent

  def enforcement(agent, %{owner: owner, name: name}) do
    source = Manager.impl().github_source(agent)
    slug = "#{owner}/#{name}"
    folder = Path.join([Superagents.profiles_root(), agent.profile, "merge-bin"])
    launcher = Path.join(folder, "gh")

    case source do
      {:ok, %{enabled: true, repository: repo, cli: ^launcher}} when is_binary(repo) ->
        if String.downcase(repo) == String.downcase(slug) and
             match?(
               {_, 0},
               guard(
                 ["installed", folder, repo, Path.join([agent.state_dir, "worker-bin", "gh"])],
                 []
               )
             ), do: :active, else: :inactive

      {:ok, _} ->
        :inactive

      _ ->
        :unknown
    end
  end

  def load(repo) do
    if GitHub.configured?(), do: read(repo, GitHub.client()), else: %{result: :unavailable}
  end

  defp guard(args, opts) do
    System.cmd(
      "python3",
      [Application.app_dir(:agent_board, "priv/merge_gate/guard.py") | args],
      [stderr_to_stdout: true] ++ opts
    )
  end
end
