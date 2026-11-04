defmodule AgentBoard.GitHub do
  @moduledoc "The GitHub client: read-only for the sync, plus the board's writes."

  @doc "A client bound to the API and the configured token, if any."
  def client do
    token = Application.get_env(:agent_board, :github_token, System.get_env("GITHUB_TOKEN", ""))

    headers = [
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", "2022-11-28"}
    ]

    headers =
      if token in [nil, ""], do: headers, else: [{"authorization", "Bearer #{token}"} | headers]

    Req.new(base_url: "https://api.github.com", headers: headers, retry: false)
  end

  @doc "The repository's issues, the pull requests filtered out."
  def issues(client, owner, repo) do
    client
    |> Req.get!(url: "/repos/#{owner}/#{repo}/issues", params: recent())
    |> Map.fetch!(:body)
    |> Enum.reject(&Map.has_key?(&1, "pull_request"))
  end

  @doc "The repository's pull requests."
  def pulls(client, owner, repo) do
    client
    |> Req.get!(url: "/repos/#{owner}/#{repo}/pulls", params: recent())
    |> Map.fetch!(:body)
  end

  @doc "The reviews of a pull request."
  def reviews(client, owner, repo, number) do
    client
    |> Req.get!(url: "/repos/#{owner}/#{repo}/pulls/#{number}/reviews", params: [per_page: 100])
    |> Map.fetch!(:body)
  end

  @doc "The check runs of a commit."
  def check_runs(client, owner, repo, ref) do
    client
    |> Req.get!(url: "/repos/#{owner}/#{repo}/commits/#{ref}/check-runs", params: [per_page: 100])
    |> Map.fetch!(:body)
    |> Map.get("check_runs", [])
  end

  @doc "The comments on an issue."
  def issue_comments(client, owner, repo, number) do
    client
    |> Req.get!(url: "/repos/#{owner}/#{repo}/issues/#{number}/comments", params: [per_page: 100])
    |> Map.fetch!(:body)
  end

  @doc "Comment on an issue."
  def create_comment(client, owner, repo, number, body) do
    client
    |> Req.post!(url: "/repos/#{owner}/#{repo}/issues/#{number}/comments", json: %{body: body})
    |> Map.fetch!(:body)
  end

  @doc "Open an issue."
  def create_issue(client, owner, repo, title, body) do
    client
    |> Req.post!(url: "/repos/#{owner}/#{repo}/issues", json: %{title: title, body: body})
    |> Map.fetch!(:body)
  end

  @doc "Close an issue."
  def close_issue(client, owner, repo, number) do
    client
    |> Req.patch!(url: "/repos/#{owner}/#{repo}/issues/#{number}", json: %{state: "closed"})
    |> Map.fetch!(:body)
  end

  defp recent, do: [state: "all", sort: "updated", direction: "desc", per_page: 100]
end
