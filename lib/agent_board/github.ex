defmodule AgentBoard.GitHub do
  @moduledoc "The GitHub client: read-only for the sync, plus the board's writes."

  @transient_statuses [500, 502, 503, 504]
  @repeatable_methods [:get, :head, :patch]
  @never_sent [:econnrefused, :nxdomain, :ehostunreach, :enetunreach]

  # tasks.number and pull_requests.number are int4: past this, Postgrex raises
  # instead of finding nothing, and the query runs on every board load.
  @max_number 2_147_483_647

  @doc """
  An issue or pull request number read from text or from the runner, or nil
  when it is not one the tables can hold. A comment can quote any URL.
  """
  @spec number(term()) :: pos_integer() | nil
  def number(value) when is_integer(value) and value > 0 and value <= @max_number, do: value

  def number(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number(number)
      _other -> nil
    end
  end

  def number(_value), do: nil

  @doc "A client bound to the API and the configured token, if any."
  def client do
    # get_env/3 only falls back when the key is MISSING; a key set to nil
    # (a test that deleted it mid-run) would crash on builder.().
    case Application.get_env(:agent_board, :github_client) do
      nil -> build()
      builder -> builder.()
    end
  end

  @doc "Whether the board can call GitHub as someone."
  @spec configured?() :: boolean()
  def configured? do
    Application.get_env(:agent_board, :github_client) != nil or token() not in [nil, ""]
  end

  defp token,
    do: Application.get_env(:agent_board, :github_token, System.get_env("GITHUB_TOKEN", ""))

  @doc false
  def build do
    token = token()

    headers = [
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", "2022-11-28"}
    ]

    headers =
      if token in [nil, ""], do: headers, else: [{"authorization", "Bearer #{token}"} | headers]

    Req.new([base_url: "https://api.github.com", headers: headers] ++ retry_options())
  end

  @doc """
  What the client tries again by itself, at most twice with a growing delay
  (`:github_retry_base_ms`, default 300 ms). A read or the closing of an issue
  can be repeated after a dropped connection or a 500/502/503/504. A write that
  may have landed cannot: it is repeated only when the connection never opened.
  A 4xx is final, and a rate limit has its own path (`RateLimited`).
  """
  @spec retry_options() :: keyword()
  def retry_options, do: [retry: &retry_decision/2, max_retries: 2, retry_log_level: false]

  @doc false
  def retry_decision(request, response_or_exception) do
    if repeatable?(request.method, response_or_exception) do
      tries = Req.Request.get_private(request, :req_retry_count, 0)
      {:delay, Application.get_env(:agent_board, :github_retry_base_ms, 300) * 3 ** tries}
    else
      false
    end
  end

  defp repeatable?(method, %Req.Response{status: status})
       when method in @repeatable_methods and status in @transient_statuses,
       do: true

  defp repeatable?(method, %Req.TransportError{}) when method in @repeatable_methods, do: true
  defp repeatable?(_method, %Req.TransportError{reason: reason}), do: reason in @never_sent
  defp repeatable?(_method, _other), do: false

  # A 4xx/5xx response is an error, not a body. Req.get! only raises on
  # transport errors, so the status is checked here.
  defp body!(response) do
    case response.status do
      status when status in 200..299 ->
        response.body

      429 ->
        raise AgentBoard.GitHub.RateLimited, retry_after: wait_seconds(response)

      403 ->
        if limited?(response) do
          raise AgentBoard.GitHub.RateLimited, retry_after: wait_seconds(response)
        else
          raise "GitHub HTTP 403: #{inspect(response.body)}"
        end

      status ->
        raise "GitHub HTTP #{status}: #{inspect(response.body)}"
    end
  end

  # A 403 is a rate limit only when GitHub says so; the same status answers a
  # token without access, and waiting would not fix that.
  defp limited?(response) do
    header(response, "x-ratelimit-remaining") == "0" or header(response, "retry-after") != nil or
      response.body |> inspect() |> String.downcase() |> String.contains?("rate limit")
  end

  # Retry-After on the secondary limit, the reset time on a spent quota; a
  # minute, the window's length, when GitHub says neither.
  defp wait_seconds(response) do
    with nil <- number_header(response, "retry-after"),
         nil <- until_reset(response) do
      60
    end
  end

  defp until_reset(response) do
    case number_header(response, "x-ratelimit-reset") do
      nil -> nil
      reset -> max(reset - System.system_time(:second), 1)
    end
  end

  defp number_header(response, name) do
    with value when is_binary(value) <- header(response, name),
         {number, ""} <- Integer.parse(value) do
      number
    else
      _no_number -> nil
    end
  end

  defp header(response, name) do
    case Map.get(response.headers, name) do
      [value | _] -> value
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  @doc "The repository's issues, the pull requests filtered out."
  def issues(client, owner, repo) do
    client
    |> Req.get!(url: "/repos/#{owner}/#{repo}/issues", params: recent())
    |> body!()
    # GitHub returns pull requests from this endpoint too. The KEY is the
    # marker and its value may be nil, so Map.has_key?/2 is deliberate --
    # a test fixture that sets "pull_request" => nil is a pull request here.
    |> Enum.reject(&Map.has_key?(&1, "pull_request"))
  end

  @doc "The repository's pull requests."
  def pulls(client, owner, repo) do
    client
    |> Req.get!(url: "/repos/#{owner}/#{repo}/pulls", params: recent())
    |> body!()
  end

  @doc "The reviews of a pull request."
  def reviews(client, owner, repo, number) do
    client
    |> Req.get!(url: "/repos/#{owner}/#{repo}/pulls/#{number}/reviews", params: [per_page: 100])
    |> body!()
  end

  @doc "The check runs of a commit."
  def check_runs(client, owner, repo, ref) do
    client
    |> Req.get!(url: "/repos/#{owner}/#{repo}/commits/#{ref}/check-runs", params: [per_page: 100])
    |> body!()
    |> Map.get("check_runs", [])
  end

  @doc """
  One page of the commits on the default branch since an instant, newest
  first, and whether GitHub has a next page.

  `sha` is omitted on purpose: GitHub then lists the default branch, whatever
  it is called. `since` filters by the committer date, the instant the commit
  landed on the branch.
  """
  def commits(client, owner, repo, %DateTime{} = since, page \\ 1) do
    response =
      Req.get!(client,
        url: "/repos/#{owner}/#{repo}/commits",
        params: [since: DateTime.to_iso8601(since), per_page: 100, page: page]
      )

    {body!(response), next_page?(response)}
  end

  # GitHub paginates with a Link header; a page without rel="next" is the last.
  defp next_page?(response) do
    response.headers
    |> Map.get("link", [])
    |> List.wrap()
    |> Enum.any?(&String.contains?(&1, ~s(rel="next")))
  end

  @doc "The comments on an issue."
  def issue_comments(client, owner, repo, number) do
    client
    |> Req.get!(url: "/repos/#{owner}/#{repo}/issues/#{number}/comments", params: [per_page: 100])
    |> body!()
  end

  @doc "One page of recently updated issue comments across a repository."
  def repository_issue_comments(client, owner, repo, since, page \\ 1) do
    response =
      Req.get!(client,
        url: "/repos/#{owner}/#{repo}/issues/comments",
        params: [
          since: DateTime.to_iso8601(since),
          sort: "updated",
          direction: "asc",
          per_page: 100,
          page: page
        ]
      )

    {body!(response), next_page?(response)}
  end

  @doc "Comment on an issue."
  def create_comment(client, owner, repo, number, body) do
    client
    |> Req.post!(url: "/repos/#{owner}/#{repo}/issues/#{number}/comments", json: %{body: body})
    |> body!()
  end

  @doc "Open an issue."
  def create_issue(client, owner, repo, title, body, labels \\ []) do
    json =
      if labels == [],
        do: %{title: title, body: body},
        else: %{title: title, body: body, labels: labels}

    client
    |> Req.post!(url: "/repos/#{owner}/#{repo}/issues", json: json)
    |> body!()
  end

  @doc "The repository's collaborators, one page of 100."
  def collaborators(client, owner, repo) do
    client
    |> Req.get!(url: "/repos/#{owner}/#{repo}/collaborators", params: [per_page: 100])
    |> body!()
  end

  @doc """
  What `login` may do in the repository (`role_name`), or `:not_found` when
  GitHub has no such account. `login` is already validated by the caller.
  """
  def collaborator_permission(client, owner, repo, login) do
    response = Req.get!(client, url: "/repos/#{owner}/#{repo}/collaborators/#{login}/permission")

    case response.status do
      404 -> :not_found
      _status -> {:ok, body!(response)["role_name"]}
    end
  end

  @doc "Close an issue."
  def close_issue(client, owner, repo, number) do
    client
    |> Req.patch!(url: "/repos/#{owner}/#{repo}/issues/#{number}", json: %{state: "closed"})
    |> body!()
  end

  defp recent, do: [state: "all", sort: "updated", direction: "desc", per_page: 100]
end
